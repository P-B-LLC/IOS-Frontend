#!/usr/bin/env python3
"""Catch missing/corrupt bundled photo assets before a blank card ships."""
import json
from pathlib import Path
import re
import struct

root = Path(__file__).resolve().parents[1]
app = root / 'IOS Frontend' / 'IOS Frontend'
presentation = (app / 'Views/Shared/RytivoSunriseDesign.swift').read_text(encoding='utf-8')
names = set(re.findall(r'return "(Training\w+)"', presentation)) | {'SunriseFoodPhoto'}
total = 0
# Keep the approved high-resolution originals rather than reintroducing the
# smaller exports that softened Home's wide Retina focus cards.
minimum_dimensions = {'TrainingStrength': (900, 1600), 'TrainingOutdoors': (1500, 1000)}
for name in sorted(names):
    folder = app / 'Assets.xcassets' / (name + '.imageset')
    manifest = json.loads((folder / 'Contents.json').read_text(encoding='utf-8-sig'))
    files = [image['filename'] for image in manifest['images'] if 'filename' in image]
    assert files, f'{name}: no image supplied'
    for filename in files:
        path = folder / filename
        data = path.read_bytes()
        if data[:8] == b'\x89PNG\r\n\x1a\n':
            width, height = struct.unpack('>II', data[16:24])
        else:
            assert data[:2] == b'\xff\xd8', f'{path}: invalid PNG/JPEG'
            offset = 2
            width = height = 0
            while offset < len(data):
                assert data[offset] == 255, f'{path}: invalid JPEG marker'
                marker = data[offset + 1]
                length = struct.unpack('>H', data[offset + 2:offset + 4])[0]
                if marker in {0xC0, 0xC1, 0xC2}:
                    height, width = struct.unpack('>HH', data[offset + 5:offset + 9])
                    break
                offset += length + 2
        assert 480 <= width <= 2048 and 480 <= height <= 2048, f'{name}: unsuitable dimensions'
        minimum_width, minimum_height = minimum_dimensions.get(name, (480, 480))
        assert width >= minimum_width and height >= minimum_height, f'{name}: lower-resolution export replaced the original'
        assert len(data) <= 3 * 1024 * 1024, f'{name}: photo exceeds bundle budget'
        total += len(data)
assert total <= 16 * 1024 * 1024, 'Sunrise photo bundle exceeds 16 MiB'
print(f'Validated {len(names)} bundled photo assets ({total / 1024 / 1024:.1f} MiB).')
