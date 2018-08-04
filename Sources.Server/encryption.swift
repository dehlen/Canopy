import PerfectCrypto
import Foundation

// strictly should be stored on a separate system in case access
// to our server is compromised, (lol security is hard)
// https://crackstation.net/hashing-security.htm
private let key = Array("cqrE;dWYbebVo$u2fsrA3aePHf)AF/BHq4UexficLEB8z9ba2BG=?JmijJ2TX+w3".utf8)

func encrypt(_ token: String) -> (encrypted: [UInt8], salt: [UInt8])? {
    let uuid = UUID().uuid
    let salt = [uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7, uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15]
    guard let encrypted = Array(token.utf8).encrypt(.aes_128_cbc, key: key, iv: salt) else {
        return nil
    }
    return (encrypted, salt)
}

func decrypt(_ encryptedData: [UInt8], salt iv: [UInt8]) -> String? {
    guard let decryptedBytes = encryptedData.decrypt(.aes_128_cbc, key: key, iv: iv) else {
        return nil
    }
    return String(validatingUTF8: decryptedBytes)
}
