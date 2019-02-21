import Foundation
import PromiseKit

public struct GitHubAPI {
    private let oauthToken: String

    public init(oauthToken: String) {
        self.oauthToken = oauthToken
    }

    private func request(url: URL) -> URLRequest {
        var rq = URLRequest(url: url)
        rq.setValue("token \(oauthToken)", forHTTPHeaderField: "Authorization")
        rq.setValue("application/json", forHTTPHeaderField: "Accept")
        return rq
    }

    public func request(path: String) -> URLRequest {
        return request(url: URL(string: "https://api.github.com")!.appendingPathComponent(path))
    }

    public func me() -> Promise<Me> {
        return firstly {
            URLSession.shared.dataTask(.promise, with: request(path: "user"))
        }.map {
            try JSONDecoder().decode(Me.self, from: $0.data)
        }
    }

    public func task(path: String, paginatedHandler: @escaping (Data) -> Promise<Void>) -> Promise<Void> {
        func page(for rq: URLRequest) -> Promise<URLResponse> {
            return firstly {
                URLSession.shared.dataTask(.promise, with: rq).validate()
            }.then { data, rsp in
                paginatedHandler(data).map{ rsp }
            }
        }

        func next(for rsp: URLResponse) -> URL? {
            guard let rsp = rsp as? HTTPURLResponse, let link = rsp.allHeaderFields["Link"] as? String else {
                return nil
            }
            let set = CharacterSet(charactersIn: "<>").union(.whitespacesAndNewlines)
            for link in link.split(separator: ",") {
                guard let semicolonIndex = link.firstIndex(of: ";") else { continue }
                guard link[semicolonIndex...].contains("next") else { continue } //FIXME better
                let urlstr = link[..<semicolonIndex].trimmingCharacters(in: set)
                return URL(string: urlstr)
            }
            return nil
        }

        func go(rq: URLRequest) -> Promise<Void> {
            return firstly {
                page(for: rq)
            }.then { rsp -> Promise<Void> in
                if let next = next(for: rsp) {
                    return go(rq: self.request(url: next))
                } else {
                    return Promise()
                }
            }
        }

        return go(rq: request(path: path))
    }

    public struct Me: Decodable {
        public let id: Int
        public let login: String
        public let avatar_url: URL
    }
}
