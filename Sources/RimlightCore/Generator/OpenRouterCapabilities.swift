import Foundation

/// What one OpenRouter image model accepts: the `supported_parameters` of its entry in
/// `GET /images/models`. OpenRouter treats a field missing from the map as unsupported, and
/// its models differ a lot (some take no `background`, some one reference image), so a request
/// sends only what the model lists.
public struct OpenRouterCapabilities: Hashable, Sendable {
    /// The allowed values of each enum field, such as `resolution`.
    public var values: [String: [String]]
    /// The bounds of each range field, such as `input_references`.
    public var ranges: [String: ClosedRange<Int>]
    /// Every field the model takes, enum, range or boolean.
    public var fields: Set<String>

    public init(values: [String: [String]] = [:], ranges: [String: ClosedRange<Int>] = [:], fields: Set<String>? = nil) {
        self.values = values
        self.ranges = ranges
        self.fields = fields ?? Set(values.keys).union(ranges.keys)
    }

    /// From one `supported_parameters` map.
    init(_ map: [String: Any]) {
        var values: [String: [String]] = [:]
        var ranges: [String: ClosedRange<Int>] = [:]
        for (key, descriptor) in map {
            guard let descriptor = descriptor as? [String: Any] else { continue }
            switch descriptor["type"] as? String {
            case "enum": values[key] = descriptor["values"] as? [String] ?? []
            case "range":
                let low = (descriptor["min"] as? NSNumber)?.intValue ?? 0
                let high = (descriptor["max"] as? NSNumber)?.intValue ?? Int.max
                if low <= high { ranges[key] = low...high }
            default: break
            }
        }
        self.init(values: values, ranges: ranges, fields: Set(map.keys))
    }

    /// The entry for `model` in a `/images/models` reply; nil when the reply doesn't list it.
    public static func find(_ model: String, in data: Data) -> OpenRouterCapabilities? {
        entries(data).first { $0["id"] as? String == model }.map(Self.init(entry:))
    }

    init(entry: [String: Any]) {
        self.init(entry["supported_parameters"] as? [String: Any] ?? [:])
    }

    static func entries(_ data: Data) -> [[String: Any]] {
        let json = try? JSONSerialization.jsonObject(with: data)
        return (json as? [String: Any])?["data"] as? [[String: Any]] ?? json as? [[String: Any]] ?? []
    }

    /// Whether the model takes `field` and, for an enum, `value` among its values.
    public func accepts(_ field: String, _ value: String? = nil) -> Bool {
        guard fields.contains(field) else { return false }
        guard let value, let allowed = values[field] else { return true }
        return allowed.contains(value)
    }

    /// Whether the model can draw on real transparency: it lists `transparent` among its
    /// `background` values. One that can't paints a ground, which Rimlight cuts out itself.
    public var drawsTransparency: Bool { accepts("background", "transparent") }

    /// Whether the model can return a raster image. Vector models list only `svg`.
    public var drawsRaster: Bool {
        guard let formats = values["output_format"] else { return true }
        return formats.contains { ["png", "webp", "jpeg"].contains($0) }
    }

    /// The `resolution` tier nearest Rimlight's 1254 px frame, by pixels; nil when the model
    /// takes none. 1K, upscaled by the normalizer, beats 1.5K and costs less.
    public var resolution: String? {
        guard let tiers = values["resolution"], !tiers.isEmpty else { return nil }
        let pixels: [String: Int] = ["512": 512, "768": 768, "1K": 1024, "1.5K": 1536, "2K": 2048, "4K": 4096]
        return tiers.filter { pixels[$0] != nil }.min {
            abs(pixels[$0]! - TileShape.renderSide) < abs(pixels[$1]! - TileShape.renderSide)
        }
    }
}
