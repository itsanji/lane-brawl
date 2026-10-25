# What we still have to do

Status on 2026-10-25: one playable lane (Blue Kael vs a Red Kael `LaneBot`), full map art, jungle monsters,
66 tests passing. The full design is in `prototype/lane-brawl-demo.html`.

## Next up (roadmap 5a)
- [ ] **Shop** — spend gold in the base (prototype: 8 items, 3 slots: damage, health, guard regen, meter gain,
      move speed, cooldown reduction, lifesteal, armor). Open with B / a tap. Bots buy too.
- [ ] **Sound** — hit/block/parry/guard-break sounds, swings, dash, jump/land, tower shots, minion deaths,
      structure destruction, level up, KO, UI ticks; ambient loop per season; music. Must stay out of the sim (listen to `combat_event`).
- [ ] **Other two lanes** — run waves and structure chains in the upper and lower lanes too (`LaneMatch` is
      single-lane today: `LANE`, `_chain`, `spawn_wave`, structure pads in `RiftLayout.ground_offset` only on floor 2).
- [ ] **Jungle routes for bots** — bots use `RiftRoutes.plan` + `RouteFollower` to move between lanes and clear camps; take Wyrm/Titan.

## Later roadmap
- [ ] **3c Per-fighter looks** for the other 4 fighters (silhouette, mask, weapon, colours).
- [ ] **4 Touch controls + Android export**: virtual stick + buttons; port the other 4 fighters from the prototype:
  - Vex (Hunter, assassin): blink behind target, dive kick, execute mark.
  - Lyra (Mid, zoner): straight and arcing projectiles, screen beam — needs a fighter projectile system.
  - Rook (Carry, marksman): ranged lights, piercing shot, backflip, arrow rain.
  - Juno (Support): tether, ally shield, team heal pulse + meter.
- [ ] **6 Online 1v1**: headless Godot server running `CombatWorld`, client prediction (maybe rollback — the sim is already deterministic and input-driven).
- [ ] **7 5v5 vertical slice**: full map, 10 fighters, Nakama matchmaking.

## Game features from the design not built yet
- [ ] Level-up skill upgrades at levels 3, 6, 9 (pick 1 of 2, no pause).
- [ ] Recall (hold Down + Guard 3 s).
- [ ] Kill-streak bounties (3+ kills).
- [ ] 10-minute match limit (more structures destroyed wins on time).
- [ ] Core vulnerable only after an enemy **gate** falls in *any* lane (today: the single chain).
- [ ] Objective spawn timers (Wyrm at 2:00 and respawning, Titan at 5:00) and HUD timers for them.
- [ ] Role AI: hunter (camp loop, ganks), support (stays with carry), grouping for objectives, defending the core.
- [ ] Screens: title (difficulty), fighter select, how-to-play, result screen with full stats (K/D/A, CS, gold, damage dealt).
- [ ] Gamepad-aware and touch-aware key labels in `SkillBar` (they're keyboard letters now).
- [ ] Pause / settings menu (volume, key rebinding).

## Bot (`LaneBot`) improvements
- [ ] Hard isn't clearly stronger than Normal (similar hit counts in bot-vs-bot dry runs): sharper spacing,
      whiff punishing, better combo choice, use EX skills and burst baits.
- [ ] Bots rarely get kills on each other (both retreat in time) — fine vs humans, but add trades/zoning that create kill chances.
- [ ] Use dodge outside of ults, use guard-break pressure, tech chases after knockdowns.
- [ ] Recall instead of walking home once recall exists; buy items once the shop exists.
- [ ] Read structures through a public `LaneMatch` accessor instead of the private `lane._chain`.

## Tech debt / small fixes
- [ ] `rift_stage.gd` `step()` (sandbox only) refills HP from `data.max_hp` instead of `max_hp()`.
- [ ] Tower/minion numbers live in `structure.gd` (`85`, `115`, `+6%/min`) and `combat_world.gd`
      (minion chip 25%, structure ×1.6) — move them into `CombatRules`.
- [ ] Monsters: no `alive()`-style safety needed yet, but if monsters ever get freed, route references through `CombatWorld.alive()` like minions.
- [ ] `LaneBot` `_plan` and `_chain` are read by tools (`autoplay.gd`) — make small public getters.
- [ ] Godot app-menu icon (Linux desktop entry) shows the default icon; `icon.svg` was changed but the launcher icon isn't wired up.
- [ ] Performance check with 10 fighters and ~30 minions on screen (target steady 60 fps, also on mobile).

## How to work on it
- Run `tools/check.sh` after every change; add a test for every new mechanic (`tests/`).
- Read `docs/README.md` for where things live, and `CLAUDE.md` for conventions and the PC-memory rules for rendering.
