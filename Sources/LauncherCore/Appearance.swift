import Foundation

/// The user's look: Liquid Glass or solid buttons, the buttons' color, and the window's color when no game is chosen.
public struct Appearance: Codable, Equatable, Sendable {
    public enum ButtonLook: String, Codable, CaseIterable, Sendable { case glass, solid }

    public var buttonLook: ButtonLook = .glass
    /// nil: the theme's own `Palette.button`.
    public var buttonColor: RGB?
    public var buttonOpacity: Double = 1
    /// nil: `Palette.fallback`, the deep indigo.
    public var mainColor: RGB?
    /// The sidebar's fill; the other tinted surfaces scale with it.
    public var tintOpacity: Double = Appearance.defaultTint

    public static let defaultTint = 0.55

    public init() {}

    public var defaultPalette: Palette { mainColor.map(Palette.solid) ?? .fallback }

    /// A surface's tint opacity, `alpha` at the default tint.
    public func tint(_ alpha: Double) -> Double { min(1, max(0, alpha * tintOpacity / Self.defaultTint)) }

    /// Dark text on a button of color `c`: only when it is light and opaque enough to hide the dark window under it.
    public func darkInk(on c: RGB) -> Bool { c.luminance > 0.6 && buttonOpacity > 0.6 }

    private enum CodingKeys: String, CodingKey { case buttonLook, buttonColor, buttonOpacity, mainColor, tintOpacity }

    // Every key optional, so settings saved by an older launcher still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        buttonLook = (try? c.decodeIfPresent(ButtonLook.self, forKey: .buttonLook)) ?? .glass
        buttonColor = try c.decodeIfPresent(RGB.self, forKey: .buttonColor)
        buttonOpacity = try c.decodeIfPresent(Double.self, forKey: .buttonOpacity) ?? 1
        mainColor = try c.decodeIfPresent(RGB.self, forKey: .mainColor)
        tintOpacity = try c.decodeIfPresent(Double.self, forKey: .tintOpacity) ?? Self.defaultTint
    }
}
