# AGENTS

## Status
Prototype v0.1. Active research and iteration. No automated test suite yet — validation is by visual inspection on real sprites until the algorithm stabilises.

## Layout
- `Compress Palette with Hue Shifting.lua` — single Lua entry point.
- `docs/design.md` — synthesised algorithm design.
- `research/` — four standalone research reports (OKLab, hue shifting, existing implementations, ramp detection). Treat as source of truth for algorithm decisions.
- `spikes/` — reserved for throwaway Python or Lua experiments. Empty in v0.1.

## Conventions
- Single `.lua` file at folder root; mirrors `Decompress to True-Scale`.
- `DEFAULT_CONFIG` table at the top; CLI params override via `parse_cli_params`.
- `COMMAND_TITLE` and `OUTPUT_LAYER_NAME` constants.
- `app.pixelColor` aliased as `pc`.
- `fail()` helper honouring `app.params.raise_errors` for CLI/batch.
- All sprite mutations inside `app.transaction(COMMAND_TITLE, function() ... end)`.
- OKLab matrices are Ottosson's reference values (see `research/01-oklab-color-science.md` §5).

## Testing (manual, until fixtures exist)
1. Open a representative RGB sprite (varied palette, ramps, transparency).
2. Run `File > Scripts > Compress Palette with Hue Shifting`.
3. Compare the new `Compressed (Hue-Shifted)` layer to the original.
4. Inspect the palette in `Window > Palette` — ramps should be grouped by hue, dark-to-light.
5. Re-run with different `Strength`, `Ramps`, and `Stops per ramp` to verify behaviour.

CLI smoke test:

```powershell
aseprite -b ".\Tests\sample.aseprite" `
  --script-param raise_errors=true `
  --script ".\Compress Palette with Hue Shifting.lua"
```

## Known issues / follow-ups
- Indexed-mode support deferred (v0.1 rejects with a message).
- `shared_shadow` parameter declared but not wired into ramp synthesis.
- No animation-aware compression (all frames share one palette).
- Performance not yet measured on large sprites; `image:pixels()` iteration may need replacement with `image.bytes` for big sources.
- No preview mode; rely on `New layer` output for non-destructive evaluation.
