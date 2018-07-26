#if swift(>=4.2)
import UserNotifications
#endif
import PromiseKit
import AppKit

extension AppDelegate: NSApplicationDelegate {
    func applicationWillFinishLaunching(_ note: Notification) {
        PromiseKit.conf.Q.map = .global()
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
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken rawDeviceToken: Data) {
        deviceToken = String(deviceToken: rawDeviceToken)

        if let oauthToken = UserDefaults.standard.gitHubOAuthToken, let deviceToken = deviceToken {
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
        if let oauthToken = userInfo["oauthToken"] as? String {
            NSApp.activate(ignoringOtherApps: true)
            UserDefaults.standard.gitHubOAuthToken = oauthToken
        } else if let message = userInfo["oauthTokenError"] as? String {
            alert(message: message, title: "GitHub Authorization Failed")
            //TODO allow sign-in again somehow
        } else {
            print(userInfo)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}