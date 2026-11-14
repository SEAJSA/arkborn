# Arkborn

An endless, single-player real-time strategy game with an Age of Empires II feel.
Civilizations emerge from the survivors of a forgotten colony ship and grow from the
stone age toward the stars, surviving recurring Long Winters along the way.

- Engine: Godot 4.7, GDScript, Compatibility renderer
- Targets: macOS and Windows, sold on Steam
- Design document: https://claude.ai/artifact/NUxdkpymsE3VsiZzYGAQd4 (see `docs/README.md`)

## Run
Open Godot, choose **Import**, select this folder's `project.godot`, then press the
Play button (top right). First-time setup on the Mac: `docs/setup-mac.md`.

### How to play (Milestone 2: a full skirmish)

You and a computer-controlled Rival Tribe each start with a Town Center and three
villagers on opposite sides of the map, hidden from each other by fog of war.
Build an economy, raise an army at a War Lodge, defend against the rival's attack
waves (the first comes around minute 9 to 13), and destroy every rival building
and unit to win.

| Action | Input |
| --- | --- |
| Select | Left click, or drag a box around units (Shift adds to selection) |
| Orders | Right click: a resource or your farm to gather, an enemy to attack, ground to move, a building site to help build |
| Build | Select villager(s), then a building button or hotkey; left click to place (Shift places several), right click or Esc cancels |
| Farms | Build a Farm (C) for food that lasts; its builder starts farming it. One villager per farm |
| Army | Build a War Lodge (G), then train Clubmen (Q), Slingers (E) or Runners (R) |
| Train villager | Select the Town Center (H), then Train Villager (Q) |
| Rally point | Select a Town Center or War Lodge and right click the ground or a resource |
| Next idle villager / whole army | . (period) / , (comma) |
| Center on selection | Space |
| Pause / speed | P or F3 to pause; + and - change speed |
| Scroll / pan / zoom | WASD, arrows, screen edges; middle-drag or two-finger swipe; wheel or pinch |
| Minimap | Click or drag to move the camera |
| Debug readout / reveal map | F12 / F11 |

Idle soldiers attack enemies that come into view. The Town Center shoots arrows at
nearby enemies. Clubmen are strong against buildings, Slingers fight from range,
Runners are fast scouts.

## Layout

    project.godot        Godot project file (open this)
    scenes/              Godot scenes; main.tscn is the entry point
    src/sim/             the simulation: world state and rules, no drawing (see its README)
    src/presentation/    drawing, camera, input, UI: reads sim state, sends commands
    data/                game content as JSON: terrain, resources, units, buildings, rules
    tests/               automated checks (see "Test" below)
    assets/              art and audio; every file logged in assets/ASSET_LOG.md
    docs/                setup guide and design notes (ignored by Godot)

## Test

    godot --headless --path . --script res://tests/test_sim.gd

Checks the economy, combat and a 20-minute game against the AI, and that every one
of them replays identically from the same seed (determinism). Prints PASS or FAIL.

Testing options for the game itself (after `--` on the command line):
`--demo` scripted opening at 4x, `--skip-minutes=N` fast-forward before showing,
`--reveal` no fog of war, `--watch-ai` start the camera on the AI's town.
On a Mac, `godot` is `/Applications/Godot.app/Contents/MacOS/Godot`.

## Config
Copy `config.env.example` to `config.env` when keys are needed (Steam, ElevenLabs).
`config.env` is gitignored.
