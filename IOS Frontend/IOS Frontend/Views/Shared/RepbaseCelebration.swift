//
//  RepbaseCelebration.swift
//  IOS Frontend
//
//  A brief app-wide celebration for meaningful completed actions.
//

import Foundation
import SwiftUI

enum RepbaseCelebrationKind: String {
    case mealLogged
    case workoutLogged
    case dayCleared

    var colors: [Color] {
        switch self {
        case .mealLogged:
            return [
                RepbasePalette.caramel,
                Color(hex: 0x29B8BA),
                Color(hex: 0xB847AD),
                Color(hex: 0xF0D6C4)
            ]
        case .workoutLogged:
            return [
                RepbasePalette.caramel,
                RepbasePalette.sage,
                Color(hex: 0xF3C66F),
                Color(hex: 0xD6E8DE)
            ]
        case .dayCleared:
            return [
                RepbasePalette.sage,
                Color(hex: 0xFF4F1F),
                Color(hex: 0x29B8BA),
                Color(hex: 0xF3C66F)
            ]
        }
    }
}

extension Notification.Name {
    static let repbaseCelebration = Notification.Name("repbase.celebration")
}

@MainActor
enum RepbaseCelebrations {
    static func show(_ kind: RepbaseCelebrationKind) {
        NotificationCenter.default.post(
            name: .repbaseCelebration,
            object: kind.rawValue
        )
    }
}

extension View {
    func repbaseCelebrationOverlay() -> some View {
        modifier(RepbaseCelebrationOverlayModifier())
    }
}

private struct ActiveCelebration: Identifiable {
    let id = UUID()
    let kind: RepbaseCelebrationKind
}

private struct RepbaseCelebrationOverlayModifier: ViewModifier {
    @State private var celebration: ActiveCelebration?
    @State private var removalTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let celebration {
                    RepbaseConfettiBurst(kind: celebration.kind)
                        .id(celebration.id)
                        .transition(.opacity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .repbaseCelebration)) { note in
                guard let rawValue = note.object as? String,
                      let kind = RepbaseCelebrationKind(rawValue: rawValue) else {
                    return
                }

                removalTask?.cancel()
                celebration = ActiveCelebration(kind: kind)
                removalTask = Task {
                    try? await Task.sleep(for: .seconds(1.7))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.18)) {
                            celebration = nil
                        }
                    }
                }
            }
            .onDisappear {
                removalTask?.cancel()
            }
    }
}

private struct ConfettiPiece: Identifiable {
    let id: Int
    let horizontalTravel: CGFloat
    let upwardTravel: CGFloat
    let fallDistance: CGFloat
    let width: CGFloat
    let height: CGFloat
    let rotation: Double
    let delay: Double
    let colorIndex: Int
    let isRound: Bool

    static let all: [ConfettiPiece] = (0..<38).map { index in
        // Deliberately deterministic: rebuilding the overlay must not make
        // pieces jump to new paths halfway through their animation.
        let spread = CGFloat((index * 47) % 101) / 100
        let lift = CGFloat((index * 31) % 59) / 58
        let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1

        return ConfettiPiece(
            id: index,
            horizontalTravel: side * (42 + spread * 154),
            upwardTravel: 52 + lift * 116,
            fallDistance: 176 + spread * 220,
            width: CGFloat(5 + (index * 3) % 6),
            height: CGFloat(9 + (index * 5) % 9),
            rotation: Double(150 + (index * 73) % 570) * Double(side),
            delay: Double(index % 7) * 0.018,
            colorIndex: index % 4,
            isRound: index.isMultiple(of: 5)
        )
    }
}

private struct RepbaseConfettiBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let kind: RepbaseCelebrationKind
    @State private var burst = false
    @State private var falling = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(ConfettiPiece.all) { piece in
                    confetti(piece, in: geometry.size)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else {
                withAnimation(.easeOut(duration: 0.55)) { falling = true }
                return
            }

            burst = true
            Task {
                try? await Task.sleep(for: .milliseconds(430))
                guard !Task.isCancelled else { return }
                falling = true
            }
        }
    }

    private func confetti(_ piece: ConfettiPiece, in size: CGSize) -> some View {
        let color = kind.colors[piece.colorIndex]
        let originY = max(150, size.height * 0.35)

        return Group {
            if piece.isRound {
                Circle().fill(color)
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color)
            }
        }
        .frame(width: piece.width, height: piece.isRound ? piece.width : piece.height)
        .rotationEffect(.degrees(burst ? piece.rotation : 0))
        .position(x: size.width / 2, y: originY)
        .offset(
            x: reduceMotion ? piece.horizontalTravel * 0.28 : (burst ? piece.horizontalTravel : 0),
            y: reduceMotion
                ? piece.upwardTravel * -0.18
                : (burst ? -piece.upwardTravel : 0) + (falling ? piece.fallDistance : 0)
        )
        .scaleEffect(falling ? 0.72 : 1)
        .opacity(falling ? 0 : 1)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.55).delay(piece.delay)
                : .easeOut(duration: 0.42).delay(piece.delay),
            value: burst
        )
        .animation(
            .easeIn(duration: reduceMotion ? 0.55 : 0.82).delay(piece.delay),
            value: falling
        )
    }
}
