import Foundation

/// The image model's prompts for a layer plan, word for word from the layer trial's `lt.py`, which drew with
/// Codex. Every image is an edit of the pick (Image 1), never a fresh prompt, so palette, light and texture
/// carry over.
public enum LayerPrompts {
    /// Raised whenever the wording below changes, so a layer drawn from older words can be told apart.
    public static let version = "1"

    /// The background with the objects taken out, edge to edge: Codex keeps a full-frame edit's layout.
    public static func ground(_ plan: LayerPlan) -> String {
        "Square image. Edit Image 1. Image 1 is an app icon. Output only its background: \(plan.ground.keep). "
            + "Remove \(plan.ground.remove). Paint what lies behind them so the background carries on naturally. "
            + "Fill the whole square edge to edge, the four corners included: no rounded tile shape, no border, "
            + "no transparency. Keep the same colours, lighting, texture, grain and detail at the same scale and "
            + "in the same place as in Image 1. No text, no watermark."
    }

    /// Dark's ground in the user's own words, `dark: {"keep": ...}`. Image 1 is the drawn light ground.
    public static func darkGround(describing words: String) -> String {
        "Square image. Edit Image 1. Make the dark-mode version of this app icon background: \(words). Keep the same "
            + "picture, layout, texture, grain and scale as Image 1; change only its colours and light as described. "
            + "Keep it edge to edge with no tile shape, no border and no transparency. No text, no watermark."
    }

    /// The prompt for Dark's ground when the image model draws it, nil when the plan makes it in code.
    public static func darkGround(_ plan: LayerPlan) -> String? {
        switch plan.dark {
        case .generate: darkGround()
        case .describe(let words): darkGround(describing: words)
        case .dim, .tone, .invert: nil
        }
    }

    /// The Dark ground for `dark: generate`. Image 1 is the drawn light ground, not the pick.
    public static func darkGround() -> String {
        "Square image. Edit Image 1. Make the dark-mode version of this app icon background, the way Apple's "
            + "dark appearance does: the same picture, layout, texture and scale, its colours stepped down to a deep, "
            + "low-light shade of the same hues, lit areas dimmed to match, so light objects placed on it stand out. "
            + "Keep it edge to edge with no tile shape, no border and no transparency. No text, no watermark."
    }

    /// One layer alone, complete where another part covers it. `key` overrides the layer's own, so a `clear`
    /// layer that came back opaque can be drawn again on magenta. A layer only in Dark is not in the pick, so it is
    /// drawn new in the pick's style.
    public static func layer(_ plan: LayerPlan, _ layer: LayerPlan.Layer, key: LayerPlan.Key? = nil) -> String {
        let key = key ?? layer.key
        if layer.only == .dark { return darkOnly(layer, key: key) }
        var s =
            "Square image. Edit Image 1. Image 1 is an app icon. Output only \(layer.what), \(backdrop(key)). "
            + "Keep it exactly as drawn in Image 1: the same position in the square, the same size, perspective, "
            + "colours, lighting, texture and detail. Draw it complete, including any part another object covers "
            + "in Image 1. "
        if let without = layer.without, !without.isEmpty { s += "Leave out \(without). " }
        // a shadow belongs to the layer it falls on; "leave out the bird" took the twig's with it
        if let shadow = layer.shadow, !shadow.isEmpty { s += "Keep \(shadow) exactly as in Image 1, drawn on this part. " }
        if plan.dark != .dim {
            // the caliper's knurl kept the orange body's copper cast, wrong on Dark's graphite; any Dark that recolours the
            // ground needs it. Not under dim, where a night scene's coloured light on its parts is the picture. It is in
            // no signature: a drawing made under another Dark stays, and its Dark copy loses the ground's hue in the fit
            s += "Light it with neutral white light: no colour cast or reflection from the background around it, "
                + "since the background changes colour in dark mode. "
        }
        s += leaveOut(plan, layer) + ". No text, no watermark."
        return s + transparency(key)
    }

    /// A layer's Dark image for `"dark": {"draw": words}`: another part in the layer's place, an edit of the pick
    /// like the layer, so it keeps the pick's style and the layer's place.
    public static func layerDark(_ plan: LayerPlan, _ layer: LayerPlan.Layer, words: String, key: LayerPlan.Key? = nil) -> String {
        let key = key ?? layer.key
        var s =
            "Square image. Edit Image 1. Image 1 is an app icon in its light appearance. Output only the dark-mode "
            + "version of \(layer.what): \(words), \(backdrop(key)). Put it where that part is in Image 1, at about the "
            + "same size, and draw it in the same style: the same rendering, lighting direction, texture and level of "
            + "detail. Draw it complete. "
        if let without = layer.without, !without.isEmpty { s += "Leave out \(without). " }
        s += leaveOut(plan, layer) + ". No text, no watermark."
        return s + transparency(key)
    }

    /// A layer only in Dark: a part the pick does not have, drawn new in the pick's style.
    static func darkOnly(_ layer: LayerPlan.Layer, key: LayerPlan.Key) -> String {
        var s =
            "Square image. Edit Image 1. Image 1 is an app icon in its light appearance. Output only a new part for "
            + "its dark-mode version: \(layer.what), \(backdrop(key)). Draw it in the same style as Image 1: the same "
            + "rendering, lighting direction, texture and level of detail, placed in the square as described. "
        if let without = layer.without, !without.isEmpty { s += "Leave out \(without). " }
        s += "Leave out everything that is in Image 1: its background and every part on it. No text, no watermark."
        return s + transparency(key)
    }

    static func backdrop(_ key: LayerPlan.Key) -> String {
        switch key {
        case .clear:
            "alone on a fully transparent background (real alpha channel, no backdrop, no checkerboard, no cast shadow)"
        case .black:
            "alone on a flat, solid, pure black (#000000) background that fills everything around it"
        case .magenta:
            "alone on a flat, solid, pure magenta (#FF00FF) background that fills everything around it, "
                + "with no shadow, glow or gradient on the magenta"
        }
    }

    /// The background and the pick's other parts, which the layer leaves out. Not a part only Dark has, which the
    /// pick does not show.
    static func leaveOut(_ plan: LayerPlan, _ layer: LayerPlan.Layer) -> String {
        // by name, so a redraw with another key still leaves the layer itself off this list
        let others = plan.layers.filter { $0.name != layer.name && $0.only != .dark }.map(\.what)
        return "Leave out the background (\(plan.ground.keep))" + (others.isEmpty ? "" : " and " + others.joined(separator: "; "))
    }

    static func transparency(_ key: LayerPlan.Key) -> String {
        key != .clear ? ""
            : " Everything around it must be real transparent pixels, alpha zero, even where it runs to the edge "
                + "of the square; never paint a grey and white checkerboard. Output a PNG with transparency."
    }
}
