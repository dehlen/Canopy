import AppKit
import Cake

@NSApplicationMain
class AppDelegate: NSObject {
    @objc dynamic var deviceToken: String?

    var ref: NSKeyValueObservation?
    var subscriptionManager: SubscriptionManager!

    weak var subscribeViewController: SubscribeViewController?

    static var shared: AppDelegate {
        return NSApp.delegate as! AppDelegate
    }

    @discardableResult
    func processRemoteNotificationUserInfo(_ userInfo: [AnyHashable: Any]) -> Bool {
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return true
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
            NSApp.terminate(sender)
        }.catch {
            alert(error: $0)
        }
    }

    @IBAction func showSubscriptionSheet(sender: Any) {
        NSApp.mainWindow?.contentViewController?.performSegue(withIdentifier: "PaymentPrompt", sender: sender)
    }

    @IBAction func openPrivacyPolicy(sender: Any) {
        NSWorkspace.shared.open(.privacyPolicy)
    }

    @IBAction func openITunesSubscriptionManager(sender: Any) {
        NSWorkspace.shared.open(.manageSubscription)
    }

    @IBAction func openTermsOfUse(sender: Any) {
        NSWorkspace.shared.open(.termsOfUse)
    }

    @IBAction func openFAQ(sender: Any) {
        NSWorkspace.shared.open(.faq)
    }

    @IBAction func openHomepage(sender: Any) {
        NSWorkspace.shared.open(.home)
    }

    @IBOutlet var createSubscriptionMenuItem: NSMenuItem!
    @IBOutlet var manageSubscriptionMenuItem: NSMenuItem!
}

var app: AppDelegate {
    return NSApp.delegate as! AppDelegate
}

extension AppDelegate: SubscriptionManagerDelegate {
    func subscriptionFinished(error: Error?, file: StaticString, line: UInt) {
        if let subscribeViewController = subscribeViewController {
            subscribeViewController.errorHandler(error: error, line: line)
        } else if let error = error {
            alert(error: error, file: file, line: line)
        }
    }
}
