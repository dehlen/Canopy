import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    @IBOutlet weak var window: NSWindow!

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

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
        print(userInfo)
    }
}

enum E: Error {
    case unexpected
}
