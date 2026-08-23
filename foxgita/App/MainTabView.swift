//
//  MainTabView.swift
//  foxgita
//

import SwiftUI

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            PracticeView()
                .tabItem { Label("练习", systemImage: "music.note.list") }
                .tag(MainTab.practice)
            RecordView()
                .tabItem { Label("记录", systemImage: "list.bullet.rectangle") }
                .tag(MainTab.record)
            HistoryView()
                .tabItem { Label("历史", systemImage: "calendar") }
                .tag(MainTab.history)
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .tint(GitaTheme.brand500)
        .onChange(of: router.selectedTab) { old, new in
            if old == .practice, new != .practice {
                router.clearJustCompleted()
            }
        }
    }
}
