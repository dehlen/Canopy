import func Foundation.exit
import PromiseKit

let teamId = "TEQMQBRC7B"

PromiseKit.conf.Q.map = .global()
PromiseKit.conf.Q.return = .global()

import PerfectNotifications

extension NotificationPusher {
    static let sandboxConfigurationName = "com.codebasesaga.sandbox"
    static let productionConfigurationName = "com.codebasesaga.production"
}

NotificationPusher.addConfigurationAPNS(
    name: NotificationPusher.sandboxConfigurationName,
    production: false,
    keyId: "5354D789X6",
    teamId: teamId,
    privateKeyPath: "./AuthKey_5354D789X6.p8")

NotificationPusher.addConfigurationAPNS(
    name: NotificationPusher.productionConfigurationName,
    production: true,
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
server.serverPort = 443
server.addRoutes(routes)
server.ssl = (
    sslCert: "/etc/letsencrypt/live/canopy.codebasesaga.com/fullchain.pem",
    sslKey: "/etc/letsencrypt/live/canopy.codebasesaga.com/privkey.pem"
)
try server.start()

