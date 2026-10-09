#!/usr/bin/env python3
"""Inspect user-supplied Serum 1 FXP data without loading a plugin.

This is a diagnostic oracle for the app's native importer, not a Serum audio
renderer or preset converter. Offsets were checked directly against uploaded
files and compared with public format notes. No uploaded preset is bundled.
The legacy VST payload is binary data; it is never executed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import zlib

MAX_FILE_BYTES = 32 * 1024 * 1024
MAX_STATE_BYTES = 256 * 1024
MAX_ASSET_BYTES = 16 * 1024 * 1024
FRAME_BYTES = 2048 * 4
# These decoded sizes are observed layouts, not a guessed plugin-version tag.
LAYOUTS = {21524: 260, 21804: 260, 21808: 260, 28232: 273, 172736: 299}
PARAMS_LOW = 0x3460
PARAMS_HIGH = 0x4AE0
PARAMETER_NAMES = {
    0: "Master volume", 1: "A level", 2: "A pan", 3: "A octave",
    4: "A semitones", 5: "A fine", 6: "A unison", 7: "A detune",
    9: "A warp amount", 11: "A wavetable position", 14: "B level",
    15: "B pan", 16: "B octave", 17: "B semitones", 18: "B fine",
    19: "B unison", 20: "B detune", 22: "B warp amount",
    24: "B wavetable position", 27: "Noise level", 33: "Sub level",
    35: "Envelope 1 attack", 36: "Envelope 1 hold",
    37: "Envelope 1 decay", 38: "Envelope 1 sustain",
    39: "Envelope 1 release", 44: "Filter type", 45: "Filter cutoff",
    46: "Filter resonance", 47: "Filter drive", 61: "LFO 1 rate",
    97: "Distortion drive", 124: "Delay mix", 154: "Distortion enabled",
    158: "Delay enabled", 168: "A warp type", 169: "B warp type",
    212: "A enabled", 213: "B enabled", 214: "Noise enabled",
    215: "Sub enabled", 216: "Filter enabled", 218: "Macro 1",
}
SOURCE_NAMES = {2: "Envelope 1", 5: "LFO 1", 13: "Velocity", 24: "Macro 1"}


class PresetReadError(ValueError):
    """Input is malformed or uses a layout not verified by this reader."""


def inflate_stream(data: bytes, limit: int) -> tuple[bytes, int]:
    """Decode exactly one zlib stream with a hard decompressed-size limit."""
    try:
        decoder = zlib.decompressobj()
        output = decoder.decompress(data, limit + 1)
    except zlib.error as error:
        raise PresetReadError("Invalid zlib stream.") from error
    if len(output) > limit or decoder.unconsumed_tail:
        raise PresetReadError("Decoded stream exceeds its size limit.")
    if not decoder.eof:
        raise PresetReadError("Truncated zlib stream.")
    return output, len(data) - len(decoder.unused_data)


def cstring(data: bytes, offset: int, size: int) -> str:
    return data[offset:offset + size].split(b"\0", 1)[0].decode("utf-8", "replace")


def matrix_records(state: bytes) -> list[dict]:
    """Read self-identifying records; never include padding/heap-memory bytes."""
    records = {}
    for marker in range(33, len(state) - 6):
        if state[marker] != 0x80 or state[marker + 2] != 0xFF:
            continue
        slot = state[marker + 1]
        base = marker - 33
        if slot >= 32 or base + 40 > len(state) or slot in records:
            continue
        if slot < 16 and base != slot * 40:
            continue
        amount, output = struct.unpack_from("<2f", state, base + 4)
        source, auxiliary = struct.unpack_from("<2H", state, base + 20)
        destination = struct.unpack_from("<H", state, base + 26)[0]
        if not (math.isfinite(amount) and -8 <= amount <= 8
                and math.isfinite(output) and 0 <= output <= 1
                and source <= 64 and auxiliary <= 64 and destination < 1024):
            continue
        records[slot] = {
            "slot": slot, "source": source,
            "sourceName": SOURCE_NAMES.get(source, f"Serum source {source}"),
            "auxiliarySource": auxiliary, "destination": destination,
            "destinationName": PARAMETER_NAMES.get(destination, f"Serum parameter {destination}"),
            "amount": amount, "outputRange": output,
            "bipolar": state[base + 12] == 1,
            "active": source != 0 and abs(amount) > 1e-6,
        }
    return [records[slot] for slot in sorted(records)]


def inspect_bytes(data: bytes, filename: str = "preset.fxp") -> dict:
    if not (60 <= len(data) <= MAX_FILE_BYTES):
        raise PresetReadError("File must contain 60 bytes to 32 MiB.")
    if data[:4] != b"CcnK" or data[8:12] != b"FPCh" or data[16:20] != b"XfsX":
        raise PresetReadError("Expected a Serum 1 VST2 opaque-chunk FXP.")
    declared_size = struct.unpack_from(">I", data, 4)[0]
    format_version = struct.unpack_from(">I", data, 12)[0]
    if declared_size not in (len(data), len(data) - 8) or format_version != 1:
        raise PresetReadError("Unsupported or inconsistent VST2 header.")
    if struct.unpack_from(">I", data, 24)[0] != 1:
        raise PresetReadError("Expected one preset program.")
    chunk_size = struct.unpack_from(">I", data, 56)[0]
    if chunk_size != len(data) - 60:
        raise PresetReadError("The FXP chunk size does not match the file.")

    state, state_compressed_bytes = inflate_stream(data[60:], MAX_STATE_BYTES)
    if len(state) not in LAYOUTS:
        raise PresetReadError(f"Unverified Serum 1 state layout ({len(state)} bytes).")
    assets, assets_compressed_bytes = inflate_stream(data[60 + state_compressed_bytes:], MAX_ASSET_BYTES)
    trailer = data[60 + state_compressed_bytes + assets_compressed_bytes:]
    if len(trailer) != 4 or struct.unpack("<I", trailer)[0] != state_compressed_bytes:
        raise PresetReadError("Invalid Serum stream-length trailer.")

    count = LAYOUTS[len(state)]
    parameters = list(struct.unpack_from("<228f", state, PARAMS_LOW))
    parameters += struct.unpack_from(f"<{count - 228}f", state, PARAMS_HIGH)
    if any(not math.isfinite(value) or not 0 <= value <= 1 for value in parameters):
        raise PresetReadError("Parameter block contains nonfinite or unnormalized values.")

    a_bytes, b_bytes = struct.unpack_from("<2I", state, 0x4968)
    if (a_bytes % FRAME_BYTES or b_bytes % FRAME_BYTES
            or a_bytes > 256 * FRAME_BYTES or b_bytes > 256 * FRAME_BYTES
            or a_bytes + b_bytes > len(assets)):
        raise PresetReadError("Embedded audio dimensions are invalid.")
    bank_summaries = []
    cursor = 0
    for index, byte_count in enumerate((a_bytes, b_bytes)):
        bank = assets[cursor:cursor + byte_count]
        samples = struct.unpack(f"<{byte_count // 4}f", bank)
        if any(not math.isfinite(sample) for sample in samples):
            raise PresetReadError("Wavetable contains nonfinite samples.")
        bank_summaries.append({
            "oscillator": index, "frameSize": 2048,
            "frames": byte_count // FRAME_BYTES, "bytes": byte_count,
            "peak": max((abs(sample) for sample in samples), default=0),
            "sha256": hashlib.sha256(bank).hexdigest(),
            "reference": cstring(state, (0x3C08, 0x3E08)[index], 512),
        })
        cursor += byte_count
    trailing_noise_bytes = len(assets) - cursor
    if len(state) == 172736:
        flags = list(state[0x84D8 + 0x2D08:0x84D8 + 0x2D08 + 6])
    else:
        flags = [state[0x1AE0 + 0x14 + index * 4] for index in range(6)]
    matrix = matrix_records(state)
    return {
        "file": filename, "name": cstring(state, 0x4972, 32) or Path(filename).stem,
        "author": cstring(state, 0x49A0, 48),
        "headerProgramName": cstring(data, 28, 28),
        "stateBytes": len(state), "stateCompressedBytes": state_compressed_bytes,
        "verifiedParameterCount": count,
        "unverifiedParameterCount": 299 - count,
        "parameters": [{"id": index, "name": PARAMETER_NAMES.get(index, f"Serum parameter {index}"),
                        "normalizedValue": value} for index, value in enumerate(parameters)],
        "matrix": matrix, "activeRouteCount": sum(record["active"] for record in matrix),
        "embeddedWavetables": bank_summaries,
        "trailingNoiseBytes": trailing_noise_bytes,
        "noiseReference": cstring(state, 0x4008, 512),
        "lfo1Flags": dict(zip(("anchor", "hertz", "dotted", "triplet", "running", "envelope"), flags)),
        "limitations": [
            "This report does not render Serum or verify matching audio.",
            "Unsupported controls, LFO shapes, effects and auxiliary routes require explicit conversion reports.",
            "External wavetable references are metadata; referenced files are not opened automatically.",
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("files", nargs="+", type=Path)
    parser.add_argument("--summary", action="store_true", help="Omit raw parameter/matrix values.")
    args = parser.parse_args()
    failed = False
    reports = []
    for path in args.files:
        try:
            # Read at most the allowed input size, including one sentinel byte.
            with path.open("rb") as handle:
                report = inspect_bytes(handle.read(MAX_FILE_BYTES + 1), path.name)
            if args.summary:
                report.pop("parameters")
                report.pop("matrix")
            reports.append(report)
        except (OSError, PresetReadError) as error:
            reports.append({"file": path.name, "error": str(error)})
            failed = True
    json.dump(reports, sys.stdout, indent=2, allow_nan=False)
    print()
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
