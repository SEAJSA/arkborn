# arkborn — notes for Claude

- Purpose: endless RTS game (AoE2 feel, emergent civilizations, Long Winters, rebirth).
  Source of truth for design: the GDD at https://claude.ai/artifact/NUxdkpymsE3VsiZzYGAQd4
- How to run/test: Godot 4.4+ opens `project.godot`. Headless check from a shell:
  `godot --headless --path . --import` then `godot --headless --path . --quit-after 120`.
- Owner is new to game development (strong networking/IT background). Explain Godot
  concepts briefly when introducing them; keep each change runnable.
- Architecture rules (do not break):
  - `src/sim/` never draws, plays sound, or touches UI. `src/presentation/` never mutates sim state directly.
  - All world changes go through commands (player, AI, future network share one path).
  - Simulation must be deterministic; real-time sim math uses integers/fixed-point, not floats.
  - Content lives in `data/*.json`, not hard-coded.
  - Save files carry a version and get migrated forward; old saves must keep loading.
- Assets: log every added art/audio file in `assets/ASSET_LOG.md` with source and license.
- Exports: make sure the export include filter covers `*.json` so data files ship.
- Milestone tracking: see the roadmap in the GDD. Current: Milestone 1 (setup).
