import SwiftUI
import UIKit

// MARK: - 全局边缘滑动返回
// 左边缘：启用系统 interactivePopGestureRecognizer（iOS 原生右滑返回）
// 右边缘：UIScreenEdgePanGestureRecognizer（从屏幕右边缘左滑）触发当前页面退出
// 用法：页面 .onAppear { EdgeSwipeBack.enable { presentationMode.wrappedValue.dismiss() } }
enum EdgeSwipeBack {
    static var onRightSwipe: (() -> Void)? {
        get { target.onSwipe }
        set { target.onSwipe = newValue }
    }
    private static let target = EdgeSwipeTarget()
    private static var pan: UIScreenEdgePanGestureRecognizer?

    static func enable(_ dismiss: @escaping () -> Void) {
        target.onSwipe = dismiss
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first?.windows.first else { return }
            // 启用系统左边缘右滑返回（NavigationView 内部是 UINavigationController）
            findNav(window.rootViewController)?.interactivePopGestureRecognizer?.isEnabled = true
            if pan == nil {
                let p = UIScreenEdgePanGestureRecognizer(target: target, action: #selector(EdgeSwipeTarget.panRight(_:)))
                p.edges = .right
                window.addGestureRecognizer(p)
                pan = p
            }
        }
    }

    private static func findNav(_ vc: UIViewController?) -> UINavigationController? {
        if let n = vc as? UINavigationController { return n }
        if let tab = vc as? UITabBarController {
            for c in tab.viewControllers ?? [] {
                if let n = findNav(c) { return n }
            }
        }
        for c in vc?.children ?? [] {
            if let n = findNav(c) { return n }
        }
        return nil
    }
}

// 手势 target：NSObject 子类，@objc 方法才能用于 #selector
private final class EdgeSwipeTarget: NSObject {
    var onSwipe: (() -> Void)?
    @objc func panRight(_ g: UIScreenEdgePanGestureRecognizer) {
        if g.state == .ended { onSwipe?() }
    }
}
