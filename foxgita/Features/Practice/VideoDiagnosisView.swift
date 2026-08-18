//
//  VideoDiagnosisView.swift
//  foxgita
//

import AVFoundation
import AVKit
import SwiftData
import SwiftUI

struct VideoDiagnosisView: View {
    let recordingId: String
    let taskTitle: String
    var onClose: () -> Void

    @Query(filter: #Predicate<RecordingRef> { $0.deletedAt == nil })
    private var recordings: [RecordingRef]

    @State private var clip = DiagnosisClipPlayer()
    @State private var selected = 0
    @State private var pane = 0

    private var recording: RecordingRef? { recordings.first { $0.id == recordingId } }
    private var findings: [VideoFinding] { recording?.videoFindings ?? [] }
    private var durationSec: Int { max(recording?.durationSec ?? 0, 0) }

    private var currentFinding: VideoFinding? {
        findings.indices.contains(selected) ? findings[selected] : nil
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 0) {
                header
                if let recording {
                    diagnosis(recording)
                } else {
                    Spacer()
                }
            }
        }
        .onAppear {
            if let recording { clip.load(url: recording.fileURL) }
        }
        .onDisappear { clip.stop() }
    }

    private var header: some View {
        HStack {
            Button("返回") { onClose() }
                .font(.system(size: 14))
                .foregroundStyle(GitaTheme.textSecondary)
                .frame(minWidth: 40, alignment: .leading)
            Text("分段诊断")
                .font(.system(size: 20, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Button("完成") { onClose() }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GitaTheme.brand500)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .frame(minHeight: 56)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func diagnosis(_ recording: RecordingRef) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(taskTitle) · \(recording.durationLabel)")
                    .font(GitaFont.caption())
                    .foregroundStyle(GitaTheme.textSecondary)

                playerCard

                SegmentedPills(titles: ["时间线", "总结"], selection: $pane)

                if pane == 1 {
                    summaryCard(recording)
                } else {
                    timelineCard
                    if let currentFinding {
                        findingCard(currentFinding)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }

        footer
    }

    private var playerCard: some View {
        VideoPlayer(player: clip.player)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius20))
            .overlay(alignment: .top) {
                overlayChip(
                    Text("\(mmss(clip.currentSec)) / \(mmss(durationSec))").monospacedDigit()
                )
            }
            .overlay(alignment: .bottom) {
                overlayChip(Text("手部与琴颈回放"))
            }
    }

    private func overlayChip(_ label: Text) -> some View {
        label
            .font(GitaFont.caption(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.black.opacity(0.45), in: Capsule())
            .padding(10)
    }

    private var timelineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if findings.isEmpty {
                Text("这次没有明确问题")
                    .font(GitaFont.callout())
                    .foregroundStyle(GitaTheme.textSecondary)
            } else {
                track
                labels
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    private var track: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(GitaTheme.borderInactive)
                    .frame(height: 4)
                ForEach(Array(findings.enumerated()), id: \.offset) { index, finding in
                    let size: CGFloat = index == selected ? 16 : 10
                    Button { select(index) } label: {
                        Circle()
                            .fill(index == selected ? GitaTheme.brand500 : GitaTheme.textTertiary)
                            .frame(width: size, height: size)
                    }
                    .buttonStyle(.plain)
                    .offset(x: dotX(finding, width: geo.size.width, size: size))
                    .accessibilityLabel(Text("\(mmss(finding.startSec)) \(finding.title)"))
                }
            }
            .frame(width: geo.size.width, height: Self.trackHeight)
        }
        .frame(height: Self.trackHeight)
    }

    private var labels: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(findings.enumerated()), id: \.offset) { index, finding in
                Button { select(index) } label: {
                    Text("\(mmss(finding.startSec)) \(finding.title)")
                        .font(GitaFont.micro(index == selected ? .semibold : .regular))
                        .foregroundStyle(
                            index == selected ? GitaTheme.brand500 : GitaTheme.textSecondary
                        )
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func findingCard(_ finding: VideoFinding) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(finding.title)
                .font(GitaFont.headline())
            Text("\(finding.evidence) · 原因：\(finding.cause)")
                .font(GitaFont.callout())
                .foregroundStyle(GitaTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("纠正建议")
                    .font(GitaFont.caption(.semibold))
                    .foregroundStyle(GitaTheme.brand500)
                Text(finding.action)
                    .font(GitaFont.callout())
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GitaTheme.brand50)
            .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius12))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    private func summaryCard(_ recording: RecordingRef) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryField(String(localized: "亮点"), recording.reviewHighlight)
            summaryField(String(localized: "优先改善"), recording.reviewFocus)
            summaryField(String(localized: "下次练法"), recording.reviewNextAction)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GitaTheme.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: GitaTheme.radius20))
        .shadow(color: GitaTheme.shadowCard, radius: 8, y: 4)
    }

    private func summaryField(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(GitaFont.caption(.semibold))
                .foregroundStyle(GitaTheme.textSecondary)
            Text(value)
                .font(GitaFont.callout())
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { clip.playFull() } label: {
                Text("完整回放")
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .contentShape(Capsule())
                    .overlay(Capsule().stroke(GitaTheme.borderSubtle, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button { playCurrentClip() } label: {
                Text("纠正片段")
                    .font(GitaFont.body(.semibold))
                    .foregroundStyle(GitaTheme.brandOn)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(findings.isEmpty ? GitaTheme.borderInactive : GitaTheme.brand500)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(findings.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 28)
    }

    private func select(_ index: Int) {
        selected = index
        guard findings.indices.contains(index) else { return }
        clip.seek(Double(findings[index].startSec))
    }

    private func playCurrentClip() {
        guard let currentFinding else { return }
        clip.play(from: currentFinding.startSec, to: currentFinding.endSec)
    }

    private func dotX(_ finding: VideoFinding, width: CGFloat, size: CGFloat) -> CGFloat {
        let ratio = CGFloat(finding.startSec) / CGFloat(max(durationSec, 1))
        return min(max(0, width * ratio - size / 2), max(0, width - size))
    }

    private func mmss(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private static let trackHeight: CGFloat = 16
}

/// Owns the clip's `AVPlayer` so the periodic time observer has a stable place
/// to live and can stop playback at a finding's `endSec`.
@Observable
@MainActor
private final class DiagnosisClipPlayer {
    let player = AVPlayer()
    /// Whole seconds so a 5 Hz observer does not invalidate the page 5 times a second.
    var currentSec: Int = 0

    @ObservationIgnored private var pauseAtSec: Double?
    @ObservationIgnored private var observer: Any?
    /// True only after a successful `acquire` in `load`, so `stop` can run safely when load never ran.
    @ObservationIgnored private var didAcquirePlayback = false

    func load(url: URL) {
        guard player.currentItem == nil else { return }
        do {
            try AudioSessionCoordinator.shared.acquire(.playback)
            didAcquirePlayback = true
        } catch {}
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
    }

    func playFull() {
        pauseAtSec = nil
        seek(0)
        player.play()
    }

    func play(from start: Int, to end: Int) {
        seek(Double(start)) { [weak self] finished in
            guard let self, finished else { return }
            self.pauseAtSec = Double(end)
            self.player.play()
        }
    }

    func seek(_ seconds: Double, completion: (@MainActor (Bool) -> Void)? = nil) {
        pauseAtSec = nil
        let target = max(0, seconds)
        currentSec = Int(target.rounded())
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { finished in
            Task { @MainActor in
                completion?(finished)
            }
        }
    }

    func stop() {
        if let observer { player.removeTimeObserver(observer) }
        observer = nil
        pauseAtSec = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        if didAcquirePlayback {
            AudioSessionCoordinator.shared.release(.playback)
            didAcquirePlayback = false
        }
    }

    private func tick(_ seconds: Double) {
        let elapsed = seconds.isFinite ? max(0, seconds) : 0
        currentSec = Int(elapsed.rounded())
        guard let pauseAtSec, elapsed >= pauseAtSec else { return }
        self.pauseAtSec = nil
        player.pause()
    }
}
