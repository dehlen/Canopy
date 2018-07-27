import PromiseKit
import AppKit

class ReposViewController: NSViewController {
    var repos = [Repo]()
    var hooked = [HookType: Guarantee<Bool>]()
    var subscribed = Set<Int>()

    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var notifyButton: NSButton!
    @IBOutlet weak var installWebhookButton: NSButton!
    @IBOutlet weak var webhookExplanation: NSTextField!
    @IBOutlet weak var installWebhookFirstLabel: NSTextField!

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
        case user(String)
    }

    var selectedItem: Foo? {
        guard outlineView.selectedRow != -1 else { return nil }

        let item = outlineView.item(atRow: outlineView.selectedRow)

        if let login = item as? String {
            let repos = rootedRepos[login]!
            if repos.isOrganization {
                let owner = repos[0].owner
                return .organization(owner.id, owner.login)
            } else {
                return .user(login)
            }
        } else {
            return .repo(item as! Repo)
        }
    }

    @IBAction private func toggleNotify(sender: NSButton) {
        guard sender.state == .on else {
            return alert(message: "Can only enable notifications for MVP", title: "Doh")
        }
        guard let token = UserDefaults.standard.gitHubOAuthToken else {
            return alert(message: "No GitHub auth token", title: "Unexpected Error")
        }
        guard let selectedItem = selectedItem else {
            return
        }
        var ids: [Int] {
            switch selectedItem {
            case .organization(_, let login), .user(let login):
                return rootedRepos[login]!.map(\.id)
            case .repo(let repo):
                return [repo.id]
            }
        }

        let prevControlState = sender.state
        sender.isEnabled = false

        let url = URL(string: "\(serverBaseUri)/subscribe")!
        var rq = URLRequest(url: url)
        rq.httpMethod = "POST"
        rq.httpBody = try! JSONEncoder().encode(ids)
        rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        rq.setValue(token, forHTTPHeaderField: "Authorization")
        firstly {
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.done { _ in
            for id in ids {
                self.subscribed.insert(id)
            }
            self.outlineView.reloadData()
        }.catch {
            alert($0)
            sender.state = prevControlState
        }.finally {
            sender.isEnabled = true
        }
    }

    @IBAction private func installWebhook(sender: NSButton) {
        guard let token = UserDefaults.standard.gitHubOAuthToken else {
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
                        "insecure_ssl": "1" //FIXME
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
        case .user(let login):
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

    private var ref: Any?

    override func viewDidLoad() {
        super.viewDidLoad()

        ref = UserDefaults.standard.observe(\.gitHubOAuthToken, options: [.initial, .new, .old]) { [weak self] defaults, change in
            guard change.newValue != nil, change.oldValue != change.newValue else { return }
            self?.fetch()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        if UserDefaults.standard.gitHubOAuthToken == nil {
            performSegue(withIdentifier: "SignIn", sender: self)
        }
    }

    private var fetching = false

    private func fetch() {
        dispatchPrecondition(condition: .onQueue(.main))

        guard !fetching, let token = UserDefaults.standard.gitHubOAuthToken else {
            return
        }

        func fetchSubs() -> Promise<Set<Int>> {
            let url = URL(string: "\(serverBaseUri)/subscribe")!
            var rq = URLRequest(url: url)
            rq.addValue(token, forHTTPHeaderField: "Authorization")
            return firstly {
                URLSession.shared.dataTask(.promise, with: rq).validate()
            }.map {
                Set(try JSONDecoder().decode([Int].self, from: $0.data))
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
        }.done { _, subs in
            self.subscribed = subs
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

        guard let token = UserDefaults.standard.gitHubOAuthToken else {
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
    enum SwitchState {
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
        installWebhookButton.isEnabled = false
        installWebhookFirstLabel.isHidden = true
        webhookExplanation.stringValue = "Canopy functions via GitHub webhooks"

        let hooked: Guarantee<SwitchState>
        guard let selectedItem = self.selectedItem else {
            notifyButton.isEnabled = false
            return
        }

        notifyButton.isEnabled = true
        notifyButton.allowsMixedState = true

        switch selectedItem {
        case .organization(let id, let login):
            installWebhookButton.isEnabled = true
            notifyButton.state = SwitchState(rootedRepos[login]!, where: { subscribed.contains($0.id) }).nsControlStateValue
            hooked = hooks(for: .organization(id, login)).map(SwitchState.init)
        case .user(let login):
            installWebhookButton.isEnabled = false

            let repos = rootedRepos[login]!
            notifyButton.state = SwitchState(repos, where: { subscribed.contains($0.id) }).nsControlStateValue

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
            notifyButton.allowsMixedState = false
            notifyButton.state = SwitchState(subscribed.contains(repo.id)).nsControlStateValue
            guard !repo.isOrganization else {
                webhookExplanation.stringValue = "Webhook is controlled at organization level"
                return
            }
            hooked = hooks(for: .repo(repo)).map(SwitchState.init)
        }

        // otherwise clicking transitions to the “mixed” state
        if notifyButton.state != .mixed {
            notifyButton.allowsMixedState = false
        }

        hooked.done {
            guard selectedItem == self.selectedItem else { return }
            // ^^ verify selectedItem hasn't changed while we were fetching state

            switch $0 {
            case .on:
                switch selectedItem {
                case .organization:
                    self.webhookExplanation.stringValue = "Organization webhook installed"
                case .user:
                    self.webhookExplanation.stringValue = "All children have webhooks installed"
                case .repo:
                    self.webhookExplanation.stringValue = "Webhook installed"
                }
                self.installWebhookButton.isEnabled = false
            case .off:
                self.installWebhookButton.isEnabled = true
                self.notifyButton.isEnabled = false
                self.installWebhookFirstLabel.isHidden = false
            case .mixed:
                self.installWebhookButton.isEnabled = true
                self.webhookExplanation.stringValue = "Some children have webhook installed"
            }
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
        if let first = first, first.isOrganization {
            return true
        } else {
            return false
        }
    }
}
