import enum PMKFoundation.PMKHTTPError
import PMKStoreKit
import Foundation
import PromiseKit
import StoreKit
import xp

public protocol SubscriptionManagerDelegate: class {
    func subscriptionFinished(error: Error?, file: StaticString, line: UInt)
}

public class SubscriptionManager: NSObject, SKPaymentTransactionObserver {
    public weak var delegate: SubscriptionManagerDelegate?

    @objc
    public dynamic var hasVerifiedReceipt = false

    static weak var shared: SubscriptionManager?

    public override init() {
        super.init()

        assert(SubscriptionManager.shared == nil)
        SubscriptionManager.shared = self

        //TODO probably should instead trigger this (here) when token changes
        //NOTE this implies any number of people can gain from the current duration of any receipt
        // but in practice maybe we don't care
        postReceipt().cauterize()
        SKPaymentQueue.default().add(self)
    }

    deinit {
        SKPaymentQueue.default().remove(self)
    }

    /// only starts the process, the delegate finishes it
    public func subscribe(to product: SKProduct) throws {
        guard let login = creds?.username else {
            throw Error.notSignedIn
        }
        let payment = SKMutablePayment(product: product)
        payment.applicationUsername = login.data(using: .utf8)?.sha256
        SKPaymentQueue.default().add(payment)
    }

    public func refreshReceipt() -> Promise<Void> {
        guard let token = creds?.token else {
            return Promise(error: Error.notSignedIn)
        }

        return firstly {
            SKReceiptRefreshRequest(receiptProperties: nil).start(.promise)
        }.then {
            self.postReceipt(url: $0, token: token)
        }
    }

    public func products() -> Promise<[SKProduct]> {
        return firstly {
            SKProductsRequest.canopy.start(.promise)
        }.map {
            $0.products.sorted{ a, _ in a.subscriptionPeriod?.unit == .year }
        }
    }

    public func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        func handle(transaction: SKPaymentTransaction) {
            switch transaction.transactionState {
            case .purchasing:
                break
            case .purchased, .restored:
                //FIXME for start+postReceipt we don't nee to do multiple iterations of that
                // and at least in the sandbox we seem to get multiple new transactions on startup
                // but this is probably just Apple doing strange test-y things
                firstly {
                    postReceipt()
                }.done {
                    self.delegate?.subscriptionFinished(error: .none, file: #file, line: #line)
                }.catch(policy: .allErrors) {
                    self.delegate?.subscriptionFinished(error: $0, file: #file, line: #line)
                }.finally {
                    // if rejected user must use the “Restore” button
                    queue.finishTransaction(transaction)
                }
            case .failed:
                delegate?.subscriptionFinished(error: transaction.error ?? Error.stateMachineViolation, file: #file, line: #line)
                queue.finishTransaction(transaction)
            case .deferred:
                delegate?.subscriptionFinished(error: Error.deferred, file: #file, line: #line)
            @unknown default:
                fatalError()
            }
        }

        for transaction in transactions {
            handle(transaction: transaction)
        }
    }

    private func postReceipt(url: URL? = nil, token: String? = nil) -> Promise<Void> {
        let receipt: URL
        if let url = url {
            receipt = url
        } else if let url = Bundle.main.appStoreReceiptURL {
            receipt = url
        } else {
            return Promise(error: Error.noReceipt)
        }
        guard FileManager.default.isReadableFile(atPath: receipt.path) else {
            return Promise(error: Error.noReceipt)
        }
        guard let token = token ?? creds?.token else {
            return Promise(error: Error.notSignedIn)
        }

        return DispatchQueue.global().async(.promise) {
            let receipt = try Data(contentsOf: receipt).base64EncodedData()
            var rq = URLRequest(.receipt)
            rq.httpMethod = "POST"
            rq.httpBody = receipt
            rq.setValue(token, forHTTPHeaderField: "Authorization")
          #if os(iOS)
            // archaically we didn't specify this on macOS so we are preserving this behavior going forward
            rq.setValue("iOS", forHTTPHeaderField: "X-Platform")
          #endif
          #if DEBUG
            rq.setValue("true", forHTTPHeaderField: "X-Debug-Mode")
          #endif
            return rq
        }.then { rq in
            URLSession.shared.dataTask(.promise, with: rq).validate()
        }.done { _ in
            self.hasVerifiedReceipt = true
        }.recover {
            if case PMKHTTPError.badStatusCode(403, _, _) = $0 {
                throw Error.subscriptionExpired
            } else if case PMKHTTPError.badStatusCode(402, _, _) = $0 {
                throw Error.noSubscriptionFound
            } else {
                throw $0
            }
        }
    }

    enum Error: TitledError {
        case deferred
        case productNotFound
        case subscriptionExpired
        case stateMachineViolation
        case noReceipt
        case notSignedIn
        case noSubscriptionFound

        var errorDescription: String? {
            switch self {
            case .productNotFound:
                return "SKProduct not found, please contact support."
            case .deferred:
                return "Thank you! You can continue to use Canopy while your purchase is pending an approval from your guardian."
            case .stateMachineViolation:
                return "Skynet has taken over."
            case .subscriptionExpired:
                return "Your subscription has expired."
            case .noReceipt:
                return "No receipt found."
            case .notSignedIn:
                return "Please sign in first; otherwise there would be no value to your subscription."
            case .noSubscriptionFound:
                return "We could not find a subscription for your account."
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
            case .subscriptionExpired, .noSubscriptionFound:
                return "Restore Purchase Error"
            case .notSignedIn:
                return "Sign‐in Required"
            }
        }
    }
}

extension SKProduct {
#if os(macOS)
    static var canopy: Set<String> { return ["sub1", "sub3"] }
#else
    static var canopy: Set<String> { return ["sub2"] }
#endif
}

extension SKProductsRequest {
    static var canopy: SKProductsRequest {
        return .init(productIdentifiers: SKProduct.canopy)
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

private extension SKReceiptRefreshRequest {
    /**
     Requests an updated receipt.
     - Returns: A promise fulfilled with Bundle.main.appStoreReceiptURL if not `nil`.
     */
    func start(_: PMKNamespacer) -> Promise<URL> {

        class SKDelegate: NSObject, SKRequestDelegate {
            let (promise, seal) = Promise<Void>.pending()
            var retainCycle: SKDelegate?

            @objc fileprivate func request(_ request: SKRequest, didFailWithError error: Error) {
                seal.reject(error)
            }

            @objc func requestDidFinish(_ request: SKRequest) {
                seal.fulfill(())
            }
        }

        let proxy = SKDelegate()
        delegate = proxy
        proxy.retainCycle = proxy
        start()
        return firstly {
            proxy.promise
        }.compactMap(on: .global()) {
            Bundle.main.appStoreReceiptURL
        }.ensure {
            proxy.retainCycle = nil
        }
    }
}

public extension SKProduct {
    var localizedPrice: String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        return formatter.string(from: price)
    }

    var buttonText: String {
        let price = localizedPrice ?? "$??"
        var duration: String {
            switch subscriptionPeriod?.unit {
            case .day?:
                return "Day"
            case .week?:
                return "Week"
            case .month?:
                return "Month"
            case .year?:
                return "Year"
            case .none:
                fallthrough
            @unknown default:
                return "??"
            }
        }
        return "\(price) / \(duration)"
    }
}
