import enum APNs.APNsNotification
import Foundation

func alert(message: String, title: String? = nil, url: URL? = nil, function: StaticString = #function) {
    do {
        print(function, message)
        var extra: [String: Any]?
        if let url = url {
            extra = ["url": url.absoluteString]
        }
        try APNsNotification(body: message, title: title, extra: extra).send(to: DB().mxcl())
    } catch {
        print("alert: error:", error)
    }
}


import LegibleError
import PerfectHTTP
import PromiseKit
import Roots

extension Routes {

    struct Response<T: Encodable> {
        let codable: T
        let headers: [HTTPResponseHeader.Name: String]

        func encode() throws -> [UInt8] {
            return [UInt8](try JSONEncoder().encode(codable))
        }
    }

    mutating func add(method: HTTPMethod, uri: URL.Canopy, handler: @escaping RequestHandler) {
        add(method: method, uri: uri.path, handler: handler)
    }

    private static func errorHandler(error: Error, rsp: HTTPResponse) {
        if let error = error as? API.Enroll.Error, let data = try? JSONEncoder().encode(error) {
            rsp.appendBody(bytes: [UInt8](data))
        } else {
            rsp.appendBody(string: error.legibleDescription)
        }
        let status = (error as? HTTPStatusCodable).map{ HTTPResponseStatus.statusFrom(code: $0.httpStatusCode) } ?? .internalServerError
        rsp.completed(status: status)
    }

    mutating func add<T: Encodable>(method: HTTPMethod, uri: URL.Canopy, handler: @escaping  (HTTPRequest) throws -> Promise<T>) {
        add(method: method, uri: uri.path, handler: { rq, rsp in
            firstly {
                try handler(rq)
                }.done {
                    rsp.appendBody(bytes: [UInt8](try JSONEncoder().encode($0)))
                    rsp.completed()
                }.catch {
                    Routes.errorHandler(error: $0, rsp: rsp)
            }
        })
    }

    mutating func add<T: Encodable>(method: HTTPMethod, uri: URL.Canopy, handler: @escaping  (HTTPRequest) throws -> Promise<Response<T>>) {
        add(method: method, uri: uri.path, handler: { rq, rsp in
            firstly {
                try handler(rq)
                }.done {
                    for (name, value) in $0.headers {
                        rsp.setHeader(name, value: value)
                    }
                    rsp.appendBody(bytes: try $0.encode())
                    rsp.completed()
                }.catch {
                    Routes.errorHandler(error: $0, rsp: rsp)
            }
        })
    }

    mutating func add(method: HTTPMethod, uri: URL.Canopy, handler: @escaping  (HTTPRequest) throws -> Promise<Void>) {
        add(method: method, uri: uri.path, handler: { rq, rsp in
            firstly {
                try handler(rq)
                }.done {
                    rsp.completed()
                }.catch {
                    Routes.errorHandler(error: $0, rsp: rsp)
            }
        })
    }
}
