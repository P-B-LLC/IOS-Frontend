import Foundation
import XCTest
@testable import AccountSafety

final class SocialPublicationTests: XCTestCase {
    private struct Post: Identifiable, Sendable, Equatable {
        let id: Int
        var label: String = "post"
        var recommendation: String? = nil
        var likes: Int = 0
    }
    private let expiry = Date(timeIntervalSince1970: 10_000)
    private let now = Date(timeIntervalSince1970: 1_000)

    private func submitted(_ id: Int, to state: inout SocialPublicationCoordinator<Post>, eligible: Bool = true) -> Bool {
        state.trackSubmission(id: id, awaitingAttachment: false)
        return state.observe(Post(id: id), isOwn: true, eligible: eligible, expiresAt: expiry).announcePublication
    }

    func testOnlyServerPublishedNonPrivateAndScreenedMediaAreShared() {
        func eligible(_ approved: Bool = true, date: Date? = Date(), privatePost: Bool = false, video: String? = nil) -> Bool {
            SocialPublicationEligibility.shared(approved: approved, publishedAt: date, isPrivate: privatePost, videoStatus: video)
        }
        XCTAssertTrue(eligible())
        XCTAssertTrue(eligible(video: "approved"))
        XCTAssertFalse(eligible(false))
        XCTAssertFalse(eligible(date: nil))
        XCTAssertFalse(eligible(privatePost: true))
        for status in ["pending", "processing", "flagged", "rejected", "unknown"] {
            XCTAssertFalse(eligible(video: status))
        }
    }

    func testPublicationUpsertsOnceAndSurvivesAStaleFirstPage() {
        var state = SocialPublicationCoordinator<Post>()
        let oldRead = state.revision
        XCTAssertTrue(submitted(10, to: &state))
        XCTAssertFalse(state.observe(Post(id: 10), isOwn: true, eligible: true, expiresAt: expiry).announcePublication)
        state.acknowledgeFirstPage(readRevision: oldRead)
        XCTAssertEqual(state.publicPage([Post(id: 2)], prependOwn: true, now: now).map(\.id), [10, 2])
        XCTAssertEqual(state.publicPage([Post(id: 10), Post(id: 10), Post(id: 2)], prependOwn: true, now: now).map(\.id), [10, 2])
    }

    func testFreshFirstPageOwnsRankingButCannotEraseANewerPublication() {
        var state = SocialPublicationCoordinator<Post>()
        _ = submitted(10, to: &state)
        let freshRead = state.revision
        _ = submitted(11, to: &state)
        state.acknowledgeFirstPage(readRevision: freshRead)
        XCTAssertEqual(state.publicPage([Post(id: 2)], prependOwn: true, now: now).map(\.id), [11, 2])
        XCTAssertEqual(state.publicPage([Post(id: 10)], prependOwn: false, now: now).map(\.id), [10])
    }

    func testPendingAndPrivateStayAuthorOnlyUntilConfirmedApproval() {
        var state = SocialPublicationCoordinator<Post>()
        XCTAssertFalse(submitted(10, to: &state, eligible: false))
        XCTAssertTrue(state.publicPage([Post(id: 10)], prependOwn: true, now: now).isEmpty)
        XCTAssertEqual(state.authorPage([], matches: { _ in true }).map(\.id), [10])
        XCTAssertEqual(state.pendingSubmissions.map(\.id), [10])
        let pendingRead = state.revision
        XCTAssertTrue(state.observe(Post(id: 10, label: "approved"), isOwn: true, eligible: true,
                                    expiresAt: expiry, readRevision: pendingRead).announcePublication)
        XCTAssertEqual(state.publicPage([], prependOwn: true, now: now).first?.label, "approved")
    }

    func testAttachmentHoldNeverExposesTheInitiallyApprovedBasePost() {
        var state = SocialPublicationCoordinator<Post>()
        state.trackSubmission(id: 10, awaitingAttachment: true)
        XCTAssertFalse(state.observe(Post(id: 10), isOwn: true, eligible: true, expiresAt: expiry).announcePublication)
        XCTAssertTrue(state.publicPage([Post(id: 10)], prependOwn: true, now: now).isEmpty)
        XCTAssertTrue(state.pendingSubmissions.isEmpty, "Status polling must not finish an in-flight attachment")
        state.attachmentFinished(id: 10)
        XCTAssertFalse(state.observe(Post(id: 10), isOwn: true, eligible: false, expiresAt: expiry).announcePublication)
        XCTAssertTrue(state.observe(Post(id: 10), isOwn: true, eligible: true, expiresAt: expiry).announcePublication)
    }

    func testRevocationWinsOverConcurrentReadsAndEngagementMutation() {
        var state = SocialPublicationCoordinator<Post>()
        _ = submitted(10, to: &state)
        let safetyRead = state.revision
        state.mutate(where: { $0.id == 10 }) { $0.likes = 1 }
        let rejected = state.observe(Post(id: 10, label: "rejected"), isOwn: true, eligible: false,
                                     expiresAt: expiry, readRevision: safetyRead)
        XCTAssertTrue(rejected.accepted)
        XCTAssertTrue(state.publicPage([Post(id: 10)], prependOwn: true, now: now).isEmpty)
        XCTAssertFalse(state.observe(Post(id: 10), isOwn: true, eligible: true,
                                     expiresAt: expiry, readRevision: safetyRead).accepted)
        XCTAssertEqual(state.authorPage([], matches: { _ in true }).first?.label, "rejected")
    }

    func testConcurrentOrdinaryApprovedReadCannotDefeatRestrictiveStatus() {
        var state = SocialPublicationCoordinator<Post>()
        let read = state.revision
        state.observe(Post(id: 10), isOwn: false, eligible: true, expiresAt: expiry, readRevision: read)
        XCTAssertTrue(state.observe(Post(id: 10), isOwn: false, eligible: false,
                                    expiresAt: expiry, readRevision: read).accepted)
        XCTAssertTrue(state.publicPage([Post(id: 10)], prependOwn: false, now: now).isEmpty)
    }

    func testDeletionCannotBeResurrectedByAReadOrRepeatedPublicationResponse() {
        var state = SocialPublicationCoordinator<Post>()
        _ = submitted(10, to: &state)
        let read = state.revision
        state.remove(id: 10)
        XCTAssertFalse(state.observe(Post(id: 10), isOwn: true, eligible: true, expiresAt: expiry, readRevision: read).accepted)
        XCTAssertFalse(state.observe(Post(id: 10), isOwn: true, eligible: true, expiresAt: expiry).accepted)
        XCTAssertTrue(state.publicPage([Post(id: 10)], prependOwn: true, now: now).isEmpty)
        XCTAssertTrue(state.authorPage([Post(id: 10)], matches: { _ in true }).isEmpty)
    }

    func testOrdinaryFeedRowsKeepDestinationRecommendationMetadata() {
        var state = SocialPublicationCoordinator<Post>()
        let following = Post(id: 10)
        let forYou = Post(id: 10, recommendation: "following")
        state.observe(forYou, isOwn: false, eligible: true, expiresAt: expiry)
        XCTAssertNil(state.publicPage([following], prependOwn: false, now: now).first?.recommendation)
        state.observe(following, isOwn: false, eligible: true, expiresAt: expiry)
        XCTAssertEqual(state.publicPage([forYou], prependOwn: false, now: now).first?.recommendation, "following")
    }

    func testOwnOverlayPreservesEngagementAndExpiresAndIsBounded() {
        var state = SocialPublicationCoordinator<Post>()
        for id in 1...25 { _ = submitted(id, to: &state) }
        XCTAssertEqual(state.publicPage([], prependOwn: true, now: now).count, 20)
        state.mutate(where: { $0.id == 25 }) { $0.likes = 3 }
        XCTAssertEqual(state.publicPage([], prependOwn: true, now: now).first?.likes, 3)
        XCTAssertTrue(state.publicPage([], prependOwn: true, now: expiry).isEmpty)
    }

    func testAccountResetClearsPendingPublishedDeletedAndAnnouncementState() {
        var state = SocialPublicationCoordinator<Post>()
        _ = submitted(10, to: &state)
        _ = submitted(11, to: &state, eligible: false)
        state.remove(id: 12)
        state.reset()
        XCTAssertEqual(state.revision, 0)
        XCTAssertTrue(state.pendingSubmissions.isEmpty)
        XCTAssertTrue(state.publicPage([], prependOwn: true, now: now).isEmpty)
        XCTAssertFalse(state.isDeleted(12))
        XCTAssertTrue(submitted(10, to: &state))
    }

    func testStatusChecksSkipTerminalFailuresAndRotatePastTheNewestFive() {
        func needsCheck(_ moderation: String, video: String? = nil, processing: String? = nil) -> Bool {
            SocialPublicationEligibility.shouldRefresh(moderationStatus: moderation, publishedAt: nil,
                                                       isPrivate: false, videoStatus: video, videoProcessingState: processing)
        }
        XCTAssertTrue(needsCheck("pending"))
        XCTAssertTrue(needsCheck("flagged"))
        XCTAssertFalse(needsCheck("rejected"))
        XCTAssertFalse(needsCheck("pending", video: "rejected"))
        XCTAssertFalse(needsCheck("pending", processing: "failed"))
        var state = SocialPublicationCoordinator<Post>()
        for id in 1...6 { _ = submitted(id, to: &state, eligible: false) }
        let first = state.pendingSubmissions.prefix(5).map(\.id)
        XCTAssertEqual(first, [6, 5, 4, 3, 2])
        for id in first { state.markStatusChecked(id: id) }
        XCTAssertEqual(state.pendingSubmissions.first?.id, 1, "Older pending work must not starve behind five newer checks")
    }

    func testStoreUsesBoundedRefreshAndAccountScopedReceiptAndBatchedPages() throws {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        let url = URL(fileURLWithPath: root).appendingPathComponent("IOS Frontend/IOS Frontend/Stores/SocialStore.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("private(set) var publicationReceipt: SocialPublicationReceipt?"))
        XCTAssertTrue(source.contains("guard publicationReceipt?.id == id else { return }"))
        XCTAssertTrue(source.contains("publications.reset()"))
        XCTAssertTrue(source.contains("publications.acknowledgeFirstPage(readRevision: readRevision)"))
        XCTAssertTrue(source.contains("snapshot.recommendation = nil"))
        XCTAssertTrue(source.contains("for post in posts { observePublication(post, readRevision: readRevision) }"))
        XCTAssertFalse(source.contains("for post in posts { replace(post, readRevision: readRevision) }"))
        XCTAssertGreaterThanOrEqual(source.components(separatedBy: "await refreshPendingPublications(using: repository, generation: generation)").count - 1, 2)
        XCTAssertTrue(source.contains("}.prefix(5)"))
        XCTAssertTrue(source.contains("func refreshPublicationStatuses() async"))
        XCTAssertTrue(source.contains("guard !isRefreshingPublicationStatuses else { return }"))
        XCTAssertTrue(source.contains("publications.markStatusChecked(id: post.id)"))
        XCTAssertTrue(source.contains("SocialPublicationEligibility.shared(approved: post.isPublished"))
        XCTAssertTrue(source.contains("post.viewerIsAuthor || canAppearInSharedFeed(post)"))
        XCTAssertTrue(source.contains("removePost(id: post.id)"))
        XCTAssertTrue(source.contains("for index in searchedPosts.indices { update(&searchedPosts[index]) }"))
        XCTAssertTrue(source.contains("change(&searchedPosts[index])"))
        XCTAssertTrue(source.contains("searchedPosts[index] = post"))
        XCTAssertTrue(source.contains("searchedPosts[index].repostOf?.video = post.video"))
    }
}
