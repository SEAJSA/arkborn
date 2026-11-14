# arkborn — notes for Claude

- Purpose: endless RTS game (AoE2 feel, emergent civilizations, Long Winters, rebirth).
  Source of truth for design: the GDD at https://claude.ai/artifact/NUxdkpymsE3VsiZzYGAQd4
- Engine: Godot 4.7 (owner's install). How to run/test from a shell:
  `godot --headless --path . --import`, then `godot --headless --path . --script res://tests/test_sim.gd`
  (must print PASS; ~30 s). Visual check: `godot --path . -- --demo` plays a scripted opening at 4x;
  `--demo-ui`, `--demo-place`, `--skip-minutes=N`, `--reveal`, `--watch-ai` help reach specific scenes.
- Untyped `game` references: never use `:=` on values from them (Godot can't infer the type); declare the type.
- Owner is new to game development (strong networking/IT background). Explain Godot
  concepts briefly when introducing them; keep each change runnable.
- Architecture rules (do not break):
  - `src/sim/` never draws, plays sound, or touches UI. `src/presentation/` never mutates sim state directly
    (it reads state, sends commands via `game.issue()`, and drains change lists through sim methods).
  - All world changes go through commands (player, AI, future network share one path).
  - Simulation must be deterministic; real-time sim math uses integers/fixed-point, not floats.
  - Content lives in `data/*.json`, not hard-coded.
  - Save files carry a version and get migrated forward; old saves must keep loading.
- Assets: log every added art/audio file in `assets/ASSET_LOG.md` with source and license.
- Exports: make sure the export include filter covers `*.json` so data files ship.
- Milestone tracking: see the roadmap in the GDD. Milestone 1 done. Milestone 2 built in three parts
  (economy, combat, AI + fog), all done; its gate (a fun 20-minute skirmish) needs the owner's playtest.
- AI (`src/sim/ai_player.gd`) runs inside the sim on a fixed schedule and acts only through commands.
  It currently sees the whole map (no fog for AI). Tuning lives in `data/rules.json` under "ai".
- Known simplifications to revisit: units only spread apart when standing; units always draw over trees;
  no garrisoning, walls, upgrades or eras yet; defeat shows a banner (rebirth comes in Milestone 4);
  AStarGrid2D is used for paths (whole-tile results, but verify cross-platform before multiplayer).
