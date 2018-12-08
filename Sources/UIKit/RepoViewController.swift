import UIKit
import Cake

class RepoViewController: UIViewController {
    let top = UIView()
    let blur = UIVisualEffectView()
    let knob = UISwitch()
    let repo: Repo
    let status = UILabel()
    var toggle: ((Bool) -> Void)?
    let enrolled: Feasability
    let container = UIStackView()
    var completion: (() -> Void)?

    enum Feasability {
        case active
        case feasible
        case impossible(EnrollmentsManager.Status.Alert)
    }

    init(repo: Repo, enrolled: Feasability) {
        self.repo = repo
        self.enrolled = enrolled
        super.init(nibName: nil, bundle: nil)
        transitioningDelegate = self
        modalPresentationStyle = .custom
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        top.translatesAutoresizingMaskIntoConstraints = false
        top.backgroundColor = UIColor(white: 0, alpha: 0.375)

        let effect = UIBlurEffect(style: .dark)
        blur.effect = effect
        let vibrancy = UIVisualEffectView(effect: UIVibrancyEffect(blurEffect: effect))

        view.addSubview(blur)
        blur.contentView.addSubview(vibrancy)
        vibrancy.contentView.addSubview(container)
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layoutMargins = UIEdgeInsets(top: 32, left: 32, bottom: 32, right: 32)
        container.isLayoutMarginsRelativeArrangement = true
        container.alignment = .center
        container.axis = .vertical
        NSLayoutConstraint.activate([
            container.leftAnchor.constraint(equalTo: view.leftAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            container.rightAnchor.constraint(equalTo: view.rightAnchor),
        ])

        top.layer.shadowRadius = 7
        top.layer.shadowOpacity = 0.617
        top.layer.shadowOffset.height = 0
        top.layer.shadowPath = UIBezierPath(rect: CGRect(x: -15, y: view.bounds.height, width: view.bounds.width + 30, height: 50)).cgPath
        top.clipsToBounds = true

        status.numberOfLines = 0
        container.spacing = 32
        status.font = .preferredFont(forTextStyle: .subheadline)

        let knobDescription = UILabel()
        let knobStackView = UIStackView(arrangedSubviews: [knob, knobDescription])
        knobStackView.spacing = 10
        knobStackView.alignment = .center

        knobDescription.font = .preferredFont(forTextStyle: .body)
        knobDescription.text = "Receive push notifications"
        knobDescription.adjustsFontForContentSizeCategory = true

        switch enrolled {
        case .active:
            knob.isOn = true
            status.isHidden = true
        case .feasible:
            status.isHidden = true
        case .impossible(let alert):
            let knobOn: Bool
            let text: String
            status.isHidden = false
            switch alert {
            case .cannotCreateHook:
                knobOn = false
                text = """
                You cannot install the webhook for this repository.

                Contact the owner and ask them to install the Canopy webhook.

                They do not need to use the app to do this, (see the Canopy FAQ) but using the app is easiest.
                """
            case .hookNotInstalled:
                knobOn = true
                text = """
                The webhook for this repository is not installed.

                Tap the switch below to install it.
                """
            case .paymentRequired:
                knobOn = true
                text = """
                You are enrolled for this repository but your subscription has lapsed.

                Tap the switch below to renew your subscription.
                """
            }
            status.text = text
            knob.isEnabled = knobOn
            knobDescription.alpha = knobOn ? 1.0 : 0.5
        }

        container.addArrangedSubview(status)
        container.addArrangedSubview(knobStackView)

        blur.translatesAutoresizingMaskIntoConstraints = false
        vibrancy.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            blur.leftAnchor.constraint(equalTo: container.leftAnchor),
            blur.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            blur.rightAnchor.constraint(equalTo: container.rightAnchor),
            blur.topAnchor.constraint(equalTo: container.topAnchor),
        ])
        NSLayoutConstraint.activate([
            blur.leftAnchor.constraint(equalTo: vibrancy.leftAnchor),
            blur.bottomAnchor.constraint(equalTo: vibrancy.bottomAnchor),
            blur.rightAnchor.constraint(equalTo: vibrancy.rightAnchor),
            blur.topAnchor.constraint(equalTo: vibrancy.topAnchor),
        ])

        view.addSubview(top)
        NSLayoutConstraint.activate([
            top.leftAnchor.constraint(equalTo: view.leftAnchor),
            top.bottomAnchor.constraint(equalTo: blur.topAnchor),
            top.rightAnchor.constraint(equalTo: view.rightAnchor),
            top.heightAnchor.constraint(equalTo: view.heightAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(_dismiss))
        view.addGestureRecognizer(tap)
        tap.delegate = self

        knob.addTarget(self, action: #selector(toggleEnrollment), for: .valueChanged)
    }

    @objc private func _dismiss() {
        dismiss(animated: true)
    }

    @objc private func toggleEnrollment() {
        toggle?(knob.isOn)
    }
}

extension RepoViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return touch.view == top
    }
}

extension RepoViewController: UIViewControllerTransitioningDelegate {
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return self
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return self
    }
}

extension RepoViewController: UIViewControllerAnimatedTransitioning {
    public func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.3
    }

    // This method can only  be a nop if the transition is interactive and not a percentDriven interactive transition.
    public func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        enum Direction {
            case present
            case dismiss
        }

        let direction = ctx.viewController(forKey: .to) is RepoViewController
            ? Direction.present
            : .dismiss

        let tableView = AppDelegate.shared.reposViewController?.tableView

        func blank() {
            top.alpha = 0
            let ty = blur.bounds.height
            top.transform.ty = ty
            blur.transform.ty = ty
        }

        if case .present = direction {
            ctx.containerView.addSubview(view)
            view.frame = ctx.containerView.bounds
            view.layoutIfNeeded()
            blank()
        }

        let duration = transitionDuration(using: ctx)

        UIView.animate(.easeInOutQuint, duration: duration) {
            switch direction {
            case .present:
                top.alpha = 1
                self.blur.transform.ty = 0
                self.top.transform.ty = 0

                if let tv = tableView, let ip = tv.indexPathForSelectedRow {
                    let rect = tv.rectForRow(at: ip)
                    let convertedRect = tv.convert(rect, to: self.view)
                    if convertedRect.maxY > self.blur.frame.minY {
                        tv.contentOffset.y += convertedRect.maxY - self.blur.frame.minY + 16
                    }
                }

            case .dismiss:
                blank()
                if let tv = tableView {
                    // if we scrolled beyond the bounce region to show the header how
                    // then scroll back to the bounce line
                    let H = tv.contentSize.height - view.bounds.height + tv.adjustedContentInset.top
                    if tv.contentOffset.y > H {
                        tv.contentOffset.y = H
                    }
                }
                self.completion?()
            }
        }.done {
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
    }
}
