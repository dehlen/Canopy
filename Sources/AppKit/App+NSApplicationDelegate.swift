import UserNotifications
import StoreKit
import AppKit
import Cake

extension AppDelegate: NSApplicationDelegate {
    override func awakeFromNib() {
        PromiseKit.conf.Q.map = .global()
    }

    func applicationWillFinishLaunching(_ note: Notification) {
        if #available(macOS 10.14, *) {
            UNUserNotificationCenter.current().delegate = self
        } else {
            NSUserNotificationCenter.default.delegate = self
        }

        print(Int.max ^ [Event].default.maskValue)
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        var userInfo: [AnyHashable: Any]?

        if #available(macOS 10.14, *) {
            let rsp = note.userInfo?[NSApplication.launchUserNotificationUserInfoKey] as? UNNotificationResponse
            userInfo = rsp?.notification.request.content.userInfo
        } else if let notification = note.userInfo?[NSApplication.launchUserNotificationUserInfoKey] as? NSUserNotification {
            userInfo = notification.userInfo
        }

        if let userInfo = userInfo, processRemoteNotificationUserInfo(userInfo) {
            // we were launched by a notification tap and only exist to open that URL in the system browser
            exit(0)
        } else {
            // k, we’re not launched from notification tap, so show dock icon and menu bar
            NSApp.setActivationPolicy(.regular)
        }

        NSApp.registerForRemoteNotifications(matching: [.alert, .sound])

        let windowController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "Root") as! NSWindowController
        windowController.showWindow(self)
        windowController.window!.makeKeyAndOrderFront(self)

        NSApp.activate(ignoringOtherApps: true) // or doesn’t respond to clicks

        subscriptionManager = SubscriptionManager()
        subscriptionManager.delegate = self

        ref = subscriptionManager.observe(\.hasVerifiedReceipt) { mgr, _ in
            app.createSubscriptionMenuItem.isHidden = mgr.hasVerifiedReceipt
            app.manageSubscriptionMenuItem.isHidden = !mgr.hasVerifiedReceipt
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken rawDeviceToken: Data) {
        deviceToken = String(deviceToken: rawDeviceToken)

        if let oauthToken = creds?.token, let deviceToken = deviceToken {
            firstly {
                updateTokens(oauth: oauthToken, device: deviceToken)
            }.catch {
                alert(error: $0)
            }
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        alert(error: error)
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        switch RemoteNotificationUserInfo(userInfo: userInfo) {
        case .creds(let login, let token):
            creds = (username: login, token: token)
            NSApp.activate(ignoringOtherApps: true)

            ProcessInfo.processInfo.enableSuddenTermination()
            ProcessInfo.processInfo.enableAutomaticTermination("User not logged in")

        case .error(let message, .authentication?):
            if creds == nil {
                fallthrough
            }
            // else… ignore. mostly happens because: user left auth page open
            // and this causes a POST to our auth endpoint, but the code was
            // consumed so GitHub errors
        case .error(let message, nil):
            alert(message: message, title: "Server Error")
        case .unknown:
            print(userInfo)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

private enum Response {
    case creds(login: String, token: String)
    case error(message: String, ServerError?)
    case unknown

    init(userInfo: [String: Any]) {
        if let token = userInfo["token"] as? String, let login = userInfo["login"] as? String {
            self = .creds(login: login, token: token)
        } else if let message = userInfo["error"] {
            let code = userInfo["error-code"] as? Int
            self = .error(message: "\(message)", code.flatMap(ServerError.init))
        } else {
            self = .unknown
        }
    }
}
