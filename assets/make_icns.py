#!/usr/bin/env python3
"""Pack PNG files into a macOS .icns (no iconutil needed).
Usage: make_icns.py OUT.icns 16.png 32.png 64.png 128.png 256.png 512.png 1024.png
The PNGs are matched to icns slots by their pixel size."""
import struct, sys

# size in px -> icns type codes (PNG payload). 2x variants reuse the next size up.
SLOTS = {16: ["icp4"], 32: ["icp5", "ic11"], 64: ["icp6", "ic12"], 128: ["ic07"],
         256: ["ic08", "ic13"], 512: ["ic09", "ic14"], 1024: ["ic10"]}

def png_size(data):
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    return struct.unpack(">II", data[16:24])[0]

def main(out, *pngs):
    chunks = []
    for path in pngs:
        data = open(path, "rb").read()
        for code in SLOTS.get(png_size(data), []):
            chunks.append(code.encode() + struct.pack(">I", 8 + len(data)) + data)
    body = b"".join(chunks)
    open(out, "wb").write(b"icns" + struct.pack(">I", 8 + len(body)) + body)
    print("wrote", out, len(chunks), "images")

if __name__ == "__main__":
    main(*sys.argv[1:])
