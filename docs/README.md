# Arkborn design notes

The living Game Design Document is a Claude doc:
https://claude.ai/artifact/NUxdkpymsE3VsiZzYGAQd4

It is the source of truth. This file only records decisions so the repo stands on its own.

## Locked decisions (Nov 2026)

| Decision | Choice |
| --- | --- |
| Title | Arkborn (formal trademark check still needed before the Steam page) |
| Setting | The Forgotten Colony, with recurring Long Winter cataclysms |
| Mode | Single-player first; architecture kept multiplayer-ready (deterministic lockstep) |
| World | One fixed giant map, dozens of emergent tribes and nations |
| Pace | Real-time throughout, with pause and speed controls |
| Defeat | No game over: collapse leads to rebirth as a successor people |
| Platforms | macOS and Windows on Steam; developed on a Mac |
| Engine | Godot 4, GDScript |
| Art and audio | Free AI tools for simple assets; ElevenLabs for detailed audio |
| Pace of work | About 10 hours a week; Early Access estimate 12 to 18 months |

## Milestones

1. Setup: Godot, Git, GitHub; scrolling isometric map runs. **(done)**
2. Core RTS prototype, in three parts: **(built; gate = playtest)**
    1. Economy: gather, carry, build, houses, farms and population, train villagers, AoE2-style UI. **(done)**
    2. Combat: War Lodge, Clubman / Slinger / Runner, health and armor, Town Center arrows. **(done)**
    3. Opponent: an AI tribe that builds, farms, trains and attacks in waves; fog of war. **(done)**
    Gate: a 20-minute skirmish against the AI is fun with placeholder art.
3. Endless engine: traits, languages, two-level world sim, versioned saves, first winter.
4. Living world and art: dozens of AI civilizations, eras 1 to 3, rebirth, real art.
5. Early Access launch on Steam.
