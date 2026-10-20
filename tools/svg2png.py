# Renders every SVG named on the command line to a 64x64 PNG beside it (Chromium).
import sys, pathlib, base64
from playwright.sync_api import sync_playwright
paths = [pathlib.Path(p) for p in sys.argv[1:]]
with sync_playwright() as p:
    b = p.chromium.launch()
    pg = b.new_page(viewport={"width": 64, "height": 64}, device_scale_factor=1)
    for svg in paths:
        data = base64.b64encode(svg.read_bytes()).decode()
        pg.set_content(f'<html><body style="margin:0;background:transparent"><img src="data:image/svg+xml;base64,{data}" width="64" height="64" style="display:block"></body></html>')
        pg.screenshot(path=str(svg.with_suffix(".png")), omit_background=True, clip={"x":0,"y":0,"width":64,"height":64})
    b.close()
print(len(paths), "rendered")
