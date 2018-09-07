import UserNotifications
import PromiseKit
import UIKit

@UIApplicationMain
class AppDelegate: UIResponder {
    var window: UIWindow?
    var hasReceipt = false
#if !targetEnvironment(simulator)
    var deviceToken: String?
#endif

    static var shared: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }

    var tabBarController: UITabBarController {
        return window!.rootViewController as! UITabBarController
    }

    var reposViewController: ReposViewController? {
        return (tabBarController.viewControllers?.first as? UINavigationController)?.viewControllers.first as? ReposViewController
    }
}

extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication, willFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        PromiseKit.conf.Q.map = .global()
        return true
    }


    func application(_ application: UIApplication, didFinishLaunchingWithOptions opts: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow()
        window!.rootViewController = UITabBarController()
        setupTabBar()
        window!.makeKeyAndVisible()
        window!.tintColor = UIColor(red: 0.15, green: 0.75, blue: 0.15, alpha: 1)

    #if !targetEnvironment(simulator)
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, error in
            DispatchQueue.main.async(execute: application.registerForRemoteNotifications)
        }
    #else
        alert(message: "Nothing works in simulator! Run on device!")
    #endif

        return true
    }

    func setupTabBar() {
        let repos = ReposViewController(style: .grouped)
        repos.title = "Canopy"
        repos.tabBarItem.image = UIImage(named: "UITabBarOctocat")
        let settings = AccountViewController(style: .grouped)
        settings.title = "Account"
        settings.tabBarItem.image = UIImage(named: "UITabBarAccount")
        let ncs = [repos, settings].map(UINavigationController.init)
        tabBarController.setViewControllers(ncs, animated: false)
        ncs[0].tabBarItem.title = "Repositories"
    }

#if !targetEnvironment(simulator)
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

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        switch RemoteNotificationUserInfo(userInfo: userInfo) {
        case .creds(let login, let token):
            creds = (username: login, token: token)

            let content = UNMutableNotificationContent()
            content.title = "Authentication Complete"
            content.body = "Tap to return to Canopy"
            let rq = UNNotificationRequest(identifier: "foo", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(rq) { _ in
                completionHandler(.newData)
            }

        case .error(let message, .authentication?):
            if creds == nil {
                fallthrough
            }
            // else… ignore. mostly happens because: user left auth page open
            // and this causes a POST to our auth endpoint, but the code was
        // consumed so GitHub errors
        case .error(let message, nil):
            alert(message: message, title: "GitHub Authorization Failed")
            completionHandler(.failed)
        case .unknown:
            print(userInfo)
            completionHandler(.noData)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let urlstr = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: urlstr) {
            UIApplication.shared.open(url)
        }
    }
}
