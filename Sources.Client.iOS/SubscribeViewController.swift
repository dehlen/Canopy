import SafariServices
import PromiseKit
import UIKit

class SubscribeViewController_iOS: UIViewController {
    @IBOutlet weak var privacyPolicyButton: UIButton!
    @IBOutlet weak var subscribeButton: UIButton!
    @IBOutlet weak var restoreButton: UIButton!
    @IBOutlet weak var termsButton: UIButton!
    @IBOutlet weak var spinner: UIActivityIndicatorView!

    var cancelButton: UIBarButtonItem {
        return navigationItem.leftBarButtonItem!
    }

    private var price: String?

    func spin() {
        UIView.animate(.easeInOutQuad, duration: 0.2) {
            self.subscribeButton.isEnabled = false
            self.subscribeButton.setTitle("", for: .normal)
            self.subscribeButton.layoutIfNeeded()
            self.spinner.startAnimating()
        }
    }

    func setSubscribeButtonTitleToPrice() {
        let title = price.map{ "\($0) / Month" } ?? "Error"
        UIView.animate(.easeInOutQuad, duration: 0.2) {
            self.subscribeButton.setTitle(title, for: .normal)
            self.spinner.stopAnimating()
            self.subscribeButton.isEnabled = self.price != nil
            self.subscribeButton.layoutIfNeeded()
        }
    }

    var mgr: SubscriptionManager {
        return AppDelegate.shared.subscriptionManager!
    }

    override func viewDidLoad() {
        //spinner.color = .disabledColor
        spin()

        firstly {
            mgr.price()
        }.done { price in
            self.price = price
            self.restoreButton.isEnabled = true
            self.subscribeButton.isEnabled = true
        }.cauterize().finally {
            self.setSubscribeButtonTitleToPrice()
        }
    }

    @IBAction private func subscribe() {
        cancelButton.isEnabled = false
        restoreButton.isEnabled = false
        subscribeButton.isEnabled = false
        spin()
        mgr.subscribe().catch{ self.errorHandler($0) }
    }

    func errorHandler(_ error: Swift.Error, title: String? = nil) {
        cancelButton.isEnabled = true
        restoreButton.isEnabled = true
        setSubscribeButtonTitleToPrice()
        alert(error: error, title: title)
    }

    @IBAction private func restore() {
        cancelButton.isEnabled = false
        restoreButton.isEnabled = false
        subscribeButton.isEnabled = false
        spin()

        firstly {
            mgr.refreshReceipt()
        }.done {
            self.dismiss(animated: true)  // receipt is verified and current
        }.catch {
            self.errorHandler($0, title: "Refresh Receipt")
        }
    }

    @IBAction private func cancel() {
        dismiss(animated: true)
    }

    @IBAction private func showTermsOfUse() {
        present(SFSafariViewController(url: .termsOfUse), animated: true)
    }

    @IBAction private func showPrivacyPolicy() {
        present(SFSafariViewController(url: .privacyPolicy), animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        AppDelegate.shared.subscribeViewController = self
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        AppDelegate.shared.subscribeViewController = nil
    }
}

class OutlineButton: UIButton {
    override func tintColorDidChange() {
        super.tintColorDidChange()
        layer.borderColor = (isEnabled ? tintColor : .disabledColor).cgColor
        layer.borderWidth = 1
        layer.cornerRadius = 10
        contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
    }

    override var isEnabled: Bool {
        didSet {
            tintColorDidChange()
        }
    }
}
