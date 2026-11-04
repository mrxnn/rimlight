import Foundation

/// What a model charges for the image it draws, as OpenRouter lists it per provider in
/// `GET /images/models/{id}/endpoints`: by the image for most models, by the token for
/// OpenAI's and Google's. The picker shows `label`; the bill itself comes from the provider.
public struct ImagePrice: Hashable, Sendable {
    /// US dollars per drawn image, cheapest and dearest size or quality; nil when billed by token.
    public var perImage: ClosedRange<Double>?
    /// US dollars per million image tokens drawn, when billed by token.
    public var perMillionTokens: Double?
    /// US dollars per reference image sent, when the model charges for them. Every fresh render
    /// sends the tile template, and every edit its parent.
    public var perReference: Double?

    public init(perImage: ClosedRange<Double>? = nil, perMillionTokens: Double? = nil, perReference: Double? = nil) {
        self.perImage = perImage
        self.perMillionTokens = perMillionTokens
        self.perReference = perReference
    }

    /// `$0.04 an image`, `$0.04 to $0.06 an image`, or `$30 per million image tokens`.
    public var label: String {
        if let perImage {
            let low = Self.dollars(perImage.lowerBound)
            return perImage.lowerBound == perImage.upperBound
                ? "\(low) an image" : "\(low) to \(Self.dollars(perImage.upperBound)) an image"
        }
        if let perMillionTokens { return "\(Self.dollars(perMillionTokens)) per million image tokens" }
        return "Price not listed"
    }

    static func dollars(_ value: Double) -> String {
        if value >= 1, value.rounded() == value { return "$\(Int(value))" }
        let text = String(format: value < 0.1 ? "%.3f" : "%.2f", value)
        // $0.040 reads as $0.04; keep a third digit only when it says something.
        let trimmed = text.hasSuffix("0") && text.split(separator: ".").last?.count == 3 ? String(text.dropLast()) : text
        return "$" + trimmed
    }

    /// The price of the first provider in an endpoints reply; nil when it lists none for the
    /// drawn image.
    public static func parse(endpoints data: Data) -> ImagePrice? {
        let json = try? JSONSerialization.jsonObject(with: data)
        var list: Any? = (json as? [String: Any])?["data"] ?? json
        if let wrapped = list as? [String: Any] { list = wrapped["endpoints"] }
        guard let endpoints = list as? [[String: Any]] else { return nil }
        for endpoint in endpoints {
            guard let pricing = endpoint["pricing"] as? [[String: Any]] else { continue }
            var images: [Double] = []
            var tokens: Double?
            var reference: Double?
            for line in pricing {
                guard let cost = (line["cost_usd"] as? NSNumber)?.doubleValue else { continue }
                switch (line["billable"] as? String, line["unit"] as? String) {
                case ("output_image", "image"): images.append(cost)
                case ("output_image", "token"): tokens = min(tokens ?? cost, cost)
                case ("input_image", "image"): reference = cost
                default: break
                }
            }
            if let low = images.min(), let high = images.max() {
                return ImagePrice(perImage: low...high, perReference: reference)
            }
            if let tokens { return ImagePrice(perMillionTokens: tokens * 1_000_000) }
        }
        return nil
    }
}
