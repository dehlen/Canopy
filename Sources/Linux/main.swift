import struct PerfectHTTP.Routes
import struct Foundation.ObjCBool
import class Foundation.FileManager
import class Dispatch.DispatchQueue
import class APNs.CurlVersionHelper
import func Foundation.exit
import PerfectHTTPServer
import PromiseKit
import Dispatch
import Roots

#if os(Linux)
import Glibc

setbuf(stdout, nil) // otherwise buffering makes systemd launched logging useless

CurlVersionHelper().checkVersion()
precondition(MemoryLayout<Int>.size == 8)  // required for our event-mask system
var isDir: ObjCBool = false
precondition(FileManager.default.fileExists(atPath: "../receipts", isDirectory: &isDir) && isDir.boolValue)
precondition(FileManager.default.fileExists(atPath: "../db.sqlite"))

let pmkQ = DispatchQueue(label: "pmkQ", qos: .default, attributes: .concurrent, autoreleaseFrequency: .workItem)
PromiseKit.conf.Q.map = pmkQ
PromiseKit.conf.Q.return = pmkQ
#endif

var routes = Routes()
routes.add(method: .post, uri: .grapnel, handler: githubHandler)
routes.add(method: .post, uri: .token, handler: updateTokensHandler)
routes.add(method: .delete, uri: .token, handler: deleteTokenHandler)
routes.add(method: .get, uri: .redirect, handler: oauthCallback)
routes.add(method: .get, uri: .subscribe, handler: subscriptionsHandler)
routes.add(method: .post, uri: .subscribe, handler: subscribeHandler)
routes.add(method: .delete, uri: .subscribe, handler: unsubscribeHandler)
routes.add(method: .post, uri: .receipt, handler: receiptHandler)
routes.add(method: .post, uri: .hook, handler: createHookHandler)
routes.add(method: .get, uri: .hook, handler: hookQueryHandler)
routes.add(method: .post, uri: .enroll, handler: enrollHandler)
routes.add(method: .delete, uri: .enroll, handler: unenrollHandler)
routes.add(method: .put, uri: .enroll, handler: eventMaskHandler)
routes.add(method: .get, uri: .enroll, handler: enrollmentsHandler)
routes.add(method: .get, uri: .refreshReceipts, handler: refreshReceiptsHandler)

let server = HTTPServer()
server.addRoutes(routes)
#if os(Linux)
    server.runAsUser = "ubuntu"
    server.serverPort = 443
    server.ssl = (
        sslCert: "/etc/letsencrypt/live/canopy.codebasesaga.com/fullchain.pem",
        sslKey: "/etc/letsencrypt/live/canopy.codebasesaga.com/privkey.pem"
    )
#else
    server.serverPort = 1088
#endif


signal(SIGINT, SIG_IGN) // prevent termination

var running = true
let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
sigint.setEventHandler {
    //TODO thread-safety
    if running {
        running = false
        print("Clean shutdown initiated")
        server.stop()
        //FIXME no way to cleanly stop the APNs engine
    } else {
        print("Already shutting down or not yet started")
    }
}
sigint.resume()

try server.start()

print("HTTPServer shutdown")
