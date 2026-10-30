import Cocoa
import FlutterMacOS

enum WindowEffect: String {
    case none
    case transparent
    case blur
    case acrylic
    case mica
    case glass
}

@available(macOS 26.0, *)
private enum SidebarGlass {
    // A split view's sidebar glass is a private variant that NSGlassEffectView's
    // public styles lack and each macOS release redraws, so it is copied off one.
    private static let sidebarAttributes: [String: Any]? = {
        let split = NSSplitViewController()
        let sidebar = NSViewController(nibName: nil, bundle: nil)
        sidebar.view = NSView()
        let content = NSViewController(nibName: nil, bundle: nil)
        content.view = NSView()
        split.addSplitViewItem(NSSplitViewItem(sidebarWithViewController: sidebar))
        split.addSplitViewItem(NSSplitViewItem(viewController: content))
        split.view.frame = NSRect(x: 0, y: 0, width: 600, height: 400)
        split.view.layoutSubtreeIfNeeded()
        guard let glass = firstGlass(in: split.view) else {
            return nil
        }
        var attributes: [String: Any] = [:]
        for key in ["_variant", "_adaptiveAppearance"]
        where glass.responds(to: NSSelectorFromString(key)) {
            attributes[key] = glass.value(forKey: key)
        }
        return attributes
    }()

    static var isAvailable: Bool {
        sidebarAttributes != nil
    }

    static func make() -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        for (key, value) in sidebarAttributes ?? [:]
        where glass.responds(to: NSSelectorFromString("set\(key):")) {
            glass.setValue(value, forKey: key)
        }
        return glass
    }

    private static func firstGlass(in view: NSView) -> NSGlassEffectView? {
        if let glass = view as? NSGlassEffectView {
            return glass
        }
        for subview in view.subviews {
            if let glass = firstGlass(in: subview) {
                return glass
            }
        }
        return nil
    }
}

private final class EffectHostViewController: NSViewController {
    let flutterViewController: FlutterViewController
    /// The window's content view, and the view that paints the material. This is
    /// the hierarchy the plugin ships — a variant that hoisted the material into
    /// a sibling view under a plain container painted the same frost but left
    /// every click in the window dead, so the arrangement is not cosmetic.
    let effectView = NSVisualEffectView()
    /// A plain layer that sits between the vibrancy material and the Flutter
    /// view. `NSVisualEffectView` composites its material into its own inner
    /// layer, so painting `effectView.layer.backgroundColor` gets swallowed and
    /// the tint never shows — a dedicated subview is the only reliable way to
    /// colour the frost.
    let tintView = NSView()
    private var glassView: NSView?

    init(hosting flutterViewController: FlutterViewController) {
        self.flutterViewController = flutterViewController
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        effectView.frame = flutterViewController.view.frame
        effectView.autoresizingMask = [.width, .height]
        effectView.blendingMode = .behindWindow
        tintView.wantsLayer = true
        tintView.frame = effectView.bounds
        tintView.autoresizingMask = [.width, .height]
        effectView.addSubview(tintView)
        addChild(flutterViewController)
        attachFlutterView()
        view = effectView
    }

    func attachFlutterView() {
        let flutterView = flutterViewController.view
        guard flutterView.superview !== effectView else {
            return
        }
        flutterView.translatesAutoresizingMaskIntoConstraints = true
        flutterView.frame = effectView.bounds
        flutterView.autoresizingMask = [.width, .height]
        effectView.addSubview(flutterView)
    }

    /// Colours the frost. `nil` clears it (used by the non-blur effects, which
    /// run with the material switched off).
    func applyTint(_ tint: NSColor?) {
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = tint?.cgColor
    }

    @available(macOS 26.0, *)
    func showGlass(tint: NSColor?) {
        let glass: NSGlassEffectView
        if let existing = glassView as? NSGlassEffectView {
            glass = existing
        } else {
            glass = SidebarGlass.make()
            glass.frame = effectView.bounds
            glass.autoresizingMask = [.width, .height]
            effectView.addSubview(glass)
            glass.contentView = flutterViewController.view
            glassView = glass
        }
        glass.tintColor = tint
    }

    func removeGlass() {
        guard let glassView else {
            return
        }
        attachFlutterView()
        glassView.removeFromSuperview()
        self.glassView = nil
    }

    /// Puts Flutter's controller back into the responder chain.
    ///
    /// AppKit delivers a click by walking `nextResponder` from the view under the
    /// cursor upwards. With the stock hierarchy the chain reaches
    /// `FlutterViewController`, which owns `mouseDown:` and forwards it to the
    /// engine. Swapping this host in as the window's content view controller
    /// replaced Flutter's controller at that place in the chain, and this class
    /// has no mouse handling — so every click was swallowed here. Hover kept
    /// working because it comes from the tracking area and never walks the chain,
    /// which is exactly the split the user reported.
    ///
    /// Forwarding the pointer events straight on restores delivery without
    /// changing the view hierarchy that the frost depends on.
    override func mouseDown(with event: NSEvent) {
        flutterViewController.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        flutterViewController.mouseUp(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        flutterViewController.mouseDragged(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        flutterViewController.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        flutterViewController.rightMouseUp(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        flutterViewController.rightMouseDragged(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        flutterViewController.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        flutterViewController.otherMouseUp(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        flutterViewController.otherMouseDragged(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        flutterViewController.scrollWheel(with: event)
    }
}

enum WindowEffectView {
    static func isSupported(_ effect: WindowEffect) -> Bool {
        switch effect {
        case .none, .transparent, .blur, .acrylic:
            return true
        case .mica:
            return false
        case .glass:
            if #available(macOS 26.0, *) {
                return SidebarGlass.isAvailable
            }
            return false
        }
    }

    /// A flat white mask at [opacity], stretched over the material. White at 1
    /// is "leave the material alone"; anything lower thins it out, which is the
    /// only way to go lighter than a system material's own density floor. Nil
    /// when no lightering is asked for.
    private static func frostMask(_ opacity: CGFloat?) -> NSImage? {
        guard let opacity, opacity < 1 else {
            return nil
        }
        let level = max(0, min(1, opacity))
        return NSImage(size: NSSize(width: 1, height: 1), flipped: false) { rect in
            NSColor.white.withAlphaComponent(level).setFill()
            rect.fill()
            return true
        }
    }

    static func appearance(brightness: String?) throws -> NSAppearance? {
        switch brightness {
        case nil:
            return nil
        case "light":
            return NSAppearance(named: .aqua)
        case "dark":
            return NSAppearance(named: .darkAqua)
        default:
            throw ArgumentError(key: "brightness")
        }
    }

    static func install(in window: NSWindow) {
        guard let flutterViewController = window.contentViewController as? FlutterViewController else {
            return
        }
        let frame = window.frame
        let host = EffectHostViewController(hosting: flutterViewController)
        window.contentViewController = host
        // macOS 12 detaches the outgoing controller's view only after loading the
        // host, by then from the effect view, which leaves the window blank.
        host.attachFlutterView()
        window.setFrame(frame, display: true)
        // Swapping the content view controller makes macOS 26 rebuild the window
        // chrome and silently drop the transparent title bar, printing a solid
        // strip over the frosted pane. Re-assert every transparent-bar setting
        // here, after the swap, so the bar stays clear and the traffic lights
        // float on the glass the way Loon does. Tahoe also paints a unified
        // toolbar background unless its accessory views are hidden.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.layoutIfNeeded()
    }

    static func apply(
        _ effect: WindowEffect,
        tint: NSColor?,
        appearance: NSAppearance?,
        opacity: CGFloat? = nil,
        to window: NSWindow
    ) {
        guard let host = window.contentViewController as? EffectHostViewController else {
            return
        }
        let effectView = host.effectView
        // `maskImage` is the one dial that lightens the frost without touching
        // the content: it masks the vibrancy material only, while the Flutter
        // view and the tint layer are its subviews and stay fully opaque.
        // (`alphaValue` on this view was tried first and faded the text with the
        // frost, because it composites the whole subtree.)
        _ = opacity
        switch effect {
        case .none, .transparent, .mica, .glass:
            effectView.maskImage = NSImage()
            effectView.state = .inactive
            host.applyTint(nil)
            host.flutterViewController.backgroundColor = effect == .none ? .windowBackgroundColor : .clear
            if effect == .glass, #available(macOS 26.0, *) {
                host.showGlass(tint: tint)
            } else {
                host.removeGlass()
            }
        case .blur, .acrylic:
            host.removeGlass()
            effectView.maskImage = WindowEffectView.frostMask(opacity)
            // `.popover` is what Loon uses (material id 6), verified by
            // disassembling its HomeMaterialBackgroundView. It blurs hard enough
            // that a window underneath dissolves into colour instead of staying
            // legible, while still transmitting the desktop's own hue — which is
            // exactly the look this is chasing. `.sidebar` was a guess and reads
            // denser and greyer; `.underWindowBackground` transmits too much and
            // let other apps' label text show through.
            //
            // `state` is forced to `.active` rather than the default
            // `.followsWindowActiveState`: the latter drops the material the
            // moment the window resigns key, so the frost vanished on blur.
            // Loon does the same, so its frost never fades when unfocused.
            effectView.material = effect == .blur ? .popover : .fullScreenUI
            effectView.state = .active
            effectView.appearance = appearance
            host.applyTint(tint)
            host.flutterViewController.backgroundColor = .clear
        }
    }
}
