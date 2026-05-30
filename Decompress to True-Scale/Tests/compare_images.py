"""Compare two PNG images pixel-by-pixel and report mismatches."""
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Installing Pillow...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow", "-q"])
    from PIL import Image


def compare_images(output_path: str, pass_path: str):
    out_img = Image.open(output_path).convert("RGBA")
    pass_img = Image.open(pass_path).convert("RGBA")

    print(f"Output: {out_img.size[0]}x{out_img.size[1]}")
    print(f"Pass:   {pass_img.size[0]}x{pass_img.size[1]}")

    if out_img.size != pass_img.size:
        print(f"SIZE MISMATCH: output={out_img.size}, pass={pass_img.size}")
        # Check offset tolerance (1-2 px)
        dw = abs(out_img.size[0] - pass_img.size[0])
        dh = abs(out_img.size[1] - pass_img.size[1])
        if dw <= 2 and dh <= 2:
            print(f"Size within 2px tolerance (dw={dw}, dh={dh}), checking overlap region")
        else:
            print("FAIL: size difference exceeds tolerance")
            return 1

    out_px = out_img.load()
    pass_px = pass_img.load()

    w = min(out_img.size[0], pass_img.size[0])
    h = min(out_img.size[1], pass_img.size[1])

    mismatches = 0
    first_mismatches = []

    for y in range(h):
        for x in range(w):
            op = out_px[x, y]
            pp = pass_px[x, y]
            if op != pp:
                mismatches += 1
                if len(first_mismatches) < 20:
                    first_mismatches.append((x, y, op, pp))

    print(f"\nTotal pixels compared: {w * h}")
    print(f"Mismatches: {mismatches}")

    if mismatches > 0:
        print(f"\nFirst mismatches (up to 20):")
        for x, y, op, pp in first_mismatches:
            print(f"  ({x},{y}): output={op} pass={pp}")
        print("\nFAIL")
        return 1
    else:
        print("\nPASS: 0 mismatches")
        return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python compare_images.py <output.png> <pass.png>")
        sys.exit(1)
    sys.exit(compare_images(sys.argv[1], sys.argv[2]))
