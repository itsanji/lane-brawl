# Lane Brawl — code documentation

A 2D side-view 5v5 MOBA with fighting-game combat (Godot 4.7, GDScript). These docs describe every script and
function in the project. For conventions and commands see `../CLAUDE.md`; for the full game design see
`../prototype/lane-brawl-demo.html`.

| Doc | Covers |
|---|---|
| [combat.md](combat.md) | `CombatRules`, `InputFrame`, `MoveData`, `FighterData`, `Roster`, `CombatWorld`, `Minion`, `Structure`, `Monster` |
| [fighter-and-controllers.md](fighter-and-controllers.md) | `Fighter` state machine; `PlayerController`, `InputBindings`, `DummyController`, `ManualController`, `RouteFollower`, `LaneBot` |
| [game.md](game.md) | `RiftStage` (main scene), `TrainingStage`, `LaneMatch` (lane rules, economy, respawns, win) |
| [world.md](world.md) | `RiftLayout` (map, terrain, structure pads), `GroundStrip`, `SolidBlock`, `RiftRoutes` |
| [art.md](art.md) | `RiftArt`, `Painter`, parallax, palettes, particles, critters, shaders |
| [ui.md](ui.md) | `EffectsLayer`, `SkillBar`, `RiftHud`, `TrainingHud` |
| [testing-and-tools.md](testing-and-tools.md) | test harness, all suites, recording/autoplay tools |
| [TODO.md](TODO.md) | what's left: roadmap, missing features, bot work, tech debt |

## How it fits together

```
InputFrame  ←  FighterController (Player / LaneBot / Dummy / Manual / RouteFollower)
     │
     ▼
CombatWorld.step()   (60 ticks/s, deterministic, no physics engine)
  1. Fighter.read_input()      buffer presses
  2. Fighter.sim_tick()        state machine + move_body (terrain, platforms)
  3. Monster / Structure / Minion .sim_tick()
  4. _tick_shots()             homing orbs
  5. _resolve_hits()           apply_hit / _hit_monster / _hit_minion / _hit_structure
  6. _remove_dead_minions()
  7. LaneMatch.tick()          waves, gold, respawns, buffs, winner
  8. _age_effects()
     │  combat_event signal (hit, ko, minion_slain, structure_destroyed, ...)
     ▼
LaneMatch rewards · HUDs · tools · tests

Rendering (read-only): Fighter._draw, Minion/Structure/Monster._draw, EffectsLayer, RiftArt, RiftHud, SkillBar
```

Rules of thumb:
- The sim only reads `InputFrame`s and never uses `randf()` — bots have their own seeded RNG.
- Anything that moves moves in `_physics_process`/sim ticks (physics interpolation is on for 100 Hz screens).
- Place things standing on the ground at `RiftLayout.ground_y(floor, x)`.
- Anything that may be a freed minion goes through `CombatWorld.alive()`.
