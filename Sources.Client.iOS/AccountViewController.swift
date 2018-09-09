import SafariServices
import MessageUI
import UIKit

class AccountViewController: UITableViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(InformationCell.self, forCellReuseIdentifier: "a")
        tableView.register(ButtonCell.self, forCellReuseIdentifier: "b")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
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
        switch row.state {
        case .button:
            cell = tableView.dequeueReusableCell(withIdentifier: "b")!
        case .disclosure:
            cell = tableView.dequeueReusableCell(withIdentifier: "c")!
            cell.accessoryType = .disclosureIndicator
        case .dead:
            cell = tableView.dequeueReusableCell(withIdentifier: "a")!
        }
        cell.textLabel?.text = row.title
        return cell
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return "Help"
        case 1:
            return "GitHub"
        case 2:
            return "App Store Subscription"
        case 3:
            return "Legal"
        default:
            fatalError()
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 3 {
            return "Free icons provided by Icons8."
        } else {
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Row(indexPath) {
        case nil:
            break
        case .restoreOrManage?:
            if AppDelegate.shared.subscriptionManager.hasVerifiedReceipt {
                let url = URL(string: "itmss://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/manageSubscriptions")!
                UIApplication.shared.open(url)
            } else {
                let vc = UIStoryboard(name: "SubscribeViewController", bundle: nil).instantiateInitialViewController()!
                AppDelegate.shared.tabBarController.present(vc, animated: true)
            }
        case .faq?:
            present(SFSafariViewController(url: .faq), animated: true)
        case .support?:
            if MFMailComposeViewController.canSendMail() {
                let vc = MFMailComposeViewController()
                vc.setToRecipients(["support@codebasesaga.com"])
                promise(vc).cauterize()
            } else {
                UIPasteboard.general.string = "support@codebasesaga.com"
                alert(message: "We have copied the support email address to your clipboard, paste it into your email client to contact support.")
            }
        case .icons8?:
            UIApplication.shared.open(URL(string: "https://icons8.com")!)
        case .signInOut?:
            if creds == nil {
                show(SignInViewController(), sender: self)
            } else {
                AppDelegate.shared.signOut()
            }
        case .subscriptionActive?:
            break
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        UIView.performWithoutAnimation {
            tableView.reloadSections([Row.subscriptionActive.indexPath.section], with: .none)
            tableView.reloadSections([Row.signInOut.indexPath.section], with: .none)
        }
    }
}

private class ButtonCell: UITableViewCell {
    override func layoutSubviews() {
        super.layoutSubviews()
        textLabel?.frame = bounds
    }

    override func tintColorDidChange() {
        textLabel?.textAlignment = .center
        textLabel?.textColor = tintColor
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
    case faq
    case support
    case signInOut
    case subscriptionActive
    case restoreOrManage
    case icons8

    var title: String {
        switch self {
        case .faq:
            return "FAQ"
        case .support:
            return "support@codebasesaga.com"
        case .signInOut:
            return creds == nil ? "Sign In…" : "Sign Out"
        case .subscriptionActive:
            if AppDelegate.shared.subscriptionManager.hasVerifiedReceipt {
                return "✅ Subscribed"
            } else {
                return "Not subscribed"
            }
        case .restoreOrManage:
            if AppDelegate.shared.subscriptionManager.hasVerifiedReceipt {
                return "Manage Subscription…"
            } else {
                return "Subscribe / Restore…"
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
        case .faq:
            return IndexPath(row: 0, section: 0)
        case .support:
            return IndexPath(row: 1, section: 0)
        case .signInOut:
            return IndexPath(row: 0, section: 1)
        case .subscriptionActive:
            return IndexPath(row: 0, section: 2)
        case .restoreOrManage:
            return IndexPath(row: 1, section: 2)
        case .icons8:
            return IndexPath(row: 0, section: 3)
        }
    }

    enum State {
        case button
        case disclosure
        case dead
    }

    var state: State {
        switch self {
        case .signInOut, .restoreOrManage, .support:
            return .button
        case .faq, .icons8:
            return .disclosure
        case .subscriptionActive:
            return .dead
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
