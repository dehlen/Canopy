import PromiseKit
import UIKit

class ReposViewController: UITableViewController {
    let mgr = EnrollmentsManager()

    override func viewDidLoad() {
        super.viewDidLoad()

        mgr.token = creds?.token
        mgr.delegate = self
        tableView.register(Cell.self, forCellReuseIdentifier: #file)

        NotificationCenter.default.addObserver(self, selector: #selector(fetch), name: .credsUpdated, object: nil)
    }

    @objc func fetch() {
        mgr.token = creds?.token
    }

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.isTracking {
            presentedViewController?.dismiss(animated: false)
            // if animated is true the animation blocks scroll events which is jarring
        }
    }

    func showZeroPopover() {
        var firstCell: UITableViewCell? {
            // avoid returning cells that are partly or fully under the top or bottom bars
            return tableView.visibleCells.first(where: { (cell) -> Bool in
                return view.bounds.inset(by: view.safeAreaInsets).contains(cell.frame)
            })
        }

        guard presentedViewController == nil, let cell = firstCell else {
            return
        }

        class Popover: UIViewController, UIPopoverPresentationControllerDelegate {
            let label = UILabel()

            override func viewDidLoad() {

                let p = NSMutableParagraphStyle()
                p.lineSpacing = 2

                let s = NSMutableAttributedString(string: """
                    Welcome! To get started receiving real‐time GitHub notifications, tap any repository.
                    """, attributes: [.paragraphStyle: p])
                s.addAttributes([.font: UIFont.boldSystemFont(ofSize: label.font.pointSize)], range: NSRange(location: 0, length: 8))

                label.numberOfLines = 0
                label.attributedText = s
                label.translatesAutoresizingMaskIntoConstraints = false
                label.textColor = .white
                view.addSubview(label)
                NSLayoutConstraint.activate([
                    label.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
                    label.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 16),
                    label.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -16),
                    label.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
                ])

                var fittingSize = UIView.layoutFittingCompressedSize
                fittingSize.width = 200
                preferredContentSize = view.systemLayoutSizeFitting(fittingSize, withHorizontalFittingPriority: .required, verticalFittingPriority: .defaultLow)

                view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close)))
            }

            @objc func close() {
                dismiss(animated: true)
            }

            func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
                return .none
            }
        }

        let popover = Popover()
        popover.modalPresentationStyle = .popover
        guard let pc = popover.popoverPresentationController else { return }
        pc.delegate = popover
        pc.sourceView = cell
        pc.sourceRect = cell.bounds.inset(by: UIEdgeInsets(top: 5, left: cell.bounds.width - 60, bottom: 5, right: 20))
        pc.permittedArrowDirections = [.up]
        pc.backgroundColor = UIColor.canopyGreen
        pc.passthroughViews = tableView.visibleCells
        present(popover, animated: true)
    }
}

extension ReposViewController/*: UITableViewDataSource*/ {
    override func numberOfSections(in tableView: UITableView) -> Int {
        return mgr.rootedRepos.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let key = mgr.rootedReposKeys[section]
        return mgr.rootedRepos[key]!.count
    }
}

extension ReposViewController/*: UITableViewDelegate*/ {
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let key = mgr.rootedReposKeys[indexPath.section]
        let repo = mgr.rootedRepos[key]![indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: #file)!
        cell.textLabel?.text = repo.full_name

        let installed = repo.isPartOfOrganization
            ? mgr.hooks.contains(repo.owner.id)
            : mgr.hooks.contains(repo.id)

        switch (mgr.enrollments.contains(repo.id), installed) {
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
        return mgr.rootedReposKeys[section]
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let key = mgr.rootedReposKeys[indexPath.section]
        let repo = mgr.rootedRepos[key]![indexPath.row]

        let vc = RepoViewController(repo: repo, enrolled:
            mgr.enrollments.contains(repo.id) ? .active : repo.permissions.admin ? .feasible : .impossible)
        vc.completion = { [weak tableView] in
            // otherwise (despite UITableViewController) doesn't happen for some reason
            tableView?.deselectRow(at: indexPath, animated: true)
        }

        var ref: Any?

        vc.toggle = { [unowned vc] _ in
            vc.knob.isUserInteractionEnabled = false  // not isEnabled as does confusing UI state animation
            UIApplication.shared.isNetworkActivityIndicatorVisible = true

            firstly {
                try self.mgr.enroll(repo: repo)
            }.catch {
                switch $0 {
                case EnrollmentsManager.Error.paymentRequired:
                    vc.knob.isOn.toggle()  // restore state

                    let sb = UIStoryboard(name: "SubscribeViewController", bundle: nil)
                    let svc = sb.instantiateInitialViewController()!
                    ref = AppDelegate.shared.subscriptionManager.observe(\.hasVerifiedReceipt) { [weak vc] mgr, _ in
                        guard mgr.hasVerifiedReceipt, let vc = vc, let toggle = vc.toggle else { return }
                        vc.knob.isOn = true
                        toggle(true)  // should be safe recursion…
                    }
                    _ = ref // suppress swift warning

                    vc.present(svc, animated: true)

                case API.Enroll.Error.hookCreationFailed:
                    // couldn't create hook BUT we are still subb’d ready for
                    // when hook is enabled so we don’t toggle the knob
                    alert(error: $0)
                default:
                    vc.knob.isOn.toggle()  // restore state
                    alert(error: $0)
                }
            }.finally { [weak vc] in
                vc?.knob.isUserInteractionEnabled = true
                UIApplication.shared.isNetworkActivityIndicatorVisible = false
            }
        }

        func go() {
            AppDelegate.shared.tabBarController.present(vc, animated: true)
        }

        // have to dismiss the onboarding-popover first if it's up
        if let ovc = presentedViewController {
            ovc.dismiss(animated: true, completion: go)
        } else {
            go()
        }
    }
}

extension ReposViewController: EnrollmentsManagerDelegate {
    func enrollmentsManager(_: EnrollmentsManager, isUpdating: Bool) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = isUpdating
    }

    func enrollmentsManagerDidUpdate(_ mgr: EnrollmentsManager) {
        tableView.reloadData()

        if mgr.enrollments.isEmpty, !mgr.isFetching {
            showZeroPopover()
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
