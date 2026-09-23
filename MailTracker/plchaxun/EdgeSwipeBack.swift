import SwiftUI
import UIKit

// 全局返回手势：根页面（无返回栈）时禁止边缘滑动返回，避免误触返回桌面
// 注：Swift 不允许在 extension 中 override viewDidLoad（编译错误），
// 系统默认行为即为"根页面不触发返回手势"，故直接移除 override，保留手势判定供 delegate 使用
extension UINavigationController: UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
}