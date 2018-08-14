import PromiseKit
import UIKit

@discardableResult
func alert(error: Error, title: String? = nil, file: StaticString = #file, line: UInt = #line) -> Guarantee<Void> {
    let title = title ?? String(describing: type(of: error))
    if let error = error as? PMKHTTPError {
        let (message, title) = error.gitHubDescription(defaultTitle: title)
        return alert(message: message, title: title)
    } else {
        return alert(message: error.legibleDescription, title: title)
    }
}

@discardableResult
func alert(message: String, title: String = "Unexpected Error", file: StaticString = #file, line: UInt = #line) -> Guarantee<Void> {
    let (promise, seal) = Guarantee<UIAlertAction>.pending()

    let alert = UIAlertController(title: message, message: message, preferredStyle: .alert)
    alert.addAction(.init(title: "OK", style: .default, handler: seal))

    print("\(file):\(line)", message)  // you should log some of these to Sentry

    guard let vc = UIApplication.shared.visibleViewController else {
        print("error: Could not present UIAlertViewController")
        return Guarantee()
    }

    if let transitionCoordinator = vc.transitionCoordinator {
        transitionCoordinator.animate(alongsideTransition: nil, completion: { _ in
            vc.present(alert, animated: true)
        })
    } else {
        vc.present(alert, animated: true)
    }

    return promise.asVoid()
}

extension UIApplication {
    var visibleViewController: UIViewController? {
        var vc = UIApplication.shared.keyWindow?.rootViewController
        while let presentedVc = vc?.presentedViewController {
            if let navVc = (presentedVc as? UINavigationController)?.viewControllers.last {
                vc = navVc
            } else if let tabVc = (presentedVc as? UITabBarController)?.selectedViewController {
                vc = tabVc
            } else {
                vc = presentedVc
            }
        }
        return vc
    }
}

public extension UIView {
    public enum AnimationType {
        case easeInCirc
        case easeOutCirc
        case easeInOutCirc
        case easeInOutQuad
        case easeInOutCubic
        case easeInOutQuint

        public var timingFunction: CAMediaTimingFunction {
            switch self {
            case .easeInCirc:
                return CAMediaTimingFunction(controlPoints: 0.6, 0.04, 0.98, 0.335)
            case .easeOutCirc:
                return CAMediaTimingFunction(controlPoints: 0.075, 0.82, 0.0, 1)
            case .easeInOutCirc:
                return CAMediaTimingFunction(controlPoints: 0.785, 0.135, 0.15, 0.86)
            case .easeInOutQuad:
                return CAMediaTimingFunction(controlPoints: 0.455, 0.03, 0.515, 0.955)
            case .easeInOutCubic:
                return CAMediaTimingFunction(controlPoints: 0.645, 0.045, 0.355, 1)
            case .easeInOutQuint:
                return CAMediaTimingFunction(controlPoints: 0.86, 0, 0.07, 1)
            }
        }
    }

    @discardableResult
    static func animate(_ type: AnimationType, duration: TimeInterval, delay: TimeInterval = 0, animations: () -> Void) -> Guarantee<Void> {
        let (g, seal) = Guarantee<Void>.pending()

        UIView.beginAnimations(nil, context: nil)
        UIView.setAnimationDuration(duration)
        UIView.setAnimationDelay(0)
        CATransaction.begin()
        CATransaction.setAnimationTimingFunction(type.timingFunction)
        CATransaction.setCompletionBlock(seal)
        animations()
        CATransaction.commit()
        UIView.commitAnimations()

        return g
    }
}
