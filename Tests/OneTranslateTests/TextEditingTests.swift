import XCTest
@testable import OneTranslate

final class TextEditingTests: XCTestCase {
    func testSelectedWordsPreserveSurroundingText() {
        let text = "Keep this. Hello world. Keep that."
        let range = (text as NSString).range(of: "Hello world")
        let plan = TextEditPlan(before: text, range: range, replacement: "你好世界")
        XCTAssertEqual(plan.after, "Keep this. 你好世界. Keep that.")
        XCTAssertEqual(plan.inverse?.after, text)
    }

    func testUTF16SelectionAfterEmoji() {
        let text = "🙂你好，世界🌍！"
        let plan = TextEditPlan(before: text, range: (text as NSString).range(of: "世界🌍"), replacement: "world")
        XCTAssertEqual(plan.after, "🙂你好，world！")
        XCTAssertEqual(plan.inverse?.after, text)
    }

    func testRepeatedWordsUseExactSelectedRange() {
        let text = "hello / hello"
        let plan = TextEditPlan(before: text, range: NSRange(location: 8, length: 5), replacement: "你好")
        XCTAssertEqual(plan.after, "hello / 你好")
        XCTAssertEqual(plan.inverse?.after, text)
    }

    func testWholeFieldUndoRestoresExactOriginalIncludingWhitespace() {
        let text = " 原文\n\n第二行 "
        let plan = TextEditPlan(before: text, range: NSRange(location: 0, length: (text as NSString).length), replacement: "Translated")
        XCTAssertEqual(plan.after, "Translated")
        XCTAssertEqual(plan.inverse?.after, text)
    }

    func testInvalidRangesCannotReplaceText() {
        for range in [NSRange(location: NSNotFound, length: 1), NSRange(location: 4, length: 2), NSRange(location: 1, length: Int.max)] {
            let plan = TextEditPlan(before: "abc", range: range, replacement: "x")
            XCTAssertNil(plan.after)
            XCTAssertNil(plan.inverse)
        }
    }

    func testReverseDirectionWithoutKeychain() {
        var settings = AppSettings()
        settings.sourceLanguage = "Chinese (Traditional)"
        XCTAssertEqual(settings.direction(forSelection: true).target, "Chinese (Traditional)")
        XCTAssertEqual(settings.direction(forSelection: false).target, "English")
        settings.reverseLanguage = "Japanese"
        XCTAssertEqual(settings.direction(forSelection: true).target, "Japanese")
    }

    func testRejectsRemoteHTTPAndURLCredentialsBeforeNetworkAccess() async {
        for endpoint in ["http://example.com/v1/chat/completions", "https://user:password@example.com/v1/chat/completions", "file:///tmp/model"] {
            var settings = AppSettings()
            settings.endpoint = endpoint
            do {
                _ = try await TranslationService().translate("test", settings: settings)
                XCTFail("Unsafe endpoint should be rejected")
            } catch TranslationError.invalidEndpoint {
                // Expected, without a network request or Keychain access.
            } catch {
                XCTFail("Unexpected error type")
            }
        }
    }
}
