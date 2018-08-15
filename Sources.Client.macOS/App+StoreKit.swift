import PromiseKit
import StoreKit
import AppKit

private enum CanopyStoreKitError: Error {
    case productNotFound
}

extension AppDelegate: SKPaymentTransactionObserver {
    @IBAction func subscribe(sender: Any) {

        //FIXME what if the user signed—out during this?
        //SOLUTION modal blocker even for menu during this

        guard let login = creds?.username else {
            return Canopy.alert(message: "As a courtesy, we don’t allow you to subscribe before we can provide you with content.", title: "Sign in Required")
        }

        let request = SKProductsRequest(productIdentifiers: ["sub1"])
        firstly {
            request.start(.promise)
        }.done {
            guard let product = $0.products.first else {
                throw CanopyStoreKitError.productNotFound
            }
            let payment = SKMutablePayment(product: product)
            payment.applicationUsername = login.data(using: .utf8)?.sha256
            SKPaymentQueue.default().add(payment)
        }.catch {
            Canopy.alert($0)
        }
    }

    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {

        func handle(transaction: SKPaymentTransaction) {
            switch transaction.transactionState {
            case .purchasing:
                print(#function, "purchasing", transaction)
            case .purchased, .restored:
                print(#function, "purchased OR restored", transaction)
                guard let url = Bundle.main.appStoreReceiptURL, let token = creds?.token else {
                    return print("No receipt or auth!")
                }
                firstly {
                    _postReceipt(token: token, receipt: url)
                }.done {
                    queue.finishTransaction(transaction)
                }.catch {
                    alert($0)
                }
            case .failed:
                print(#function, "failed", transaction)
                if let error = transaction.error as? SKError, error.code == .paymentCancelled { return }
                alert(transaction.error ?? CocoaError.error(.coderInvalidValue))
            case .deferred:
                //TODO should I finish or what?
                print(#function, "deferred", transaction)
            }
        }

        for transaction in transactions {
            handle(transaction: transaction)
        }
    }

    private func _postReceipt(token: String, receipt: URL) -> Promise<Void> {
        return DispatchQueue.global().async(.promise) {
            let receiptData = try Data(contentsOf: receipt).base64EncodedString()
            let receipt = Receipt(isProduction: isProductionAPNsEnvironment, base64: receiptData)
            var rq = URLRequest(.receipt)
            rq.httpMethod = "POST"
            rq.httpBody = try JSONEncoder().encode(receipt)
            rq.setValue("application/json", forHTTPHeaderField: "Content-Type")
            rq.setValue(token, forHTTPHeaderField: "Authorization")
            return rq
        }.then { rq in
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.done { _ in
            NotificationCenter.default.post(name: .receiptVerified, object: nil)
        }
    }

    func postReceiptIfPossible() {
        guard let url = Bundle.main.appStoreReceiptURL, let token = creds?.token, FileManager.default.isReadableFile(atPath: url.path) else {
            return
        }
        firstly {
            _postReceipt(token: token, receipt: url)
        }.catch {
            alert($0)
        }
    }
}

import CommonCrypto

private extension Data {
    var sha256: String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        withUnsafeBytes { bytes -> Void in
            CC_SHA256(bytes, CC_LONG(count), &hash)
        }
        return Data(bytes: hash, count: hash.count).base64EncodedString()
    }
}

extension Notification.Name {
    static var receiptVerified: Notification.Name {
        return .init("com.codebasesaga.receiptVerified")
    }
}
