"""Synthetic binary fixtures; uploaded/third-party presets are never bundled."""
import importlib.util
from pathlib import Path
import struct
import unittest
import zlib

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "inspect_serum_presets.py"
SPEC = importlib.util.spec_from_file_location("inspector", SCRIPT)
inspector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inspector)


def fixture(state_size=21808, a_frames=1, b_frames=1, extra_noise=b""):
    state = bytearray(state_size)
    for index in range(228):
        struct.pack_into("<f", state, inspector.PARAMS_LOW + index * 4, .5)
    count = inspector.LAYOUTS.get(state_size, 260)
    for index in range(count - 228):
        struct.pack_into("<f", state, inspector.PARAMS_HIGH + index * 4, .5)
    state[0x4972:0x4972 + 13] = b"Test bank mix"
    struct.pack_into("<2I", state, 0x4968, a_frames * 8192, b_frames * 8192)
    for slot in range(16):
        base = slot * 40
        state[base + 33:base + 36] = bytes((0x80, slot, 0xFF))
        struct.pack_into("<f", state, base + 8, 1)
    struct.pack_into("<f", state, 4, .25)
    struct.pack_into("<H", state, 20, 5)
    struct.pack_into("<H", state, 26, 45)
    samples = struct.pack("<f", .25) * ((a_frames + b_frames) * 2048) + extra_noise
    first = zlib.compress(state)
    payload = first + zlib.compress(samples) + struct.pack("<I", len(first))
    header = bytearray(60)
    header[:4] = b"CcnK"
    header[8:12] = b"FPCh"
    header[16:20] = b"XfsX"
    struct.pack_into(">I", header, 4, 60 + len(payload))
    struct.pack_into(">I", header, 12, 1)
    struct.pack_into(">I", header, 20, 1)
    struct.pack_into(">I", header, 24, 1)
    struct.pack_into(">I", header, 56, len(payload))
    return bytes(header) + payload


class InspectorTests(unittest.TestCase):
    def test_known_layout_parameter_counts(self):
        for layout, count in inspector.LAYOUTS.items():
            with self.subTest(layout=layout):
                parsed = inspector.inspect_bytes(fixture(layout))
                self.assertEqual(parsed["verifiedParameterCount"], count)
                self.assertEqual(len(parsed["parameters"]), count)

    def test_actual_binary_fields_and_bank_split(self):
        parsed = inspector.inspect_bytes(fixture(a_frames=2, b_frames=3))
        self.assertEqual(parsed["name"], "Test bank mix")
        self.assertEqual([bank["frames"] for bank in parsed["embeddedWavetables"]], [2, 3])
        self.assertEqual(parsed["embeddedWavetables"][0]["peak"], .25)
        self.assertEqual(parsed["activeRouteCount"], 1)
        route = parsed["matrix"][0]
        self.assertEqual((route["source"], route["destination"], route["amount"]), (5, 45, .25))

    def test_empty_banks_and_separate_noise_bytes(self):
        parsed = inspector.inspect_bytes(fixture(a_frames=0, b_frames=0, extra_noise=b"\0" * 40))
        self.assertEqual(parsed["trailingNoiseBytes"], 40)
        self.assertEqual(parsed["embeddedWavetables"][0]["frames"], 0)

    def test_trailing_opaque_noise_need_not_be_float_aligned(self):
        parsed = inspector.inspect_bytes(fixture(extra_noise=b"\0" * 2501))
        self.assertEqual(parsed["trailingNoiseBytes"], 2501)
        self.assertEqual([bank["frames"] for bank in parsed["embeddedWavetables"]], [1, 1])

    def test_standard_vst_header_size_is_accepted(self):
        data = bytearray(fixture())
        struct.pack_into(">I", data, 4, len(data) - 8)
        self.assertEqual(inspector.inspect_bytes(data)["stateBytes"], 21808)

    def test_wrong_plugin_and_inconsistent_lengths_rejected(self):
        for offset, changed in ((16, b"Nope"), (4, b"\0" * 4), (56, b"\0" * 4)):
            data = bytearray(fixture())
            data[offset:offset + 4] = changed
            with self.subTest(offset=offset), self.assertRaises(inspector.PresetReadError):
                inspector.inspect_bytes(data)

    def test_corrupt_and_missing_trailer_rejected(self):
        data = fixture()
        for changed in (data[:-1], data[:-4] + b"\0" * 4, data[:100]):
            with self.assertRaises(inspector.PresetReadError):
                inspector.inspect_bytes(changed)

    def test_unknown_layout_rejected(self):
        with self.assertRaises(inspector.PresetReadError):
            inspector.inspect_bytes(fixture(state_size=22000))

    def test_inflation_has_a_hard_output_limit(self):
        with self.assertRaises(inspector.PresetReadError):
            inspector.inflate_stream(zlib.compress(b"\0" * 5000), 1000)

    def test_incomplete_zlib_rejected(self):
        with self.assertRaises(inspector.PresetReadError):
            inspector.inflate_stream(zlib.compress(b"hello")[:-2], 1000)

    def test_no_embedded_asset_can_exceed_256_frames(self):
        with self.assertRaises(inspector.PresetReadError):
            inspector.inspect_bytes(fixture(a_frames=257))


if __name__ == "__main__":
    unittest.main()
