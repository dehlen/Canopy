import UserNotifications
import UIKit
import Cake

@UIApplicationMain
class AppDelegate: UIResponder {
    var window: UIWindow?
#if !targetEnvironment(simulator)
    @objc dynamic var deviceToken: String?
#endif

    var subscriptionManager: SubscriptionManager!
    var subscribeViewController: SubscribeViewController_iOS?

    static var shared: AppDelegate {
        return UIApplication.shared.delegate as! AppDelegate
    }

    var tabBarController: UITabBarController {
        return window!.rootViewController as! UITabBarController
    }

    var reposViewController: ReposViewController? {
        return (tabBarController.viewControllers?.first as? UINavigationController)?.viewControllers.first as? ReposViewController
    }

    var signInViewController: SignInViewController? {
        return (tabBarController.viewControllers?[safe: 1] as? UINavigationController)?.viewControllers.last as? SignInViewController
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
        window!.tintColor = .canopyGreen

    #if !targetEnvironment(simulator)
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().getNotificationSettings {
            switch $0.authorizationStatus {
            case .notDetermined:
                if creds != nil {
                    fallthrough  // already logged in via mac app or previous installation, let’s ask!
                }
            case .authorized, .provisional:
                Promise { seal in
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: seal.resolve)
                }.done { _ in
                    application.registerForRemoteNotifications()
                }.cauterize()
            case .denied:
                break
            }
        }
    #else
        print("warning: nothing works in the simulator!")
    #endif

        subscriptionManager = SubscriptionManager()
        subscriptionManager.delegate = self

        if creds == nil {
            signOut()
        }

        return true
    }

    func signOut() {
        let vc = SignInViewController()
        tabBarController.viewControllers![1].show(vc, sender: self)
        tabBarController.viewControllers![0].tabBarItem.isEnabled = false
        tabBarController.selectedIndex = 1
        creds = nil
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        //TODO probably should just react to the registration of the creds

        if creds != nil, let nc = signInViewController?.navigationController, let vc = reposViewController {
            nc.popToRootViewController(animated: false)
            vc.tabBarItem.isEnabled = true
            tabBarController.selectedIndex = 0
        }
    }

    func setupTabBar() {
        let repos = ReposViewController(style: .grouped)
        repos.title = "Repositories"
        repos.tabBarItem.image = UIImage(named: "UITabBarOctocat")
        let settings = AccountViewController(style: .grouped)
        settings.title = "Account"
        settings.tabBarItem.image = UIImage(named: "UITabBarAccount")
        let ncs = [repos, settings].map(UINavigationController.init)
        ncs[0].navigationBar.prefersLargeTitles = true
        ncs[1].navigationBar.prefersLargeTitles = true
        tabBarController.setViewControllers(ncs, animated: false)
        ncs[0].tabBarItem.title = "Repositories"
    }

#if !targetEnvironment(simulator)
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken rawDeviceToken: Data) {
        deviceToken = String(deviceToken: rawDeviceToken)
        postTokens()
    }

    func postTokens() {
        if let oauthToken = creds?.token, let deviceToken = deviceToken {
            updateTokens(oauth: oauthToken, device: deviceToken).cauterize()
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
            UIApplication.shared.open(url) { _ in
                completionHandler()
            }
        } else {
            completionHandler()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .badge, .sound])
    }
}

extension AppDelegate: SubscriptionManagerDelegate {
    func subscriptionFinished(error: Error?, file: StaticString, line: UInt) {
        guard let subscribeViewController = subscribeViewController else {
            if let error = error {
                alert(error: error, file: file, line: line)
            }
            return
        }
        if let error = error {
            subscribeViewController.errorHandler(error)
        } else {
            subscribeViewController.dismiss(animated: true)
        }
    }
}
