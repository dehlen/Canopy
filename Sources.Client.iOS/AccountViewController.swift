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
        case _:
            return "App Store Subscription"
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            return "Signs out of Canopy on all devices."
        } else if AppDelegate.shared.hasReceipt {
            return "You can manage your subscription in the iPhone Settings app."
        } else {
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
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
    case restorePurchases

    var title: String {
        switch self {
        case .signOut:
            return "Sign Out"
        case .subscriptionActive:
            if AppDelegate.shared.hasReceipt {
                return "Subscribed, renewing monthly"
            } else {
                return "Not subscribed"
            }
        case .restorePurchases:
            return "Restore Purchases"
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
        case .restorePurchases:
            return IndexPath(row: 1, section: 1)
        }
    }

    var canSelect: Bool {
        switch self {
        case .signOut, .restorePurchases:
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
