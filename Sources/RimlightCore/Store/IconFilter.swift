import Foundation

/// The order a grid shows its icons in.
public enum IconSort: String, CaseIterable, Codable, Sendable {
    /// Newest first. One batch, made in the same second, reads in slug order.
    case newest
    case oldest
    /// By title as Finder orders names, newest first among equal titles.
    case title

    /// True when `a` comes before `b`. Ties fall to the slug, then the set, so the order is total.
    public func precedes(_ a: IconSnapshot, _ b: IconSnapshot) -> Bool {
        switch self {
        case .newest:
            if a.icon.created != b.icon.created { return a.icon.created > b.icon.created }
        case .oldest:
            if a.icon.created != b.icon.created { return a.icon.created < b.icon.created }
        case .title:
            let order = a.icon.title.localizedStandardCompare(b.icon.title)
            if order != .orderedSame { return order == .orderedAscending }
            if a.icon.created != b.icon.created { return a.icon.created > b.icon.created }
        }
        if a.icon.slug != b.icon.slug { return a.icon.slug < b.icon.slug }
        return a.setID < b.setID
    }
}

/// Which icons a grid shows. Picks within a group widen it (an icon needs any one of them);
/// groups narrow it (an icon needs every group that has a pick). The groups are the kind, what
/// an icon was made with (`references` and `models`), whether it has a build, and the periods.
/// Empty shows every icon.
public struct IconFilter: Hashable, Sendable {
    public enum Kind: CaseIterable, Hashable, Sendable {
        /// Made from a prompt alone (`IconMode.generate`).
        case generated
        /// Made from another icon (`IconMode.refine`).
        case refined
    }

    /// Whether the icon has a finished Icon Composer build (`ProjectStore.hasBuild`).
    public enum Build: CaseIterable, Hashable, Sendable {
        case built
        case notBuilt
    }

    /// Calendar periods, in the user's calendar: weeks start on its first weekday.
    public enum Period: CaseIterable, Hashable, Sendable {
        case today
        case thisWeek
        case lastWeek
        case thisMonth
        case lastMonth

        /// The period around `now`. Empty when the calendar can't place it.
        public func range(now: Date, calendar: Calendar) -> Range<Date> {
            let interval: DateInterval? =
                switch self {
                case .today: calendar.dateInterval(of: .day, for: now)
                case .thisWeek: calendar.dateInterval(of: .weekOfYear, for: now)
                case .lastWeek: Self.previous(.weekOfYear, now, calendar)
                case .thisMonth: calendar.dateInterval(of: .month, for: now)
                case .lastMonth: Self.previous(.month, now, calendar)
                }
            guard let interval else { return now..<now }
            return interval.start..<interval.end
        }

        private static func previous(_ unit: Calendar.Component, _ now: Date, _ calendar: Calendar) -> DateInterval? {
            guard let current = calendar.dateInterval(of: unit, for: now) else { return nil }
            return calendar.dateInterval(of: unit, for: current.start.addingTimeInterval(-1))
        }
    }

    public var kinds: Set<Kind>
    /// Made with reference images.
    public var references: Bool
    /// Drawn by one of these image models, by the id `icon.json` records (`GeneratorInfo.model`).
    public var models: Set<String>
    public var builds: Set<Build>
    public var periods: Set<Period>

    public init(
        kinds: Set<Kind> = [], references: Bool = false, models: Set<String> = [], builds: Set<Build> = [],
        periods: Set<Period> = []
    ) {
        self.kinds = kinds
        self.references = references
        self.models = models
        self.builds = builds
        self.periods = periods
    }

    public var isEmpty: Bool { kinds.isEmpty && !references && models.isEmpty && builds.isEmpty && periods.isEmpty }

    /// The image models that drew `icons`, each once, ordered by name.
    public static func models(in icons: some Sequence<IconSnapshot>) -> [String] {
        Set(icons.compactMap { $0.icon.generator?.model }.filter { !$0.isEmpty })
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// A test for one icon, with the periods' bounds worked out once from `now`. `built` holds the
    /// ids, `<set>/<slug>`, of the icons with a build.
    public func matcher(
        now: Date = .now, calendar: Calendar = .current, built: Set<String> = []
    ) -> @Sendable (IconSnapshot) -> Bool {
        let kinds = kinds
        let references = references
        let models = models
        let builds = builds
        let ranges = periods.map { $0.range(now: now, calendar: calendar) }
        return { snapshot in
            let icon = snapshot.icon
            if !kinds.isEmpty, !kinds.contains(icon.mode == .refine ? .refined : .generated) { return false }
            if references || !models.isEmpty {
                let withReferences = references && !icon.refs.isEmpty
                let byModel = icon.generator.map { models.contains($0.model) } ?? false
                if !withReferences && !byModel { return false }
            }
            if !builds.isEmpty, !builds.contains(built.contains(snapshot.id) ? .built : .notBuilt) { return false }
            if !ranges.isEmpty, !ranges.contains(where: { $0.contains(icon.created) }) { return false }
            return true
        }
    }

    /// The icons that pass, in `sort`'s order. One pass and an n log n sort.
    public func arrange(
        _ icons: [IconSnapshot], by sort: IconSort, now: Date = .now, calendar: Calendar = .current,
        built: Set<String> = []
    ) -> [IconSnapshot] {
        var kept = icons
        if !isEmpty {
            let matches = matcher(now: now, calendar: calendar, built: built)
            kept.removeAll { !matches($0) }
        }
        kept.sort(by: sort.precedes)
        return kept
    }
}
