"""Drive Aseprite iterations: copy baseline aseprite, run wrapper, analyse output."""
import shutil, subprocess, sys
from pathlib import Path
from collections import Counter
from PIL import Image
import math

ASEPRITE = r"C:\Program Files (x86)\Steam\steamapps\common\Aseprite\Aseprite.exe"
ROOT = Path(r"D:\Aseprite\Compress Palette with Hue Shifting\Tests")
BASELINE = ROOT / "Mia Fircha Token V2 001.aseprite"
WRAPPER = ROOT / "_run_iteration.lua"
ORIG_DIR = ROOT / "Original"

def linearise(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def rgb_to_oklab(r, g, b):
    rl = linearise(r); gl = linearise(g); bl = linearise(b)
    l = 0.4122214708*rl + 0.5363325363*gl + 0.0514459929*bl
    m = 0.2119034982*rl + 0.6806995451*gl + 0.1073969566*bl
    s = 0.0883024619*rl + 0.2817188376*gl + 0.6299787005*bl
    l_ = l**(1/3); m_ = m**(1/3); s_ = s**(1/3)
    L = 0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_
    A = 1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_
    B = 0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_
    return L, A, B

def scan(folder):
    hist = Counter()
    for p in sorted(folder.glob("*.png")):
        for r,g,b,a in Image.open(p).convert("RGBA").getdata():
            if a == 0: continue
            hist[(r,g,b)] += 1
    return hist

def chroma_of(rgb):
    L,A,B = rgb_to_oklab(*rgb)
    return math.hypot(A,B), L

def summarise(label, hist, top=12):
    print(f"  {label}: {len(hist)} unique colours, {sum(hist.values())} pixels")
    rows = sorted(((chroma_of(rgb)[0], chroma_of(rgb)[1], w, rgb) for rgb, w in hist.items()), reverse=True)
    print(f"    top {top} by chroma:")
    for C,L,w,(r,g,b) in rows[:top]:
        print(f"      C={C:.3f} L={L:.3f} w={w:4d}  #{r:02X}{g:02X}{b:02X}")

def overlap(orig, comp, tol=0.04):
    """For each high-chroma original colour, find nearest compressed RGB in OKLab."""
    high = [rgb for rgb in orig if chroma_of(rgb)[0] > 0.08]
    comp_lab = [(rgb_to_oklab(*rgb), rgb) for rgb in comp]
    survived, lost = 0, []
    for rgb in high:
        L,A,B = rgb_to_oklab(*rgb)
        best = min(((L-l)**2+(A-a)**2+(B-b)**2, c) for (l,a,b), c in comp_lab)
        d = math.sqrt(best[0])
        if d <= tol:
            survived += 1
        else:
            lost.append((chroma_of(rgb)[0], rgb, d, best[1]))
    print(f"  high-chroma source colours (C>0.08): {len(high)}")
    print(f"  preserved within ΔE<={tol}: {survived}/{len(high)}")
    if lost:
        print(f"  lost (top 8 by source chroma):")
        for C, rgb, d, near in sorted(lost, reverse=True)[:8]:
            print(f"    src C={C:.3f} #{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X} -> nearest #{near[0]:02X}{near[1]:02X}{near[2]:02X} ΔE={d:.3f}")

def run_iteration(label, params):
    out = ROOT / label
    out.mkdir(exist_ok=True)
    target = out / BASELINE.name
    shutil.copy2(BASELINE, target)
    cmd = [ASEPRITE, "-b", str(target)]
    for k, v in params.items():
        cmd += ["-script-param", f"{k}={v}"]
    cmd += ["-script", str(WRAPPER)]
    print(f"\n=== {label} ===")
    print("params:", params)
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        print("STDOUT:", r.stdout[-2000:])
        print("STDERR:", r.stderr[-2000:])
        raise RuntimeError(f"Aseprite failed: {r.returncode}")
    if r.stdout.strip():
        print("STDOUT:", r.stdout.strip()[:500])
    orig_hist = scan(ORIG_DIR)
    comp_hist = scan(out)
    summarise("ORIG", orig_hist, top=8)
    summarise("COMP", comp_hist, top=12)
    overlap(orig_hist, comp_hist)

if __name__ == "__main__":
    label = sys.argv[1] if len(sys.argv) > 1 else "iter-current"
    extra = {}
    for arg in sys.argv[2:]:
        k, v = arg.split("=", 1)
        extra[k] = v
    defaults = {"target_colours": "64"}
    defaults.update(extra)
    run_iteration(label, defaults)
