import SwiftUI

private enum GuitarTool: String, CaseIterable, Identifiable {
    case metronome, chords, tuner, alternateTuning, chromaticTuner, playAlong, playChords, chordMemory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .metronome: String(localized: "节拍器")
        case .chords: String(localized: "和弦库")
        case .tuner: String(localized: "调音器")
        case .alternateTuning: String(localized: "交替调音")
        case .chromaticTuner: String(localized: "半音调音器")
        case .playAlong: String(localized: "一起演奏")
        case .playChords: String(localized: "弹奏和弦")
        case .chordMemory: String(localized: "和弦记忆")
        }
    }

    var subtitle: String {
        switch self {
        case .metronome: String(localized: "稳住每一次拨弦")
        case .chords: String(localized: "随时查找和弦指法")
        case .tuner: String(localized: "调准六根弦，开始今天的练习")
        case .alternateTuning: String(localized: "探索更多调弦方式")
        case .chromaticTuner: String(localized: "准确识别每一个音")
        case .playAlong: String(localized: "跟随伴奏，找到感觉")
        case .playChords: String(localized: "听一听和弦的声音")
        case .chordMemory: String(localized: "把常用和弦练熟")
        }
    }

    var image: String {
        switch self {
        case .metronome: "ToolMetronome"
        case .chords: "ToolChords"
        case .tuner: "ToolTuner"
        case .alternateTuning: "ToolAlternateTuning"
        case .chromaticTuner: "ToolChromaticTuner"
        case .playAlong: "ToolPlayAlong"
        case .playChords: "ToolPlayChords"
        case .chordMemory: "ToolChordMemory"
        }
    }

    var color: Color {
        switch self {
        case .metronome: GitaTheme.categoryOrangeSoft
        case .chords: GitaTheme.categoryYellow
        case .tuner: GitaTheme.brand50
        case .alternateTuning: GitaTheme.categoryGreenSoft
        case .chromaticTuner, .playAlong: GitaTheme.categoryBlueSoft
        case .playChords: GitaTheme.categoryPurple
        case .chordMemory: GitaTheme.categoryPinkSoft
        }
    }
}

struct ToolsView: View {
    @State private var unavailableTool: GuitarTool?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GitaTheme.s24) {
                    header
                    VStack(alignment: .leading, spacing: GitaTheme.s12) {
                        section("节奏与和弦", tools: [.metronome, .chords])
                        section("调音", tools: [.tuner, .alternateTuning, .chromaticTuner])
                        section("听觉与演奏", tools: [.playAlong, .playChords, .chordMemory])
                    }
                }
                .padding(.horizontal, GitaTheme.s20)
                .padding(.top, GitaTheme.s12)
                .padding(.bottom, GitaTheme.s24)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(GitaTheme.bgSurface.ignoresSafeArea(edges: .top))
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: GuitarTool.self) { tool in
                if tool == .metronome { ToolMetronomeView() }
                if tool == .tuner { TunerView() }
            }
            .alert(unavailableTool?.title ?? "", isPresented: Binding(
                get: { unavailableTool != nil },
                set: { if !$0 { unavailableTool = nil } }
            )) {
                Button("知道了", role: .cancel) { unavailableTool = nil }
            } message: {
                Text("这项工具尚未开放，敬请期待。")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GitaTheme.s4) {
            HStack(spacing: GitaTheme.s12) {
                Text("工具")
                    .font(GitaFont.largeTitle())
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Text("\(GuitarTool.allCases.count) 款工具")
                    .font(GitaFont.micro())
                    .foregroundStyle(GitaTheme.textSecondary)
                    .padding(.horizontal, GitaTheme.s12)
                    .padding(.vertical, 6)
                    .background(GitaTheme.bgSubtle, in: Capsule())
            }
            .frame(minHeight: 42)
            Text("调准音，跟上拍，把每一步练扎实")
                .font(GitaFont.caption())
                .foregroundStyle(GitaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(GitaTheme.textPrimary)
    }

    private func section(_ title: LocalizedStringKey, tools: [GuitarTool]) -> some View {
        VStack(alignment: .leading, spacing: GitaTheme.s4) {
            Text(title)
                .font(GitaFont.callout(.bold))
                .foregroundStyle(GitaTheme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(tools) { tool in
                if tool == .metronome || tool == .tuner {
                    NavigationLink(value: tool) { ToolRow(tool: tool) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tools.item.\(tool.id)")
                } else {
                    Button { unavailableTool = tool } label: { ToolRow(tool: tool) }
                        .buttonStyle(.plain)
                        .accessibilityHint("这项工具尚未开放")
                        .accessibilityIdentifier("tools.item.\(tool.id)")
                }
            }
        }
    }
}

private struct ToolRow: View {
    let tool: GuitarTool
    @ScaledMetric(relativeTo: .callout) private var titleSize = 15

    var body: some View {
        HStack(spacing: GitaTheme.s12) {
            Image(tool.image)
                .frame(width: 38, height: 38)
                .background(tool.color, in: RoundedRectangle(cornerRadius: GitaTheme.radius12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .font(.system(size: titleSize, weight: .bold))
                    .foregroundStyle(GitaTheme.textPrimary)
                Text(tool.subtitle)
                    .font(GitaFont.micro())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Image("ToolChevron").accessibilityHidden(true)
        }
        .padding(GitaTheme.s12)
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .background(GitaTheme.bgSurface, in: RoundedRectangle(cornerRadius: GitaTheme.radius20))
        .overlay {
            RoundedRectangle(cornerRadius: GitaTheme.radius20)
                .strokeBorder(GitaTheme.borderSubtle, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: GitaTheme.radius20))
        .accessibilityElement(children: .combine)
    }
}
