import PromiseKit
import AppKit

@NSApplicationMain
class AppDelegate: NSObject {
    @objc dynamic var hasVerifiedReceipt = false
    @objc dynamic var deviceToken: String?

    var ref: NSKeyValueObservation?

    weak var subscribeViewController: SubscribeViewController?

    @discardableResult
    func processRemoteNotificationUserInfo(_ userInfo: [AnyHashable: Any]) -> Bool {
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            return NSWorkspace.shared.open(url)
        } else {
            return false
        }
    }

    @IBAction func signOut(sender: Any) {
        var rq = URLRequest(.token)
        rq.httpMethod = "DELETE"
        rq.httpBody = deviceToken?.data(using: .utf8)

        firstly {
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.done { _ in
            creds = nil
        }.catch {
            alert($0)
        }
    }

    @IBAction func showSubscriptionSheet(sender: Any) {
        NSApp.mainWindow?.contentViewController?.performSegue(withIdentifier: "PaymentPrompt", sender: sender)
    }

    @IBAction func openPrivacyPolicy(sender: Any) {
        NSWorkspace.shared.open(.privacyPolicy)
    }

    @IBAction func openITunesSubscriptionManager(sender: Any) {
        let url = URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/manageSubscriptions")!
        NSWorkspace.shared.open(url)
    }

    @IBAction func openTermsOfUse(sender: Any) {
        NSWorkspace.shared.open(.termsOfUse)
    }

    @IBAction func openFAQ(sender: Any) {
        NSWorkspace.shared.open(.faq)
    }

    @IBOutlet var createSubscriptionMenuItem: NSMenuItem!
    @IBOutlet var manageSubscriptionMenuItem: NSMenuItem!
}

var app: AppDelegate {
    return NSApp.delegate as! AppDelegate
}
