import SwiftUI
import UIKit

// MARK: - 边缘滑动返回（SwiftUI 手势版，交互式：跟手拖动、可取消，类似 iOS 系统级返回）
// 用法：页面 body 上 .interactiveEdgeSwipeBack { presentationMode.wrappedValue.dismiss() }
// 支持：屏幕左边缘右滑（横向为主、纵向位移小于 80pt 才触发）
// 交互效果：拖动时当前页跟手右移、左边露出上一页快照；回滑或松手未过半则回弹取消；
//          过半或快速滑动则动画移出并真正返回（与 iOS 系统 pop 手势一致）
enum EdgeSwipeBack {
    /// 禁用系统左缘 pop 手势：带导航栏页面（内网/外网）的系统返回手势会吞掉左边缘触摸
    /// 但又不触发（navigationBarBackButtonHidden 下），导致页面自己的手势也收不到。
    static func disableSystemPop() {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first?.windows.first else { return }
            findNav(window.rootViewController)?.interactivePopGestureRecognizer?.isEnabled = false
        }
    }

    /// 截取导航栈「上一页」的全屏快照（交互式返回时左边露出的内容）。
    /// 当前页是 NavigationLink push 的，栈倒数第二个 VC 就是返回目标页。
    static func snapshotOfPreviousPage() -> UIImage? {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first?.windows.first,
            let nav = findNav(window.rootViewController) else { return nil }
        let vcs = nav.viewControllers
        guard vcs.count >= 2, let prev = vcs[vcs.count - 2].view else { return nil }
        let size = prev.bounds.size
        guard size.width > 0, size.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            prev.drawHierarchy(in: prev.bounds, afterScreenUpdates: false)
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

// MARK: - 交互式边缘返回 modifier

struct InteractiveSwipeBackModifier: ViewModifier {
    let onSwipe: () -> Void
    @State private var offset: CGFloat = 0
    @State private var active = false
    @State private var snapshot: UIImage?

    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            // 左边露出的上一页内容（快照；未取到快照时显示半透明占位）
            if let img = snapshot {
                Image(uiImage: img)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            content
                .offset(x: offset)
                // 内容层补不透明背景：内网/外网页自身无背景，否则底下主界面快照会透出叠加
                .background(Color(.systemBackground))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 25)
                .onChanged { value in
                    let sx = value.startLocation.x
                    let dy = value.translation.height
                    // 仅左缘 45pt 内向右的横向手势触发；纵向位移大于 80pt 视为滚动，不触发
                    guard sx < 45, value.translation.width > 0, abs(dy) < 80 else { return }
                    active = true
                    offset = min(max(0, value.translation.width), UIScreen.main.bounds.width)
                }
                .onEnded { value in
                    guard active else { return }
                    active = false
                    let w = UIScreen.main.bounds.width
                    // 过半（40%）或快速滑动（预测位移>35%）→ 完成返回；否则回弹取消
                    let shouldPop = offset > w * 0.4 || value.predictedEndTranslation.width > w * 0.35
                    if shouldPop {
                        // 直接交给系统返回动画：不再自己补滑出动画、不延迟，避免与系统pop动画叠加闪一下主界面
                        onSwipe()
                    } else {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { offset = 0 }
                    }
                }
        )
        .onAppear { snapshot = EdgeSwipeBack.snapshotOfPreviousPage() }
    }
}

extension View {
    func interactiveEdgeSwipeBack(_ onSwipe: @escaping () -> Void) -> some View {
        modifier(InteractiveSwipeBackModifier(onSwipe: onSwipe))
    }
}

// MARK: - 旧版：一次性判断触发（保留备用）

extension View {
    func edgeSwipeBack(_ onSwipe: @escaping () -> Void) -> some View {
        self.highPriorityGesture(
            DragGesture(minimumDistance: 25)
                .onEnded { value in
                    let w = UIScreen.main.bounds.width
                    let sx = value.startLocation.x
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dy) < 80 else { return }
                    if sx < 45 && dx > 70 {
                        onSwipe()
                    } else if sx > w - 45 && dx < -70 {
                        onSwipe()
                    }
                }
        )
    }
}
