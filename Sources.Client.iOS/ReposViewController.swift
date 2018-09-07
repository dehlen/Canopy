import UIKit

class ReposViewController: UITableViewController {
    let mgr = EnrollmentsManager()

    var hasReceipt: Bool {
        set { (UIApplication.shared.delegate as! AppDelegate).hasReceipt = newValue }
        get { return (UIApplication.shared.delegate as! AppDelegate).hasReceipt }
    }

    var repos = SortedArray<Repo>() {
        didSet {
            tableView.reloadData()
        }
    }
    var installations: Set<Int> = [] {
        didSet {
            tableView.reloadData()
        }
    }
    var subscriptions: Set<Int> = [] {
        didSet {
            tableView.reloadData()
        }
    }

    //TODO DUPED
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
    //TODO DUPED ENDS

    override func viewDidLoad() {
        super.viewDidLoad()

        mgr.token = creds?.token
        mgr.delegate = self
        tableView.register(Cell.self, forCellReuseIdentifier: #file)

        NotificationCenter.default.addObserver(self, selector: #selector(fetch), name: .credsUpdated, object: nil)
        //TODO NotificationCenter.default.addObserver(self, selector: #selector(subscriptionPurchased), name: .receiptVerified, object: nil)
    }

    @objc func fetch() {
        mgr.token = creds?.token
        mgr.update()
    }
}

extension ReposViewController/*: UITableViewDataSource*/ {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return rootedRepos.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let key = rootedReposKeys[section]
        return rootedRepos[key]!.count
    }
}

extension ReposViewController/*: UITableViewDelegate*/ {
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let key = rootedReposKeys[indexPath.section]
        let repo = rootedRepos[key]![indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: #file)!
        cell.textLabel?.text = repo.full_name

        let installed = repo.isPartOfOrganization
            ? installations.contains(repo.owner.id)
            : installations.contains(repo.id)

        switch (subscriptions.contains(repo.id), installed) {
        case (true, true):
            cell.accessoryType = .checkmark
        case (false, false), (false, true):
            cell.accessoryType = .none
        case (true, false):
            cell.accessoryType = !mgr.isFetching ? .disclosureIndicator : .none
        }

        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return rootedReposKeys[section]
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let key = rootedReposKeys[indexPath.section]
        let repo = rootedRepos[key]![indexPath.row]
        //let hasHook = installations.contains(repo.isPartOfOrganization ? repo.owner.id : repo.id)

        let vc = RepoViewController(repo: repo, enrolled:
            subscriptions.contains(repo.id) ? .active : repo.permissions.admin ? .feasible : .impossible)
        vc.completion = {
            // otherwise (despite UITableViewController) doesn't happen for some reason
            self.tableView.deselectRow(at: indexPath, animated: true)
        }
        AppDelegate.shared.tabBarController.present(vc, animated: true)
    }
}

extension ReposViewController: EnrollmentsManagerDelegate {
    func enrollmentsManagerDidReset() {
        repos.removeAll()
    }

    func enrollmentsManager(_: EnrollmentsManager, isUpdating: Bool) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = isUpdating
    }

    func enrollmentsManager(_: EnrollmentsManager, append newRepos: [Repo]) {
        repos.insert(contentsOf: newRepos)
    }

    func enrollmentsManager(_: EnrollmentsManager, subscriptions: Set<Int>, hasReceipt: Bool) {
        self.subscriptions = subscriptions
        self.hasReceipt = hasReceipt
    }

    func enrollmentsManager(_: EnrollmentsManager, append installations: Set<Int>) {
        for x in installations {
            self.installations.insert(x)
        }
    }

    func enrollmentsManager(_: EnrollmentsManager, error: Error) {
        alert(error: error)
    }
}

private class Cell: UITableViewCell {
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        label.text = "⚠️"
        label.sizeToFit()
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    override var accessoryType: UITableViewCell.AccessoryType {
        set {
            switch newValue {
            case .disclosureIndicator:
                accessoryView = label
                super.accessoryType = .none
            default:
                accessoryView = nil
                super.accessoryType = newValue
            }
        }
        get {
            return super.accessoryType
        }
    }
}
