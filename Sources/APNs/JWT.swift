import struct Foundation.Date
import PerfectCrypto
import Dispatch

private let teamId = "TEQMQBRC7B"

private let q = DispatchQueue(label: #file, attributes: .concurrent)
private var sigtime = Date(timeIntervalSince1970: 0)
private var lastJwt: String!

var jwt: String {
    //TODO thread-safety
    let now = Date()
    let t = q.sync{ sigtime }
    if t.timeIntervalSince(now) < -3590 {
        return q.sync(flags: .barrier) {
            let payload: [String: Any] = ["iss": teamId, "iat": Int(now.timeIntervalSince1970)]
            let jwt = JWTCreator(payload: payload)!
            let pem = try! PEMKey(pemPath: "../AuthKey_5354D789X6.p8")
            lastJwt = try! jwt.sign(alg: JWT.Alg.es256, key: pem, headers: ["kid": "5354D789X6"])
            sigtime = now
            return lastJwt
        }
    } else {
        return q.sync{ lastJwt }
    }
}
