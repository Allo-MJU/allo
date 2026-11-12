"""Remove the supplied near-white JPEG matte without redrawing colored pixels.
Usage: python prepare_woodland_logo.py source.jpeg output.png (requires Pillow).
"""
import sys
from pathlib import Path
from PIL import Image

source, output = map(Path, sys.argv[1:])
im = Image.open(source).convert('RGBA')
pixels = []
for r, g, b, _ in im.getdata():
    low, high = min(r,g,b), max(r,g,b)
    alpha = min(1, max(0, (245-low)/30))
    if alpha == 0:
        pixels.append((0,0,0,0))
    elif alpha < 1:
        rgb = tuple(round(min(255,max(0,(c-255*(1-alpha))/alpha))) for c in (r,g,b))
        pixels.append((*rgb, round(alpha*255)))
    else:
        pixels.append((r,g,b,255))
im.putdata(pixels)
box = im.getbbox()
im = im.crop((max(0,box[0]-8), max(0,box[1]-8), min(im.width,box[2]+8), min(im.height,box[3]+8)))
output.parent.mkdir(parents=True, exist_ok=True)
im.save(output)
print(f'{output}: {im.size}; opaque source RGB preserved')
