# README

Quick and dirty scripts for Aseprite written in Lua, built to make pixel art easier to export, scale, and clean up.

I designed these scripts in regards to my own workflows for running pixel art ttrpg campaigns in FoundryVTT but I found them becoming generically useful so I've decided to open source them.

## Scripts

### Export For FoundryVTT

Exports PNG files beside source file for each frame of every non-empty slice in a saved sprite. If no slices exist, it exports the full sprite instead. Background layers are ignored. Supports custom output names, optional 10x nearest-neighbour upscaling, optional white outline, and 4-way or 8-way outline mode. Outline is applied inside exact export bounds, so tightly cropped slices can clip the outline.

Run it from `File > Scripts > Export For FoundryVTT`, or from CLI with `--script` and `--script-param`:

```text
aseprite -b ".\token.aseprite" --script ".\Export For FoundryVTT\Export For FoundryVTT.lua"
aseprite -b ".\token.aseprite" --script-param name=Goblin --script-param outline=8-way --script-param upscale=false --script-param whiteOutline=true --script-param quiet=true --script ".\Export For FoundryVTT\Export For FoundryVTT.lua"
```

### Decompress to True-Scale

Downscales compressed token art back toward true scale inside Aseprite. It works on current sprite, processes all frames, and replaces sprite contents with a new output layer at detected target size.

Run it from `File > Scripts > Decompress to True-Scale V5`, leave **Colours** at its default if you want current frame colour count, then click **Snap**.

```text
aseprite -b ".\token.aseprite" --script ".\Decompress to True-Scale\Decompress to True-Scale.lua"
aseprite -b ".\token.aseprite" --script-param kColors=4 --script-param raise_errors=true --script ".\Decompress to True-Scale\Decompress to True-Scale.lua"
```

### Import PDN to Aseprite

Imports a Paint.NET `.pdn` file into a new Aseprite sprite while preserving supported bitmap layers, names, visibility, opacity, and blend modes that Aseprite can represent directly.

Run it from `File > Scripts > Import PDN to Aseprite`, choose a `.pdn` file, and the script will build a new RGB sprite. Unsupported Paint.NET layer types are skipped with a warning. Unsupported Paint.NET blend modes fall back to **Normal** and are noted on the imported layer.

## Installation

Clone repo, then symlink or copy the script or folder you want into Aseprite's scripts folder:

- Windows: `%APPDATA%\Aseprite\scripts`
- macOS: `~/Library/Application Support/Aseprite/scripts`
- Linux: `~/.config/aseprite/scripts`

After that, run `File > Scripts > Rescan Scripts`, or restart Aseprite.

## Archived Gists

These scripts were originally published as individual GitHub Gists:

- **Decompress to True-Scale:** https://gist.github.com/fb2aaa86d2701e4e5cb20767b3c80cb7
- **Export For FoundryVTT:** https://gist.github.com/bc42a9748dc73beaa14b708774acf5db
- **Import PDN to Aseprite:** https://gist.github.com/HaydenReeve/d1f75e4bb4aa9d38c1fc86c592976ae2
