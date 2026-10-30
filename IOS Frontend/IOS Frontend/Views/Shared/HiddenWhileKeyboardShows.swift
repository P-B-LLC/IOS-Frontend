//
//  HiddenWhileKeyboardShows.swift
//  IOS Frontend
//
//  A bottom bar that steps aside for the keyboard.
//

import Combine
import SwiftUI
import UIKit

/// Shows its content except while the software keyboard is up.
///
/// For a bar inset at the bottom of a scrolling page. An inset rides up with
/// the keyboard and parks on top of it, which on a search field means it
/// covers the very results being typed for. Hidden, the page gets the room
/// back; dismissing the keyboard brings the bar back where it was.
struct HiddenWhileKeyboardShows<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var keyboardShown = false

    var body: some View {
        VStack(spacing: 0) {
            if !keyboardShown { content() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardShown = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardShown = false
        }
    }
}
