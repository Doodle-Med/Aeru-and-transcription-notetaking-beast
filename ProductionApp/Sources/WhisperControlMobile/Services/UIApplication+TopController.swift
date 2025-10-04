import UIKit

extension UIApplication {
    var activeWindowScene: UIWindowScene? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }

    func topViewController(base: UIViewController? = UIApplication.shared.activeWindowScene?.windows.first { $0.isKeyWindow }?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return tab.selectedViewController.flatMap { topViewController(base: $0) }
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
