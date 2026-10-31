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
                .tabItem { Label { Text("练习") } icon: { Image("HomeTabPractice").renderingMode(.template) } }
                .tag(MainTab.practice)
            RecordView()
                .tabItem { Label { Text("记录") } icon: { Image("HomeTabRecord").renderingMode(.template) } }
                .tag(MainTab.record)
            ToolsView()
                .tabItem { Label { Text("工具") } icon: { Image("HomeTabTools").renderingMode(.template) } }
                .tag(MainTab.tools)
            SettingsView()
                .tabItem { Label { Text("设置") } icon: { Image("HomeTabSettings").renderingMode(.template) } }
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
