import UserNotifications
import PromiseKit
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var hasReceipt = false

    static var shared: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        PromiseKit.conf.Q.map = .global()
        return true
    }

    var tabBarController: UITabBarController {
        return window!.rootViewController as! UITabBarController
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow()
        window!.rootViewController = UITabBarController()
        setupTabBar()
        window!.makeKeyAndVisible()

    #if !targetEnvironment(simulator)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, error in
            DispatchQueue.main.async(execute: application.registerForRemoteNotifications)
        }
    #endif

        return true
    }

    func setupTabBar() {
        let repos = ReposViewController(style: .grouped)
        repos.title = "Canopy"
        let settings = AccountViewController(style: .grouped)
        settings.title = "Account"
        let ncs = [repos, settings].map(UINavigationController.init)
        tabBarController.setViewControllers(ncs, animated: false)
        ncs[0].tabBarItem.title = "Repositories"
    }

#if !targetEnvironment(simulator)
    var deviceToken: String?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken rawDeviceToken: Data) {

        deviceToken = String(deviceToken: rawDeviceToken)

        if let oauthToken = creds?.token, let deviceToken = deviceToken {
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
#endif
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        alert(error: error)
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let token = userInfo["token"] as? String, let login = userInfo["login"] as? String {
            creds = (login, token)

            let content = UNMutableNotificationContent()
            content.title = "Authentication Complete"
            content.body = "Tap to return to Canopy"
            let rq = UNNotificationRequest(identifier: "foo", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(rq) { _ in
                completionHandler(.newData)
            }
        } else if let message = userInfo["error"] as? String {
            alert(message: message, title: "GitHub Authorization Failed")
            //TODO allow sign-in again somehow
            completionHandler(.failed)
        } else {
            print(userInfo)
            completionHandler(.noData)
        }
    }
}
