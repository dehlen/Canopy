import PromiseKit
import StoreKit
import AppKit

class SubscribeViewController: NSViewController {
    @IBOutlet var subscribeButton: NSButton!
    @IBOutlet var cancelButton: NSButton!
    @IBOutlet var spinner: NSProgressIndicator!

    private var price: String? {
        didSet {
            if let price = price {
                subscribeButton.title = "\(price) / Month"
            } else {
                subscribeButton.title = ""
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        app.subscribeViewController = self

        subscribeButton.keyEquivalent = "\r"
        
        spinner.startAnimation(self)

        firstly {
            SKProductsRequest.canopy.start(.promise)
        }.compactMap {
            $0.products.first?.localizedPrice
        }.done {
            self.price = $0
            self.subscribeButton.isEnabled = true
        }.ensure {
            self.spinner.stopAnimation(self)
        }.catch {
            self.subscribeButton.title = "Error"
            alert($0)
        }
    }

    func paymentFailed(sender: Any) {
        spinner.stopAnimation(sender)
        let p = price
        price = p // reset subscribe text
        subscribeButton.isEnabled = true
        cancelButton.isEnabled = true
    }

    deinit {
        app.subscribeViewController = nil
    }

    @IBAction func subscribe(sender: Any) {
        spinner.startAnimation(self)
        subscribeButton.title = ""
        subscribeButton.isEnabled = false
        cancelButton.isEnabled = false

        app.subscribe(sender: sender)
    }
}

extension SKProduct {
    var localizedPrice: String? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        return formatter.string(from: price)
    }
}
