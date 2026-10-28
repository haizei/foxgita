"""Build reversible natural-transient candidates; never overwrite bundled sounds."""
from pathlib import Path
import argparse
import json
import subprocess
import wave

import numpy as np

RATE = 44_100
COUNT = round(RATE * 0.070)
PEAK = 10 ** (-1.2 / 20)
SOURCES = {
    "realMetronome": ("474030__olesouwester__metronome-01.wav",) * 2,
    "electronicMetronome": ("793346__sadiquecat__metronome-click.wav",) * 2,
    "windChime": ("398492__anthousai__wind-chimes-single-03.wav",) * 2,
    "woodblock": ("53403__calaudio__wood-block.wav",) * 2,
    "drumKit1": ("50980__matiasreccius__snared16.wav",) * 2,
    "drumKit2": ("378377__karolist__closed-hi-hat.wav", "132418__sajmund__rimshot-sweet.aiff"),
    "handClap": ("561089__sorinious_genious__clap-1.wav",) * 2,
}


def decode(path):
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(RATE), "-f", "f32le", "-"],
        capture_output=True, check=True,
    )
    return np.frombuffer(result.stdout, dtype="<f4").astype(np.float64)


def weighted(signal):
    frequency = np.fft.rfftfreq(len(signal), 1 / RATE)
    squared = frequency * frequency
    numerator = 12194**2 * squared**2
    denominator = ((squared + 20.6**2) * np.sqrt((squared + 107.7**2) * (squared + 737.9**2)) * (squared + 12194**2))
    response = np.divide(numerator, denominator, out=np.zeros_like(frequency), where=denominator != 0)
    return np.fft.irfft(np.fft.rfft(signal) * response * 10 ** (2 / 20), n=len(signal))


def calibrate(signal, target):
    rms = np.sqrt(np.mean(weighted(signal) ** 2))
    result = signal * (10 ** (target / 20)) / max(rms, 1e-12)
    peak = np.max(np.abs(result))
    return result * min(1, PEAK / max(peak, 1e-12))


def natural_transient(signal, strong):
    energy = np.r_[0.0, np.cumsum(signal * signal)]
    start = int(np.argmax(energy[COUNT:] - energy[:-COUNT])) if len(signal) > COUNT else 0
    window = signal[start:start + COUNT]
    active = np.flatnonzero(np.abs(window) > max(np.max(np.abs(window)), 1e-12) * 0.03)
    start = max(0, start + (int(active[0]) if len(active) else 0) - 22)
    clip = np.pad(signal[start:start + COUNT], (0, max(0, COUNT - len(signal[start:start + COUNT]))))
    if strong:
        # A modest related pitch change, rather than the former 3x slowdown/stacking.
        clip = np.interp(np.arange(COUNT) / 1.08, np.arange(COUNT), clip)
    clip -= np.mean(clip)
    frequency = np.fft.rfftfreq(COUNT, 1 / RATE)
    clip = np.fft.irfft(np.fft.rfft(clip) / np.sqrt(1 + (frequency / 6500) ** 6), n=COUNT)
    clip[:31] *= np.linspace(0, 1, 31)
    clip[-441:] *= np.linspace(1, 0, 441)
    return calibrate(clip, -12 if strong else -15)


def write(path, signal):
    pcm = np.round(np.clip(signal, -PEAK, PEAK) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm.tobytes())


def preview(beat, strong, level, bpm=100, subdivisions=1):
    scale = level / max(np.sqrt(np.mean(weighted(beat) ** 2)), 1e-12)
    result = np.zeros(round(RATE * 60 / bpm * 8))
    for index in range(8 * subdivisions):
        offset = round(index * RATE * 60 / bpm / subdivisions)
        click = strong if index % (4 * subdivisions) == 0 else beat
        gain = 1 if index % subdivisions == 0 else 0.6
        result[offset:offset + len(click)] += click * scale * gain
    return result


def matched_level(versions):
    # One common achievable level; independent peak limiting biases an A/B.
    limits = [10 ** (-20 / 20)]
    for beat, strong in versions:
        rms = np.sqrt(np.mean(weighted(beat) ** 2))
        peak = max(np.max(np.abs(beat)), np.max(np.abs(strong)), 1e-12)
        limits.append(rms * PEAK / peak)
    return min(limits)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--bundle-dir", type=Path, required=True)
    args = parser.parse_args()
    output = Path(__file__).parent
    samples = output / "candidates"
    samples.mkdir(exist_ok=True)
    report = {}
    for preset, sources in SOURCES.items():
        for variant, source in zip(("beat", "strong"), sources):
            signal = natural_transient(decode(args.source_dir / source), variant == "strong")
            write(samples / f"{preset}-{variant}.wav", signal)
            report[f"{preset}-{variant}"] = {
                "frames": len(signal), "sample_rate": RATE,
                "peak_dbfs": float(20 * np.log10(max(np.max(np.abs(signal)), 1e-12))),
                "a_rms_dbfs": float(20 * np.log10(max(np.sqrt(np.mean(weighted(signal) ** 2)), 1e-12))),
            }
    previews = {}
    for preset, label in (("woodblock", "wood"), ("electronicMetronome", "electronic"), ("realMetronome", "strong-beat")):
        versions = [tuple(decode(folder / f"{preset}-{kind}.wav") for kind in ("beat", "strong"))
                    for folder in (args.bundle_dir, samples)]
        level = matched_level(versions)
        for suffix, bpm, subdivisions in (("", 100, 1), ("-80bpm", 80, 1), ("-160bpm", 160, 1), ("-160bpm-sixteenth", 160, 4)):
            old, new = [preview(*version, level, bpm, subdivisions) for version in versions]
            name = f"ab-{label}{suffix}.wav"
            write(output / name, np.concatenate([old, np.zeros(round(RATE * 0.8)), new]))
            previews[name] = {"bpm": bpm, "subdivisions": subdivisions,
                              "ordinary_a_rms_dbfs_both": float(20 * np.log10(max(level, 1e-12)))}
    report = {"candidates": report, "previews": previews}
    (output / "metrics.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"Built {len(report['candidates'])} candidate samples and {len(previews)} A/B previews in {output}")


if __name__ == "__main__":
    main()
