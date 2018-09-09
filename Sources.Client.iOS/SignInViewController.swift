import UserNotifications
import SafariServices
import PromiseKit
import UIKit

class SignInViewController: UIViewController {

    //TODO if push notifications already enabled then wait for token and skip first button

    let label1 = UILabel()
    let button1 = OutlineButton(type: .system)
    let button2 = OutlineButton(type: .system)
    let check1 = UILabel()
    let check2 = UILabel()

    override func viewDidLoad() {
        label1.text = .defaultLabel
        label1.numberOfLines = 0
        label1.textAlignment = .center

        for c in [check1, check2] {
            c.text = "✓"
            c.textColor = .canopyGreen
            c.alpha = 0
        }

        button1.setTitle("Enable Push Notifications", for: .normal)
        button1.titleLabel!.font = .preferredFont(forTextStyle: .headline)
        button1.addTarget(self, action: #selector(requestPushNotifications), for: .touchUpInside)

        button2.setTitle("Sign In With GitHub", for: .normal)
        button2.titleLabel!.font = .preferredFont(forTextStyle: .headline)
        button2.alpha = 0
        button2.addTarget(self, action: #selector(signIn), for: .touchUpInside)

        view.backgroundColor = .white

        let terms = UIButton(type: .system)
        terms.setTitle("Terms of Use", for: .normal)
        terms.addTarget(self, action: #selector(openTermsOfUse), for: .touchUpInside)
        terms.titleLabel!.font = .preferredFont(forTextStyle: .caption2)

        for v in [label1, button1, button2, check1, check2, terms] {
            view.addSubview(v)
            v.translatesAutoresizingMaskIntoConstraints = false
        }

        NSLayoutConstraint.activate([
            label1.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, constant: -80),
            label1.widthAnchor.constraint(lessThanOrEqualToConstant: 300),
            label1.centerXAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerXAnchor),

            button1.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            button1.topAnchor.constraint(equalTo: label1.bottomAnchor, constant: 40),
            button1.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            button2.topAnchor.constraint(equalTo: button1.bottomAnchor, constant: 20),
            button2.widthAnchor.constraint(equalTo: button1.widthAnchor),
            button2.centerXAnchor.constraint(equalTo: button1.centerXAnchor),

            check1.centerYAnchor.constraint(equalTo: button1.centerYAnchor),
            check2.centerYAnchor.constraint(equalTo: button2.centerYAnchor),

            check1.leadingAnchor.constraint(equalTo: button1.trailingAnchor, constant: 16),
            check2.leadingAnchor.constraint(equalTo: button2.trailingAnchor, constant: 16),

            terms.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            terms.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])

        checkNotificationSettings()
        NotificationCenter.default.addObserver(self, selector: #selector(checkNotificationSettings), name: UIApplication.didBecomeActiveNotification, object: nil)

    #if !targetEnvironment(simulator)
        ref = AppDelegate.shared.observe(\.deviceToken, options: .initial) { [unowned self] appDelegate, _ in
            if appDelegate.deviceToken != nil {
                self.checkNotificationSettings()
            }
        }
    #endif
    }

    @objc private func checkNotificationSettings() {
    #if !targetEnvironment(simulator)
        Guarantee(resolver: UNUserNotificationCenter.current().getNotificationSettings).done {
            if $0.authorizationStatus == .denied {
                self.label1.text = """
                    Notifications are disabled, please enable notifications in the device Settings app.
                    """
                self.check1.text = "⚠️"
                self.check1.alpha = 1
                self.button1.isEnabled = false
                self.button2.alpha = 0
            } else if AppDelegate.shared.deviceToken != nil {
                self.check1.text = "✓"
                self.check1.alpha = 1
                self.label1.text = .defaultLabel
                self.transition()
            } else {
                self.button1.isEnabled = true
                self.check1.text = "✓"
                self.check1.alpha = 0
                self.label1.text = .defaultLabel
                self.button2.alpha = 0
            }
        }
    #endif
    }

    private var ref: Any?

    @objc func requestPushNotifications() {
        button1.isEnabled = false

        Promise { seal in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound], completionHandler: seal.resolve)
        }.done { granted in
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                self.checkNotificationSettings()
            }
        }.catch {
            alert(error: $0)
        }
    }

    private func transition() {
        guard self.button2.alpha == 0 else { return }

        self.button2.transform.ty = 20

        firstly {
            UIView.animate(.easeInOutQuint, duration: 0.3) {
                self.check1.alpha = 1
                self.button1.isEnabled = false
            }
        }.then(on: .main) {
            UIView.animate(.easeInOutQuint, duration: 0.3) {
                self.button2.transform.ty = 0
                self.button2.alpha = 1
            }
        }

    }

    @objc func signIn() {
    #if !targetEnvironment(simulator)
        guard let deviceToken = AppDelegate.shared.deviceToken else { return }
        guard let url = URL.signIn(deviceToken: deviceToken) else { return }
        UIApplication.shared.open(url)
    #endif
    }

    @objc func openTermsOfUse() {
        present(SFSafariViewController(url: .termsOfUse), animated: true)
    }
}

private extension String {
    static let defaultLabel = """
        Stay on top of development with Canopy. Receive push notifications for events on your repositories at GitHub.
        """
}
