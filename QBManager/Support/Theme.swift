import SwiftUI
import UIKit

/// 仿 Claude 的視覺風格：暖色系配色＋襯線字體（系統 New York）。
/// Claude 官方字體（Styrene / Tiempos 等）為商用授權，因此以系統內建的 New York 襯線字體近似。
enum Theme {
    /// Claude 品牌橘 #D97757
    static let accent = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)

    /// 背景：淺色 #F5F4ED（象牙白）／深色 #262624
    static let background = dynamic(light: 0xF5F4ED, dark: 0x262624)
    /// 卡片：淺色 #FFFFFF／深色 #30302E
    static let card = dynamic(light: 0xFFFFFF, dark: 0x30302E)
    /// 次要文字：#73726C／#A6A39A
    static let secondaryText = dynamic(light: 0x73726C, dark: 0xA6A39A)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { trait in
            UIColor(hex: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    static func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        guard let d = base.fontDescriptor.withDesign(.serif) else { return base }
        return UIFont(descriptor: d, size: size)
    }

    /// UIKit 元件（導覽列標題）也套用襯線字體與品牌色
    @MainActor static func configureAppearance() {
        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [.font: serif(34, .semibold)]
        nav.titleTextAttributes = [.font: serif(17, .semibold)]
        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(accent)
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Liquid Glass（iOS 26+），舊系統退回 Material

extension View {
    /// 套用 Liquid Glass；iOS 26 以下改用 ultraThinMaterial。
    @ViewBuilder
    func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.15), lineWidth: 0.5))
        }
    }

    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        glass(Capsule(), tint: tint, interactive: interactive)
    }

    /// 玻璃按鈕樣式；prominent 為品牌色實心玻璃
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// 浮動列：iOS 26+ 用 safeAreaBar（內容捲到下方時套用系統捲動邊緣模糊），舊版退回 safeAreaInset
    @ViewBuilder
    func glassBar<C: View>(edge: VerticalEdge, @ViewBuilder content: () -> C) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: 0, content: content)
        }
    }

    /// 讓清單捲動時內容可以在玻璃元件下方透出
    func themedList() -> some View {
        scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
    }
}

/// iOS 26+ 用 GlassEffectContainer 讓相鄰玻璃元件互相融合
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 12
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}
