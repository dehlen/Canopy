import struct Foundation.Date
import PerfectCrypto
import Dispatch

private let teamId = "TEQMQBRC7B"

private let q = DispatchQueue(label: #file, attributes: .concurrent)
private var sigtime = Date(timeIntervalSince1970: 0)
private var lastJwt = ""

var jwt: String {
    let now = Date()
    let jwt = q.sync{ (time: sigtime, token: lastJwt) }

    if now.timeIntervalSince(jwt.time) >= 3590 {
        return jwt.token
    }

    // generate new token
    return q.sync(flags: .barrier) {

        // yay for async!
        guard now.timeIntervalSince(sigtime) >= 3590 else {
            return lastJwt
        }

        let payload: [String: Any] = ["iss": teamId, "iat": Int(now.timeIntervalSince1970)]
        let jwt = JWTCreator(payload: payload)!
        let pem = try! PEMKey(pemPath: "../AuthKey_5354D789X6.p8")
        lastJwt = try! jwt.sign(alg: JWT.Alg.es256, key: pem, headers: ["kid": "5354D789X6"])
        sigtime = now // slightly off, but ok
        return lastJwt
    }
}
