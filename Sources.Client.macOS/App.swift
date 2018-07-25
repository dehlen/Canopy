import AppKit

//NOTE we get log messages in console.app that imply we are doing bad
// mising UserNotificationCenter and the *old* way, however if we don’t
// call `NSApp.registerForRemoteNotifications(matching: [.alert, .sound])`
// no notifications get to our app *at all*

//TODO use spotlight to check if multiple versions are installed
// if so, warn the user this will break shit
//TODO store the github key such that if they then install the
// iOS app it already has the key, probably iCloud ubiquituous storage

//TODO at the very least store the github key outside user-defaults

//TODO verify that members of an organization get read access to all of that org
// ie. that you cannot make something private to other members

//TODO gracefully handle when oauth token is revoked

//TODO better encrypt/decrupt the state parameter or someone will notice and be weird about it

//TODO sucks to open the app when you tap the notifications, should just open safari if poss

//TODO better authorizing… webpage

//TODO should use postgres or another not-in-process database since that puts the onus on *us* to never crash

// 0. Store users on server-db with device tokens & topics & webhook interests
// 1. Make work on High Sierra then give out to staff
// 2. Figure out how to ensure private repos only go to valid users†
// 3. Add secrets to hooks
// 4. Get own domain, add SSL, add universal links for iOS
// 5. Icon
// 6. IAP for private repos, or initial launch doesn't support them
// 7. FAQ on website that desribes how we get private data briefly (maybe github apps can fix that?)

// † How can we handle this for users that are removed from orgs?


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
