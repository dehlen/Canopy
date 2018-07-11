import PerfectNotifications

let apnsTopicId = "com.codebasesaga.GitBell"

NotificationPusher.addConfigurationAPNS(
    name: apnsTopicId,
    production: false, // should be false when running pre-release app in debugger
    keyId: "5354D789X6",
    teamId: "TEQMQBRC7B",
    privateKeyPath: "./AuthKey_5354D789X6.p8")

import PerfectHTTPServer

let server = HTTPServer()
server.serverPort = 1889
server.addRoutes(routes)
try server.start()
