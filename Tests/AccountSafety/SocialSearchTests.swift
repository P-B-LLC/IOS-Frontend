import Foundation
import XCTest
@testable import AccountSafety

final class SocialSearchTests: XCTestCase {
    func testWhitespaceOnlyIsNotASearch() {
        XCTAssertEqual(SocialSearchPolicy.normalizedQuery(" \n\t "), "")
        XCTAssertEqual(SocialSearchPolicy.normalizedQuery(""), "")
    }

    func testNormalizationPreservesCasePrefixesAndInteriorSpaces() {
        XCTAssertEqual(SocialSearchPolicy.normalizedQuery(" \n#LegDay\t "), "#LegDay")
        XCTAssertEqual(SocialSearchPolicy.normalizedQuery("  @Aaron.Pio "), "@Aaron.Pio")
        XCTAssertEqual(SocialSearchPolicy.normalizedQuery("  Aaron  Pio  "), "Aaron  Pio")
    }

    func testEnteringHashtagSelectsPosts() {
        XCTAssertEqual(scope("#", after: "", current: .people), .posts)
        XCTAssertEqual(scope("  #legday", after: "legs", current: .people), .posts)
    }

    func testEnteringHandleSelectsPeople() {
        XCTAssertEqual(scope("@", after: "", current: .posts), .people)
        XCTAssertEqual(scope(" @Aaron", after: "Aaron", current: .posts), .people)
    }

    func testChangingBetweenPrefixesSelectsTheirMatchingScope() {
        XCTAssertEqual(scope("@legday", after: "#legday", current: .posts), .people)
        XCTAssertEqual(scope("#legday", after: "@legday", current: .people), .posts)
    }

    func testManualScopeSurvivesTypingWithinTheSamePrefix() {
        XCTAssertEqual(scope("#legday", after: "#leg", current: .people), .people)
        XCTAssertEqual(scope("@Aaron", after: "@Aa", current: .posts), .posts)
        XCTAssertEqual(scope(" #legday ", after: "#legday", current: .people), .people)
    }

    func testOrdinaryTypingAndRemovingPrefixPreserveChosenScope() {
        XCTAssertEqual(scope("Leg day", after: "Leg", current: .posts), .posts)
        XCTAssertEqual(scope("Aaron", after: "Aar", current: .people), .people)
        XCTAssertEqual(scope("legday", after: "#legday", current: .posts), .posts)
        XCTAssertEqual(scope("workout #legday", after: "workout", current: .people), .people)
    }

    func testClearingSearchResetsTheNextSearchToPeople() {
        XCTAssertEqual(scope("", after: "#legday", current: .posts), .people)
        XCTAssertEqual(scope(" \n ", after: "legs", current: .posts), .people)
    }

    func testScopesUseStableUniqueIdentifiersAndHonestLabels() {
        XCTAssertEqual(SocialSearchScope.allCases.map(\.rawValue), ["People", "Posts"])
        XCTAssertEqual(Set(SocialSearchScope.allCases.map(\.id)).count, 2)
    }

    // These wiring guards protect the modal boundary in the SwiftUI source.
    // They supplement the policy tests; simulator tests still need to verify
    // actual taps, focus, scroll restoration and accessibility layout.
    func testSearchIsPresentedWithoutReplacingAnyFeed() throws {
        let source = try appSource("Views/Social/SocialFeedView.swift")
        let posts = try section(source, from: "private var displayedPosts:", to: "private func composeButton")
        XCTAssertTrue(posts.contains("return store.forYou"))
        XCTAssertTrue(posts.contains("return store.feed"))
        XCTAssertTrue(posts.contains("return store.discoverPosts"))
        XCTAssertFalse(posts.contains("searchedPosts"))

        let action = try section(source, from: "private func searchButton", to: "private func postButton")
        XCTAssertTrue(action.contains("isSearching = true"))
        XCTAssertFalse(action.contains("feedMode ="), "Opening search must not force Discover")
    }

    func testPersistentHeaderAndModalCleanupStayWired() throws {
        let source = try appSource("Views/Social/SocialFeedView.swift")
        let inset = try section(source, from: ".safeAreaInset(edge: .top", to: ".scrollIndicators")
        XCTAssertTrue(inset.contains("socialHeader(timeOfDay:"))
        XCTAssertTrue(inset.contains("modePicker(timeOfDay:"))

        let presentation = try section(source, from: ".fullScreenCover(isPresented: $isSearching", to: ".sheet(item: $commenting)")
        XCTAssertTrue(presentation.contains("onDismiss:"))
        XCTAssertTrue(presentation.contains("store.clearSearch()"))
        XCTAssertTrue(presentation.contains("SocialSearchView(initialQuery:"))
    }

    func testCollapsedSearchIsIconOnlyButStillAccessible() throws {
        let source = try appSource("Views/Social/SocialFeedView.swift")
        let button = try section(source, from: "private func searchButton", to: "private func postButton")
        XCTAssertTrue(button.contains("Image(systemName: \"magnifyingglass\")"))
        XCTAssertFalse(button.contains("Label("))
        XCTAssertFalse(button.contains("Text("))
        XCTAssertTrue(button.contains(".frame(width: 72, height: 44)"))
        XCTAssertTrue(button.contains(".modifier(SocialSearchGlass())"))
        XCTAssertTrue(button.contains(".accessibilityLabel(\"Search people or hashtags\")"))
        XCTAssertTrue(button.contains(".accessibilityIdentifier(\"social.search\")"))
    }

    func testCompactControlExpandsIntoSearchAndRespectsReducedMotion() throws {
        let source = try appSource("Views/Social/SocialFeedView.swift")
        XCTAssertTrue(source.contains("@Environment(\\.accessibilityReduceMotion)"))
        XCTAssertTrue(source.contains(".matchedTransitionSource(id: \"social.search\", in: searchTransition)"))
        let presentation = try section(source, from: ".fullScreenCover(isPresented: $isSearching", to: ".sheet(item: $commenting)")
        XCTAssertTrue(presentation.contains("if reduceMotion {"))
        XCTAssertTrue(presentation.contains(".navigationTransition(.zoom(sourceID: \"social.search\", in: searchTransition))"))
        let reduced = try section(presentation, from: "if reduceMotion {", to: "} else {")
        XCTAssertFalse(reduced.contains(".zoom("))
        let header = try section(source, from: "private func socialHeader", to: "private func searchButton")
        XCTAssertEqual(header.components(separatedBy: "searchButton(timeOfDay:").count - 1, 1,
                       "Only one mounted search source may own the matched transition")
    }

    func testExpandedGlassFieldFocusesOnceAndKeepsAccessibilityFallbacks() throws {
        let source = try appSource("Views/Social/SocialSearchView.swift")
        let glass = try section(source, from: "struct SocialSearchGlass:", to: "struct SocialSearchView:")
        XCTAssertTrue(glass.contains("@Environment(\\.accessibilityReduceTransparency)"))
        XCTAssertTrue(glass.contains("contrast == .increased"))
        XCTAssertTrue(glass.contains("Color(.secondarySystemBackground)"))
        XCTAssertTrue(glass.contains(".glassEffect(.regular.interactive(), in: Capsule())"))
        let field = try section(source, from: "private var queryField:", to: "private var scopePicker:")
        XCTAssertTrue(field.contains(".modifier(SocialSearchGlass())"))
        XCTAssertTrue(field.contains(".focused($isQueryFocused)"))
        XCTAssertTrue(source.contains("guard !didFocusOnPresentation else { return }"))
        XCTAssertTrue(source.contains("isQueryFocused = query.isEmpty"))
        XCTAssertTrue(field.contains(".onSubmit { isQueryFocused = false }"),
                      "Dismissing the keyboard must not dismiss search")
    }

    func testSearchUsesRealResultsAndExistingNavigation() throws {
        let source = try appSource("Views/Social/SocialSearchView.swift")
        XCTAssertTrue(source.contains("await store.search(normalizedQuery)"))
        XCTAssertTrue(source.contains("ForEach(store.searchedPeople, id: \\.id)"))
        XCTAssertTrue(source.contains("ForEach(store.searchedPosts)"))
        XCTAssertFalse(source.contains("searchedPeople.prefix("), "Do not silently hide returned people")
        XCTAssertTrue(source.contains("PostCard(post: post"))
        XCTAssertTrue(source.contains("PostDetailView(postID: id)"))
        XCTAssertTrue(source.contains("PersonProfileView(userID: person.id)"))
        XCTAssertTrue(source.contains("PostCommentsSheet(postID: target.id"))
        XCTAssertTrue(source.contains("store.searchErrorMessage"))
    }

    func testSearchResponsesAreFencedByRequestAndAccountNotOnlyQueryText() throws {
        let source = try appSource("Stores/SocialStore.swift")
        let search = try section(source, from: "func search(_ query:", to: "func clearSearch()")
        XCTAssertTrue(search.contains("let requestID = UUID()"))
        XCTAssertTrue(search.contains("searchRequestID = requestID"))
        XCTAssertTrue(search.contains("let generation = connectionGeneration"))
        let success = try section(search, from: "let found = try await", to: "} catch {")
        XCTAssertTrue(success.contains("connectionGeneration == generation"))
        XCTAssertTrue(success.contains("searchRequestID == requestID"))
        XCTAssertTrue(success.contains("!Task.isCancelled"))
        XCTAssertTrue(success.contains("searchedPeople ="))
        XCTAssertTrue(success.contains("searchedPosts ="))
        XCTAssertFalse(search.contains("searchQuery == trimmed"), "A repeated A→B→A query needs a new request identity")
    }

    func testClearingAndDisconnectingInvalidateSearchAndItsErrors() throws {
        let source = try appSource("Stores/SocialStore.swift")
        let clear = try section(source, from: "func clearSearch()", to: "// MARK: - One person's posts")
        for expected in ["searchRequestID = UUID()", "searchQuery = \"\"", "searchedPeople = []",
                         "searchedPosts = []", "isSearching = false", "searchErrorMessage = nil"] {
            XCTAssertTrue(clear.contains(expected), "Missing search reset: \(expected)")
        }
        let disconnect = try section(source, from: "func disconnect()", to: "// MARK: - Reading")
        XCTAssertTrue(disconnect.contains("connectionGeneration = UUID()"))
        XCTAssertTrue(disconnect.contains("clearSearch()"))
    }

    func testSearchFiltersBlockedResultsAndKeepsFailuresInsideSearch() throws {
        let source = try appSource("Stores/SocialStore.swift")
        let search = try section(source, from: "func search(_ query:", to: "func clearSearch()")
        XCTAssertTrue(search.contains("searchedPeople = found.0.filter { !locallyBlockedAuthorIDs.contains($0.id) }"))
        XCTAssertTrue(search.contains("searchedPosts = reconcileAuthorVisiblePage(found.1"))
        XCTAssertTrue(search.contains("searchErrorMessage = error.userFacingMessage"))
        XCTAssertTrue(search.contains("!error.isCancellation"))
        XCTAssertFalse(search.contains("showFailure("), "A search error must not become the underlying feed's error")
        let visibility = try section(source, from: "private func canAppearInAuthorVisibleSurface", to: "private func ownRecommendation")
        XCTAssertTrue(visibility.contains("locallyBlockedAuthorIDs.contains(post.author.id)"))
        XCTAssertTrue(visibility.contains("locallyBlockedAuthorIDs.contains(post.displayed.author.id)"))
        XCTAssertTrue(visibility.contains("post.viewerIsAuthor"), "Own private submissions retain author-only access")
    }

    private func scope(
        _ query: String,
        after previous: String,
        current: SocialSearchScope
    ) -> SocialSearchScope {
        SocialSearchPolicy.preferredScope(for: query, previousQuery: previous, currentScope: current)
    }

    private func appSource(_ path: String) throws -> String {
        let root = try XCTUnwrap(ProcessInfo.processInfo.environment["RYTIVO_TEST_REPOSITORY"])
        return try String(contentsOf: URL(fileURLWithPath: root)
            .appendingPathComponent("IOS Frontend/IOS Frontend/\(path)"), encoding: .utf8)
            .replacingOccurrences(of: "\r\n", with: "\n")
    }

    private func section(_ source: String, from start: String, to end: String) throws -> String {
        let beginning = try XCTUnwrap(source.range(of: start))
        let ending = try XCTUnwrap(source.range(of: end, range: beginning.upperBound..<source.endIndex))
        return String(source[beginning.lowerBound..<ending.lowerBound])
    }
}
