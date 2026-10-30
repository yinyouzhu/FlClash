import Cocoa
import FlutterMacOS
import window
import LaunchAtLogin

class MainFlutterWindow: NSWindow {
    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)

        // Make the title bar transparent and let content run full-width from
        // the very top, so the native bar never prints a solid strip over the
        // frosted pane (macOS 26 kept the opaque bar when this was left to the
        // plugin alone). The blur plugin still drives the vibrancy material.
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        self.styleMask.insert(.fullSizeContentView)
        self.isOpaque = false
        self.backgroundColor = .clear

        FlutterMethodChannel(
            name: "launch_at_startup", binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        .setMethodCallHandler { (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "launchAtStartupIsEnabled":
                result(LaunchAtLogin.isEnabled)
            case "launchAtStartupSetEnabled":
                if let arguments = call.arguments as? [String: Any] {
                    LaunchAtLogin.isEnabled = arguments["setEnabledValue"] as! Bool
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        // A process row wants the same thing the Finder shows: the app's
        // localized name and its icon. Neither is reachable from Dart — the
        // icon may live in Assets.car and the name in a localized
        // InfoPlist.strings — so both come from the system here.
        FlutterMethodChannel(
            name: "fl_clash/app_identity",
            binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        .setMethodCallHandler { (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
            guard call.method == "resolve",
                  let arguments = call.arguments as? [String: Any],
                  let executable = arguments["path"] as? String,
                  !executable.isEmpty
            else {
                result(FlutterMethodNotImplemented)
                return
            }
            result(self.appIdentity(of: executable))
        }

        RegisterGeneratedPlugins(registry: flutterViewController)
        super.awakeFromNib()
    }
    override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        hiddenWindowAtLaunch()
    }

    /// Walks up from an executable to the bundle that holds it, then asks the
    /// system for that bundle's display name and icon.
    private func appIdentity(of executable: String) -> [String: Any]? {
        // Keep climbing past the first bundle: a helper lives in its own .app
        // inside the app that ships it (QQEXDOC.app inside QQ.app), and the
        // row wants the app a person recognises, not the helper's name.
        var path = executable
        var outermost: String? = nil
        while path != "/" && !path.isEmpty {
            if path.hasSuffix(".app") {
                outermost = path
            }
            path = (path as NSString).deletingLastPathComponent
        }
        path = outermost ?? executable
        if !path.hasSuffix(".app") {
            // A system XPC — Safari's networking runs in one — has no bundle
            // of its own, but it may still be a running application the
            // system can name and draw.
            if let app = NSWorkspace.shared.runningApplications.first(
                where: { $0.executableURL?.path == executable }
            ), let icon = app.icon {
                var payload: [String: Any] = ["name": app.localizedName ?? ""]
                payload["icon"] = FlutterStandardTypedData(bytes: png(of: icon))
                return payload
            }
            return nil
        }
        let name = FileManager.default.displayName(atPath: path)
        var payload: [String: Any] = ["name": name, "bundle": path]
        payload["icon"] = FlutterStandardTypedData(
            bytes: png(of: NSWorkspace.shared.icon(forFile: path))
        )
        return payload
    }

    private func png(of image: NSImage) -> Data {
        image.size = NSSize(width: 64, height: 64)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:])
        else {
            return Data()
        }
        return data
    }
}
