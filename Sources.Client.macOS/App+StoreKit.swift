import PromiseKit
import StoreKit
import AppKit

extension SKProductsRequest {
    static var canopy: SKProductsRequest {
        return .init(productIdentifiers: ["sub1"])
    }
}

private enum E: TitledError {
    case productNotFound
    case deferred
    case stateMachineViolation

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "SKProduct not found, please contact support."
        case .deferred:
            return "Thank you! You can continue to use Canopy while your purchase is pending an approval from your parent."
        case .stateMachineViolation:
            return "Skynet has taken over."
        }
    }

    var title: String {
        switch self {
        case .productNotFound:
            return "Unexpected Error"
        case .deferred:
            return "Waiting For Approval"
        case .stateMachineViolation:
            return "State Machine Error"
        }
    }
}

extension AppDelegate: SKPaymentTransactionObserver {
    @IBAction func restorePurchases(sender: Any) {
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    func finish(error: Error?) {
        DispatchQueue.main.async { [weak subscribeViewController] in
            if let error = error {
                subscribeViewController?.paymentFailed(sender: self)
                if let error = error as? SKError, error.code == .paymentCancelled { return }
                alert(error)
            } else {
                subscribeViewController?.dismiss(self)
            }
        }
    }

    @IBAction func subscribe(sender: Any) {

        //FIXME what if the user signed—out during this?
        //SOLUTION modal blocker even for menu during this

        guard let login = creds?.username else {
            alert(message: "As a courtesy, we don’t allow you to subscribe before we can provide you with content.", title: "Sign‐in Required")
            finish(error: nil)
            return
        }

        let request = SKProductsRequest.canopy
        firstly {
            request.start(.promise)
        }.done {
            guard let product = $0.products.first else {
                throw E.productNotFound
            }
            let payment = SKMutablePayment(product: product)
            payment.applicationUsername = login.data(using: .utf8)?.sha256
            SKPaymentQueue.default().add(payment)
        }.catch {
            self.finish(error: $0)
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
                    self.finish(error: .none)
                }.catch {
                    self.finish(error: $0)
                }
            case .failed:
                finish(error: transaction.error ?? E.stateMachineViolation)
            case .deferred:
                finish(error: E.deferred)
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

    func postReceiptIfPossibleNoErrorUI() {
        guard let url = Bundle.main.appStoreReceiptURL, let token = creds?.token, FileManager.default.isReadableFile(atPath: url.path) else {
            return
        }
        _postReceipt(token: token, receipt: url).cauterize()
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
