import Foundation
import Testing

@testable import RimlightCore

@Suite("The grid's filter and sort")
struct IconFilterTests {
    /// Gregorian in UTC with weeks starting on Monday, so the periods don't move with the machine.
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// Wednesday 15 October 2025, 12:00 UTC.
    private static let now = date(2025, 10, 15, 12)

    private static func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private static func icon(
        _ slug: String, set: String = "set-001", title: String? = nil, created: Date = now,
        parent: IconParent? = nil, refs: [IconReference] = [], model: String? = nil
    ) -> IconSnapshot {
        let icon = Icon(
            slug: slug, title: title ?? slug, created: created, by: "test", prompt: "", parent: parent, refs: refs,
            generator: model.map { GeneratorInfo(tool: "test", model: $0) },
            image: ImageInfo(width: 1254, height: 1254, alpha: true))
        let folder = URL(filePath: "/tmp/\(set)/\(slug)")
        return IconSnapshot(
            icon: icon, setID: set, folder: folder, imageURL: folder.appending(path: "icon.png"), stamp: nil)
    }

    private static func slugs(_ filter: IconFilter, _ icons: [IconSnapshot], _ sort: IconSort = .oldest) -> [String] {
        filter.arrange(icons, by: sort, now: now, calendar: calendar).map(\.icon.slug)
    }

    @Test func newestFirstKeepsABatchInSlugOrder() {
        let icons = [
            Self.icon("b", created: Self.date(2025, 10, 1)),
            Self.icon("a", created: Self.date(2025, 10, 1)),
            Self.icon("c", created: Self.date(2025, 10, 2)),
        ]
        #expect(Self.slugs(IconFilter(), icons, .newest) == ["c", "a", "b"])
        #expect(Self.slugs(IconFilter(), icons, .oldest) == ["a", "b", "c"])
    }

    @Test func titlesSortAsFinderDoesNumbersIncluded() {
        let icons = [
            Self.icon("x", title: "Bowl 10"),
            Self.icon("y", title: "bowl 2"),
            Self.icon("z", title: "Anchor"),
        ]
        #expect(Self.slugs(IconFilter(), icons, .title) == ["z", "y", "x"])
    }

    @Test func picksInAGroupWidenAndGroupsNarrow() {
        let parent = IconParent(set: "set-001", icon: "a")
        let icons = [
            Self.icon("a"),
            Self.icon("b", parent: parent, model: "gpt-6-luna"),
            Self.icon("c", refs: [.file("/ref.png")], model: "x-ai/grok-imagine-image-2.0"),
            Self.icon("d", parent: parent, model: "x-ai/grok-imagine-image-2.0"),
            Self.icon("e", model: "gpt-6-luna"),
        ]
        #expect(Self.slugs(IconFilter(kinds: [.refined]), icons) == ["b", "d"])
        #expect(Self.slugs(IconFilter(kinds: [.generated, .refined]), icons) == ["a", "b", "c", "d", "e"])
        #expect(Self.slugs(IconFilter(references: true), icons) == ["c"])
        #expect(Self.slugs(IconFilter(models: ["gpt-6-luna"]), icons) == ["b", "e"])
        // References and a model are one group, so either one lets an icon through.
        #expect(Self.slugs(IconFilter(references: true, models: ["gpt-6-luna"]), icons) == ["b", "c", "e"])
        #expect(Self.slugs(IconFilter(kinds: [.refined], models: ["x-ai/grok-imagine-image-2.0"]), icons) == ["d"])
    }

    @Test func buildsSplitBuiltFromNot() {
        let icons = [Self.icon("a"), Self.icon("b"), Self.icon("c")]
        let built: Set<String> = ["set-001/b"]
        func slugs(_ builds: Set<IconFilter.Build>) -> [String] {
            IconFilter(builds: builds).arrange(icons, by: .oldest, now: Self.now, calendar: Self.calendar, built: built)
                .map(\.icon.slug)
        }
        #expect(slugs([.built]) == ["b"])
        #expect(slugs([.notBuilt]) == ["a", "c"])
        #expect(slugs([.built, .notBuilt]) == ["a", "b", "c"])
    }

    @Test func modelsAreListedOnceByName() {
        let icons = [
            Self.icon("a", model: "x-ai/grok-imagine-image-2.0"),
            Self.icon("b"),
            Self.icon("c", model: "gpt-6-luna"),
            Self.icon("d", model: "x-ai/grok-imagine-image-2.0"),
        ]
        #expect(IconFilter.models(in: icons) == ["gpt-6-luna", "x-ai/grok-imagine-image-2.0"])
    }

    @Test func periodsFollowTheCalendar() {
        let icons = [
            Self.icon("today", created: Self.date(2025, 10, 15, 1)),
            // Monday of this week.
            Self.icon("monday", created: Self.date(2025, 10, 13)),
            // Sunday, the last day of last week.
            Self.icon("sunday", created: Self.date(2025, 10, 12, 23)),
            Self.icon("lastweek", created: Self.date(2025, 10, 6)),
            Self.icon("september", created: Self.date(2025, 9, 30)),
            Self.icon("august", created: Self.date(2025, 8, 31)),
        ]
        #expect(Self.slugs(IconFilter(periods: [.today]), icons, .newest) == ["today"])
        #expect(Self.slugs(IconFilter(periods: [.thisWeek]), icons, .newest) == ["today", "monday"])
        #expect(Self.slugs(IconFilter(periods: [.lastWeek]), icons, .newest) == ["sunday", "lastweek"])
        #expect(
            Self.slugs(IconFilter(periods: [.thisMonth]), icons, .newest) == ["today", "monday", "sunday", "lastweek"])
        #expect(Self.slugs(IconFilter(periods: [.lastMonth]), icons, .newest) == ["september"])
    }

    @Test func lastMonthCrossesTheYear() {
        let range = IconFilter.Period.lastMonth.range(now: Self.date(2026, 1, 10), calendar: Self.calendar)
        #expect(range == Self.date(2025, 12, 1)..<Self.date(2026, 1, 1))
    }
}
