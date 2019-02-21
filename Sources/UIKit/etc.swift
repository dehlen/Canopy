import PromiseKit
import UIKit

extension UIColor {
    static let canopyGreen = UIColor(red: 0.15, green: 0.75, blue: 0.15, alpha: 1)
    static let disabledColor = UIColor(white: 0.8, alpha: 1)
}

public extension UIView {
    enum AnimationType {
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
