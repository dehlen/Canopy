import UserNotifications
import PromiseKit
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, willFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        PromiseKit.conf.Q.map = .global()
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow()
        window!.rootViewController = ViewController()
        window!.makeKeyAndVisible()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, error in
            DispatchQueue.main.async(execute: application.registerForRemoteNotifications)
        }

        return true
    }

    var deviceToken: String?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken rawDeviceToken: Data) {
        deviceToken = String(deviceToken: rawDeviceToken)

        if let oauthToken = UserDefaults.standard.gitHubOAuthToken, let deviceToken = deviceToken {
            firstly {
                updateTokens(oauth: oauthToken, device: deviceToken)
            }.catch {
                alert(error: $0)
            }
        } else if let deviceToken = deviceToken {
            let sheet = UIAlertController(title: "Sign‑in to GitHub", message: nil, preferredStyle: .actionSheet)
            sheet.addAction(.init(title: "Open Safari", style: .default, handler: { _ in
                if let url = URL.signIn(deviceToken: deviceToken) {
                    UIApplication.shared.open(url)
                }
            }))
            window!.rootViewController!.present(sheet, animated: true)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        alert(error: error)
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let oauthToken = userInfo["oauthToken"] as? String {
            UserDefaults.standard.gitHubOAuthToken = oauthToken

            let content = UNMutableNotificationContent()
            content.title = "Authentication Complete"
            content.body = "Tap to return to Canopy"
            let rq = UNNotificationRequest(identifier: "foo", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(rq) { _ in
                completionHandler(.newData)
            }
        } else if let message = userInfo["oauthTokenError"] as? String {
            alert(message: message, title: "GitHub Authorization Failed")
            //TODO allow sign-in again somehow
            completionHandler(.failed)
        } else {
            print(userInfo)
            completionHandler(.noData)
        }
    }
}
