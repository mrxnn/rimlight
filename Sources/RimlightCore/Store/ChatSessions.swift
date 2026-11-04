import Foundation

/// Every session a chat has had, kept beside `chat` in set.json and icon.json so New Session
/// forgets the current one without losing it. The Sessions menu lists them.
public enum ChatSessions {
    /// The most sessions one chat keeps; the oldest go first.
    public static let limit = 100

    /// Appends `session` to the harness's list unless it is already there.
    public static func record(_ session: String, in history: inout [String: [String]], harness: String) {
        var list = history[harness] ?? []
        guard !list.contains(session) else { return }
        list.append(session)
        if list.count > limit { list.removeFirst(list.count - limit) }
        history[harness] = list
    }

    /// The harness's sessions, oldest first. A record written before the history existed lists
    /// none, so its current session is added at the end.
    public static func sessions(chat: [String: String], history: [String: [String]], harness: String) -> [String] {
        var list = history[harness] ?? []
        if let current = chat[harness], !list.contains(current) { list.append(current) }
        return list
    }
}
