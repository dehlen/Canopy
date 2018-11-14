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
        if #available(macOS 10.14, *) {
            UNUserNotificationCenter.current().delegate = self
        }

        // so tapping notifications doesn’t show the app temporarily
        //TODO verify there is no flash, may need to set this in storyboard
        NSApp.mainWindow?.setIsVisible(false)
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.registerForRemoteNotifications(matching: [.alert, .sound])

        func chunk(with userInfo: [String: Any]) {
            if processRemoteNotificationUserInfo(userInfo) {
                NSApp.terminate(self)
            }
        }

        var userInfo: [AnyHashable: Any]?

        if #available(macOS 10.14, *) {
            let rsp = note.userInfo?[NSApplication.launchUserNotificationUserInfoKey] as? UNNotificationResponse
            userInfo = rsp?.notification.request.content.userInfo
        } else if let notification = note.userInfo?[NSApplication.launchUserNotificationUserInfoKey] as? NSUserNotification {
            userInfo = notification.userInfo
        }

        if let userInfo = userInfo, processRemoteNotificationUserInfo(userInfo) {
            // we were launched by a notification tap and only exist to open that URL in the system browser
            NSApp.terminate(self)
        } else {
            SKPaymentQueue.default().add(self)
            postReceiptIfPossibleNoErrorUI()

            // show icon and menu now (we are LSUIElement so taps on notifications don't appear to open the app)
            NSApp.mainWindow?.setIsVisible(true)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true) // or menu doesn’t respond to clicks
        }
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
