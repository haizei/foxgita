//
//  ContentView.swift
//  foxgita
//

import SwiftData
import SwiftUI

struct ContentView: View {
    @State private var programs = PracticePrograms()

    var body: some View {
        MainTabView()
            .environment(programs)
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
