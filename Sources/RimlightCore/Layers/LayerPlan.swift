import Foundation

/// The agent's `plan.json` for `rimlight build`: the ground, how Dark gets its own ground, and the layers the image model
/// draws, bottom to top. Each field comes from the layer trial (`Rimlight-Research/layer-trial/`).
public struct LayerPlan: Codable, Sendable, Equatable {
    public var ground: Ground
    public var dark: Dark
    /// Bottom to top.
    public var layers: [Layer]
    /// What must survive from the pick, in the agent's words: the sheet prints them every round, so a review
    /// re-reads them against the renders. The first build of the user's eclipse turned its tapering crescent into
    /// an even band and the review still called it the pick. They draw nothing and cost nothing.
    public var checks: [String]
    /// The user's own words agreeing that Dark shows other parts than Default, which a plan needs before any layer
    /// has `"only"` or `"dark": {"draw": ...}`. The skill asks first; the command refuses the plan without them.
    public var consent: String?

    public init(ground: Ground, dark: Dark, layers: [Layer], checks: [String] = [], consent: String? = nil) {
        self.ground = ground
        self.dark = dark
        self.layers = layers
        self.checks = checks
        self.consent = consent
    }

    /// Whether Dark shows other parts than Default: a layer in one of them only, or one the image model draws again for Dark.
    public var differsByMode: Bool { layers.contains(where: \.differsByMode) }

    private enum CodingKeys: String, CodingKey { case ground, dark, layers, checks, consent }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ground = try c.decode(Ground.self, forKey: .ground)
        dark = try c.decode(Dark.self, forKey: .dark)
        layers = try c.decode([Layer].self, forKey: .layers)
        checks = try c.decodeIfPresent([String].self, forKey: .checks) ?? []
        consent = try c.decodeIfPresent(String.self, forKey: .consent)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ground, forKey: .ground)
        try c.encode(dark, forKey: .dark)
        try c.encode(layers, forKey: .layers)
        if !checks.isEmpty { try c.encode(checks, forKey: .checks) }
        try c.encodeIfPresent(consent, forKey: .consent)
    }

    /// The background with the objects taken out. Always named `ground`, its files `ground.png` and `ground-dark.png`.
    public struct Ground: Codable, Sendable, Equatable {
        public var keep: String
        public var remove: String

        public init(keep: String, remove: String) {
            self.keep = keep
            self.remove = remove
        }
    }

    /// Dark's own ground. The user may want a colour of their own there: the caliper's orange housing came back a
    /// burnt orange from `generate`, and the user wanted matte black, which neither fixed choice could give.
    public enum Dark: Codable, Sendable, Equatable {
        /// The image model draws a night version of the ground: a light ground.
        case generate
        /// The ground a step darker, made in code: a ground that is dark already.
        case dim
        /// `{"keep": "..."}`: the image model draws Dark's ground from these words, as an edit of the ground.
        case describe(String)
        /// `{"tone": "#rrggbb"}`: the ground recoloured in code to this colour, its own grain and shading kept.
        case tone(String)
        /// The ground's lightness flipped in code, its hue kept: white paper becomes black paper. With each layer's
        /// own `"dark": "invert"` it is the full flip the user asked for on the eclipse.
        case invert

        /// Whether the image model draws Dark's ground, `gen/ground-dark.png`.
        public var drawn: Bool {
            switch self {
            case .generate, .describe: true
            case .dim, .tone, .invert: false
            }
        }

        /// `#rrggbb` as sRGB values 0...1.
        public static func rgb(_ hex: String) -> SIMD3<Float>? {
            guard hex.count == 7, hex.first == "#", let v = UInt32(hex.dropFirst(), radix: 16) else { return nil }
            return SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
        }

        private enum Keys: String, CodingKey { case keep, tone }

        public init(from decoder: Decoder) throws {
            if let s = try? decoder.singleValueContainer().decode(String.self) {
                switch s {
                case "generate": self = .generate
                case "dim": self = .dim
                case "invert": self = .invert
                default:
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "dark \(s)"))
                }
                return
            }
            let c = try decoder.container(keyedBy: Keys.self)
            if let words = try c.decodeIfPresent(String.self, forKey: .keep) {
                self = .describe(words)
            } else {
                self = .tone(try c.decode(String.self, forKey: .tone))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .generate:
                var c = encoder.singleValueContainer()
                try c.encode("generate")
            case .dim:
                var c = encoder.singleValueContainer()
                try c.encode("dim")
            case .invert:
                var c = encoder.singleValueContainer()
                try c.encode("invert")
            case .describe(let words):
                var c = encoder.container(keyedBy: Keys.self)
                try c.encode(words, forKey: .keep)
            case .tone(let hex):
                var c = encoder.container(keyedBy: Keys.self)
                try c.encode(hex, forKey: .tone)
            }
        }
    }

    /// What the image model draws a layer on.
    public enum Key: String, Codable, Sendable, CaseIterable {
        /// The image model edits the whole frame, and Codex mostly keeps the layer's size and place on it.
        case magenta
        /// Lights and glows: brightness is alpha, with no coloured rings.
        case black
        /// Real transparency, for translucent glass. Codex tends to centre and enlarge a lone part, so it needs a box.
        case clear
    }

    /// Where a `clear` layer sits, in tile pixels (0...1024).
    public struct Box: Codable, Sendable, Equatable {
        public var x0: Int
        public var y0: Int
        public var x1: Int
        public var y1: Int

        public init(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
            self.x0 = x0
            self.y0 = y0
            self.x1 = x1
            self.y1 = y1
        }

        /// `[x0, y0, x1, y1]`; whole numbers written as `207.0` read too, since the check takes them.
        public init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            var v: [Int] = []
            while !c.isAtEnd {
                let d = try c.decode(Double.self)
                guard d == d.rounded(), let n = Int(exactly: d) else {
                    throw DecodingError.dataCorruptedError(in: c, debugDescription: "box values are whole numbers")
                }
                v.append(n)
            }
            guard v.count == 4 else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "a box is [x0, y0, x1, y1]")
            }
            self.init(v[0], v[1], v[2], v[3])
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.unkeyedContainer()
            try c.encode(contentsOf: [x0, y0, x1, y1])
        }
    }

    public struct Layer: Codable, Sendable, Equatable {
        /// `[a-z0-9-]{1,32}`, the layer's file name.
        public var name: String
        public var what: String
        /// What to leave out of the layer, and what to paint where it was.
        public var without: String?
        /// A shadow another part casts on this layer, kept on it.
        public var shadow: String?
        public var key: Key
        public var box: Box?
        /// A glow whose opacity the fit sets.
        public var soft: Bool
        /// Lifted to light grey in Clear and Tinted.
        public var hero: Bool
        /// Plain metal: its colour is taken out after drawing.
        public var grey: Bool
        /// Moved onto the pick's colour after the fit.
        public var match: Bool
        /// The layer's own Dark image.
        public var dark: DarkCopy?
        /// The one appearance the layer shows in; nil for every appearance.
        public var only: Only?

        /// Whether Dark shows another part here than Default does.
        public var differsByMode: Bool {
            if only != nil { return true }
            if case .draw = dark { return true }
            return false
        }

        /// A layer in Default only, or in Dark only. Clear and Tinted show what Default shows.
        public enum Only: String, Codable, Sendable, CaseIterable {
            /// In Default, Clear and Tinted, hidden in Dark: the sun of a sky that has a moon at night.
            case light
            /// In Dark only, a part the pick does not have: the stars of that night sky. The image model draws it new, in the
            /// pick's style.
            case dark
        }

        /// How a layer's Dark image is made: from the layer in code, free, or drawn again by the image model.
        public enum DarkCopy: Codable, Sendable, Equatable {
            /// Lightness flipped, hue, chroma, alpha and shading kept: the eclipse's black tile turns white on a
            /// black Dark, where it vanished as it was.
            case invert
            /// Moved onto the pick's colour, shading and texture kept: a part recoloured for Default, such as the
            /// eclipse's disc drawn brown on a brown ground, goes back to the pick's charcoal in Dark.
            case pick
            /// `{"tone": "#rrggbb"}`: moved onto this colour as `pick` moves onto the pick's, for a Dark colour the
            /// pick does not have.
            case tone(String)
            /// `{"draw": "words"}`: the image model draws the layer's Dark image from these words, in the layer's place: a
            /// sun that is a moon in Dark. One image, and the plan needs the user's consent.
            case draw(String)

            private enum Keys: String, CodingKey { case tone, draw }

            public init(from decoder: Decoder) throws {
                if let s = try? decoder.singleValueContainer().decode(String.self) {
                    switch s {
                    case "invert": self = .invert
                    case "pick": self = .pick
                    default:
                        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "dark \(s)"))
                    }
                    return
                }
                let c = try decoder.container(keyedBy: Keys.self)
                if let words = try c.decodeIfPresent(String.self, forKey: .draw) {
                    self = .draw(words)
                } else {
                    self = .tone(try c.decode(String.self, forKey: .tone))
                }
            }

            public func encode(to encoder: Encoder) throws {
                switch self {
                case .invert:
                    var c = encoder.singleValueContainer()
                    try c.encode("invert")
                case .pick:
                    var c = encoder.singleValueContainer()
                    try c.encode("pick")
                case .tone(let hex):
                    var c = encoder.container(keyedBy: Keys.self)
                    try c.encode(hex, forKey: .tone)
                case .draw(let words):
                    var c = encoder.container(keyedBy: Keys.self)
                    try c.encode(words, forKey: .draw)
                }
            }
        }

        public init(
            name: String, what: String, without: String? = nil, shadow: String? = nil, key: Key = .magenta,
            box: Box? = nil, soft: Bool = false, hero: Bool = false, grey: Bool = false, match: Bool = false,
            dark: DarkCopy? = nil, only: Only? = nil
        ) {
            self.name = name
            self.what = what
            self.without = without
            self.shadow = shadow
            self.key = key
            self.box = box
            self.soft = soft
            self.hero = hero
            self.grey = grey
            self.match = match
            self.dark = dark
            self.only = only
        }

        private enum CodingKeys: String, CodingKey { case name, what, without, shadow, key, box, soft, hero, grey, match, dark, only }

        /// An absent flag is false and an absent key is magenta.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            what = try c.decode(String.self, forKey: .what)
            without = try c.decodeIfPresent(String.self, forKey: .without)
            shadow = try c.decodeIfPresent(String.self, forKey: .shadow)
            key = try c.decodeIfPresent(Key.self, forKey: .key) ?? .magenta
            box = try c.decodeIfPresent(Box.self, forKey: .box)
            soft = try c.decodeIfPresent(Bool.self, forKey: .soft) ?? false
            hero = try c.decodeIfPresent(Bool.self, forKey: .hero) ?? false
            grey = try c.decodeIfPresent(Bool.self, forKey: .grey) ?? false
            match = try c.decodeIfPresent(Bool.self, forKey: .match) ?? false
            dark = try c.decodeIfPresent(DarkCopy.self, forKey: .dark)
            only = try c.decodeIfPresent(Only.self, forKey: .only)
        }

        /// Writes the key always, and the rest only when set, as an agent would.
        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(what, forKey: .what)
            try c.encodeIfPresent(without, forKey: .without)
            try c.encodeIfPresent(shadow, forKey: .shadow)
            try c.encode(key, forKey: .key)
            try c.encodeIfPresent(box, forKey: .box)
            if soft { try c.encode(true, forKey: .soft) }
            if hero { try c.encode(true, forKey: .hero) }
            if grey { try c.encode(true, forKey: .grey) }
            if match { try c.encode(true, forKey: .match) }
            try c.encodeIfPresent(dark, forKey: .dark)
            try c.encodeIfPresent(only, forKey: .only)
        }
    }
}

/// Checks and stores `plan.json`. `rimlight build --plan-file` is its only writer; the check names every problem
/// with its place, so a typo fails before an image is spent.
public enum PlanFile {
    public static let tile = 1024
    /// Each layer is one image; more than this is a plan to split differently.
    public static let maxLayers = 8
    /// A review re-reads every check each round; more than this is a description, not the few things that must hold.
    public static let maxChecks = 8
    /// The ground's own files.
    public static let reservedNames: Set<String> = ["ground", "ground-dark"]
    public static let knownKeys: Set<String> = ["ground", "dark", "layers", "checks", "consent"]
    public static let groundKeys: Set<String> = ["keep", "remove"]
    public static let layerKeys: Set<String> = ["name", "what", "without", "shadow", "key", "box", "soft", "hero", "grey", "match", "dark", "only"]

    public struct Invalid: Error, CustomStringConvertible, Equatable {
        public var problems: [String]
        public var description: String {
            "plan.json is not valid:\n" + problems.map { "  - \($0)" }.joined(separator: "\n")
        }
    }

    public struct Checked: Equatable, Sendable {
        public var plan: LayerPlan
        public var warnings: [String]
    }

    /// Throws `Invalid` listing every problem; returns the plan and the warnings: an unknown key (kept and
    /// ignored), more than one hero, a soft layer keyed on magenta. A box on a keyed layer is no warning: Codex
    /// moved and enlarged a small part even on magenta (the tortoise's head), and the box puts it back.
    public static func check(_ data: Data) throws -> Checked {
        guard let object = try? JSONSerialization.jsonObject(with: data), let j = object as? [String: Any] else {
            throw Invalid(problems: ["it is not a JSON object"])
        }
        var problems: [String] = []
        var warnings: [String] = []
        func isNumber(_ v: Any?) -> Bool {
            guard let n = v as? NSNumber else { return false }
            return CFGetTypeID(n) != CFBooleanGetTypeID()
        }
        func isBool(_ v: Any?) -> Bool {
            guard let n = v as? NSNumber else { return false }
            return CFGetTypeID(n) == CFBooleanGetTypeID()
        }
        func filled(_ v: Any?) -> Bool {
            (v as? String).map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? false
        }

        if let ground = j["ground"] as? [String: Any] {
            if !filled(ground["keep"]) { problems.append("ground.keep is needed: the background as it should stay") }
            if !filled(ground["remove"]) { problems.append("ground.remove is needed: everything on the background, taken out") }
            for k in ground.keys.sorted() where !groundKeys.contains(k) {
                warnings.append("ground has an unknown key \"\(k)\", kept and ignored")
            }
        } else {
            problems.append("ground is needed: an object with keep and remove")
        }

        let darkChoices = "dark is \"generate\" (the image model draws a night ground), \"dim\" (the ground a step darker), "
            + "\"invert\" (the ground's lightness flipped in code), {\"keep\": \"words\"} (the image model draws Dark's ground from "
            + "your words) or {\"tone\": \"#rrggbb\"} (the ground recoloured to that colour in code)"
        switch j["dark"] {
        case let s as String where s == "generate" || s == "dim" || s == "invert": break
        case let s as String where s == "keep":
            problems.append("dark \"keep\" is gone: every icon gets its own Dark ground, \"dim\" for a ground that is dark already")
        case let d as [String: Any]:
            let words = d["keep"], tone = d["tone"]
            if words != nil && tone != nil {
                problems.append("dark has keep or tone, not both")
            } else if let words {
                if (words as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    problems.append("dark keep is the words the image model draws Dark's ground from, not empty")
                }
            } else if let tone {
                if (tone as? String).flatMap(LayerPlan.Dark.rgb) == nil {
                    problems.append("dark tone is a colour written #rrggbb, such as \"#1c1c1e\"")
                }
            } else {
                problems.append(darkChoices)
            }
            for k in d.keys.sorted() where k != "keep" && k != "tone" {
                warnings.append("dark has an unknown key \"\(k)\", kept and ignored")
            }
        default:
            problems.append(darkChoices)
        }

        var heroes: [String] = []
        // layers that make Dark show other parts than Default, and those Default shows
        var differing: [String] = []
        var inDefault = 0
        if let raw = j["layers"] {
            if let list = raw as? [Any] {
                if list.isEmpty { problems.append("layers is empty: a plan draws at least one layer") }
                if list.count > maxLayers {
                    problems.append("layers has \(list.count): at most \(maxLayers), one image each")
                }
                var seen: [String: Int] = [:]
                for (n, item) in list.enumerated() {
                    guard let layer = item as? [String: Any] else { problems.append("layers[\(n)] is not an object"); continue }
                    let name = layer["name"] as? String
                    let place = "layers[\(n)]" + (name.map { " (\($0))" } ?? "")
                    if let name {
                        if !validName(name) {
                            problems.append("\(place) name is 1 to 32 of a-z, 0-9 and -")
                        } else if reservedNames.contains(name) {
                            problems.append("\(place) name is the ground's own")
                        } else if name.hasSuffix("-mono") || name.hasSuffix("-dark") {
                            // a hero's Mono image is `<name>-mono.png` beside it in the package, a layer's Dark one
                            // `<name>-dark.png`
                            problems.append("\(place) name ends in -\(name.hasSuffix("-mono") ? "mono" : "dark"), which a layer's \(name.hasSuffix("-mono") ? "Mono" : "Dark") image takes")
                        } else if let first = seen[name] {
                            problems.append("\(place) has the same name as layers[\(first)]")
                        } else {
                            seen[name] = n
                        }
                    } else if layer["name"] == nil {
                        problems.append("\(place) has no name")
                    } else {
                        problems.append("\(place) name is not a string")
                    }
                    if layer["what"] == nil {
                        problems.append("\(place) has no what")
                    } else if !filled(layer["what"]) {
                        problems.append("\(place) what is not a description")
                    }
                    for k in ["without", "shadow"] where layer[k] != nil && !(layer[k] is String) {
                        problems.append("\(place) \(k) is not a string")
                    }
                    for k in ["soft", "hero", "grey", "match"] where layer[k] != nil && !isBool(layer[k]) {
                        problems.append("\(place) \(k) is true or false")
                    }

                    var key: LayerPlan.Key? = .magenta
                    if let k = layer["key"] {
                        key = (k as? String).flatMap(LayerPlan.Key.init(rawValue:))
                        if key == nil { problems.append("\(place) key is \"magenta\", \"black\" or \"clear\"") }
                    }
                    if let box = layer["box"] {
                        if let b = box as? [Any], b.count == 4, b.allSatisfy(isNumber) {
                            let v = b.compactMap { ($0 as? NSNumber)?.doubleValue }
                            let t = Double(tile)
                            if !v.allSatisfy({ $0 == $0.rounded() }) {
                                problems.append("\(place) box [\(v.map(fmt).joined(separator: ", "))] is not four whole numbers")
                            } else if !(0 <= v[0] && v[0] < v[2] && v[2] <= t && 0 <= v[1] && v[1] < v[3] && v[3] <= t) {
                                problems.append(
                                    "\(place) box [\(v.map(fmt).joined(separator: ", "))] needs 0 <= x0 < x1 <= 1024 and 0 <= y0 < y1 <= 1024")
                            }
                        } else {
                            problems.append("\(place) box is not [x0, y0, x1, y1]")
                        }
                    } else if key == .clear {
                        problems.append("\(place) is key \"clear\" without a box: alone on transparency Codex tends to move and enlarge a part, and the box puts it back")
                    }
                    if (layer["soft"] as? Bool) == true, isBool(layer["soft"]), key == .magenta {
                        warnings.append("\(place) is soft on magenta: a glow keyed off magenta gets coloured rings; key it on black")
                    }
                    if let d = layer["dark"] {
                        problems += darkCopyProblems(d).map { "\(place) \($0)" }
                        if (d as? [String: Any])?["draw"] != nil { differing.append(name ?? "layers[\(n)]") }
                    }
                    let only = layer["only"].map { ($0 as? String).flatMap(LayerPlan.Layer.Only.init(rawValue:)) }
                    switch only {
                    case nil: inDefault += 1
                    case .some(nil): problems.append("\(place) only is \"light\" (in Default, Clear and Tinted, hidden in Dark) or \"dark\" (in Dark only)")
                    case .some(.some(let o)):
                        differing.append(name ?? "layers[\(n)]")
                        if o == .light { inDefault += 1 }
                        if layer["dark"] != nil {
                            problems.append(o == .dark
                                ? "\(place) is only in Dark, so it is its own Dark image: leave out its dark"
                                : "\(place) is only in Default, so it has no Dark image: leave out its dark")
                        }
                        if o == .dark {
                            // each acts on the layer against the pick, which has nothing of a part only Dark shows
                            for k in ["hero", "soft", "match"] where (layer[k] as? Bool) == true && isBool(layer[k]) {
                                problems.append("\(place) is only in Dark, and \(k) " + [
                                    "hero": "lifts a part in Clear and Tinted, which show Default's layers",
                                    "soft": "sets a glow's strength against the pick, which does not have it",
                                    "match": "takes the pick's colour, which the pick does not have",
                                ][k]!)
                            }
                        }
                    }
                    if (layer["hero"] as? Bool) == true, isBool(layer["hero"]) { heroes.append(name ?? "layers[\(n)]") }
                    for k in layer.keys.sorted() where !layerKeys.contains(k) {
                        warnings.append("\(place) has an unknown key \"\(k)\", kept and ignored")
                    }
                }
            } else {
                problems.append("layers is not a list")
            }
        } else {
            problems.append("layers is needed: the layers the image model draws, bottom to top")
        }
        if let raw = j["checks"] {
            if let list = raw as? [Any] {
                if list.count > maxChecks {
                    problems.append("checks has \(list.count): at most \(maxChecks), the few things the pick must keep")
                }
                for (n, item) in list.enumerated() where !filled(item) {
                    problems.append("checks[\(n)] is not a sentence: say what must survive from the pick")
                }
            } else {
                problems.append("checks is a list of sentences, each a thing the pick must keep")
            }
        }
        if !differing.isEmpty, inDefault == 0 {
            problems.append("every layer is only in Dark, so Default would show the ground alone")
        }
        let consent = j["consent"]
        if let consent, !filled(consent) {
            problems.append("consent is the user's own words agreeing, not empty")
        } else if consent == nil, !differing.isEmpty {
            problems.append("\(differing.joined(separator: ", ")) make Dark show other parts than Default (\"only\", or "
                + "\"dark\": {\"draw\": ...}). That is a last resort: ask the user first, and put their reply, in their "
                + "own words, in \"consent\"")
        } else if consent != nil, differing.isEmpty {
            warnings.append("consent is kept, but no layer needs it: none has \"only\" or \"dark\": {\"draw\": ...}")
        }
        if heroes.count > 1 {
            warnings.append("\(heroes.count) layers are hero (\(heroes.joined(separator: ", "))): hero marks the one main part, lifted in Clear and Tinted")
        }
        for k in j.keys.sorted() where !knownKeys.contains(k) {
            warnings.append("unknown key \"\(k)\", kept and ignored by the build")
        }
        if !problems.isEmpty { throw Invalid(problems: problems) }
        do {
            return Checked(plan: try JSONDecoder().decode(LayerPlan.self, from: data), warnings: warnings)
        } catch {
            // the check above should catch everything the decoder refuses; if not, say so rather than crash
            throw Invalid(problems: ["it does not read as a plan: \(error)"])
        }
    }

    /// What is wrong with a layer's `dark`, if anything.
    static func darkCopyProblems(_ d: Any) -> [String] {
        let choices = "dark is \"invert\" (the layer's lightness flipped), \"pick\" (the layer in the pick's colour) "
            + "or {\"tone\": \"#rrggbb\"} (the layer in that colour), each made in Dark's copy of the layer; or, with "
            + "the user's consent, {\"draw\": \"words\"} (the image model draws Dark's copy from the words)"
        switch d {
        case let s as String where s == "invert" || s == "pick": return []
        case let o as [String: Any] where o.keys.sorted() == ["tone"]:
            return (o["tone"] as? String).flatMap(LayerPlan.Dark.rgb) == nil
                ? ["dark tone is a colour written #rrggbb, such as \"#1c1c1e\""] : []
        case let o as [String: Any] where o.keys.sorted() == ["draw"]:
            return (o["draw"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? [] : ["dark draw is the words the image model draws the layer's Dark copy from, not empty"]
        default: return [choices]
        }
    }

    static func validName(_ name: String) -> Bool {
        (1...32).contains(name.utf8.count)
            && name.utf8.allSatisfy { (0x61...0x7A).contains($0) || (0x30...0x39).contains($0) || $0 == 0x2D }
    }

    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }

    /// Stores `data` as `<folder>/plan.json`. The one there moves to `rounds/plan-<n>.json`, n one past the highest
    /// there, unless the two are the same JSON, so a round can be put back word for word. Returns the round it
    /// made, if any.
    @discardableResult
    public static func store(_ data: Data, in folder: URL) throws -> URL? {
        let fm = FileManager.default
        let dest = folder.appending(path: "plan.json", directoryHint: .notDirectory)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var round: URL?
        if let old = fm.contents(atPath: dest.path) {
            if sameJSON(old, data) { return nil }
            let rounds = folder.appending(path: "rounds", directoryHint: .isDirectory)
            try fm.createDirectory(at: rounds, withIntermediateDirectories: true)
            let taken = ((try? fm.contentsOfDirectory(atPath: rounds.path)) ?? []).compactMap { name -> Int? in
                guard name.hasPrefix("plan-"), name.hasSuffix(".json") else { return nil }
                return Int(name.dropFirst("plan-".count).dropLast(".json".count))
            }
            let url = rounds.appending(path: "plan-\((taken.max() ?? 0) + 1).json", directoryHint: .notDirectory)
            try fm.moveItem(at: dest, to: url)
            round = url
        }
        try AtomicFile.write(data.last == UInt8(ascii: "\n") ? data : data + Data("\n".utf8), to: dest)
        return round
    }

    static func sameJSON(_ a: Data, _ b: Data) -> Bool {
        guard let x = try? JSONSerialization.jsonObject(with: a), let y = try? JSONSerialization.jsonObject(with: b)
        else { return a == b }
        return (x as AnyObject).isEqual(y)
    }
}
