import RimlightCore
import Testing

@Test func versionIsThreeNumbers() {
    let parts = Rimlight.version.split(separator: ".").map { Int($0) }
    #expect(parts.count == 3)
    #expect(parts.allSatisfy { $0 != nil })
}
