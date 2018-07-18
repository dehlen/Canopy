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

    print("\(file):\(line)", message)  // you should log some of these to Sentry

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
