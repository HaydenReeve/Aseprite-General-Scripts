# AGENTS

All versions must be tested against all `Tests/` folders before committing. The `.aseprite` source must produce output matching `Pass/*.png` pixel-for-pixel (or within 1-2px translation offset).

## Test Fixtures

- `*.aseprite` — source files (read-only)
- `*Original*.png` — exported source PNGs for Python prototype (read-only)
- `Pass/*.png` — expected correct output (read-only)
- `Tests/compare_images.py` — pixel comparison utility (exit 0 = pass)
- `Tests/content_anchored.py` — Python reference implementation

## Running Tests

```powershell
$aseprite = "<path-to-aseprite>\aseprite.exe"
Start-Process -FilePath $aseprite -ArgumentList "-b `"Tests\Test N\file.aseprite`" --script `"Decompress to True-Scale.lua`"" -Wait -NoNewWindow
python Tests\compare_images.py "Tests\Test N\file Output.png" "Tests\Test N\Pass\expected.png"
```

## Architecture

Sampling paths in priority order:

1. **Content-anchored elastic grid** — detects opaque bbox, row transitions, derives compression ratio, anchors output grid using centre-based positioning. Majority-vote resampling with 30% opaque threshold.
2. **Elastic grid** — fallback when content-anchored fails. Transition-based boundaries with majority vote.
3. **Regularised DP walker** — used when profile pitch matches run-length pitch and frame is not bottom-anchored.
4. **Split point sampling** — last resort. Binary-split offset heuristic with repair pass.
