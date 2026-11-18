#!/usr/bin/env python3
"""Validate approved local branding without image-library dependencies.

This checks exported assets and catalog wiring, not native UI rendering.
Update the provenance manifest only after a newly approved design/export.
"""
import hashlib
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET
import zlib

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "IOS Frontend/IOS Frontend/Assets.xcassets"
manifest = json.loads((ROOT / "Brand/Rytivo/approved-brand-assets.json").read_text())

for relative, expected in manifest["sha256"].items():
    path = ROOT / relative
    data = path.read_bytes()
    assert 0 < len(data) < 256 * 1024, f"Unexpected brand asset size: {relative}"
    # SVGs are text; tolerate a Windows checkout's line-ending conversion.
    canonical = data.replace(b"\r\n", b"\n") if path.suffix == ".svg" else data
    assert hashlib.sha256(canonical).hexdigest() == expected, f"Unapproved or corrupt brand export: {relative}"

mark_set = ASSETS / "RytivoLogoMark.imageset"
catalog = json.loads((mark_set / "Contents.json").read_text())
images = catalog["images"]
assert [i["filename"] for i in images] == ["RytivoLogoMark.svg", "RytivoLogoMarkDark.svg"]
assert images[1]["appearances"] == [{"appearance": "luminosity", "value": "dark"}]
assert catalog["properties"]["preserves-vector-representation"] is True
shapes = []
for image in images:
    svg = ET.parse(mark_set / image["filename"]).getroot()
    assert svg.attrib["width"] == svg.attrib["height"] == "256"
    assert svg.attrib["viewBox"] == "0 0 256 256"
    paths = list(svg.iter("{http://www.w3.org/2000/svg}path"))
    assert len(paths) == 2, "The approved mark contains only the head and continuous R."
    shapes.append([p.attrib["d"] for p in paths])
    expected_color = "white" if "appearances" in image else "#292421"
    assert {p.attrib.get("fill") for p in paths} == {expected_color}
    assert not list(svg.iter("{http://www.w3.org/2000/svg}image")), "Logo must remain vector."
assert shapes[0] == shapes[1], "Light/dark marks must use identical geometry."

icon_set = ASSETS / "AppIcon.appiconset"
icon_catalog = json.loads((icon_set / "Contents.json").read_text())
icon_entry = icon_catalog["images"][0]
assert icon_entry["filename"] == "Rytivo-AppIcon-1024.png"
assert icon_entry["size"] == "1024x1024" and icon_entry["platform"] == "ios"
png = (icon_set / icon_entry["filename"]).read_bytes()
assert png[:8] == b"\x89PNG\r\n\x1a\n"
offset = 8
header = None
chunks = []
while offset < len(png):
    length = struct.unpack_from(">I", png, offset)[0]
    kind = png[offset + 4:offset + 8]
    payload = png[offset + 8:offset + 8 + length]
    crc = struct.unpack_from(">I", png, offset + 8 + length)[0]
    assert zlib.crc32(kind + payload) & 0xFFFFFFFF == crc, "Corrupt PNG chunk."
    if kind == b"IHDR":
        header = struct.unpack(">IIBBBBB", payload)
    chunks.append(kind)
    offset += length + 12
assert header == (1024, 1024, 8, 2, 0, 0, 0), "App icon must be an opaque 1024px RGB PNG."
assert b"tRNS" not in chunks and chunks[-1] == b"IEND" and offset == len(png)

ink = json.loads((ASSETS / "RytivoBrandInk.colorset/Contents.json").read_text())
for entry, expected in zip(ink["colors"], [(0x29, 0x24, 0x21), (255, 255, 255)]):
    components = entry["color"]["components"]
    assert tuple(int(components[c], 16) for c in ("red", "green", "blue")) == expected
    assert float(components["alpha"]) == 1
assert ink["colors"][1]["appearances"] == [{"appearance": "luminosity", "value": "dark"}]
assert (ROOT / "IOS Frontend/IOS Frontend/Resources/Fonts/NunitoSans-SemiBold.ttf").is_file()
print("Validated approved two-shape vector marks, matching brand ink, opaque 1024px icon, and preview.")
