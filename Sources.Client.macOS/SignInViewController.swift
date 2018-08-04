import AppKit

class SignInViewController: NSViewController {
    private var ref: Any?

    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(dismissIfSignedIn), name: .credsUpdated, object: nil)
    }

    @objc private func dismissIfSignedIn() {
        if creds?.token != nil {
            dismiss(nil)
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.preventsApplicationTerminationWhenModal = false

        if app.deviceToken == nil {
            performSegue(withIdentifier: "WaitingToken", sender: self)
        }
    }

    @IBAction func signIn(sender: NSButton) {
        //TODO wait for token and show message to that effect
        guard let deviceToken = app.deviceToken else {
            return alert(message: "Pending Device Token", title: "Please check your Internet connection.")
        }

        performSegue(withIdentifier: "Authenticating", sender: sender)

        if let url = URL.signIn(deviceToken: deviceToken) {
            NSWorkspace.shared.open(url)
        }
    }
}

class WaitingTokenViewController: NSViewController {
    private var ref: Any?

    override func viewDidLoad() {
        super.viewDidLoad()

        ref = app.observe(\.deviceToken, options: .new) { [weak self] _, value in
            if let value = value.newValue, value != nil {
                self?.dismiss(nil)
            }
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.preventsApplicationTerminationWhenModal = false
    }
}

class WaitingAuthViewController: NSViewController {
    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.preventsApplicationTerminationWhenModal = false
    }
}
