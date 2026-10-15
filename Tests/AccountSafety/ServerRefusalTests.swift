import Foundation
import OpenAPIRuntime
import XCTest

@testable import RepbaseAPI

/// What a person reads when the server refuses a post or a clip.
///
/// The server says why in a sentence filed under the field it is about. Shown
/// as "HTTP 400", a refused upload looks like the app breaking; shown with
/// the field's wire name in front -- "Image Base64: ..." -- it looks like a
/// debug log. Posting asks for the sentence alone.
final class ServerRefusalTests: XCTestCase {
    private func refusal(
        _ status: Int,
        _ json: String,
        unlabeled: Set<String> = []
    ) async -> String? {
        let payload = UndocumentedPayload(headerFields: [:], body: HTTPBody(Data(json.utf8)))
        return await RepbaseAPIHTTPError.decode(
            statusCode: status, payload: payload, unlabeled: unlabeled
        ).errorDescription
    }

    func testANamedFieldIsShownAsItsSentence() async {
        let message = await refusal(
            400, #"{"image_base64": ["Add a photo or a video to post."]}"#,
            unlabeled: ["image_base64", "video"]
        )
        XCTAssertEqual(message, "Add a photo or a video to post.")
    }

    func testTheOneClipAtATimeLimitReadsAsWhatToDo() async {
        let message = await refusal(
            400, #"{"video": "Finish your pending video before uploading another."}"#,
            unlabeled: ["video"]
        )
        XCTAssertEqual(message, "Finish your pending video before uploading another.")
    }

    func testOtherFieldsStillSayWhichFieldTheyAreAbout() async {
        let message = await refusal(400, #"{"caption": ["Too long."]}"#, unlabeled: ["video"])
        XCTAssertEqual(message, "Caption: Too long.")
    }

    func testWithoutTheListEveryFieldIsLabelledAsBefore() async {
        let message = await refusal(400, #"{"video": ["Too long."]}"#)
        XCTAssertEqual(message, "Video: Too long.")
    }

    func testAServerFailureKeepsTheGenericSentence() async {
        let message = await refusal(500, #"{"video": ["Storage is down."]}"#, unlabeled: ["video"])
        XCTAssertEqual(message, "The server returned an unexpected response (HTTP 500).")
    }
}
