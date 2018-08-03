import PromiseKit
import AppKit

class ReposViewController: NSViewController {
    var repos = [Repo]()
    var hooked = [HookType: Guarantee<Bool>]()
    var subscribed = Set<Int>()
    var hasVerifiedReceipt = false

    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var notifyButton: NSButton!
    @IBOutlet weak var installWebhookButton: NSButton!
    @IBOutlet weak var webhookExplanation: NSTextField!
    @IBOutlet weak var installWebhookFirstLabel: NSTextField!
    @IBOutlet weak var privateReposAdviceLabel: NSTextField!

    var rootedRepos: [String: [Repo]] {
        return Dictionary(grouping: repos, by: { $0.owner.login })
    }
    var rootedReposKeys: [String] {
        return rootedRepos.keys.map{ ($0, $0.lowercased()) }.sorted{ $0.1 < $1.1 }.map{ $0.0 }
    }

    enum HookType: Hashable {
        case repo(Repo)
        case organization(Int, String)
    }

    enum Foo: Equatable {
        case repo(Repo)
        case organization(Int, String)
        case user(Int, String)
    }

    var selectedItem: Foo? {
        guard outlineView.selectedRow != -1 else { return nil }

        let item = outlineView.item(atRow: outlineView.selectedRow)

        if let login = item as? String {
            let repos = rootedRepos[login]!
            if repos.isOrganization {
                let owner = repos[0].owner  // safe as we wouldn't show anything if empty
                return .organization(owner.id, owner.login)
            } else {
                let id = repos[0].owner.id  // safe as we wouldn't show anything if empty
                return .user(id, login)
            }
        } else {
            return .repo(item as! Repo)
        }
    }

    func requiresReceipt(item: Foo) -> Bool {
        switch item {
        case .organization(_, let login), .user(_, let login):
            return rootedRepos[login]!.satisfaction{ $0.private } == .none
        case .repo(let repo):
            return repo.private
        }
    }

    func paymentPrompt() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Private Repository Subscription"
        alert.informativeText = "Receiving notifications for private repositories requires a recurring subscription fee."
        alert.addButton(withTitle: "Subscribe")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { rsp in
            switch rsp {
            case .cancel:
                break
            default:
                app.subscribe(sender: self)
            }
        }
    }

    private func state(for item: Foo) -> SwitchState {
        switch item {
        case .organization(_, let login), .user(_, let login):
            return SwitchState(rootedRepos[login]!, where: { subscribed.contains($0.id) })
        case .repo(let repo):
            return subscribed.contains(repo.id) ? .on : .off
        }
    }

    @IBAction private func toggleNotify(sender: NSButton) {
        guard let selectedItem = selectedItem else {
            return
        }
        let subscribe = sender.state == .on
        let restoreState = state(for: selectedItem).nsControlStateValue

        guard let token = creds?.token else {
            sender.state = restoreState
            return alert(message: "No GitHub auth token", title: "Unexpected Error")
        }
        if subscribe, !hasVerifiedReceipt, requiresReceipt(item: selectedItem) {
            sender.state = restoreState
            return paymentPrompt()
        }

        var ids: [Int] {
            switch selectedItem {
            case .organization(_, let login), .user(_, let login):
                return rootedRepos[login]!.map(\.id)
            case .repo(let repo):
                return [repo.id]
            }
        }

        sender.isEnabled = false

        let url = URL(string: "\(serverBaseUri)/subscribe")!
        var rq = URLRequest(url: url)
        rq.httpMethod = subscribe ? "POST" : "DELETE"
        rq.httpBody = try! JSONEncoder().encode(ids)
        rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        rq.setValue(token, forHTTPHeaderField: "Authorization")

        firstly {
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.done { _ in
            for id in ids {
                if subscribe {
                    self.subscribed.insert(id)
                } else {
                    self.subscribed.remove(id)
                }
            }
            self.outlineView.reloadData()
        }.catch {
            sender.state = restoreState
            alert($0)
        }.finally {
            sender.isEnabled = true
        }
    }

    @IBAction private func installWebhook(sender: NSButton) {
        guard let token = creds?.token else {
            return alert(message: "No GitHub auth token", title: "Unexpected Error")
        }
        guard let selectedItem = selectedItem else {
            return
        }

        //TODO don't allow toggling during activity
        //TODO UI feedback for activity

        func createHook(for hookType: HookType) -> Promise<HookType> {
            do {
                //TODO secret, which means probably doing this server side…
                let json: [String: Any] = [
                    "name": "web",
                    "events": ["*"],
                    "config": [
                        "url": hookUri,
                        "content_type": "json",
                        "insecure_ssl": "0"
                    ]
                ]
                let path: String
                switch hookType {
                case .organization(_, let login):
                    path = "/orgs/\(login)/hooks"
                case .repo(let repo):
                    path = "/repos/\(repo.full_name)/hooks"
                }
                var rq = GitHubAPI(oauthToken: token).request(path: path)
                rq.httpMethod = "POST"
                rq.httpBody = try JSONSerialization.data(withJSONObject: json)
                return URLSession.shared.dataTask(.promise, with: rq).validate().map{ _ in hookType }
            } catch {
                return Promise(error: error)
            }
        }

        installWebhookButton.isEnabled = false

        let types: [HookType]
        switch selectedItem {
        case .organization(let id, let login):
            types = [.organization(id, login)]
        case .repo(let repo):
            types = [.repo(repo)]
        case .user(_, let login):
            types = rootedRepos[login]!.map{ .repo($0) }.filter{ hooked[$0] == nil }
        }

        firstly {
            when(resolved: types.map(createHook))
        }.done { results in
            for result in results {
                switch result {
                case .fulfilled(let hookType):
                    self.hooked[hookType] = .value(true)
                case .rejected(let error):
                    alert(error)
                    self.installWebhookButton.isEnabled = true
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        privateReposAdviceLabel.isHidden = true
        installWebhookFirstLabel.isHidden = true

        NotificationCenter.default.addObserver(self, selector: #selector(fetch), name: .credsUpdated, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(subscriptionPurchased), name: .receiptVerified, object: nil)
    }

    @objc func subscriptionPurchased() {
        hasVerifiedReceipt = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        if creds == nil {
            performSegue(withIdentifier: "SignIn", sender: self)
        } else {
            fetch()
        }
    }

    private var fetching = false

    @objc private func fetch() {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !fetching else {
            return
        }
        guard let token = creds?.token else {
            repos = []
            hooked = [:]
            subscribed = []
            outlineView.reloadData()
            performSegue(withIdentifier: "SignIn", sender: self)
            return
        }

        func fetchSubs() -> Promise<(Set<Int>, Bool)> {
            let url = URL(string: "\(serverBaseUri)/subscribe")!
            var rq = URLRequest(url: url)
            rq.addValue(token, forHTTPHeaderField: "Authorization")
            return firstly {
                URLSession.shared.dataTask(.promise, with: rq).validate()
            }.map { data, rsp -> (Set<Int>, Bool) in
                let subs = Set(try JSONDecoder().decode([Int].self, from: data))
                let verifiedReceipt = (rsp as? HTTPURLResponse)?.allHeaderFields["Upgrade"] as? String == "true"
                return (subs, verifiedReceipt)
            }
        }

        fetching = true
        repos = []
        subscribed = []

        let p1 = GitHubAPI(oauthToken: token).task(path: "/user/repos") { data in
            DispatchQueue.global().async(.promise) {
                try JSONDecoder().decode([Repo].self, from: data)
            }.done {
                self.repos.append(contentsOf: $0)
                self.outlineView.reloadData()
            }
        }

        let p2 = fetchSubs()

        firstly {
            when(fulfilled: p1, p2)
        }.done {
            let (subs, hasReceipt) = $1
            self.subscribed = subs
            self.hasVerifiedReceipt = hasReceipt
            self.outlineView.reloadData()
            self.outlineView.expandItem(nil, expandChildren: true)
        }.catch {
            alert($0)
        }.finally {
            self.fetching = false
        }
    }

    private func hooks(for hookType: HookType) -> Guarantee<Bool> {
        dispatchPrecondition(condition: .onQueue(.main))

        guard let token = creds?.token else {
            return .value(false)
        }
        func get(_ prefix: String) -> Guarantee<Bool> {
            let rq = GitHubAPI(oauthToken: token).request(path: "\(prefix)/hooks")
            return firstly {
                URLSession.shared.dataTask(.promise, with: rq).validate()
            }.map { data, rsp in
                try JSONDecoder().decode([Hook].self, from: data)
            }.recover { error -> Guarantee<[Hook]> in
                print(#function, error)
                return .value([]) //FIXME
            }.map {
                $0.map(\.config.url).contains(hookUri)
            }
        }

        if let promise = hooked[hookType] {
            return promise
        } else {
            let promise: Guarantee<Bool>
            switch hookType {
            case .organization(_, let login):
                promise = get("/orgs/\(login)")
            case .repo(let repo):
                promise = get("/repos/\(repo.full_name)")
            }
            hooked[hookType] = promise
            return promise
        }
    }
}

extension ReposViewController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let login = item as? String {
            return rootedRepos[login]!.count
        } else {
            return rootedRepos.keys.count
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is String
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let login = item as? String {
            return rootedRepos[login]![index]
        } else {
            return rootedReposKeys[index]
        }
    }

    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        if item is String {
            return item
        } else {
            return (item as! Repo).full_name
        }
    }
}

extension ReposViewController: NSOutlineViewDelegate {
    fileprivate enum SwitchState {
        case on
        case off
        case mixed

        init(_ bool: Bool) {
            if bool {
                self = .on
            } else {
                self = .off
            }
        }

        init<T>(_ array: [T], where: (T) -> Bool) {
            guard let first = array.first else {
                self = .off
                return
            }
            let prev = `where`(first)
            for x in array.dropFirst() {
                guard `where`(x) == prev else {
                    self = .mixed
                    return
                }
            }
            self.init(prev)
        }

        var nsControlStateValue: NSControl.StateValue {
            switch self {
            case .on:
                return .on
            case .off:
                return .off
            case .mixed:
                return .mixed
            }
        }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let defaultWebhookExplanation = "Canopy functions via GitHub webhooks"
        notifyButton.isEnabled = false
        installWebhookButton.isEnabled = false
        installWebhookFirstLabel.isHidden = true
        privateReposAdviceLabel.isHidden = true
        webhookExplanation.stringValue = defaultWebhookExplanation

        let hooked: Guarantee<SwitchState>
        guard let selectedItem = self.selectedItem else {
            return
        }

        notifyButton.allowsMixedState = true
        notifyButton.state = state(for: selectedItem).nsControlStateValue
        // otherwise clicking transitions to the “mixed” state
        if notifyButton.state != .mixed {
            notifyButton.allowsMixedState = false
        }

        switch selectedItem {
        case .organization(let id, let login):
            privateReposAdviceLabel.isHidden = rootedRepos[login]!.allSatisfy{ !$0.private }
            installWebhookButton.isEnabled = true
            hooked = hooks(for: .organization(id, login)).map(SwitchState.init)
        case .user(_, let login):
            privateReposAdviceLabel.isHidden = rootedRepos[login]!.allSatisfy{ !$0.private }
            installWebhookButton.isEnabled = false

            let repos = rootedRepos[login]!
            let promises = repos.map{ hooks(for: .repo($0)) }
            let voided = promises.map{ $0.asVoid() }
            hooked = when(guarantees: voided).map { _ -> SwitchState in
                if Set(promises.map{ $0.value! }).count == 1 {
                    return SwitchState(promises[0].value!)
                } else {
                    return .mixed
                }
            }
        case .repo(let repo):
            privateReposAdviceLabel.isHidden = !repo.private
            notifyButton.allowsMixedState = false
            if repo.isPartOfOrganization {
                hooked = hooks(for: .organization(repo.owner.id, repo.owner.login)).map(SwitchState.init)
            } else {
                hooked = hooks(for: .repo(repo)).map(SwitchState.init)
            }
        }

        hooked.done {
            guard selectedItem == self.selectedItem else { return }
            // ^^ verify selectedItem hasn't changed while we were fetching state

            let webhookExplanationText: String
            let webhookButtonEnabled: Bool
            let notifyButtonEnabled: Bool

            switch $0 {
            case .on:
                webhookButtonEnabled = false
                notifyButtonEnabled = true

                switch selectedItem {
                case .organization:
                    webhookExplanationText = "Organization webhook installed"
                case .user:
                    webhookExplanationText = "All children have webhooks installed"
                case .repo(let repo):
                    if repo.isPartOfOrganization {
                        webhookExplanationText = "Webhook installed at organization level"
                    } else {
                        webhookExplanationText = "Webhook installed"
                    }
                }
            case .off:
                notifyButtonEnabled = false

                switch selectedItem {
                case .repo(let repo):
                    if repo.isPartOfOrganization {
                        webhookExplanationText = "Webhook installation is controlled at the organization level"
                        webhookButtonEnabled = false
                    } else if repo.permissions.admin {
                        webhookExplanationText = defaultWebhookExplanation
                        webhookButtonEnabled = true
                    } else {
                        webhookExplanationText = "Contact the repo admin to install the webhook"
                        webhookButtonEnabled = false
                    }
                case .organization(_, let login), .user(_, let login):
                    switch self.rootedRepos[login]!.satisfaction({ $0.permissions.admin }) {
                    case .none:
                        webhookButtonEnabled = false
                        webhookExplanationText = "Contact the repo admin to install the webhook"
                    case .some:
                        webhookButtonEnabled = false
                        webhookExplanationText = "You do not have admin clearance for all repositories"
                    case .all:
                        webhookButtonEnabled = true
                        webhookExplanationText = defaultWebhookExplanation
                    }
                }
            case .mixed:
                notifyButtonEnabled = false
                webhookButtonEnabled = true
                webhookExplanationText = "Some children have webhook installed"
            }

            self.notifyButton.isEnabled = notifyButtonEnabled
            self.webhookExplanation.stringValue = webhookExplanationText
            self.installWebhookButton.isEnabled = webhookButtonEnabled
            self.installWebhookFirstLabel.isHidden = notifyButtonEnabled
        }
    }

    func outlineView(_ outlineView: NSOutlineView, dataCellFor tableColumn: NSTableColumn?, item: Any) -> NSCell? {
        guard let cell = tableColumn?.dataCell(forRow: 0) as? NSTextFieldCell else {
            return nil
        }
        let integrated: Bool
        if let login = item as? String {
            let set = Set(rootedRepos[login]!.map{ subscribed.contains($0.id) })
            if set.count == 1 {
                integrated = set.first!
            } else {
                integrated = false //TODO mixed
            }
        } else {
            integrated = subscribed.contains((item as! Repo).id)
        }
        cell.textColor = integrated
            ? .labelColor
            : .secondaryLabelColor
        return cell
    }
}

private struct Hook: Decodable {
    let id: Int
    let config: Config

    struct Config: Decodable {
        let url: String?
        let content_type: String?
    }
}

private extension Array where Element == Repo {
    var isOrganization: Bool {
        if let first = first, first.isPartOfOrganization {
            return true
        } else {
            return false
        }
    }
}
