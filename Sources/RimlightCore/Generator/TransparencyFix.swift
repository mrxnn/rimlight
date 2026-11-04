import Foundation

/// The automatic transparency fix of an opaque render. Attempts stop at the first transparent
/// result and go in this order:
///
/// 1. An edit of the opaque render with `prompt`. It usually returns real alpha with the icon
///    unchanged.
/// 2. A fresh roll of the original request: its prompt and refs (for a refine, the parent
///    render; for a plain generate, none). An edit of a painted checkerboard tends to keep it,
///    while a new roll of the same request usually comes back clear.
/// 3. An edit of attempt 2's render with `prompt`, when that render came back opaque.
///
/// Past three the pattern repeats: odd attempts edit the newest opaque render, even ones roll
/// the original request again. An attempt the image model refuses for a limit ends them.
///
/// Last, when the render is still opaque, `BackgroundCutout` clears its painted ground on the
/// Mac, for free. A model that draws transparency gets its paid attempts first, since its own
/// alpha is cleaner than any cutout; one that can't gets the cutout alone, since a paid
/// attempt would come back painted too.
public enum TransparencyFix {
    /// The one fix prompt, used by `rimlight generate` and `rimlight fix` and recorded in `fixes`.
    public static let prompt = """
        Edit Image 1. Remove the backdrop, the checkerboard and any cast shadow so that everything \
        outside the icon tile is fully transparent: a real alpha channel, no painted background of any \
        kind. Keep the icon tile itself and everything on it identical: its shape, size, position, \
        materials, colours, lighting, camera angle, framing and the image size. Output a PNG with \
        transparency.
        """

    public static let defaultAttempts = 3

    /// A fix's image and the model that made it.
    public struct Render: Sendable {
        public var image: URL
        public var model: String

        public init(image: URL, model: String) {
            self.image = image
            self.model = model
        }
    }

    public struct Attempt: Sendable {
        /// 1-based. A re-roll that could not run keeps its number, so the next attempt is 3.
        public var number: Int
        public var kind: FixAttempt.Kind
        public var seconds: Double
        /// nil when the render failed or did not return a readable PNG.
        public var probe: ImageProbe?
        public var error: String?

        public var isTransparent: Bool { probe?.isTransparent == true }

        /// The attempt as `icon.json` records it, seconds to a tenth.
        public var record: FixAttempt {
            FixAttempt(kind: kind, transparent: isTransparent, seconds: (seconds * 10).rounded() / 10)
        }
    }

    public struct Outcome: Sendable {
        /// The image to store: the first transparent result, else the original.
        public var image: URL
        public var probe: ImageProbe
        /// The model that made `image` when it is a fix, nil when it is the original.
        public var fixModel: String?
        public var attempts: [Attempt]
        /// Whether `image` descends from a fresh roll of the original request, so it replaces
        /// the original render rather than editing it.
        public var rerolled: Bool
        /// The prompts of the edits made to `image` after it was rendered: `prompt` when an edit
        /// won, none when the original or a re-roll stands as rendered.
        public var fixes: [String]
        /// Set when the image model refused an attempt for a limit; no attempt follows it.
        public var limit: RenderLimit?
        /// Whether `image` is the render with its ground cut away on the Mac: the render as the
        /// model drew it otherwise, so it keeps its own prompt and model.
        public var cutout = false
        /// The opaque render `image` was made from, when `image` is an edit or a cutout of it
        /// rather than a render as the model drew it; nil otherwise. Kept as `original.png`.
        public var source: URL?
        /// The paid attempts made before the cutout, which the person is told about.
        public var paidAttempts: Int { attempts.filter { $0.kind != .cutout }.count }

        public var isFixed: Bool { fixModel != nil || cutout }
        /// `attempts` as `icon.json` records them.
        public var records: [FixAttempt] { attempts.map(\.record) }
    }

    /// The edit of `image` with `prompt`, with `settings`' model, effort and timeout when given.
    public static func editRequest(_ image: URL, like settings: ImageRequest?) -> ImageRequest {
        var request = ImageRequest(
            prompt: prompt, refs: [image], model: settings?.model, effort: settings?.effort)
        if let settings { request.timeout = settings.timeout }
        return request
    }

    /// Fixes an opaque `image` in the order above: up to `attempts` paid renders when `paid`,
    /// then the cutout into `cutout` when given. `original` is the request that made `image`; nil
    /// skips the re-roll attempts, and the edit after one then edits `image` again. A
    /// transparent `image` or `attempts` 0 does nothing. `render(request, attempt)` makes one
    /// image; `onAttempt` hears each attempt as it ends, the cutout last.
    public static func run(
        _ image: URL,
        probe: ImageProbe,
        original: ImageRequest?,
        attempts: Int,
        cutout: URL? = nil,
        paid: Bool = true,
        render: (_ request: ImageRequest, _ attempt: Int) throws -> Render,
        onAttempt: (Attempt) -> Void = { _ in }
    ) -> Outcome {
        var outcome = Outcome(
            image: image, probe: probe, fixModel: nil, attempts: [], rerolled: false, fixes: [], limit: nil)
        guard !probe.isTransparent, attempts > 0 else { return outcome }
        if paid { attemptPaid(&outcome, image, original: original, attempts: attempts, render: render, onAttempt: onAttempt) }
        if !outcome.isFixed, let cutout { attemptCutout(&outcome, image, to: cutout, number: outcome.attempts.count + 1, onAttempt: onAttempt) }
        return outcome
    }

    /// The paid attempts, in the order above, until one comes back transparent.
    private static func attemptPaid(
        _ outcome: inout Outcome, _ image: URL, original: ImageRequest?, attempts: Int,
        render: (_ request: ImageRequest, _ attempt: Int) throws -> Render, onAttempt: (Attempt) -> Void
    ) {
        // The newest opaque render, which the next edit works on.
        var latest = image
        var latestIsReroll = false
        let clock = ContinuousClock()
        for number in 1...attempts {
            let kind: FixAttempt.Kind = number.isMultiple(of: 2) ? .reroll : .transparencyEdit
            let request: ImageRequest
            switch kind {
            case .transparencyEdit, .cutout:
                request = editRequest(latest, like: original)
            case .reroll:
                guard var reroll = original else { continue }
                reroll.count = 1
                reroll.outputDir = nil
                request = reroll
            }
            let started = clock.now
            var attempt = Attempt(number: number, kind: kind, seconds: 0, probe: nil, error: nil)
            var made: Render?
            do {
                made = try render(request, number)
                attempt.probe = made.flatMap { ImageProbe.read($0.image) }
                if attempt.probe == nil { attempt.error = "the fix did not return a readable PNG" }
            } catch {
                attempt.error = "\(error)"
                if case ImageFailure.limit(let limit) = error { outcome.limit = limit }
            }
            let elapsed = started.duration(to: clock.now)
            attempt.seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            onAttempt(attempt)
            outcome.attempts.append(attempt)
            // Every later attempt would be refused too.
            if outcome.limit != nil { break }
            guard let made, let madeProbe = attempt.probe else { continue }
            if madeProbe.isTransparent {
                outcome.image = made.image
                outcome.probe = madeProbe
                outcome.fixModel = made.model
                outcome.rerolled = kind == .reroll || latestIsReroll
                outcome.fixes = kind == .reroll ? [] : [prompt]
                outcome.source = kind == .reroll ? nil : latest
                break
            }
            if kind == .reroll {
                latest = made.image
                latestIsReroll = true
            }
        }
    }

    /// The render as drawn, its ground cut away on the Mac into `output`.
    private static func attemptCutout(
        _ outcome: inout Outcome, _ image: URL, to output: URL, number: Int, onAttempt: (Attempt) -> Void
    ) {
        let clock = ContinuousClock()
        let started = clock.now
        let method = BackgroundCutout.cut(image, to: output)
        let elapsed = started.duration(to: clock.now)
        var attempt = Attempt(
            number: number, kind: .cutout,
            seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
            probe: method == nil ? nil : ImageProbe.read(output),
            error: method == nil ? "no ground to cut away around a tile" : nil)
        if method != nil, attempt.probe == nil { attempt.error = "the cutout did not write a readable PNG" }
        onAttempt(attempt)
        outcome.attempts.append(attempt)
        if let made = attempt.probe, made.isTransparent {
            outcome.image = output
            outcome.probe = made
            outcome.cutout = true
            outcome.source = image
        }
    }
}
