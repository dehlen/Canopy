import PerfectCrypto
import Foundation
import PromiseKit
import CCurl

final class APNs {
    let curlHandle: UnsafeMutableRawPointer
    let url: String

    init(production: Bool) {
        curlHandle = curl_multi_init()
        if production {
            url = "https://api.push.apple.com/3/device/"
        } else {
            url = "https://api.sandbox.push.apple.com/3/device/"
        }
        curlHelperSetMultiOpt(curlHandle, CURLMOPT_PIPELINING, CURLPIPE_MULTIPLEX)
    }

    deinit {
        curl_multi_cleanup(curlHandle)
    }

    private let connectionQueue = DispatchQueue(label: "VaporAPNS.connection-managment")
    private var connections: [Connection] = []

    private func complete(connection: Connection) {
        connectionQueue.async {
            if let index = self.connections.firstIndex(of: connection) {
                self.connections.remove(at: index)
            } else {
                print("error: LEAK!")
            }
            self.performQueue.async {
                var code = 0
                curlHelperGetInfoLong(connection.handle, CURLINFO_RESPONSE_CODE, &code)

                curl_multi_remove_handle(self.curlHandle, connection.handle)
                self.handleCompleted(code: code, connection: connection)
            }
        }
    }

    private func handleCompleted(code: Int, connection: Connection) {
        var error: APNsError? {
            switch code {
            case 200..<300:
                return nil
            case 410:
                return .badToken(connection.token)
            default:
                break
            }

            guard let str = String(data: connection.data, encoding: .utf8) else {
                return .fundamental("APNs response was not valid string")
            }

            // Split into two pieces by '\r\n\r\n' as the response has two
            // newlines before the returned data. This causes us to have two
            // pieces, the headers/crap and the server returned data.
            let splittedString = str.components(separatedBy: "\r\n\r\n")

            guard splittedString.count > 1 else {
                return .fundamental("APNs response had unexpected form")
            }
            let responseString = splittedString[1]
            guard !responseString.isEmpty else {
                return .fundamental("APNs response was empty")
            }

            guard let data = responseString.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data, options: []),
                let responseJSON = json as? [String: Any],
                let reason = responseJSON["reason"] as? String
            else {
                return .fundamental("APNs response was not JSON")
            }

            if reason == "BadDeviceToken" {
                return .badToken(connection.token)
            } else {
                return .reason(reason)
            }
        }

        if let error = error {
            connection.errorHandler(error)
        } else {
            print("APNs 200")
        }
    }

    private let performQueue: DispatchQueue = DispatchQueue(label: "dev.mxcl.Canopy.curl_multi_perform")
    private var runningConnectionsCount: Int32 = 0
    private var repeats = 0

    /// Core cURL-multi Loop is done here
    private func performActiveConnections() {
    #if os(Linux)
        dispatchPrecondition(condition: .onQueue(performQueue))
    #endif

        var numfds: Int32 = 0
        var code = curl_multi_perform(curlHandle, &runningConnectionsCount)
        if code == CURLM_OK {
            code = curl_multi_wait(curlHandle, nil, 0, 1000, &numfds);
        }
        guard code == CURLM_OK else {
            let err = String(cString: curl_multi_strerror(code))
            print("error: curl_multi_wait failed:", code, err)
            return
        }

        if numfds != 0 {
            self.repeats += 1
        } else {
            self.repeats = 0
        }

        var numMessages: Int32 = 0
        var curlMessage: UnsafeMutablePointer<CURLMsg>?

        repeat {
            curlMessage = curl_multi_info_read(curlHandle, &numMessages)
            guard let message = curlMessage else {
                continue
            }

            let handle = message.pointee.easy_handle
            let msg = message.pointee.msg

            guard msg == CURLMSG_DONE else {
                let err = String(cString: curl_easy_strerror(message.pointee.data.result))
                print("error: connection failiure:", msg, err)
                continue
            }

            connectionQueue.async {
                guard let connection = self.connections.first(where: { $0.handle == handle }) else {
                    self.performQueue.async {
                        print("warning: removing handle not in connection list")
                        curl_multi_remove_handle(self.curlHandle, handle)
                    }
                    return
                }
                self.complete(connection: connection)
            }
        } while numMessages > 0

        if runningConnectionsCount > 0 {
            performQueue.async {
                if self.repeats > 1 {
                    self.performQueue.asyncAfter(deadline: DispatchTime.now() + 0.1) {
                        self.performActiveConnections()
                    }
                } else {
                    self.performActiveConnections()
                }
            }
        }

    }

    func send(to deviceToken: String, topic: String, json: Data, id: String?, collapseId: String?, errorHandler: @escaping (APNsError) -> Void) {
        guard let connection = configureCurlHandle(url: url, json: json, token: deviceToken, topic: topic, id: id, collapseId: collapseId, errorHandler: errorHandler) else {
            errorHandler(.fundamental("Could not configure cURL"))
            return
        }

        connectionQueue.async {
            self.connections.append(connection)
            let ptr = Unmanaged<Connection>.passUnretained(connection).toOpaque()
            let _ = curlHelperSetOptWriteFunc(connection.handle, ptr) { (ptr, size, nMemb, privateData) -> Int in
                let realsize = size * nMemb

                let pointee = Unmanaged<Connection>.fromOpaque(privateData!).takeUnretainedValue()
                var bytes: [UInt8] = [UInt8](repeating: 0, count: realsize)
                memcpy(&bytes, ptr!, realsize)

                pointee.append(bytes: bytes)
                return realsize
            }

            self.performQueue.async {
                // curlHandle should only be touched on performQueue
                curl_multi_add_handle(self.curlHandle, connection.handle)
                self.performActiveConnections()
            }
        }
    }
}

private class Connection: Equatable {
    private(set) var data: Data = Data()
    let handle: UnsafeMutableRawPointer
    let headers: UnsafeMutablePointer<curl_slist>?
    let messageId: String
    let token: String
    let errorHandler: (APNsError) -> Void

    func append(bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    init(handle: UnsafeMutableRawPointer, id: String?, token: String, headers: UnsafeMutablePointer<curl_slist>?, errorHandler: @escaping (APNsError) -> Void) {
        self.handle = handle
        self.messageId = id ?? UUID().uuidString
        self.token = token
        self.errorHandler = errorHandler
        self.headers = headers
    }

    deinit {
        curl_slist_free_all(headers)
        curl_easy_cleanup(handle)
    }

    static func == (lhs: Connection, rhs: Connection) -> Bool {
        return lhs.messageId == rhs.messageId && lhs.token == rhs.token
    }
}

private func configureCurlHandle(url: String, json: Data, token deviceToken: String, topic: String, id: String?, collapseId: String?, errorHandler: @escaping (APNsError) -> Void) -> Connection? {
    guard let handle = curl_easy_init() else { return nil }

    curlHelperSetOptInt(handle, CURLOPT_HTTP_VERSION, CURL_HTTP_VERSION_2_0)
    curlHelperSetOptString(handle, CURLOPT_URL, url + deviceToken)
    curlHelperSetOptInt(handle, CURLOPT_PORT, 443)
    curlHelperSetOptBool(handle, CURLOPT_FOLLOWLOCATION, CURL_TRUE)
    curlHelperSetOptBool(handle, CURLOPT_POST, CURL_TRUE)
    curlHelperSetOptInt(handle, CURLOPT_PIPEWAIT, 1)

    curlHelperSetOptInt(handle, CURLOPT_POSTFIELDSIZE, json.count)
    var json = json
    json.append(0)
    json.withUnsafeBytes { ptr -> Void in
        curlHelperSetOptString(handle, CURLOPT_COPYPOSTFIELDS, ptr.baseAddress?.assumingMemoryBound(to: Int8.self))
    }

//// headers
    curlHelperSetOptBool(handle, CURLOPT_HEADER, CURL_TRUE)

    var curlHeaders: UnsafeMutablePointer<curl_slist>?
    curlHeaders = curl_slist_append(curlHeaders, "Authorization: bearer \(jwt)")
    curlHeaders = curl_slist_append(curlHeaders, "User-Agent: Canopy")
    curlHeaders = curl_slist_append(curlHeaders, "apns-topic: \(topic)")
    if let id = id {
        curlHeaders = curl_slist_append(curlHeaders, "apns-id: \(id)")
    }
    if let collapseId = collapseId {
        curlHeaders = curl_slist_append(curlHeaders, "apns-collapse-id: \(collapseId)")
    }
    curlHeaders = curl_slist_append(curlHeaders, "Accept: application/json")
    curlHeaders = curl_slist_append(curlHeaders, "Content-Type: application/json");
    curlHelperSetOptList(handle, CURLOPT_HTTPHEADER, curlHeaders)

    return Connection(handle: handle,
                      id: id,
                      token: deviceToken,
                      headers: curlHeaders,
                      errorHandler: errorHandler)
}
