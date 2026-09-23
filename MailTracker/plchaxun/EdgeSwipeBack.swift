import SwiftUI
import UIKit

// MARK: - 边缘滑动返回（SwiftUI 手势版）
// 不往 UIWindow 添加手势识别器（会干扰全 App 按钮点击）。
// 用法：页面 body 上 .edgeSwipeBack { presentationMode.wrappedValue.dismiss() }
// 支持：屏幕左边缘右滑 / 屏幕右边缘左滑（横向为主、纵向位移小于 80pt 才触发）
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
