import UserNotifications
import AppKit

extension AppDelegate: NSApplicationDelegate {
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

        fetchRepos()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "sealegs" {
            guard let parameters = url.gitHubParameters else { continue }
            guard parameters.state == deviceToken else { continue }

            finishSignIn(code: parameters.code, state: parameters.state)
            deviceToken = nil

            break // would be dumb to attempt more than one at a time, also: since we have a single `state`, how would this work?
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken rawDeviceToken: Data) {
        deviceToken = rawDeviceToken.map{ String(format: "%02.2hhx", $0) }.joined()
        do {
            guard let url = URL(string: "http://ci.codebasesaga.com:1889/token") else {
                throw E.unexpected
            }
            var rq = URLRequest(url: url)
            let payload = [
                "token": deviceToken!
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
