# AGENTS

All commits must be user approved and use the appropriate commit styling skills for user adherence.

All versions must be tested against all `/Tests/`, with the `.aseprite` export matching the `Pass/*.png` image.

- The `Original` images are read-only and are the source material for the tests.
- The `.aseprite` files are read-only and are used to run the tests against.
- A pass requires pixel-for-pixel match, or a match within 1-2 pixel translation offset.

## Testing

Run all tests via CLI:

```powershell
$aseprite = "C:\Program Files (x86)\Steam\steamapps\common\Aseprite\aseprite.exe"
& $aseprite -b "Tests\Test N\file.aseprite" --script-param raise_errors=true `
    --script "Decompress to True-Scale.lua" --save-as "output.png"
```

Compare output against `Tests/Test N/Pass/*.png` using PIL/numpy:

```python
from PIL import Image
import numpy as np
o = np.array(Image.open('output.png').convert('RGBA'))
e = np.array(Image.open('pass.png').convert('RGBA'))
mismatches = (o != e).any(axis=2).sum()
```

## Architecture

Two sampling paths exist in the integer sampler:

- **Regularised** — DP walker places grid cuts at profile peaks. Used when profile pitch matches run-length pitch and frame is not bottom-anchored.
- **Integer** — Binary-split offset heuristic. Used when profile is unreliable or frame is bottom-anchored.

## Documentation

- `README.md` — project overview, installation, test suite
- `docs/iteration-history.md` — scientific record of each algorithm iteration

All tests must pass in order to be considered a success.
