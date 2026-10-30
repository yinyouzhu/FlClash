import Cocoa
import FlutterMacOS

/// A card background that is a real `NSVisualEffectView`.
///
/// FlClash paints its entire UI into one Flutter surface, so a Flutter "card"
/// can only ever be a translucent rectangle stacked on the window's single
/// global frost — it cannot itself be a second vibrancy layer. That is the one
/// structural thing Loon has over this app: its cards are genuine system
/// vibrancy subviews, so each panel frosts what is behind it (the already
/// frosted window) with the compositor, instead of Flutter faking it with flat
/// alpha. Embedding an `NSVisualEffectView` per card closes that gap.
///
/// Everything that decides how the panel looks is passed from Dart in the
/// creation arguments (`material`, `appearance`, `blending`, `tint`, `radius`)
/// so the look can be tuned by a hot restart rather than a native rebuild.
final class FrostedCardView: NSView {
    private let radius: CGFloat
    private let effect = NSVisualEffectView()

    /// `NSVisualEffectView` composites its material into its own inner layer,
    /// so a tint painted on `effect.layer` is swallowed; a sibling layer above
    /// the material is the only reliable way to colour the frost.
    private let tintView = NSView()

    init(viewId: Int64, arguments: Any?) {
        let args = arguments as? [String: Any] ?? [:]
        radius = CGFloat((args["radius"] as? NSNumber)?.doubleValue ?? 0)
        super.init(frame: .zero)

        // The panel's own rounded geometry is clipped here, not by Flutter: a
        // platform view is composited by the engine, so a Flutter clip would
        // not reliably round it, while masking the superview layer does.
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = radius

        effect.frame = bounds
        effect.autoresizingMask = [.width, .height]
        effect.blendingMode = FrostedCardView.blendingMode(args["blending"] as? String)
        effect.material = FrostedCardView.material(args["material"] as? String)
        // `.active` rather than the default `.followsWindowActiveState`: the
        // latter drops the material the moment the window resigns key, which is
        // exactly the "frost only while focused" bug Loon does not have.
        effect.state = .active
        effect.appearance = FrostedCardView.appearance(args["appearance"] as? String)
        addSubview(effect)

        tintView.wantsLayer = true
        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        if let raw = args["tint"] as? NSNumber {
            tintView.layer?.backgroundColor = NSColor(argb: raw.intValue).cgColor
        }
        addSubview(tintView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = radius
    }

    /// This view is a background only: the card's own Flutter `InkWell` sits
    /// above it and must keep receiving the clicks. Returning nil from hit
    /// testing leaves every mouse event to the Flutter view behind.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private static func blendingMode(_ name: String?) -> NSVisualEffectView.BlendingMode {
        name == "behindWindow" ? .behindWindow : .withinWindow
    }

    private static func appearance(_ name: String?) -> NSAppearance? {
        switch name {
        case "darkAqua":
            return NSAppearance(named: .darkAqua)
        case "aqua":
            return NSAppearance(named: .aqua)
        default:
            return nil
        }
    }

    private static func material(_ name: String?) -> NSVisualEffectView.Material {
        switch name {
        case "titlebar":
            return .titlebar
        case "selection":
            return .selection
        case "menu":
            return .menu
        case "popover":
            return .popover
        case "headerView":
            return .headerView
        case "sheet":
            return .sheet
        case "windowBackground":
            return .windowBackground
        case "hudWindow":
            return .hudWindow
        case "fullScreenUI":
            return .fullScreenUI
        case "toolTip":
            return .toolTip
        case "contentBackground":
            return .contentBackground
        case "underWindowBackground":
            return .underWindowBackground
        case "sidebar":
            return .sidebar
        default:
            return .sidebar
        }
    }
}

final class FrostedCardFactory: NSObject, FlutterPlatformViewFactory {
    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
        FrostedCardView(viewId: viewId, arguments: args)
    }
}
