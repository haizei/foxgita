//
//  MetronomeSpeedSheet.swift
//  foxgita
//

import SwiftUI

struct MetronomeSpeedSheet: View {
    let metronome: MetronomeEngine
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: GitaTheme.s24) {
                bpmControls
                MetronomeTempoRulerView(bpm: metronome.bpm) { value in
                    metronome.setBpm(value)
                }
                .padding(.horizontal, 10)
            }
            .padding(.horizontal, GitaTheme.s20)
            .padding(.top, GitaTheme.s8)
            .padding(.bottom, GitaTheme.s24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(GitaTheme.bgSurface)
            .navigationTitle(String(localized: "调整速度"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "完成"), action: onDone)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.6)])
        .presentationDragIndicator(.visible)
    }

    private var bpmControls: some View {
        HStack(spacing: GitaTheme.s12) {
            MetronomeStepButton(
                kind: .decrease,
                diameter: 48,
                enabled: metronome.bpm > 40
            ) {
                metronome.bump(-1)
            }

            VStack(spacing: 2) {
                Text("\(metronome.bpm)")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(GitaTheme.brand500)
                    .monospacedDigit()
                Text("BPM")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)
                Text(MetronomeTempoName.name(for: metronome.bpm))
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)

            MetronomeStepButton(
                kind: .increase,
                diameter: 48,
                enabled: metronome.bpm < 200
            ) {
                metronome.bump(1)
            }
        }
    }
}

#Preview {
    MetronomeSpeedSheet(metronome: MetronomeEngine(), onDone: {})
}
