# UI — `src/ui/`

All UI is drawn with `_draw()` (no Control scenes or textures) and only reads simulation state.

## `effects_layer.gd` — `EffectsLayer` (Node2D, world space)
- **`_process()`**: redraws every frame.
- **`_draw()`**: draws `CombatWorld.shots` (glowing orbs) and every `CombatWorld.effects` entry by kind:
  `spark` (hit sparks, big for heavy hits), `ring` (expanding rings: parry, burst, respawn, level up), `block`
  (guard flash), `dust`, `ghost` (dash afterimages), `puff` (minion/structure death smoke), `text` (floating numbers and labels).

## `skill_bar.gd` — `SkillBar` (Control)
Bottom-right ability slots for one `fighter`: Dash, S1, S2, Ult — cooldown sweeps with seconds left, a short
"ready" pulse, the meter ring and EX pips on the Ult slot. With `show_vitals` (Rift) also HP, guard, level,
gold and XP at the bottom left. `bottom_margin` moves it up (the training HUD's help text sits below it).
- **`_ready()`**, **`_process()`**: setup and per-frame redraw.
- **`_slots() -> Array`**: slot descriptions (id, key label, name, ticks left, total) from the fighter's data and cooldowns.
- **`_draw()`**: lays out the slots and vitals.
- **`_draw_slot(c, slot)`**: one round slot with icon, cooldown sweep, key label and ready pulse; Ult slot shows the meter ring and EX pips.
- **`_icon(id, c, col)`**: simple vector icon per ability.
- **`_draw_vitals(at)`**: HP bar, LV badge, gold with a diamond icon, XP bar, guard bar.
- **`_label_center(text, at, size, col)`**: centred text helper.

## `rift_hud.gd` — `RiftHud` (Control, Rift scene)
- **`_ready()`**: full-screen, ignores the mouse, sets up the serif title font, adds a `SkillBar` for the player.
- **`_process(delta)`**: tracks which band (or base sanctuary) the player is in to trigger the area title card; redraws.
- **`_draw()`**: minimap, title card, and in a match the match bar, kill feed, respawn overlay and result; the controls hint for the first 14 s.
- **`_draw_minimap(at)`**: ornate framed map (`MAP_SIZE` 340×124): bands with season glyphs, terrain lines,
  base crystals, structures, minions, monsters, fighters (KO'd hidden) and the current area name.
- **`_season_glyph(c, season, color)`**: snowflake / blossom / sun / maple leaf.
- **`_draw_title(vp)`**: Hollow Knight-style area title that fades in and out when you enter a band.
- **`_draw_match_bar(lane, vp)`**: clock, next-wave timer, team kills, structure pips per team, active buffs, "vs <difficulty> bot (F2)".
- **`_draw_feed(lane, top_right)`**: the last kill-feed lines, fading with age.
- **`_draw_respawn(vp)`**: "SLAIN — respawning in N" while the player is KO.
- **`_draw_result(lane, vp)`**: VICTORY/DEFEAT banner with the player's stats and "Press Enter".
- **`_text_center(...)`**, **`_title_center(...)`**: centred text helpers (normal / title font).

## `training_hud.gd` — `TrainingHud` (Control, training room)
- **`_ready()`**: listens to `combat_event`, adds a `SkillBar` without vitals.
- **`_process()`**: redraw.
- **`_on_combat_event(kind, info)`**: remembers the player's last move and its result (whiff / hit / counter hit / blocked / guard break / parried) and the combo stats.
- **`_draw()`**: both fighters' HP/guard/meter bars, combo counter, frame data of your last move, dummy mode, and the two help lines.
- **`_bar(at, size, fill, color)`**: one bar.
