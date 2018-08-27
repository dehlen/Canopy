import PromiseKit
import AppKit

@NSApplicationMain
class AppDelegate: NSObject {
    weak var window: NSWindow!
    weak var subscribeViewController: SubscribeViewController?

    @objc dynamic var deviceToken: String?

    func processRemoteNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
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
        window.contentViewController?.performSegue(withIdentifier: "PaymentPrompt", sender: sender)
    }

    @IBAction func openPrivacyPolicy(sender: Any) {
        let url = URL(string: "https://codebasesaga.com/canopy/#privacy-policy")!
        NSWorkspace.shared.open(url)
    }

    @IBAction func openITunesSubscriptionManager(sender: Any) {
        let url = URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/manageSubscriptions")!
        NSWorkspace.shared.open(url)
    }

    @IBAction func openTermsOfUse(sender: Any) {
        let url = URL(string: "https://codebasesaga.com/canopy/#terms-of-use")!
        NSWorkspace.shared.open(url)
    }

    @IBOutlet var createSubscriptionMenuItem: NSMenuItem!
    @IBOutlet var manageSubscriptionMenuItem: NSMenuItem!
}

var app: AppDelegate {
    return NSApp.delegate as! AppDelegate
}
