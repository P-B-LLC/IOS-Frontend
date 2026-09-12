//
//  AccessibleLayout.swift
//  IOS Frontend
//
//  Two tools for the accessibility text sizes, because the app broke at them
//  in two different ways and they do not have the same remedy.
//
//  The app already scales: `Font.community` is built with `relativeTo:`, so
//  every label grows with the reader's setting. What it did not have was any
//  layout that survived the growing. At the largest accessibility size the
//  saved meals list rendered "Chicke / n rice / bowl" -- a name broken across
//  three lines mid-word -- and the planner's month grid gave up entirely:
//  weekday headings came apart into stacked single letters, and the dates
//  themselves collapsed into ellipses, so the calendar stopped saying which
//  day anything was on.
//
//  Those are different failures. A row has somewhere to put its contents if
//  it stops insisting on one line. A seven-column grid does not: it has seven
//  columns at every text size, so a date needing more than a seventh of the
//  screen has nowhere to go at all.
//

import SwiftUI

/// A row that becomes a column once the text is large enough to need it.
///
/// The spacer belongs to this type rather than to the caller, which is the
/// whole reason it takes two builders instead of one. A `Spacer` written into
/// a row's content pushes horizontally as intended and then pushes
/// *vertically* the moment that row becomes a column, which turns a cramped
/// row into a torn-apart one -- worse than what it replaced.
struct AdaptiveRow<Leading: View, Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    var spacing: CGFloat = 12
    /// The part that carries the text, and the part that needs the room.
    @ViewBuilder var leading: () -> Leading
    /// Values and controls. Kept side by side in both arrangements: these are
    /// small and fixed, and stacking them too would waste the height just won.
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) {
                leading()
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: spacing) { trailing() }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: spacing) {
                leading()
                Spacer(minLength: 8)
                trailing()
            }
        }
    }
}

extension View {
    /// Stops the text inside this subtree growing past `ceiling`.
    ///
    /// A last resort, for the few places whose layout cannot reflow at any
    /// size. A month grid is seven columns wide because a week is seven days;
    /// that is not a layout choice to be relaxed under pressure, and no amount
    /// of stacking makes a date fit into a seventh of the screen at
    /// `accessibility-extra-extra-extra-large`.
    ///
    /// It is only defensible where the capped thing is a compact *index* into
    /// something that does scale. Picking a day in the grid opens that day's
    /// own screen, which is text in a column and grows the whole way. Capping
    /// a screen that is the destination rather than the index would just be
    /// refusing to support the setting, so don't.
    func typeSizeCeiling(_ ceiling: DynamicTypeSize = .xxxLarge) -> some View {
        dynamicTypeSize(...ceiling)
    }
}
