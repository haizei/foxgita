"""Rebuild the device's generic glyph atlas from rendered fonts (no score images)."""
import struct
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "docs/qa/2026-11-04-tab-omr/geometry"))
from probe import templates

payload = bytearray()
for char, bitmap, aspect in templates():
    payload.extend(struct.pack("<cf", char.encode(), aspect))
    payload.extend(bitmap.tobytes())
(root / "foxgita/Resources/tab-glyphs.bin").write_bytes(payload)

# A separate atlas for isolated digits, preserving the original TAB/X classifier.
import probe
probe.FONTS = ["Georgia Bold", "Times New Roman Bold", "Arial Bold", "Verdana Bold", "Tahoma Bold"]
payload = bytearray()
for char, bitmap, aspect in probe.templates():
    if char.isdigit():
        payload.extend(struct.pack("<cf", char.encode(), aspect))
        payload.extend(bitmap.tobytes())
(root / "foxgita/Resources/tab-bold-glyphs.bin").write_bytes(payload)
