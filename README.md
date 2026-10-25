# Lane Brawl

A 2D side-view **5v5 MOBA with fighting-game combat** — League of Legends structure (lanes, minions, towers,
jungle, gold and levels) with Smash/Brawlhalla-style fights (combos, launchers, juggles, guard, parry, burst).
Crossplay PC + mobile is the goal. Built in **Godot 4.7, GDScript**, with all art procedural.

Playable now: a one-lane match in the middle lane — you (Blue Kael) vs a Red Kael bot (Easy/Normal/Hard, F2),
with minion waves, towers → gate → core, gold/XP/levels, respawns and jungle monsters on a seasonal map.

```bash
godot --path .                               # play
godot --path . res://scenes/training.tscn    # combat training room
tools/check.sh                               # import + tests + smoke run
```

Controls: A/D move · W/Space jump · Shift dash · J light · K heavy (W+K launcher) · U/I skills · O ult ·
L guard (tap = parry, + direction = dodge, + J = grab, + K = burst when hit) · F1 hitboxes · Enter restart.

- Code docs: [docs/README.md](docs/README.md)
- What's left: [docs/TODO.md](docs/TODO.md)
- Design prototype (HTML): `prototype/lane-brawl-demo.html`
