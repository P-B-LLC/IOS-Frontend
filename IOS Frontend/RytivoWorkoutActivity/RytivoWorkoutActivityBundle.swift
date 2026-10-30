//
//  RytivoWorkoutActivityBundle.swift
//  RytivoWorkoutActivity
//
//  The widget extension's entry point. It holds the Live Activity alone.
//

import SwiftUI
import WidgetKit

@main
struct RytivoWorkoutActivityBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivityWidget()
    }
}
