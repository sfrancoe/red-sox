import Foundation

private final class FixtureBundle: NSObject {}
func testFixture(_ name: String) -> URL {
    Bundle(for: FixtureBundle.self).url(forResource: name, withExtension: "json")!
}
