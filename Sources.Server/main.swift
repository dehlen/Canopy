import PromiseKit

let teamId = "TEQMQBRC7B"

PromiseKit.conf.Q.map = .global()
PromiseKit.conf.Q.return = .global()


import PerfectNotifications

extension NotificationPusher {
    static let confName = "com.codebasesaga"
}

NotificationPusher.addConfigurationAPNS(
    name: NotificationPusher.confName,
    production: false, // should be false when running pre-release app in debugger
    keyId: "5354D789X6",
    teamId: teamId,
    privateKeyPath: "./AuthKey_5354D789X6.p8")

import PerfectHTTPServer
import PerfectHTTP
import Foundation

var routes = Routes()
routes.add(method: .post, uri: "/github", handler: githubHandler)
routes.add(method: .post, uri: "/token", handler: updateTokensHandler)
routes.add(method: .get, uri: "/oauth", handler: oauthCallback)
routes.add(method: .get, uri: "/subscribe", handler: subscriptionsHandler)
routes.add(method: .post, uri: "/subscribe", handler: subscribeHandler)
routes.add(method: .delete, uri: "/subscribe", handler: unsubscribeHandler)
routes.add(method: .get, uri: "/apple-app-site-association", handler: appleAppSiteAssociationHandler)

let server = HTTPServer()
server.serverPort = 1889
server.addRoutes(routes)
try server.start()

