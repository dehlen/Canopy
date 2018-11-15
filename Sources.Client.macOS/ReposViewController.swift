import PromiseKit
import AppKit

class ReposViewController: NSViewController {
    let mgr = EnrollmentsManager()

    var repos: SortedSet<Repo> { return mgr.repos }
    var hooked: Set<Int> { return mgr.hooks }
    var fetching: Bool { return mgr.isFetching }
    var subscribed: Set<Int> { return mgr.enrollments }
    var rootedRepos: [String: [Repo]] { return mgr.rootedRepos }
    var rootedReposKeys: [String] { return mgr.rootedReposKeys }
    var nodes: Set<Node> { return mgr.nodes }

    @IBOutlet weak var outlineView: NSOutlineView!
    @IBOutlet weak var mainColumn: NSTableColumn!
    @IBOutlet weak var statusColumn: NSTableColumn!
    @IBOutlet weak var statusLabel: NSTextField!
    @IBOutlet weak var notifyButton: NSButton!
    @IBOutlet weak var versionLabel: NSTextField!

    var hasVerifiedReceipt: Bool {
        return app.subscriptionManager.hasVerifiedReceipt
    }


    var selectedItem: OutlineViewItem? {
        guard outlineView.selectedRow != -1 else { return nil }

        let item = outlineView.item(atRow: outlineView.selectedRow)

        if let login = item as? String {
            let repos = rootedRepos[login]!
            if repos.isOrganization {
                let owner = repos[0].owner  // safe as we wouldn't show anything if empty
                return .organization(login: owner.login, id: owner.id)
            } else {
                return .user(login)
            }
        } else {
            return .repo(item as! Repo)
        }
    }

    func requiresReceipt(item: OutlineViewItem) -> Bool {
        switch item {
        case .organization(let login, _), .user(let login):
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
        case .organization(let login, _), .user(let login):
            return SwitchState(rootedRepos[login]!, where: { subscribed.contains($0.id) })
        case .repo(let repo):
            return subscribed.contains(repo.id) ? .on : .off
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        mgr.delegate = self
        NotificationCenter.default.addObserver(mgr, selector: #selector(EnrollmentsManager.update), name: .credsUpdated, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        if let creds = creds {
            mgr.token = creds.token
            mgr.update()
        } else {
            performSegue(withIdentifier: "SignIn", sender: self)
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
            guard rsp == .OK else { return }

            self.mgr.add(repoFullName: tf.stringValue).done { repo in
                self.outlineView.reloadData()
                let row = self.outlineView.row(forItem: repo)
                self.outlineView.scrollRowToVisible(row)
                self.outlineView.selectRowIndexes([row], byExtendingSelection: false)
            }.catch {
                Canopy.alert(error: $0)
            }
        }
    }

    @IBAction func showHelp(_ sender: Any) {
        NSWorkspace.shared.open(.faq)
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

extension ReposViewController: EnrollmentsManagerDelegate {
    func enrollmentsManager(_: EnrollmentsManager, isUpdating: Bool) {
        //TODO
    }

    func enrollmentsManagerDidUpdate(_ mgr: EnrollmentsManager, expandTree: Bool) {
        outlineView.reloadData()
        if expandTree {
            outlineView.expandItem(nil, expandChildren: true)
        }
    }

    func enrollmentsManager(_: EnrollmentsManager, error: Error) {
        alert(error: error)
    }
}
