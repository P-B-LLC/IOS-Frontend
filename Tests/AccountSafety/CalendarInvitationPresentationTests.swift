import Foundation
import XCTest
@testable import AccountSafety

final class CalendarInvitationPresentationTests: XCTestCase {
    func testOnePendingInvitationHasAnExactBadgeCount() {
        let value = CalendarInvitationPresentation(pendingCount: 1, isLoading: false, hasError: false, isSupported: true)
        XCTAssertEqual(value, .pending(1))
        XCTAssertEqual(value.pendingCount, 1)
    }

    func testManyAndLargePendingCountsArePreservedWithoutTruncationOrOverflow() {
        for count in [2, 17, 100, Int.max] {
            let value = CalendarInvitationPresentation(pendingCount: count, isLoading: false, hasError: false, isSupported: true)
            XCTAssertEqual(value, .pending(count))
            XCTAssertEqual(value.pendingCount, count)
        }
    }

    func testZeroWhileLoadingIsNotAnEmptyInbox() {
        let value = CalendarInvitationPresentation(pendingCount: 0, isLoading: true, hasError: false, isSupported: true)
        XCTAssertEqual(value, .loading)
        XCTAssertNil(value.pendingCount)
    }

    func testUnsupportedOrFailedLoadingNeverClaimsThereAreNoInvitations() {
        for state in [(supported: false, error: false), (supported: true, error: true), (supported: false, error: true)] {
            let value = CalendarInvitationPresentation(
                pendingCount: 0, isLoading: false, hasError: state.error, isSupported: state.supported
            )
            XCTAssertEqual(value, .unavailable)
            XCTAssertNotEqual(value, .empty)
            XCTAssertNil(value.pendingCount)
        }
    }

    func testKnownSupportedZeroIsTheOnlyEmptyState() {
        let value = CalendarInvitationPresentation(pendingCount: 0, isLoading: false, hasError: false, isSupported: true)
        XCTAssertEqual(value, .empty)
        XCTAssertNil(value.pendingCount)
    }

    func testNegativeCountsBehaveLikeZeroAndNeverBecomeABadge() {
        for count in [-1, -50, Int.min] {
            for loading in [false, true] {
                for error in [false, true] {
                    for supported in [false, true] {
                        let negative = CalendarInvitationPresentation(
                            pendingCount: count, isLoading: loading, hasError: error, isSupported: supported
                        )
                        let zero = CalendarInvitationPresentation(
                            pendingCount: 0, isLoading: loading, hasError: error, isSupported: supported
                        )
                        XCTAssertEqual(negative, zero)
                        XCTAssertNil(negative.pendingCount)
                    }
                }
            }
        }
    }

    func testKnownPendingInvitationsWinOverRefreshErrorsOrUnavailableStatus() {
        for count in [1, 24, Int.max] {
            for loading in [false, true] {
                for error in [false, true] {
                    for supported in [false, true] {
                        let value = CalendarInvitationPresentation(
                            pendingCount: count, isLoading: loading, hasError: error, isSupported: supported
                        )
                        XCTAssertEqual(value, .pending(count))
                        XCTAssertEqual(value.pendingCount, count)
                    }
                }
            }
        }
    }

    func testRefreshWinsOverUnavailableWhenThereIsNoKnownPendingCount() {
        for supported in [false, true] {
            for error in [false, true] {
                let value = CalendarInvitationPresentation(
                    pendingCount: 0, isLoading: true, hasError: error, isSupported: supported
                )
                XCTAssertEqual(value, .loading)
                XCTAssertNil(value.pendingCount)
            }
        }
    }

    // The real SwiftUI composition stays out of the Foundation test target.
    // These boundary assertions prevent the invitation entry point slipping
    // back into a horizontally scrolling owner-filter strip or a second sheet.
    private func source(_ relative: String) throws -> String {
        let repository = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: repository).appendingPathComponent(relative), encoding: .utf8)
    }

    private func block(named name: String, in source: String) throws -> String {
        let declaration = try XCTUnwrap(source.range(of: name), "Missing source boundary: \(name)")
        let start = try XCTUnwrap(source[declaration.upperBound...].firstIndex(of: "{"))
        var depth = 0
        for index in source[start...].indices {
            if source[index] == "{" { depth += 1 }
            if source[index] == "}" {
                depth -= 1
                if depth == 0 { return String(source[start...index]) }
            }
        }
        XCTFail("Unclosed source boundary: \(name)")
        return ""
    }

    func testInvitationButtonStaysAboveAndOutsideHorizontallyScrollingFilters() throws {
        let workspace = try source("IOS Frontend/IOS Frontend/Views/Planner/CalendarWorkspaceView.swift")
        let controls = try block(named: "private var visibilityControls", in: workspace)
        let invitation = try XCTUnwrap(controls.range(of: "invitationButton"))
        let horizontal = try XCTUnwrap(controls.range(of: "ScrollView(.horizontal"))
        XCTAssertLessThan(invitation.lowerBound, horizontal.lowerBound)
        let filterContents = try block(named: "ScrollView(.horizontal", in: controls)
        XCTAssertFalse(filterContents.contains("invitationButton"))
        XCTAssertFalse(filterContents.contains("showingInvitations = true"))
    }

    func testDedicatedInvitationButtonUsesTheSingleWorkspaceSheetPath() throws {
        let workspace = try source("IOS Frontend/IOS Frontend/Views/Planner/CalendarWorkspaceView.swift")
        XCTAssertEqual(workspace.components(separatedBy: ".sheet(isPresented: $showingInvitations)").count - 1, 1)
        XCTAssertEqual(workspace.components(separatedBy: "CalendarInvitationsView()").count - 1, 1)
        XCTAssertTrue(workspace.contains("pendingCount: sharing.pendingInvitations.count"))
        XCTAssertTrue(workspace.contains("if sharing.pendingInvitations.isEmpty { inboxStatus }"))
        let button = try source("IOS Frontend/IOS Frontend/Views/Planner/CalendarInvitationButton.swift")
        XCTAssertTrue(button.contains("struct CalendarInvitationButton"))
        XCTAssertTrue(button.contains("CalendarInvitationPresentation"))
        XCTAssertTrue(button.contains("Button(action: action)"))
        XCTAssertFalse(button.contains(".sheet("), "Presentation belongs to the workspace, not a second button-owned route")
        XCTAssertFalse(button.contains("CalendarInvitationsView("))
        XCTAssertTrue(button.contains(".accessibilityValue(accessibilityStatus)"))
        XCTAssertTrue(button.contains("Text(\"\\(count) incoming invitations\")"))
    }
}
