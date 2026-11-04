import Foundation

/// An Icon Composer package as the layered build writes it: the plan's layers in one group over the ground in
/// another. The trial settled every setting: no glass and no specular, since each layer carries the concept's own
/// light; a neutral shadow under the subject, since the ground is drawn with the objects' shadows removed.
public enum IconPackage {
    /// One object layer, bottom to top as the plan lists them.
    public struct Layer: Sendable, Equatable {
        public var name: String
        /// Clear and Tinted draw a dark layer as clear glass, so the hero gets a light grey image there.
        public var hero: Bool
        /// Dark gets `<name>-dark.png`, the layer's own Dark image.
        public var dark: Bool
        /// The one appearance the layer shows in, hidden in the others; nil for every appearance.
        public var only: LayerPlan.Layer.Only?

        public init(name: String, hero: Bool = false, dark: Bool = false, only: LayerPlan.Layer.Only? = nil) {
            self.name = name
            self.hero = hero
            self.dark = dark
            self.only = only
        }
    }

    /// The asset names: `<name>.png`, a hero's `<name>-mono.png`, and the ground's `ground.png` and
    /// `ground-dark.png`.
    public static func assetName(_ layer: String, mono: Bool = false, dark: Bool = false) -> String {
        mono ? "\(layer)-mono.png" : dark ? "\(layer)-dark.png" : "\(layer).png"
    }
    public static let ground = "ground.png"
    public static let groundDark = "ground-dark.png"

    /// `icon.json` for `layers` over the ground. Clear and Tinted get `tintedGround`, the darker of the two grounds:
    /// a light ground there washes the subject out. That is usually Dark's, but an inverted Dark is light, and
    /// quiet-pick's flipped direction lost its white square in all four.
    public static func document(layers: [Layer], tintedGround: String = groundDark) -> [String: Any] {
        let off: [String: Any] = ["glass": false]
        let objects: [[String: Any]] = layers.reversed().map { layer in
            var entry = off
            entry["name"] = layer.name
            if layer.hero || layer.dark {
                var images: [[String: String]] = [["value": assetName(layer.name)]]
                if layer.dark { images.append(["appearance": "dark", "value": assetName(layer.name, dark: true)]) }
                if layer.hero { images.append(["appearance": "tinted", "value": assetName(layer.name, mono: true)]) }
                entry["image-name-specializations"] = images
            } else {
                entry["image-name"] = assetName(layer.name)
            }
            // Tinted is said too, so Clear and Tinted show what Default shows whatever they fall back to
            if let only = layer.only {
                entry["hidden-specializations"] = [
                    ["value": only == .dark], ["appearance": "dark", "value": only == .light],
                    ["appearance": "tinted", "value": only == .dark],
                ]
            }
            return entry
        }
        var groundLayer = off
        groundLayer["name"] = "ground"
        groundLayer["image-name-specializations"] = [
            ["value": ground], ["appearance": "dark", "value": groundDark], ["appearance": "tinted", "value": tintedGround],
        ]
        func group(_ name: String, _ layers: [[String: Any]], shadow: String) -> [String: Any] {
            [
                "name": name, "layers": layers, "shadow": ["kind": shadow, "opacity": 0.5], "specular": false,
                "translucency": ["enabled": false, "value": 0.5],
            ]
        }
        return [
            "groups": [group("subject", objects, shadow: "neutral"), group("ground", [groundLayer], shadow: "none")],
            "supported-platforms": ["circles": ["watchOS"], "squares": "shared"],
        ]
    }

    /// Writes the package at `url` afresh: `icon.json` and every file of `assets` (asset name to source file)
    /// into `Assets/`. A package left from an earlier run is replaced whole, so no stale asset stays.
    public static func write(to url: URL, layers: [Layer], assets: [String: URL], tintedGround: String = groundDark) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        let assetsDir = url.appending(path: "Assets", directoryHint: .isDirectory)
        try fm.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        for (name, source) in assets.sorted(by: { $0.key < $1.key }) {
            try fm.copyItem(at: source, to: assetsDir.appending(path: name, directoryHint: .notDirectory))
        }
        let data = try JSONSerialization.data(withJSONObject: document(layers: layers, tintedGround: tintedGround), options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url.appending(path: "icon.json", directoryHint: .notDirectory), options: .atomic)
    }
}

extension ICTool {
    /// The six appearances the review judges, in the order the sheet shows them.
    public static let renditions = ["Default", "Dark", "ClearLight", "ClearDark", "TintedLight", "TintedDark"]

    /// Renders `package` in every rendition into `dir/<Rendition>.png`, 1024 px (512 pt at 2x), macOS. ictool
    /// writes Display P3; a reader converts.
    public static func render(_ package: URL, into dir: URL, tool: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for rendition in renditions {
            let out = dir.appending(path: "\(rendition).png", directoryHint: .notDirectory)
            let result = try Subprocess.run(
                tool,
                [package.path, "--export-image", "--output-file", out.path, "--platform", "macOS", "--rendition", rendition,
                 "--width", "512", "--height", "512", "--scale", "2"],
                environment: ProcessInfo.processInfo.environment, timeout: 120)
            guard result.status == 0 else {
                let said = String(decoding: result.stdout + result.stderr, as: UTF8.self)
                throw StoreError.io("ictool refused \(package.lastPathComponent) (\(rendition)): \(said)")
            }
        }
    }
}
