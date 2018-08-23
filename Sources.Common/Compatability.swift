#if !swift(>=4.1.5)
public extension Collection where Element: Equatable {
    func firstIndex(of member: Element) -> Self.Index? {
        return self.index(of: member)
    }
}
#endif

public extension Sequence {
    //@inlinable
    func map<T>(_ keyPath: KeyPath<Element, T>) -> [T] {
        return map {
            $0[keyPath: keyPath]
        }
    }

    //@inlinable
    func compactMap<T>(_ keyPath: KeyPath<Element, T?>) -> [T] {
        return compactMap {
            $0[keyPath: keyPath]
        }
    }
}

import struct Foundation.Data

public extension Data {
    var xor: Data {
        return Data(map{ $0 ^ 176 })
    }
}

import struct Foundation.URLRequest

extension URLRequest {
    var description: String {
        var data : String = ""
        let complement = "\\\n    "
        let method = "-X \(httpMethod ?? "GET") \(complement)"
        let url = "\"\(self.url?.absoluteString ?? "")\""

        var header = ""

        if let httpHeaders = allHTTPHeaderFields, httpHeaders.keys.count > 0 {
            for (key,value) in httpHeaders {
                header += "-H \"\(key): \(value)\" \(complement)"
            }
        }

        if let bodyData = httpBody, let bodyString = String(data:bodyData, encoding:.utf8) {
            data = "-d \"\(bodyString)\" \(complement)"
        }

        let command = "curl -i " + complement + method + header + data + url

        return command
    }
}

public extension String {
    func chuzzled() -> String? {
        let str = trimmingCharacters(in: .whitespacesAndNewlines)
        return str.isEmpty ? nil : str
    }
}
