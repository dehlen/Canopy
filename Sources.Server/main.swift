import struct Foundation.ObjCBool
import class Foundation.FileManager
import class Dispatch.DispatchQueue
import func Foundation.exit
import PromiseKit

#if os(Linux)
import Glibc
// otherwise buffering makes systemd launched logging useless
setbuf(stdout, nil)
#endif

CurlVersionHelper().checkVersion()

var isDir: ObjCBool = false
precondition(FileManager.default.fileExists(atPath: "../receipts", isDirectory: &isDir) && isDir.boolValue)
precondition(FileManager.default.fileExists(atPath: "../db.sqlite"))

let teamId = "TEQMQBRC7B"

#if os(Linux)
let pmkQ = DispatchQueue(label: "pmkQ", qos: .default, attributes: .concurrent, autoreleaseFrequency: .workItem)
PromiseKit.conf.Q.map = pmkQ
PromiseKit.conf.Q.return = pmkQ
#endif

import PerfectHTTPServer
import PerfectHTTP
import Foundation
import Roots

private extension Routes {
    mutating func add(method: HTTPMethod, uri: URL.Canopy, handler: @escaping RequestHandler) {
        add(method: method, uri: uri.path, handler: handler)
    }

    mutating func add(method: HTTPMethod, uri: URL.Canopy, handler: @escaping  (HTTPRequest) throws -> Promise<Void>) {
        add(method: method, uri: uri.path, handler: { rq, rsp in
            firstly {
                try handler(rq)
            }.done {
                rsp.completed()
            }.catch { error in
                if let error = error as? API.Enroll.Error, let data = try? JSONEncoder().encode(error) {
                    rsp.appendBody(bytes: [UInt8](data))
                } else {
                    rsp.appendBody(string: error.legibleDescription)
                }
                let status = (error as? HTTPStatusCodable).map{ HTTPResponseStatus.statusFrom(code: $0.httpStatusCode) } ?? .internalServerError
                rsp.completed(status: status)
            }
        })
    }
}

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


import Dispatch

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
