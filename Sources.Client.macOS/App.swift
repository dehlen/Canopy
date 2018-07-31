import AppKit

//TODO store oauth token in at least the keychain
//TODO encrypt the state parameter or someone will notice and be weird about it
//TODO prettier authorizing… webpage
//TODO should use postgres or another not-in-process database since that puts the onus on *us* to never crash
//TODO Laurie couldn't see that the webhook was installed, may be necessary to store this info serverside
//  unless switching to a github app fixes this
//TODO Add secrets to hooks
//TODO icon
//TODO IAP-subscription for private repos
//TODO ensure private repos only go to valid users (HEAD request with oauth token)
//TODO FAQ on website that desribes how we get private data briefly (maybe github apps can fix that?)
//  talks about future server app distibution, talks about how we plan to improve this
//TODO ensure we are transactional where it counts (let's never break ffs!)
//TODO db backups
//TODO organization events have to be directed someplace, maybe API request to get list of members?


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
        UserDefaults.standard.removeGitHubOAuthToken()
        NSApp.terminate(sender)
    }
}

var app: AppDelegate {
    return NSApp.delegate as! AppDelegate
}
