import PromiseKit
import StoreKit
import AppKit

class SubscribeViewController: NSViewController {
    @IBOutlet var subscribeButton: NSButton!
    @IBOutlet var restoreButton: NSButton!
    @IBOutlet var cancelButton: NSButton!
    @IBOutlet var spinner: NSProgressIndicator!

    var mgr: SubscriptionManager {
        return app.subscriptionManager
    }

    var spinCounter: Int = 0 {
        didSet {
            dispatchPrecondition(condition: .onQueue(.main))

            if spinCounter > 0 {
                spinner.startAnimation(self)
                restoreButton.isEnabled = false
                subscribeButton.isEnabled = false
                subscribeButton.title = ""
            } else {
                spinner.stopAnimation(self)
                restoreButton.isEnabled = true
                subscribeButton.isEnabled = true
                subscribeButton.priceValue = price
                cancelButton.isEnabled = true
            }
        }
    }

    private var price: Result<String>? {
        didSet {
            subscribeButton.priceValue = price
        }
    }

    @IBAction func refreshReceipt(sender: NSButton) {
        sender.isEnabled = false
        spinCounter += 1

        firstly {
            mgr.refreshReceipt()
        }.done { [weak self] in
            self?.dismiss(self)
        }.ensure { [weak self] in
            self?.spinCounter -= 1
        }.catch {
            let pair: (String, Int) = { ($0.domain, $0.code) }($0 as NSError)
            if ("SKErrorDomain", 2) == pair { return } // user-cancelled

            if case PMKHTTPError.badStatusCode(403, _, _) = $0 {
                alert(message: "Your subscription has expired.", title: "Refresh Receipt")
            } else if case CocoaError.fileReadNoSuchFile = $0 {
                alert(message: "No subscription on record.", title: "Refresh Receipt")
            } else {
                // ^^ what you get when the user cancels the operation
                alert(error: $0)
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        app.subscribeViewController = self
        subscribeButton.keyEquivalent = "\r"
        spinCounter += 1

        firstly {
            mgr.price()
        }.tap(on: .main) {
            self.price = $0
        }.ensure {
            self.spinCounter -= 1
        }.catch {
            alert(error: $0)
        }
    }

    func paymentFailed(sender: Any) {
        spinCounter -= 1
    }

    deinit {
        app.subscribeViewController = nil
    }

    @IBAction func subscribe(sender: Any) {
        spinCounter += 1
        cancelButton.isEnabled = false  // Apple will do a bunch of dialogs whatever so we cannot allow cancel
        mgr.subscribe().catch {
            // if it doesn't initally fail it calls us back later
            // also may fail later, but this won't be called then
            self.spinCounter -= 1
            self.cancelButton.isEnabled = true
            alert(error: $0)
        }
    }

    func errorHandler(error: Error?, line: UInt = #line) {
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else { return }
            if let error = error {
                self.paymentFailed(sender: self)
                if let error = error as? SKError, error.code == .paymentCancelled { return }
                alert(error: error, title: "App Store Error", line: line)
            } else {
                self.dismiss(self)
            }
        }
    }
}

private extension NSButton {
    var priceValue: Result<String>? {
        set {
            switch newValue {
            case .fulfilled(let price)?:
                title = "\(price) / Month"
            case .rejected?:
                title = "Error"
            case .none:
                title = ""
            }
        }
        get {
            fatalError()
        }
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
