import Foundation
import RepbaseAPI
import XCTest
@testable import AccountSafety

final class NotificationActivityTests: XCTestCase {
    private func event(
        _ id: Int, kind: SocialNotification.Kind = .like, actor: Int = 10,
        post: Int? = 50, time: TimeInterval = 100, read: Bool = false,
        scoped: Bool = true, preview: SocialNotificationPostPreview? = nil
    ) -> SocialNotification {
        SocialNotification(
            id: id, kind: kind, actorID: actor,
            actorUsername: "person\(actor)", actorFirstName: "", actorLastName: "",
            actorPhotoURL: nil, postID: post, commentBody: nil, isRead: read,
            createdAt: Date(timeIntervalSince1970: time), postPreview: preview,
            supportsScopedRead: scoped
        )
    }

    func testSamePostAcrossDatesAndPagesHasOneCardAndDistinctPeople() throws {
        let rows = [
            event(1, actor: 10, time: 100),
            event(2, kind: .comment, actor: 10, time: 100_000),
            event(3, kind: .comment, actor: 11, time: 99_000),
            event(4, kind: .repost, actor: 12, time: 99_100),
            event(5, post: 70, time: 90_000),
        ]
        let groups = SocialNotificationGrouping.groups(from: rows)
        XCTAssertEqual(groups.map(\.id), ["post:50", "post:70"])
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.notifications.map(\.id), [2, 4, 3, 1])
        XCTAssertEqual(group.actors.map(\.actorID), [10, 12, 11])
        XCTAssertEqual(group.likes, 1)
        XCTAssertEqual(group.comments, 2)
        XCTAssertEqual(group.reposts, 1)
        XCTAssertEqual(group.createdAt, Date(timeIntervalSince1970: 100_000))
    }

    func testDuplicateEventsDoNotInflateActionsOrUnreadState() throws {
        let groups = SocialNotificationGrouping.groups(from: [
            event(1, read: true), event(1, read: false), event(2, kind: .comment),
        ])
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(group.likes, 1)
        XCTAssertEqual(group.comments, 1)
        XCTAssertEqual(group.actors.count, 1)
        XCTAssertEqual(group.unreadIDs, [2])
        XCTAssertFalse(group.isRead)
    }

    func testFollowModerationAndUnknownRemainSeparateFromPostActivity() {
        let rows = [
            event(1), event(2, kind: .follow, post: nil),
            event(3, kind: .followRequest, post: nil),
            event(4, kind: .followApproved, post: nil),
            event(5, kind: .moderationRejected), event(6, kind: .unknown),
            event(7, post: nil),
        ]
        let groups = SocialNotificationGrouping.groups(from: rows)
        XCTAssertEqual(groups.count, 7)
        XCTAssertEqual(groups.filter(\.isPostActivity).map(\.id), ["post:50"])
        XCTAssertNil(groups.first { $0.id == "notification:5" }?.postID)
    }

    func testMissingPreviewDoesNotReuseAnOlderAuthorizedURL() throws {
        let preview = SocialNotificationPostPreview(
            id: 50, kind: "meal", title: "Lunch", thumbnailURL: "https://example.test/private", mediaKind: "photo"
        )
        let groups = SocialNotificationGrouping.groups(from: [
            event(1, time: 10, preview: preview), event(2, time: 20),
        ])
        XCTAssertNil(try XCTUnwrap(groups.first).preview)
    }

    func testEqualTimestampsSortDeterministicallyAndUnknownDatesGoLast() {
        var missing = event(90, post: 99)
        missing.createdAt = nil
        let groups = SocialNotificationGrouping.groups(from: [event(1), missing, event(2, post: 51)])
        XCTAssertEqual(groups.map(\.id), ["post:51", "post:50", "post:99"])
    }

    func testOnlyDisplayedSupportedUnreadEventsAreQueued() {
        let rows = [
            event(1), event(2, scoped: false), event(3, read: true), event(4),
        ]
        var reads = SocialNotificationReadState()
        reads.enqueue([1, 2, 3, 999], in: rows)
        XCTAssertEqual(reads.takeBatch(), [1])
        reads.complete([1])
        let updated = reads.applyingConfirmedReads(to: rows)
        XCTAssertTrue(updated[0].isRead)
        XCTAssertFalse(updated[1].isRead, "Legacy backend rows never trigger a mark-all write")
        XCTAssertFalse(updated[3].isRead, "An undisplayed event remains unread")
        reads.enqueue([1], in: rows)
        XCTAssertTrue(reads.pending.isEmpty, "A stale response cannot queue a confirmed ID again")
    }

    func testReadBatchesAreBoundedAndFailedBatchesCanRetryWithoutLosingNewEvents() {
        let rows = (1...510).map { event($0) }
        var reads = SocialNotificationReadState()
        reads.enqueue(Array(1...505), in: rows)
        let first = reads.takeBatch()
        XCTAssertEqual(first.count, 500)
        reads.enqueue([510], in: rows)
        reads.retry(first)
        XCTAssertEqual(reads.pending.count, 506)
        reads.complete(first)
        XCTAssertEqual(reads.takeBatch(), [501, 502, 503, 504, 505, 510])
    }

    func testRefreshRetainsOnlyCurrentAccountRowsAndResetForgetsConfirmations() {
        var reads = SocialNotificationReadState()
        reads.complete([1, 2])
        reads.enqueue([3], in: [event(3)])
        reads.retain([2, 3])
        XCTAssertEqual(reads.confirmed, [2])
        reads = SocialNotificationReadState()
        XCTAssertFalse(reads.applyingConfirmedReads(to: [event(2)])[0].isRead)
        XCTAssertTrue(reads.pending.isEmpty)
    }

    func testOldServerNotificationDecodesWithoutPreviewOrScopedReadCapability() throws {
        let json = #"{"id":1,"kind":"like","actor_id":10,"actor_username":"mateo","actor_first_name":"Mateo","actor_last_name":"","actor_photo_url":"https://example.test/avatar.jpg","post":50,"comment_body":null,"is_read":false,"message":null,"created_at":"2026-10-29T12:30:00Z"}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Components.Schemas.Notification.self, from: Data(json.utf8))
        let row = NotificationPayloadMapping.notification(from: payload)
        XCTAssertEqual(row.actorPhotoURL, "https://example.test/avatar.jpg")
        XCTAssertNotNil(row.createdAt)
        XCTAssertNil(row.postPreview)
        XCTAssertFalse(row.supportsScopedRead)
    }

    func testTestingServerMapsAuthorizedPreviewAndScopedReadCapability() throws {
        let json = #"{"id":1,"kind":"like","actor_id":10,"actor_username":"mateo","actor_first_name":"Mateo","actor_last_name":"","actor_photo_url":null,"post":50,"comment_body":null,"is_read":false,"message":null,"created_at":"2026-10-29T12:30:00Z","supports_scoped_read":true,"post_preview":{"id":50,"kind":"meal","title":"Lunch","thumbnail_url":"https://example.test/signed-photo.jpg","media_kind":"photo"}}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Components.Schemas.Notification.self, from: Data(json.utf8))
        let row = NotificationPayloadMapping.notification(from: payload)
        XCTAssertTrue(row.supportsScopedRead)
        XCTAssertEqual(row.postPreview?.id, 50)
        XCTAssertEqual(row.postPreview?.title, "Lunch")
        XCTAssertEqual(row.postPreview?.thumbnailURL, "https://example.test/signed-photo.jpg")
        XCTAssertEqual(row.postPreview?.mediaKind, "photo")
    }

    func testGeneratedReadBodyEncodesExactIDsRatherThanMarkAll() throws {
        let data = try JSONEncoder().encode(Components.Schemas.NotificationReadRequest(ids: [2, 3]))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(body["ids"] as? [Int], [2, 3])
        XCTAssertEqual(body.keys.sorted(), ["ids"])
    }
}
