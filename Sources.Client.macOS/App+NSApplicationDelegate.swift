#if swift(>=4.2)
import UserNotifications
#endif
import PromiseKit
import StoreKit
import AppKit

extension AppDelegate: NSApplicationDelegate {
    override func awakeFromNib() {
        PromiseKit.conf.Q.map = .global()

        ref = observe(\.hasVerifiedReceipt) { app, _ in
            app.createSubscriptionMenuItem.isHidden = app.hasVerifiedReceipt
            app.manageSubscriptionMenuItem.isHidden = !app.hasVerifiedReceipt
        }
    }

    func applicationWillFinishLaunching(_ note: Notification) {
        NSUserNotificationCenter.default.delegate = self
    #if swift(>=4.2)
        if #available(macOS 10.14, *) {
            UNUserNotificationCenter.current().delegate = self
        }
    #endif
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSApp.windows.first
        
        NSApp.registerForRemoteNotifications(matching: [.alert, .sound])

        // with 10.14-beta3 at least the UNUserNotificationCenterDelegate is not called
        // at startup, I think this is an Apple bug though
        if let notification = note.userInfo?[NSApplication.launchUserNotificationUserInfoKey] as? NSUserNotification {
            if let userInfo = notification.userInfo {
                processRemoteNotificationUserInfo(userInfo)
            }
        }
    #if swift(>=4.2)
        if #available(macOS 10.14, *), let rsp = note.userInfo?[NSApplication.launchUserNotificationUserInfoKey] as? UNNotificationResponse {
            processRemoteNotificationUserInfo(rsp.notification.request.content.userInfo)
        }
    #endif

        SKPaymentQueue.default().add(self)
        postReceiptIfPossibleNoErrorUI()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken rawDeviceToken: Data) {
        deviceToken = String(deviceToken: rawDeviceToken)

        if let oauthToken = creds?.token, let deviceToken = deviceToken {
            firstly {
                updateTokens(oauth: oauthToken, device: deviceToken)
            }.catch {
                alert($0)
            }
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        alert(error)
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        switch RemoteNotificationUserInfo(userInfo: userInfo) {
        case .creds(let login, let token):
            creds = (username: login, token: token)
            NSApp.activate(ignoringOtherApps: true)
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
