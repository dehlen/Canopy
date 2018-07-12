import UserNotifications
import AppKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSUserNotificationCenter.default.delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.registerForRemoteNotifications(matching: [.alert, .sound])
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
}

// macOS < 10.14
extension AppDelegate: NSUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: NSUserNotificationCenter, didDeliver notification: NSUserNotification) {
        //noop
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        if let userInfo = notification.userInfo, let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
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
        let userInfo = response.notification.request.content.userInfo
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, openSettingsFor notification: UNNotification?) {
        //noop
    }
}

enum E: Error {
    case unexpected
}
