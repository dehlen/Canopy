import LegibleError
import PerfectHTTP
import Foundation
import PromiseKit
import Roots

private enum E: Error {
    case noSuchDirectory
    case invalidFilename(String)
}

func refreshReceiptsHandler(request rq: HTTPRequest) throws -> Promise<Void> {

    print("Re‐validating receipts…")

    guard let ls = FileManager.default.enumerator(atPath: "../receipts") else {
        throw E.noSuchDirectory
    }

    let generator = AnyIterator<Promise<Void>> { () -> Promise<Void>? in
        guard let filename = ls.nextObject() as? String else {
            return nil
        }

        print("~/receipts/\(filename)")

        //TODO need to get error out
        do {
            let receipt = try String(contentsOfFile: "../receipts/\(filename)")
            let sku = filename.filePathExtension.chuzzled()
            let uidString: String
            if let sku = sku {
                uidString = String(filename.dropLast(sku.count + 1))
            } else {
                uidString = filename
            }

            guard let userId = Int(uidString) else {
                throw E.invalidFilename(filename)
            }
            return validateReceipt(userId: .value(userId), sku: sku, receipt: receipt).recover {
                if "\($0)" != "expired", "\($0)" != "noExpiryDate" {
                    print("error:", $0.legibleDescription)
                }
            }
        } catch {
            return Promise(error: error)
        }
    }

    return when(fulfilled: generator, concurrently: 4).asVoid()
}
