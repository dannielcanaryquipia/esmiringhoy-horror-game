## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
- **Scope limit:** graphify's AST does NOT parse GDScript. The graph covers only `tools/*.py` (the asset generators). For the game itself (`scripts/*.gd`), ignore graphify and use the GDScript map below / read the files directly.

---

# Esmiringhoy — Agent Orchestration (the `.opencode/` team, bridged into Claude Code)

This project is wired to the portable AI-team workspace at
`C:\Users\Danniel Canary\.opencode\`. Treat that folder as the authoritative
source of crews, skills, guides and conventions. Opus 4.8 is the **orchestrator
("god")**; it reads the guides, splits work, and either loads Skills inline or
dispatches subagents.

## Read-first guides (in `.opencode/`)
- `TEAM-GUIDE.md` — the 5 crews, full skill inventory per crew, work-splitting protocol.
- `AGENTS.md` / `CLAUDE.md` — graphify-first, skills-before-code, design-before-UI, QA-gate rules.
- `SKILLS-GUIDE.md` — 112 collections / 353 skills, indexed by project type.
- Game work leans on the **Game Dev** crew (`agent/game-dev.md`) + the `godot-*` skills.

## Crew → Claude Code mapping
OpenCode's `agent/*.md` subagents can't execute here. Reproduce each crew with
Claude Code's own primitives — the **same skills are installed in this session**
(invoke with the Skill tool) and crews become **Agent** subagents when a chunk is
big/independent:

| `.opencode` crew | Reproduce in Claude Code as | Relevant to this Godot project? |
|---|---|---|
| `ops-planning` | Opus orchestrator inline; skills `superpowers-brainstorming`, `writing-plans`, `superpowers-executing-plans` | Yes — kickoff, specs, splitting |
| `game-dev` | `Agent(subagent_type:"game-developer")` or inline skills `godot-gdscript-patterns`, `godot-scene`, `godot-tscn-format`, `godot-singleton-pattern`, `game-development-3d-games` | **Primary** — all engine/gameplay code |
| `dev-build` | inline skills `test-driven-development`, `systematic-debugging`, `ponytail`, `superpowers-verification` | Yes — non-engine code, refactors |
| `qa-review` | `Agent(subagent_type:"Explore")` for read-only audit + skills `superpowers-request-review`, `superpowers-verification`, `code-review` | Yes — the completion gate |
| `design-studio` | n/a | No — no web/UI surface (game is in-engine) |

## Model-as-god mapping (replaces `.opencode/MODEL-PLAN.md`, which lists OpenCode models)
The OpenCode free-model plan does not apply in Claude Code. Use model overrides on
the `Agent` tool instead:
- **Planning / architecture / security-sensitive / the orchestrator** → Opus (me).
- **Feature code, debugging, routine implementation** → `model: "sonnet"` subagents.
- **Routine QA sweeps, docs, mechanical passes** → `model: "haiku"` subagents.

## Work-splitting protocol (hybrid — inline by default, subagents for parallel chunks)
1. **Orient** — graphify for `tools/` Python; the GDScript map below + direct reads for the game.
2. **Brainstorm → spec → plan** (ops-planning skills) for anything multi-step.
3. **Split** by concern: engine/gameplay → game-dev; other code → dev-build; completion claims → qa-review.
4. **Dispatch**: load the crew's Skills inline; spawn an `Agent` only when a chunk is large AND independent of what I'm holding in context. Parallelize independent subagents in one message.
5. **Verify** with real output (see Godot verification below) — never claim done without it.
6. **QA gate**: `qa-review` (read-only) must pass before "done".

## Rules
- **Skills before code** — load the matching skill (engine/design/planning) before improvising. GDScript/Godot APIs: load a `godot-*` skill first; never guess an engine API.
- **QA is a gate, not a step** — no "done" without a verification pass + evidence.
- **One crew per concern** — don't let one agent design + code + QA in a single shot.
- **Read the repo first** — this file, the brief, and neighboring files before writing (avoid duplicate scripts).

---

# Godot project conventions (authoritative for `scripts/*.gd`)
- **Engine:** Godot 4.x (project targets "4.7", Forward+). Main scene `scenes/lobby.tscn`. No Godot 3 APIs (`yield`, `instance()`, `KinematicBody`).
- **Zero warnings policy** — fix every Output/Debugger warning. Common traps here: unused params (prefix `_`), and locals/params shadowing base-class members (`size`, `look_at`, `name`, `position`, `rotation`, `scale`, `visible`). Use `look_target` not `look_at`, etc.
- **Typed GDScript** — declare types explicitly; `:=` can't infer from an untyped (Variant) receiver, so write `var t: Tween = untyped.create_tween()`.
- **Keep scripts focused**, roughly ≤400 lines; split by responsibility.
- **No downloaded assets / addons** — everything is procedural (Godot primitives, CSG, or the Python generators in `tools/`).
- **Physics layers (do not renumber):** 1 world · 2 demon blockers (moonlit patches) · 3 players · 4 demons · 5 interactables (candles) · 6 hiding spots.
- **Lessons:** doorways ≥1.4 m (demon agent radius 0.4); NavMesh cell_size/height must match `project.godot` (0.1); catch range (1.6 m) > player+demon radius; `room.gd` is `@tool` — guard runtime-only code with `if not Engine.is_editor_hint()`.

## GDScript file map (graphify can't see these — maintained by hand)
- `scripts/main.gd` — game flow: input binds, WorldEnvironment, audio, HUD wiring, demon wake timer, haunting tells, candle win, the **third-person death cinematic** (`_on_caught`).
- `scripts/room.gd` — `@tool` house builder (Ang Silid + wing + 2nd floor), furniture, **enterable hiding spots** (`_build_furniture_and_spots`), navmesh bake.
- `scripts/player.gd` — CharacterBody3D FPS: move/look/sprint/flashlight/battery, candle lighting, **hiding + breath + footstep noise**, death-cinematic camera.
- `scripts/demon.gd` — AI state machine: DORMANT/LURK/INVESTIGATE/HUNT/FROZEN/STUTTER/CATCH/BANISHED, senses, **hearing (`hear_noise`)**, spot-checking.
- `scripts/demon_body.gd` — procedural demon rig + animation (walk, catch, **eat** pose).
- `scripts/player_body.gd` — survivor body shown only in the death cinematic (`set_death`).
- `scripts/hiding_spot.gd` — `Area3D` hide trigger (cam_pos/look_target, occupied).
- `scripts/candle.gd` · `hud.gd` · `pickup.gd` · `pause.gd` · `lobby.gd` — ritual candle, HUD, battery pickup, pause menu, title.

## Verification (Godot not on PATH here — ask for the `.exe` path, or run yourself)
```
godot --headless --import                 # import assets, catch parse errors
godot --headless --quit-after 10          # boot ~10 s, watch for errors/warnings
```
Use `Godot_v4.x-stable_win64_console.exe` so Output appears in the terminal.
