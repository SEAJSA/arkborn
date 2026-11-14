# Arkborn

An endless, single-player real-time strategy game with an Age of Empires II feel.
Civilizations emerge from the survivors of a forgotten colony ship and grow from the
stone age toward the stars, surviving recurring Long Winters along the way.

- Engine: Godot 4 (4.4 or newer 4.x), GDScript, Compatibility renderer
- Targets: macOS and Windows, sold on Steam
- Design document: https://claude.ai/artifact/NUxdkpymsE3VsiZzYGAQd4 (see `docs/README.md`)

## Run
Open Godot, choose **Import**, select this folder's `project.godot`, then press the
Play button (top right). First-time setup on the Mac: `docs/setup-mac.md`.

Controls in the current prototype:

| Action | Input |
| --- | --- |
| Scroll | WASD, arrow keys, or push the mouse to a screen edge |
| Pan | Middle-mouse drag, or two-finger swipe on a trackpad |
| Zoom | Mouse wheel, or pinch on a trackpad |

## Layout

    project.godot        Godot project file (open this)
    scenes/              Godot scenes; main.tscn is the entry point
    src/sim/             the simulation: world state and rules, no drawing (see its README)
    src/presentation/    drawing, camera, UI: reads sim state, never changes it
    data/                game content as JSON (terrain now; units, techs, eras later)
    assets/              art and audio; every file logged in assets/ASSET_LOG.md
    docs/                setup guide and design notes (ignored by Godot)

## Config
Copy `config.env.example` to `config.env` when keys are needed (Steam, ElevenLabs).
`config.env` is gitignored.
