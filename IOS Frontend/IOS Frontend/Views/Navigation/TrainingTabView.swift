//
//  TrainingTabView.swift
//  IOS Frontend
//
//  Workouts and food on one tab: what you did, and what you ate.
//

import SwiftUI

/// The two halves of a training day, behind one switch.
///
/// They were a tab each, which spent two of five slots on things a person
/// moves between constantly anyway — and left no room for the feed. The switch
/// sits at the top of this tab rather than being a second bar at the bottom, so
/// there is still only one control in the app that changes area.
struct TrainingTabView: View {
    nonisolated enum Half: String, CaseIterable, Identifiable {
        case workouts
        case food

        var id: String { rawValue }

        var title: String {
            switch self {
            case .workouts: "Workouts"
            case .food: "Food"
            }
        }

        var symbol: String {
            switch self {
            case .workouts: "dumbbell.fill"
            case .food: "fork.knife"
            }
        }
    }

    @State private var half: Half = .workouts

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let timeOfDay = HomeTimeOfDay(date: context.date)

            VStack(spacing: 0) {
                switcher(timeOfDay: timeOfDay)

                switch half {
                case .workouts: WorkoutsView()
                case .food: FoodTrackingView()
                }
            }
            .homeTimeScreen(timeOfDay)
        }
    }

    private func switcher(timeOfDay: HomeTimeOfDay) -> some View {
        HStack(spacing: 3) {
            ForEach(Half.allCases) { item in
                Button {
                    half = item
                } label: {
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(item == half ? RepbasePalette.cream : timeOfDay.canvasSecondaryText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if item == half {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(RepbaseDesign.ink)
                                    .shadow(color: Color.black.opacity(0.16), radius: 6, x: 0, y: 3)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(item == half ? [.isSelected] : [])
            }
        }
        .padding(4)
        .repbaseInsetSurface(cornerRadius: 13)
        .padding(.horizontal, RepbaseDesign.pageInset)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .animation(.easeOut(duration: 0.18), value: half)
    }
}
