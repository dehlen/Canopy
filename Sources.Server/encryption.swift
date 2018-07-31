import CommonCrypto
import Foundation

// strictly should be stored on a separate system in case access
// to our server is compromised, (lol security is hard)
// https://crackstation.net/hashing-security.htm
private let encryptionKey = "cqrE;dWYbebVo$u2fsrA3aePHf)AF/BHq4UexficLEB8z9ba2BG=?JmijJ2TX+w3"

func encrypt(_ token: String) throws -> (encrypted: Data, salt: String) {
    let salt = UUID().uuidString
    let encryptedData = try aesEncrypt(input: token, key: encryptionKey, iv: salt)
    return (encryptedData, salt)
}

// perfect is stupid
func decrypt(_ encryptedData: [UInt8], salt: String) throws -> String {
    var bytes = encryptedData
    let data = Data(bytes: &bytes, count: encryptedData.count)
    return try aesDecrypt(input: data, key: encryptionKey, iv: salt)
}

func decrypt(_ encryptedData: Data, salt: String) throws -> String {
    return try aesDecrypt(input: encryptedData, key: encryptionKey, iv: salt)
}

func aesEncrypt(input: String, key: String, iv: String, options: Int = kCCOptionPKCS7Padding) throws -> Data {
    guard let keyData = key.data(using: String.Encoding.utf8),
          let data = input.data(using: String.Encoding.utf8),
          let cryptData    = NSMutableData(length: Int((data.count)) + kCCBlockSizeAES128)
    else {
        throw CocoaError.error(.coderInvalidValue)
    }

    let keyLength              = size_t(kCCKeySizeAES128)
    let operation: CCOperation = UInt32(kCCEncrypt)
    let algoritm:  CCAlgorithm = UInt32(kCCAlgorithmAES128)
    let options:   CCOptions   = UInt32(options)
    var numBytesEncrypted: size_t = 0

    let cryptStatus = CCCrypt(operation,
                              algoritm,
                              options,
                              (keyData as NSData).bytes, keyLength,
                              iv,
                              (data as NSData).bytes, data.count,
                              cryptData.mutableBytes, cryptData.length,
                              &numBytesEncrypted)

    guard UInt32(cryptStatus) == UInt32(kCCSuccess) else {
        throw CocoaError.error(.coderInvalidValue)
    }

    cryptData.length = Int(numBytesEncrypted)
    return cryptData as Data
}

private func aesDecrypt(input: Data, key: String, iv: String, options: Int = kCCOptionPKCS7Padding) throws -> String {
    guard let keyData = key.data(using: String.Encoding.utf8),
          let cryptData = NSMutableData(length: input.count + kCCBlockSizeAES128)
    else {
        throw CocoaError.error(.coderInvalidValue)
    }

    let keyLength              = size_t(kCCKeySizeAES128)
    let operation: CCOperation = UInt32(kCCDecrypt)
    let algoritm:  CCAlgorithm = UInt32(kCCAlgorithmAES128)
    let options:   CCOptions   = UInt32(options)

    var numBytesEncrypted :size_t = 0

    let cryptStatus = CCCrypt(operation,
                              algoritm,
                              options,
                              (keyData as NSData).bytes, keyLength,
                              iv,
                              (input as NSData).bytes, input.count,
                              cryptData.mutableBytes, cryptData.length,
                              &numBytesEncrypted)

    guard UInt32(cryptStatus) == UInt32(kCCSuccess) else {
        throw CocoaError.error(.coderInvalidValue)
    }
    cryptData.length = Int(numBytesEncrypted)

    guard let unencryptedString = String(data: cryptData as Data, encoding: .utf8) else {
        throw CocoaError.error(.coderInvalidValue)
    }

    return unencryptedString
}
