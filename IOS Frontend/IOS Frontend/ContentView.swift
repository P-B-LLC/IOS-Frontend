//
//  ContentView.swift
//  IOS Frontend
//
//  Created by user299988 on 8/9/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hand.wave.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Hello from VSCode + Claude! 🎉")
                .font(.title2)
                .bold()
            Text("Edited on Windows, running on Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Round-trip test · 2026-08-09")
                .font(.caption)
                .foregroundStyle(.green)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
