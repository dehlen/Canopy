import UIKit

class AccountViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(InformationCell.self, forCellReuseIdentifier: "a")
        tableView.register(ButtonCell.self, forCellReuseIdentifier: "b")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Row.allCases.map(\.indexPath.section).distinctCount
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return Row.allCases.filter{ $0.indexPath.section == section }.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = Row(indexPath)!
        let cell: UITableViewCell
        if row.canSelect {
            cell = tableView.dequeueReusableCell(withIdentifier: "b")!
        } else {
            cell = tableView.dequeueReusableCell(withIdentifier: "a")!
        }
        cell.textLabel?.text = row.title
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "GitHub"
        case 1:
            return "App Store Subscription"
        case 2:
            return "Legal"
        default:
            fatalError()
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 2 {
            return "Free icons provided by Icons8."
        } else {
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Row(indexPath) {
        case .restoreOrManage?:
            if AppDelegate.shared.hasReceipt {
                let url = URL(string: "itmss://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/manageSubscriptions")!
                UIApplication.shared.open(url)
            } else {
                #warning("TODO")
            }
        case .icons8?:
            UIApplication.shared.open(URL(string: "https://icons8.com")!)
        default:
            break
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UIView.performWithoutAnimation {
            tableView.reloadSections([Row.subscriptionActive.indexPath.section], with: .none)
        }
    }
}

private class ButtonCell: UITableViewCell {
    override func layoutSubviews() {
        super.layoutSubviews()
        textLabel?.textAlignment = .center
        textLabel?.textColor = UIButton(type: .system).tintColor
        textLabel?.frame = bounds
    }
}

private class InformationCell: UITableViewCell {
    override func layoutSubviews() {
        super.layoutSubviews()
        textLabel?.textColor = .gray
        selectionStyle = .none
    }
}

private enum Row: CaseIterable {
    case signOut
    case subscriptionActive
    case restoreOrManage
    case icons8

    var title: String {
        switch self {
        case .signOut:
            return "Sign Out"
        case .subscriptionActive:
            if AppDelegate.shared.hasReceipt {
                return "✅ Subscribed"
            } else {
                return "Not subscribed"
            }
        case .restoreOrManage:
            if AppDelegate.shared.hasReceipt {
                return "Manage Subscription"
            } else {
                return "Restore Purchases"
            }
        case .icons8:
            return "https://icons8.com"
        }
    }

    init!(_ indexPath: IndexPath) {
        for x in type(of: self).allCases {
            if indexPath == x.indexPath {
                self = x
                return
            }
        }
        return nil
    }

    var indexPath: IndexPath {
        switch self {
        case .signOut:
            return IndexPath(row: 0, section: 0)
        case .subscriptionActive:
            return IndexPath(row: 0, section: 1)
        case .restoreOrManage:
            return IndexPath(row: 1, section: 1)
        case .icons8:
            return IndexPath(row: 0, section: 2)
        }
    }

    var canSelect: Bool {
        switch self {
        case .signOut, .restoreOrManage, .icons8:
            return true
        case .subscriptionActive:
            return false
        }
    }
}

private extension Collection where Element: Hashable {
    var distinctCount: Int {
        var set = Set<Element>()
        for x in self { set.insert(x) }
        return set.count
    }
}
