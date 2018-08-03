import PromiseKit
import AppKit

//TODO encrypt the state parameter or someone will notice and be weird about it
//TODO Laurie couldn't see that the webhook was installed, may be necessary to store this info serverside
//  unless switching to a github app fixes this
//TODO Add secrets to hooks
//TODO icon
//TODO check no fatalErrors!
//TODO research scaling AWS instance
//TODO need a safe way to shutdown the app
//TODO can we rely on push to deliver the oauth token back? Debug mode suggests not.

//TODO prettier authorizing… webpage
//TODO FAQ on website that desribes how we get private data briefly (maybe github apps can fix that?)
//  talks about future server app distibution, talks about how we plan to improve this

//TODO ensure we keep SSL certificate up-to-date, look into automating it
//TODO ensure our Apple Developer account renews 
//TODO look into how sqlite handles crashes and CTRL-C
//TODO db backups
//TODO ensure we are transactional where it counts (let's never break ffs!)
//TODO allow disabling actions made by yourself (leave *on* since it is a good wow-moment to get the push when you do stuff)
//TODO organization subscription plan
//TODO uninstall webhook
//TODO organization events have to be directed someplace, maybe API request to get list of members?
//TODO get a read-only token for server: https://developer.github.com/apps/building-oauth-apps/authorizing-oauth-apps/#creating-multiple-tokens-for-oauth-apps

@NSApplicationMain
class AppDelegate: NSObject {
    weak var window: NSWindow!

    @objc dynamic var deviceToken: String?

    func processRemoteNotificationUserInfo(_ userInfo: [AnyHashable: Any]) {
        if let urlString = userInfo["url"] as? String, let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    @IBAction func signOut(sender: Any) {
        let url = URL(string: serverBaseUri)!.appendingPathComponent("token")
        var rq = URLRequest(url: url)
        rq.httpMethod = "DELETE"
        rq.httpBody = deviceToken?.data(using: .utf8)

        firstly {
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.done { _ in
            creds = nil
        }.catch {
            alert($0)
        }
    }
}

var app: AppDelegate {
    return NSApp.delegate as! AppDelegate
}
