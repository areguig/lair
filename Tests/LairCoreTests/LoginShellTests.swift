@testable import LairCore
import Testing

struct LoginShellTests {
    @Test func keepsOnlyWhatFollowsTheMarker() {
        #expect(LoginShell.parse("Welcome!\n\(LoginShell.marker)/a/bin:/usr/bin") == "/a/bin:/usr/bin")
    }

    @Test func returnsNilWithoutMarkerOrPath() {
        #expect(LoginShell.parse("no marker") == nil)
        #expect(LoginShell.parse(LoginShell.marker) == nil)
    }

    @Test func readsTheRealLoginPath() async {
        let path = await LoginShell.path()
        #expect(path?.contains("/usr/bin") == true)
    }
}
