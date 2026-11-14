# src/sim — the simulation

Everything that decides *what happens* in the game lives here: world state, units,
economy, combat, civilizations, saves. Rules for this folder:

- No drawing, sound, or UI code. Presentation reads sim state; it never changes it directly.
- Every change to the world arrives as a command (player, AI and, later, network all use the same path).
- Deterministic: same starting state + same commands = same result.
