import PromiseKit
import AppKit

class ReposViewController: NSViewController {
    var repos = SortedArray<Repo>()
    var hooked = Set<Node>()
    var fetching = false
    var subscribed = Set<Int>()

    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var mainColumn: NSTableColumn!
    @IBOutlet weak var statusColumn: NSTableColumn!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var notifyButton: NSButton!
    @IBOutlet weak var versionLabel: NSTextField!

    var hasVerifiedReceipt: Bool {
        return app.hasVerifiedReceipt
    }

    var rootedRepos: [String: [Repo]] {
        return Dictionary(grouping: repos, by: { $0.owner.login })
    }

    var rootedReposKeys: [String] {
        return rootedRepos.keys.map{ ($0, $0.lowercased()) }.sorted{ $0.1 < $1.1 }.map{ $0.0 }
    }

    var nodes: Set<Node> {
        return Set(repos.map { repo in
            if repo.isPartOfOrganization {
                return .organization(repo.owner.login)
            } else {
                return .init(repo)
            }
        })
    }

    var selectedItem: OutlineViewItem? {
        guard outlineView.selectedRow != -1 else { return nil }

        let item = outlineView.item(atRow: outlineView.selectedRow)

        if let login = item as? String {
            let repos = rootedRepos[login]!
            if repos.isOrganization {
                let owner = repos[0].owner  // safe as we wouldn't show anything if empty
                return .organization(owner.login)
            } else {
                return .user(login)
            }
        } else {
            return .repo(item as! Repo)
        }
    }

    func requiresReceipt(item: OutlineViewItem) -> Bool {
        switch item {
        case .organization(let login), .user(let login):
            return rootedRepos[login]!.satisfaction{ $0.private } != .none
        case .repo(let repo):
            return repo.private
        }
    }

    func paymentPrompt() {
        performSegue(withIdentifier: "PaymentPrompt", sender: self)
    }

    func state(for item: OutlineViewItem) -> SwitchState {
        switch item {
        case .organization(let login), .user(let login):
            return SwitchState(rootedRepos[login]!, where: { subscribed.contains($0.id) })
        case .repo(let repo):
            return subscribed.contains(repo.id) ? .on : .off
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(fetch), name: .credsUpdated, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        if creds == nil {
            performSegue(withIdentifier: "SignIn", sender: self)
        } else {
            fetch()
        }
    }

    @IBAction func addManualSubscription(sender: Any) {
        let tf = NSTextField(frame: CGRect(x: 0, y: 0, width: 200, height: 24))
        tf.placeholderString = "owner/repository"

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Add Repository"
        alert.informativeText = "Get updates for any repository that has the Canopy webhook installed."
        alert.accessoryView = tf
        alert.addButton(withTitle: "Add").tag = NSApplication.ModalResponse.OK.rawValue
        alert.addButton(withTitle: "Cancel").tag = NSApplication.ModalResponse.cancel.rawValue
        alert.beginSheetModal(for: view.window!) { rsp in
            if rsp == .OK {
                self.add(repoFullName: tf.stringValue)
            }
        }
    }

    @IBAction func showHelp(_ sender: Any) {
        if let url = URL(string: "https://codebasesaga.com/canopy/#faq") {
            NSWorkspace.shared.open(url)
        }
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
