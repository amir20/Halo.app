import PackagePlugin
import Foundation

/// `swift package bundle-app`
///
/// Builds the executable in release mode and assembles it into a
/// double-clickable macOS `.app` bundle in the package root.
@main
struct BundleApp: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        // Product to bundle: first non-flag argument, defaulting to Halo.
        let appName = arguments.first { !$0.hasPrefix("-") } ?? "Halo"
        let displayName = appName
        // Bundle identifier and signing identity are overridable from the
        // environment so CI can inject release values; both fall back to local
        // defaults (ad-hoc signing, "-", needs no certificate).
        let env = ProcessInfo.processInfo.environment
        let bundleID = env["BUNDLE_ID"] ?? "me.amirraminfar.\(appName.lowercased())"
        let signIdentity = env["SIGN_IDENTITY"].flatMap { $0.isEmpty ? nil : $0 } ?? "-"

        // 1. Build the executable in release mode.
        Diagnostics.remark("Building \(appName) (release)…")
        let build = try packageManager.build(
            .product(appName),
            parameters: .init(configuration: .release)
        )
        guard build.succeeded else {
            Diagnostics.error("Build failed:\n\(build.logText)")
            return
        }
        guard let binary = build.builtArtifacts.first(where: { $0.kind == .executable })?.url else {
            Diagnostics.error("Could not locate the built executable.")
            return
        }

        // 2. Assemble the .app bundle layout in the package root.
        let fm = FileManager.default
        let root = context.package.directoryURL
        let bundle = root.appending(component: "\(appName).app")
        let macOSDir = bundle.appending(component: "Contents").appending(component: "MacOS")
        let resourcesDir = bundle.appending(component: "Contents").appending(component: "Resources")

        try? fm.removeItem(at: bundle)
        try fm.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        try fm.copyItem(at: binary, to: macOSDir.appending(component: appName))

        // 2b. App icon: copy Icons/AppIcon.icns into Resources (if present).
        let iconSrc = root.appending(component: "Icons").appending(component: "AppIcon.icns")
        let hasIcon = fm.fileExists(atPath: iconSrc.path(percentEncoded: false))
        if hasIcon {
            try fm.copyItem(at: iconSrc,
                            to: resourcesDir.appending(component: "AppIcon.icns"))
        }

        // 3. Write Info.plist as a compiled *binary* property list — the format
        // Xcode actually ships — built from typed data instead of an XML string.
        var info: [String: Any] = [
            "CFBundleName": appName,
            "CFBundleDisplayName": displayName,
            "CFBundleIdentifier": bundleID,
            "CFBundleVersion": "1.0",
            "CFBundleShortVersionString": "1.0",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": appName,
            "LSMinimumSystemVersion": "26.0",
            "NSHighResolutionCapable": true,
            "NSPrincipalClass": "NSApplication",
        ]
        if hasIcon {
            info["CFBundleIconFile"] = "AppIcon"
            info["CFBundleIconName"] = "AppIcon"
        }
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
        try infoData.write(to: bundle.appending(component: "Contents").appending(component: "Info.plist"))

        // 4. Code signature. With SIGN_IDENTITY set (a "Developer ID
        //    Application: …" identity) produce a real, distributable signature:
        //    hardened runtime + secure timestamp, both required by notarization.
        //    Unset, it ad-hoc signs ("-") so a local build runs without a cert.
        var signArgs = ["--force", "--sign", signIdentity]
        if signIdentity != "-" {
            signArgs += ["--options", "runtime", "--timestamp"]
        }
        signArgs.append(bundle.path(percentEncoded: false))

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = signArgs
        try codesign.run()
        codesign.waitUntilExit()
        guard codesign.terminationStatus == 0 else {
            Diagnostics.error("codesign failed (identity: \(signIdentity)).")
            return
        }

        Diagnostics.remark("Created \(bundle.path(percentEncoded: false))")
        print("✅ Built \(appName).app — open it with:  open \(appName).app")
    }
}
