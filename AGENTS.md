# AGENTS

## Commit Standard

All commits must use the `git-commit-standards` skill. Commits require user approval before pushing.

## Structure

```
├── Decompress to True-Scale/   # Mixel decompression script (V5)
│   ├── Tests/                  # 7 test cases with pass images
│   ├── docs/                   # Research notes
│   ├── AGENTS.md               # Script-specific testing instructions
│   ├── CHANGELOG.md            # Version history
│   └── README.md               # Script documentation
├── Export For FoundryVTT/      # FoundryVTT export script
├── Import PDN to Aseprite/     # Paint.NET importer script
├── .gitignore
└── README.md                   # Project overview
```

## Maintenance

- Each script lives in its own folder with a single `.lua` entry point.
- Scripts are symlinked into `%APPDATA%\Aseprite\scripts` for development.
- Test artifacts (output PNGs, trace files) are gitignored.
