import UserNotifications
import AppKit

//NOTE we get log messages in console.app that imply we are doing bad
// mising UserNotificationCenter and the *old* way, however if we don’t
// call `NSApp.registerForRemoteNotifications(matching: [.alert, .sound])`
// no notifications get to our app *at all*

//TODO use spotlight to check if multiple versions are installed
// if so, warn the user this will break shit
//TODO store the github key such that if they then install the
// iOS app it already has the key, probably iCloud ubiquituous storage

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!

    func applicationWillFinishLaunching(_ note: Notification) {
        NSUserNotificationCenter.default.delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.registerForRemoteNotifications(matching: [.alert, .sound])

        // with 10.14-beta3 at least the UNUserNotificationCenterDelegate is not called
        // at startup, I think this is an Apple bug though
        if let rsp = note.userInfo?[NSApplication.launchUserNotificationUserInfoKey] as? UNNotificationResponse {
            userNotificationCenter(UNUserNotificationCenter.current(), didReceive: rsp, withCompletionHandler: {})
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        do {
            guard let url = URL(string: "http://ci.codebasesaga.com:1889/token") else {
                throw E.unexpected
            }
            var rq = URLRequest(url: url)
            let payload = [
                "token": deviceToken.map{ String(format: "%02.2hhx", $0) }.joined()
            ]
            rq.httpMethod = "POST"
            rq.httpBody = try JSONSerialization.data(withJSONObject: payload)

            URLSession.shared.dataTask(with: rq) { data, rsp, error in
                if let data = data, let string = String(data: data, encoding: .utf8) {
                    print("Received:", string)
                } else {
                    print(error ?? E.unexpected)
                }
            }.resume()
        } catch {
            print(error)
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print(error)
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        print(userInfo)
    }

    func processRemoteNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}

// macOS < 10.14
extension AppDelegate: NSUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: NSUserNotificationCenter, didDeliver notification: NSUserNotification) {
        //noop
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        if let userInfo = notification.userInfo {
            processRemoteNotificationUserInfo(userInfo)
        }
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        // *always* show our notifications
        return true
    }
}

// macOS >= 10.14
extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.alert, .badge, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        processRemoteNotificationUserInfo(response.notification.request.content.userInfo)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        //noop
    }
}

enum E: Error {
    case unexpected
}
