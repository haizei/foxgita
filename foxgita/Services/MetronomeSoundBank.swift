//
//  MetronomeSoundBank.swift
//  foxgita
//

import AVFoundation
import Foundation
import os

struct MetronomeSoundBuffers {
    let beat: AVAudioPCMBuffer
    let strong: AVAudioPCMBuffer
}

private let metronomeSoundBankLog = Logger(
    subsystem: "com.haizei.foxgita", category: "metronome-sound-bank"
)

/// Eagerly loads the complete sound bank before playback so the scheduling
/// path never performs file I/O. A damaged optional preset falls back to the
/// default preset; a missing default preset is a launch-time playback error.
final class MetronomeSoundBank {
    private let bundle: Bundle
    private var buffersByPreset: [MetronomeSoundPreset: MetronomeSoundBuffers] = [:]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func preloadAll(expectedFormat: AVAudioFormat) throws {
        guard buffersByPreset.isEmpty else { return }
        let defaultBuffers = try load(.realMetronome, expectedFormat: expectedFormat)
        buffersByPreset[.realMetronome] = defaultBuffers

        for preset in MetronomeSoundPreset.allCases where preset != .realMetronome {
            do {
                buffersByPreset[preset] = try load(preset, expectedFormat: expectedFormat)
            } catch {
                buffersByPreset[preset] = defaultBuffers
                metronomeSoundBankLog.error(
                    "preset fallback preset=\(preset.rawValue, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    func buffers(for preset: MetronomeSoundPreset) -> MetronomeSoundBuffers? {
        buffersByPreset[preset]
    }

    private func load(
        _ preset: MetronomeSoundPreset, expectedFormat: AVAudioFormat
    ) throws -> MetronomeSoundBuffers {
        MetronomeSoundBuffers(
            beat: try loadBuffer(
                named: preset.beatResourceName, expectedFormat: expectedFormat
            ),
            strong: try loadBuffer(
                named: preset.strongResourceName, expectedFormat: expectedFormat
            )
        )
    }

    private func loadBuffer(
        named name: String, expectedFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard let url = bundle.url(forResource: name, withExtension: "wav") else {
            throw MetronomeError.soundAssetUnavailable(name)
        }
        let file = try AVAudioFile(forReading: url)
        guard file.processingFormat.sampleRate == expectedFormat.sampleRate,
              file.processingFormat.channelCount == expectedFormat.channelCount else {
            throw MetronomeError.soundAssetInvalid(name)
        }
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw MetronomeError.soundAssetInvalid(name)
        }
        try file.read(into: buffer)
        guard buffer.frameLength > 0 else {
            throw MetronomeError.soundAssetInvalid(name)
        }
        return buffer
    }
}
