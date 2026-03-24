# RPG Board Game Prototype

This workspace currently contains:

- [RPG_BOARD_GAME_PLAN.md](./RPG_BOARD_GAME_PLAN.md): high-level vision and product plan
- [V1_RULES_SPEC.md](./V1_RULES_SPEC.md): concrete v1 rules and first-pass numbers
- `data/`: editable balance and content definitions
- `scenes/`: Godot scenes
- `scripts/`: Godot scripts

## Structure

```text
data/
  balance/
  content/
scenes/
  main/
scripts/
  core/
  main/
```

## Editing Guide

- Change rules and balance values in `data/balance/`
- Change origins, skills, items, mobs, bosses, and cell definitions in `data/content/`
- Add scenes and UI under `scenes/`
- Add gameplay code under `scripts/`

## Suggested Next Build Order

1. Implement the board graph model
2. Implement turn state and travel die movement
3. Implement combat resolution
4. Implement cell resolution
5. Implement property claim, upgrades, and raids
6. Add world phase, mobs, and boss encounters
7. Add multiplayer authority and autosave/restore

