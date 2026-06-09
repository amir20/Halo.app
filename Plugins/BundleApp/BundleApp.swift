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
        let bundleID = "com.example.\(appName.lowercased())"

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
        guard let binary = build.builtArtifacts.first(where: { $0.kind == .executable })?.path else {
            Diagnostics.error("Could not locate the built executable.")
            return
        }

        // 2. Assemble the .app bundle layout in the package root.
        let fm = FileManager.default
        let root = context.package.directory
        let bundle = root.appending("\(appName).app")
        let macOSDir = bundle.appending("Contents").appending("MacOS")
        let resourcesDir = bundle.appending("Contents").appending("Resources")

        try? fm.removeItem(atPath: bundle.string)
        try fm.createDirectory(atPath: macOSDir.string, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: resourcesDir.string, withIntermediateDirectories: true)
        try fm.copyItem(atPath: binary.string, toPath: macOSDir.appending(appName).string)

        // 2b. App icon: copy Icons/AppIcon.icns into Resources (if present).
        let iconSrc = root.appending("Icons").appending("AppIcon.icns")
        let hasIcon = fm.fileExists(atPath: iconSrc.string)
        if hasIcon {
            try fm.copyItem(atPath: iconSrc.string,
                            toPath: resourcesDir.appending("AppIcon.icns").string)
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
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": true,
            "NSPrincipalClass": "NSApplication",
        ]
        if hasIcon {
            info["CFBundleIconFile"] = "AppIcon"
            info["CFBundleIconName"] = "AppIcon"
        }
        let infoData = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
        try infoData.write(to: URL(fileURLWithPath: bundle.appending("Contents").appending("Info.plist").string))

        // 4. Ad-hoc code signature so Gatekeeper allows local launch.
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--deep", "--sign", "-", bundle.string]
        try? codesign.run()
        codesign.waitUntilExit()

        Diagnostics.remark("Created \(bundle.string)")
        print("✅ Built \(appName).app — open it with:  open \(appName).app")
    }
}
