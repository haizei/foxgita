//
//  ContentView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct ContentView: View {
    var body: some View {
        MainTabView()
    }
}

#Preview {
    ContentView()
        .environment(AppRouter())
        .modelContainer(
            for: [TaskItem.self, PracticeSession.self, RecordingRef.self, LocalProfile.self, MemoryItem.self],
            inMemory: true
        )
}
