import Foundation

/// One line of `codex exec --json` output, reduced to what the generator needs.
public enum CodexEvent: Hashable, Sendable {
    /// `thread.started`: the id that names `generated_images/<thread>/`.
    case threadStarted(String)
    /// `item.completed` with an `agent_message` item.
    case agentMessage(String)
    /// `turn.completed`, with its token counts.
    case turnCompleted(ImageUsage?)
    /// `error` or `turn.failed`: the event's `error`, else its `message`, else the whole event, as JSON.
    case failure(String)
    /// Any other event, by type.
    case other(String)

    /// nil for a line that is not a JSON object with a `type`.
    public static func parse<S: StringProtocol>(_ line: S) -> CodexEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)),
            let event = object as? [String: Any], let type = event["type"] as? String
        else { return nil }
        switch type {
        case "thread.started":
            guard let id = event["thread_id"] as? String else { return .other(type) }
            return .threadStarted(id)
        case "item.completed":
            guard let item = event["item"] as? [String: Any], item["type"] as? String == "agent_message" else {
                return .other(type)
            }
            return .agentMessage(item["text"] as? String ?? "")
        case "turn.completed":
            return .turnCompleted((event["usage"] as? [String: Any]).map(ImageUsage.init(json:)))
        case "error", "turn.failed":
            let value = [event["error"], event["message"]].lazy.compactMap { $0 }.first { isTruthy($0) } ?? (event as Any)
            return .failure(jsonText(value))
        default:
            return .other(type)
        }
    }

    /// Every event in a stdout capture, one per line, skipping lines that are not events.
    public static func parseAll(_ data: Data) -> [CodexEvent] {
        String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { parse($0) }
    }

    /// Python's truthiness, which the script's `a or b or c` relies on.
    private static func isTruthy(_ value: Any) -> Bool {
        switch value {
        case is NSNull: return false
        case let s as String: return !s.isEmpty
        case let d as [String: Any]: return !d.isEmpty
        case let a as [Any]: return !a.isEmpty
        default: return true
        }
    }

    private static func jsonText(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
        else { return String(describing: value) }
        return String(decoding: data, as: UTF8.self)
    }
}

/// What one Codex turn said, folded from its events.
public struct CodexTranscript: Hashable, Sendable {
    public var threadID: String?
    public var messages: [String] = []
    public var usage: ImageUsage?
    public var errors: [String] = []

    public init(_ events: [CodexEvent]) {
        for event in events {
            switch event {
            case .threadStarted(let id): threadID = id
            case .agentMessage(let text): messages.append(text)
            case .turnCompleted(let u): usage = u
            case .failure(let text): errors.append(text)
            case .other: break
            }
        }
    }
}
