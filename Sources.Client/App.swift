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
class AppDelegate: NSObject {
    @IBOutlet private weak var window: NSWindow!
    var deviceToken: String?

    func processRemoteNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    @IBAction func signIn(sender: NSButton) {
        guard let deviceToken = deviceToken else { return } //TODO error handling

        var cc = URLComponents()
        cc.scheme = "https"
        cc.host = "github.com"
        cc.path = "/login/oauth/authorize"
        cc.queryItems = [
            "client_id": clientId,
            "redirect_uri": redirectUri,
            "scope": "admin:repo_hook admin:org_hook repo",
            "state": deviceToken,
            "allow_signup": "false"
        ].map(URLQueryItem.init)

        guard let url = cc.url else {
            NSAlert(error: E.unexpected).runModal(); return
        }

        NSWorkspace.shared.open(url)
    }

    func finishSignIn(code: String, state: String) {

        //TODO should SSL server *and* handle there since we should not be shipping our secret

        do {
            guard let url = URL(string: "https://github.com/login/oauth/access_token") else { return }
            let json = [
                "client_id": clientId,
                "client_secret": "2397959358b460caf90f943c9a0f548cb084d5f2",
                "code": code,
                "redirect_uri": redirectUri,
                "state": state
            ]
            var rq = URLRequest(url: url)
            rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            rq.setValue("application/json", forHTTPHeaderField: "Accept")
            rq.httpMethod = "POST"
            rq.httpBody = try JSONSerialization.data(withJSONObject: json)

            struct Response: Decodable {
                let access_token: String
                let scope: String?  // docs aren't clear if this is always present
            }

            URLSession.shared.dataTask(with: rq) { data, _, err in
                do {
                    guard let data = data else { throw err ?? E.unexpected }
                    let token = try JSONDecoder().decode(Response.self, from: data).access_token
                    UserDefaults.standard.gitHubToken = token
                    self.fetchRepos()
                } catch {
                    DispatchQueue.main.async {
                        NSAlert(error: error).runModal()
                    }
                }
            }.resume()

        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func fetchRepos() {
        guard let token = UserDefaults.standard.gitHubToken else { return }
        guard var rq = URL(string: "https://api.github.com/user/repos").map({ URLRequest(url: $0) }) else { return }
        rq.setValue("token \(token)", forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: rq) { data, rsp, err in
            guard let data = data else { return }

            struct Response: Decodable {
                let full_name: String
            }

            let responses = try! JSONDecoder().decode([Response].self, from: data)
            print(responses.map{ $0.full_name })

            print()
            if let rsp = rsp as? HTTPURLResponse, let link = rsp.allHeaderFields["Link"] {
                print(link)
            }

        }.resume()
    }
}

