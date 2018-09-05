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
    case notSignedIn
    case subscriptionExpired
    case noReceipt

    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "SKProduct not found, please contact support."
        case .deferred:
            return "Thank you! You can continue to use Canopy while your purchase is pending an approval from your parent."
        case .stateMachineViolation:
            return "Skynet has taken over."
        case .notSignedIn:
            return "As a courtesy, we won’t subscribe before we can provide you with content. Please sign in first."
        case .subscriptionExpired:
            return "Your subscription has expired."
        case .noReceipt:
            return "No receipt found."
        }
    }

    var title: String {
        switch self {
        case .productNotFound:
            return "Unexpected Error"
        case .deferred:
            return "Waiting For Approval"
        case .stateMachineViolation, .noReceipt:
            return "State Machine Error"
        case .notSignedIn:
            return "Sign‐in Required"
        case .subscriptionExpired:
            return "Restore Purchase Error"
        }
    }
}

extension AppDelegate: SKPaymentTransactionObserver {
    func finish(error: Error?, line: UInt = #line) {
        DispatchQueue.main.async { [weak subscribeViewController] in
            if let error = error {
                subscribeViewController?.paymentFailed(sender: self)
                if let error = error as? SKError, error.code == .paymentCancelled { return }
                alert(error, line: line)
            } else {
                subscribeViewController?.dismiss(self)
            }
        }
    }

    @IBAction func subscribe(sender: Any) {

        //FIXME what if the user signed—out during this?
        //SOLUTION modal blocker even for menu during this

        guard let login = creds?.username else {
            return finish(error: E.notSignedIn)
        }

        firstly {
            SKProductsRequest.canopy.start(.promise)
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
                break
            case .purchased, .restored:
                firstly {
                    try start()
                }.then { token, url in
                    self.postReceipt(token: token, receipt: url)
                }.ensure {
                    // if rejected user must use the “Restore” button
                    queue.finishTransaction(transaction)
                }.done {
                    self.finish(error: .none)
                }.catch {
                    if case PMKHTTPError.badStatusCode(403, _, _) = $0 {
                        self.finish(error: E.subscriptionExpired)
                    } else {
                        self.finish(error: $0)
                    }
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

    func postReceiptIfPossibleNoErrorUI() {
        guard let url = Bundle.main.appStoreReceiptURL, let token = creds?.token, FileManager.default.isReadableFile(atPath: url.path) else {
            return
        }
        postReceipt(token: token, receipt: url).cauterize()
    }

    func postReceipt(token: String, receipt: URL) -> Promise<Void> {
        return DispatchQueue.global().async(.promise) {
            let receipt = try Data(contentsOf: receipt).base64EncodedData()
            var rq = URLRequest(.receipt)
            rq.httpMethod = "POST"
            rq.httpBody = receipt
            rq.setValue(token, forHTTPHeaderField: "Authorization")
            return rq
        }.then { rq in
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.done { _ in
            self.hasVerifiedReceipt = true
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

private func start() throws -> Promise<(String, URL)> {
    guard let token = creds?.token else {
        throw E.notSignedIn
    }
    guard let url = Bundle.main.appStoreReceiptURL else {
        throw E.noReceipt
    }
    return .value((token, url))
}
