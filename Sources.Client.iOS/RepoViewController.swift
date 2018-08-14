import PromiseKit
import UIKit

class RepoViewController: UIViewController {
    let base = UIStackView()
    let repo: Repo
    var completion: (() -> Void)?

    init(repo: Repo) {
        self.repo = repo
        super.init(nibName: nil, bundle: nil)
        transitioningDelegate = self
        modalPresentationStyle = .custom
    }

    required init(coder: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(white: 0, alpha: 0.375)
        base.backgroundColor = .white

        view.addSubview(base)
        base.translatesAutoresizingMaskIntoConstraints = false
        base.layoutMargins = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        NSLayoutConstraint.activate([
            base.leftAnchor.constraint(equalTo: view.leftAnchor),
            base.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            base.rightAnchor.constraint(equalTo: view.rightAnchor),
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(_dismiss))
        view.addGestureRecognizer(tap)
        tap.delegate = self
    }

    @objc private func _dismiss() {
        dismiss(animated: true)
    }
}

extension RepoViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return touch.view == view
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
            case present(UIColor?)
            case dismiss
        }

        let direction = ctx.viewController(forKey: .to) is RepoViewController ? Direction.present(view.backgroundColor) : .dismiss

        func blank() {
            view.backgroundColor = .clear
            base.transform.ty = base.bounds.height
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
            case .present(let color):
                self.view.backgroundColor = color
                self.base.transform.ty = 0
            case .dismiss:
                blank()
                self.completion?()
            }
        }.done {
            ctx.completeTransition(!ctx.transitionWasCancelled)
        }
    }
}
