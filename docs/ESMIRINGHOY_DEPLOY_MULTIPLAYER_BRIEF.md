# ESMIRINGHOY — Deploy & Multiplayer Brief for Claude Code

> **How to use this file**
> 1. Put it in the project as `docs/ESMIRINGHOY_DEPLOY_MULTIPLAYER_BRIEF.md`, next to `docs/ESMIRINGHOY_GAMEPLAY_BRIEF.md`.
> 2. Also save the story doc (exported as Markdown) as `docs/ESMIRINGHOY_STORY.md`. The lobby and credits use its names and text.
> 3. Open a terminal in the project folder, start Claude Code and send:
>    **"Read docs/ESMIRINGHOY_DEPLOY_MULTIPLAYER_BRIEF.md and docs/ESMIRINGHOY_STORY.md completely, then do Section 12 (First steps)."**

---

## 0. Role and rules

You are the release and network engineer for **Esmiringhoy**, a first-person co-op horror game made with **Godot 4** and **GDScript**. Your job:

1. Make the game **buildable and shippable**: export presets, a one-command build, and a one-command upload to **itch.io** with **butler**.
2. Make **Host / Join** genuinely usable over the internet: a proper **lobby**, **UPnP** automatic port opening, and **room codes through noray** (NAT punch-through with relay fallback), so friends can play without port-forwarding.

Rules (same as the gameplay brief):

- **Read the whole project first.** It may already contain host/join code added earlier. Audit and extend it; don't duplicate it.
- **Check the Godot version** (`godot --version`, or ask me for the path to my Godot `.exe` on Windows). Only use APIs from that version.
- **Work in phases (Section 10).** Stop after each phase with: what changed, how to test it (a step-by-step checklist), automated test results, and open questions. Wait for me to say "continue".
- **Zero GDScript warnings**, typed GDScript, no file over ~400 lines.
- **Third-party code:** the only allowed addon is **netfox.noray** (MIT, from the Godot Asset Library or the foxssake/netfox GitHub releases), and only in the noray phase. If it doesn't fit our Godot version, implement the small noray client protocol yourself instead. Ask me before adding anything else.
- **Never put secrets in the repo** (butler API key, server passwords). Use environment variables and `.gitignore`.
- **The game's web build is out of scope.** Browsers can't run ENet, and the web renderer drops volumetric fog. We ship **Windows** (required) and **Linux** (optional) downloads.
- **Content tone** is as in the gameplay brief: dread and suspense, no sexual content, no gore.

---

## 1. Context

- Engine: **Godot 4** (Forward+ renderer, volumetric fog), language **GDScript**.
- Development tools used on this project: **OpenCode**, **Freebuff** and **Claude Code** (AI-assisted development). These are credited in-game and on the store page (Section 3.4 and Section 4.3).
- The story, characters and lines are in `docs/ESMIRINGHOY_STORY.md`. The six playable cousins are **Ana, Isko, Mara, Bea, Tess and Paolo**. Solo play is always Ana.
- Gameplay systems are described in `docs/ESMIRINGHOY_GAMEPLAY_BRIEF.md` (Section 11.6: route all game-state changes through `GameState` so they can become host-authoritative). Follow that.
- The original multiplayer concept: **1–6 players**. One Esmiringhoy (AI-controlled, run by the host) hunts everyone. **Caught players become lesser demons ("anak")** and hunt their cousins. Survivors win by finishing the rite, which frees every turned cousin. Everyone caught = the Turned ending.
- A trailer recorder exists in `trailer/` (Movie Maker scene). It must not ship in the build.

---

## 2. Phase A: Export presets and the build pipeline

### 2.1 Export templates
- Check whether export templates for the exact Godot version are installed. If not, tell me to install them (**Editor → Manage Export Templates → Download and Install**). Don't try to download them yourself.

### 2.2 `export_presets.cfg`
Create (or fix) presets:

| Preset name | Platform | Output | Notes |
|---|---|---|---|
| `Windows Desktop` | Windows x86_64 | `build/windows/Esmiringhoy.exe` | **Embed PCK = on** (single exe). Product name "Esmiringhoy", company/author from me, file and product version from `project.godot`. Icon from `assets/ui/icon.ico` (create it: Section 2.4) |
| `Linux` | Linux x86_64 | `build/linux/Esmiringhoy.x86_64` | Embed PCK on |

For both presets:
- **Export filter: exclude** `trailer/*, tests/*, docs/*, tools/*, server/*, build/*, *.md, *.py`.
- Debug symbols off for release, texture format **S3TC/BPTC** (desktop).
- The `.gdignore` files in `docs/` and `tools/` stay.

### 2.3 Versioning
- Add `application/config/version="0.1.0"` to `project.godot`. Single source of truth.
- Show the version small in the corner of the title screen (`v0.1.0`) and in the pause menu.
- Write it to `build/version.txt` during the build (butler reads it, Section 3).

### 2.4 Icon and branding
- Generate an original app icon with Python (`tools/gen_icon.py`): the ember-cracked horned silhouette on black, at 16, 32, 48, 64, 128 and 256 px → `assets/ui/icon.ico` + `icon.png` (set `application/config/icon`).
- Boot splash: black background with the ESMIRINGHOY wordmark in ember orange (`application/boot_splash/*`). Keep it short.

### 2.5 License compliance
Godot is MIT licensed, and shipped games **must include Godot's license notice**:
- Add a **Credits** screen (from the title menu) and a `LICENSE_THIRD_PARTY.txt` packed into the build output folder, containing the Godot Engine copyright and license (use `Engine.get_license_text()` and `Engine.get_copyright_info()` at runtime for the in-game screen) and the netfox license if used.

### 2.6 One-command build
Create `tools/build.ps1` (Windows PowerShell, my main machine) and `tools/build.sh` (Linux/macOS), which:
1. Read the version from `project.godot`.
2. Run `godot --headless --path . --export-release "Windows Desktop" build/windows/Esmiringhoy.exe` (and Linux if `-Linux` / `--linux` is passed).
3. Copy `LICENSE_THIRD_PARTY.txt` and a short `README.txt` (controls, how to host/join, troubleshooting) into each build folder.
4. Write `build/version.txt`.
5. Print the output sizes and fail loudly on any export error.

The Godot executable path comes from the env var `GODOT_BIN` (fallback `godot`). Document this.

**Acceptance (Phase A):** `tools/build.ps1` produces `build/windows/Esmiringhoy.exe` that launches on Windows, shows the title screen with the version, plays solo end-to-end, and contains no trailer/test/doc files (verify by listing the PCK contents or checking the exe size before/after the filters).

---

## 3. Phase B: itch.io release with butler

### 3.1 What I do by hand (give me a checklist; you can't do these)
1. Create the itch.io project: **Kind of project = Downloadable**, title "Esmiringhoy", URL slug `esmiringhoy`, Classification: Games, Genre: **Survival** + **Horror**.
2. Install **butler** (from the itch app, or the standalone download on itch.io) and run `butler login` once.
3. Set visibility to **Draft** or **Restricted** until we launch.

### 3.2 `tools/deploy_itch.ps1` and `tools/deploy_itch.sh`
- Params: itch user (default from env `ITCH_USER`), game slug (default `esmiringhoy`), `-Channel` suffix (default stable; `-Beta` → `windows-beta`).
- Run the build script first unless `-SkipBuild`.
- Push:
  ```
  butler push build/windows  <user>/esmiringhoy:windows  --userversion-file build/version.txt
  butler push build/linux    <user>/esmiringhoy:linux    --userversion-file build/version.txt   (if built)
  ```
  Channel names containing `windows` / `linux` get platform-tagged automatically by itch.io.
- Afterwards run `butler status <user>/esmiringhoy` and print the result.
- For CI later: support the `BUTLER_API_KEY` environment variable (never write it to disk). Optionally add a GitHub Actions workflow in `.github/workflows/release.yml` that builds on tag push with the official Godot headless binary + templates and pushes with butler. Make it **opt-in** and document the secret to add.

### 3.3 Store page kit: `docs/ITCH_PAGE.md`
Produce copy-paste-ready content:
- **Short description** (one line, ≤ 120 characters).
- **Full description** built from the story's store blurb (`docs/ESMIRINGHOY_STORY.md`, "Store-page blurb"), plus **Features** (bullets: 1–6 co-op, hide-and-seek AI that learns, flashlight that saves and betrays you, Filipino ancestral house, caught players become hunters, four endings), **Controls**, **How to play together** (Section 7.4 text), **System requirements** (Windows 10/11 64-bit, a Vulkan-capable GPU, e.g. GTX 1050 / RX 560 or better; 4 GB RAM; ~300 MB disk; measure the real build size), and **Credits**.
- **Tags** (up to 10): horror, co-op, multiplayer, first-person, survival-horror, psychological-horror, atmospheric, folklore, 3d, godot.
- **Screenshot list:** 5 shots with captions. Re-use or extend the trailer scene to render them at 1920×1080 (Movie Maker or `get_viewport().get_texture().get_image().save_png()`), and a **cover image 630×500** with the title.
- **Trailer:** reference `trailer/README.txt` (record → ffmpeg → upload to YouTube → paste the link in the itch page's video field).
- **AI disclosure:** itch.io lets every project tag whether it uses generative AI (it is mandatory for asset pages, optional for games). Draft an honest disclosure line for me to confirm, e.g.: *"Code was written with AI-assisted development tools (OpenCode, Freebuff, Claude Code). Textures and sounds were generated procedurally by scripts in the project."* I'll choose the final wording and the tag setting.

### 3.4 In-game credits screen
```
ESMIRINGHOY
Created by Danniel Canary Quipia      ← confirm the exact credit name with me
Made with Godot Engine — GDScript
Development tools: OpenCode · Freebuff · Claude Code
Godot Engine license notice …         (Section 2.5)
```

**Acceptance (Phase B):** a dry run (`-WhatIf` / `--dry-run` flag prints the butler commands without running them) works; `docs/ITCH_PAGE.md` is complete; screenshots and the cover image exist in `build/press/`.

---

## 4. Network architecture (applies to Phases C–F)

### 4.1 Model
- **Host-authoritative peer-hosted ENet.** One player hosts (server + plays); the others are clients. No dedicated server for now.
- Port: default **UDP 27777** (configurable in Settings).
- Max players **6**.
- **The host decides everything that matters:** the demon AI, catches, turning, hiding-spot checks, candle and ritual state, item pickups, puzzle results, endings. Clients send **requests** (RPCs) and render the results.
- Clients own **their own movement and look** (client-authoritative position with server sanity checks: speed clamp, no teleporting through walls; snap back if violated). This keeps movement responsive on high-latency connections, which is common between home connections.

### 4.2 Autoload: `Net` (`scripts/net/net.gd`)
Responsibilities:
- `host(port := 27777) -> Error`, `join(address: String, port := 27777) -> Error`, `host_with_code()`, `join_with_code(code: String)` (Phase F), `leave()`.
- Signals: `hosting_started`, `joined`, `join_failed(reason: String)`, `player_joined(peer_id)`, `player_left(peer_id)`, `connection_lost(reason)`, `lobby_changed`.
- Keeps `players: Dictionary` (peer_id → `{name, cousin, ready, state: "survivor"|"anak"|"spectator", ping}`), synced from the host.
- Handles `multiplayer.peer_disconnected`, `server_disconnected`, `connection_failed` with clear messages ("The host left the game." / "Couldn't reach the host. Check the code or IP." / "The game is full.").
- **Version check on join:** the client sends its game version; the host rejects mismatches with "Version mismatch: host is v0.2.0, you have v0.1.0."
- **Join timeout:** 10 s.

### 4.3 What gets synchronized

| Thing | Authority | How |
|---|---|---|
| Player body position, yaw, head pitch, crouch | Owning client | `MultiplayerSynchronizer` (unreliable, ~20 Hz) + interpolation on others |
| Flashlight on/off, battery %, aim | Owning client (on/off), host validates battery | Synced property; others see the beam |
| Hidden in a spot / which spot | Host | Client requests enter/exit by RPC; host confirms; hidden players are invisible to others except the head-poke view |
| Survivor / anak state | Host | RPC `turn_player(peer_id)` broadcast; the turned player gets the lesser demon body + red vision |
| The Esmiringhoy (transform, state, animation mode, eyes, flare) | Host | `MultiplayerSynchronizer`; the AI runs **only** on the host; clients play the animation from the synced mode/speed |
| Doors, candles, items, puzzles, fuse box, ritual progress | Host | Reliable RPCs → `GameState` changes → broadcast |
| Noise events | Host | Clients send `request_noise(pos, radius, source)` (the host validates distance from that player); the demon only listens on the host |
| Fear / hallucinations / music | Local only | Each client computes its own (hallucinations are deliberately different per player) |
| Death screens / ending | Host | Broadcast `end_game(ending_id, stats)` |

- Use `MultiplayerSpawner` for player characters (spawn path `World/Players`) and lesser demons.
- **Lesser demons are player-controlled** (the turned player keeps control); they can catch survivors (host validates distance ≤ 1.6 m); they're frozen by flashlights for 3.5 s.
- **Proximity voice chat is out of scope.** Note it as a future idea.

### 4.4 Solo still works
- Solo = an `OfflineMultiplayerPeer` (or just no peer) with the same code paths: the local player is the host. Never fork the gameplay code into "solo" and "online" versions.

---

## 5. Phase C: Host / Join by IP (foundation)

- Main menu: **Play Solo · Host Game · Join Game · Settings · Credits · Quit**.
- **Host Game:** starts ENet server → Lobby (Section 6).
- **Join Game:** text field for IP (and port, default 27777), a "Join" button → Lobby.
- Implement Sections 4.2–4.4.
- **Local testing:** support command-line flags after `--`: `--host`, `--join=127.0.0.1`, `--name=Tester2`, `--cousin=Isko`, `--autostart` (the host starts as soon as N players are in, for tests). Configure Godot's **Debug → Customize Run Instances** with 2–3 instances using these flags, and describe it to me.

**Acceptance (Phase C):** two instances on one PC: host + join by `127.0.0.1`, both walk around, see each other's flashlights, the demon chases and catches the client, the client turns into an anak, and the host sees it. Then the same on two PCs on the same Wi-Fi by LAN IP.

---

## 6. Phase D: The lobby

A proper pre-game room that makes hosting feel finished.

**Layout** (dark, minimal, ember accents; matches the HUD style):
- Left: **player list** (up to 6 slots): name, chosen cousin portrait (a simple generated silhouette per cousin, each a different colour accent), ping, ready ✓. Empty slots show "Waiting…".
- Centre: **cousin picker:** Ana, Isko, Mara, Bea, Tess, Paolo, each with their one-line description from the story doc. Each cousin can be taken once.
- Right: **room info:** room code (Phase F) with a **Copy** button, or "Your IP: x.x.x.x" with Copy (Phase E), plus difficulty (host only), and a **Ready** toggle.
- Bottom: **Start** (host only; enabled when everyone is ready, or the host overrides with a hold-to-start), **Leave**.
- **Lobby chat** (simple text, last 20 lines, 120 chars max, plain text only: sanitize BBCode).
- **Kick** (host only) per player.
- Players who join mid-game are refused: "Game already in progress."

**In-game:**
- Tab = scoreboard overlay: cousins, survivor/anak/hidden status (hidden shows as "?" to others), ping.
- When the host leaves: everyone returns to the menu with "The host left the game." (No host migration.)
- When a client disconnects mid-game: their character drops its flashlight and becomes an empty husk (or simply vanishes). The game continues.
- **Spectating:** if every remaining survivor is gone except one and they're in a hiding spot, dead/turned players **can't** see them (no ghosting). Turned players are still playing as anak anyway.

**Acceptance (Phase D):** 3 instances: join, pick distinct cousins (blocked from duplicates), chat, ready up, the host starts, everyone loads into the house at their act-1 wake-up spots (story: each cousin wakes in a different room), and kick works.

---

## 7. Phase E: UPnP (automatic port opening)

When hosting by IP:
1. On a **background `Thread`** (UPnP discovery blocks for seconds), run `UPNP.discover()`; if a valid gateway is found, `add_port_mapping(port, port, "Esmiringhoy", "UDP")`, then `query_external_address()`.
2. In the lobby show: **"Internet: ready, your address is 203.0.113.5:27777 [Copy]"**, or on failure **"Internet: couldn't open the port automatically. Friends on the same Wi-Fi can still join; for internet play use a room code (recommended) or see Help."**
3. **Remove the mapping** (`delete_port_mapping`) when hosting stops and on quit (`NOTIFICATION_WM_CLOSE_REQUEST`).
4. **Detect CGNAT:** if the router's external address is in `100.64.0.0/10` or another private range, warn "Your internet provider uses CGNAT; direct hosting won't work. Use a room code." Many home and mobile ISPs do this.
5. A **Help** popup for players: what UPnP is, and the alternative of a virtual LAN app (Radmin VPN / ZeroTier / Tailscale) plus joining by that app's IP.

**Acceptance (Phase E):** UPnP runs without freezing the UI; success and failure both show clear messages; the mapping is removed on exit (verify in logs).

---

## 8. Phase F: Room codes with noray (the real internet solution)

### 8.1 What noray does
**noray** is an open-source server (by foxssake, MIT) that helps two players behind routers connect: it orchestrates **NAT punch-through**, and if that fails it **relays** the traffic. The **netfox.noray** Godot addon wraps it. Flow from its docs:

**Host:**
1. `Noray.connect_to_host(NORAY_ADDRESS, 8890)`
2. `Noray.register_host()` → await `Noray.on_pid` (the host also receives its public **OpenID**, `oid`, via `on_oid`)
3. `await Noray.register_remote()` (sets `Noray.local_port`)
4. Start the ENet server **on `Noray.local_port`**
5. Handle `Noray.on_connect_nat` / `Noray.on_connect_relay` (address, port) by running the netfox `PacketHandshake.over_enet(...)` toward that client

**Client:**
1. Connect + `register_host()` + `register_remote()` the same way
2. Get the host's **OpenID** (the room code). noray itself doesn't share it, so we show and copy it in the lobby.
3. `Noray.connect_nat(oid)`; on failure / timeout (5 s) fall back to `Noray.connect_relay(oid)`
4. In `on_connect_nat` / `on_connect_relay`: bind a `PacketPeerUDP` to `Noray.local_port`, run `PacketHandshake.over_packet_peer(udp)`, close it, then `ENetMultiplayerPeer.create_client(address, port, 0, 0, 0, Noray.local_port)`

Never show or send the **PrivateID** (pid). It's a secret.

Verify every call name against the addon version you install; adapt if the API differs.

### 8.2 Room code UX
- **Host Game → "Online (room code)"** (default) or "LAN / IP".
- The lobby shows **ROOM CODE: `<oid>` [Copy]**. If the OpenID is long, show it in a monospace box and make **Copy** the main action (players paste it into Messenger or Discord). If you can, also show a short 6-character display code derived from it, but joining must use the full OpenID unless we add our own code lookup (don't build a lookup service in this phase; note it as an option).
- **Join Game → "Room code"** field (paste-friendly, trims spaces), **Join**.
- Status text during connect: "Contacting matchmaker… → Finding host… → Connecting directly… → Using relay (slower)… → Connected!" Show **"Relay"** in the scoreboard ping column for relayed players.
- If the noray server is unreachable: "Online service is offline. Try LAN / IP or a virtual LAN app."

### 8.3 Server config
- The noray address and port come from `res://config/net.cfg` (`ConfigFile`), so I can change servers without code changes:
  ```
  [noray]
  host="noray.example.com"
  port=8890
  ```
- Also allow an override in Settings (an "Advanced" section) for testing.

### 8.4 Deploying the noray server (`server/noray/`)
Create, but don't run on my behalf:
- `server/noray/docker-compose.yml` using the prebuilt image `ghcr.io/foxssake/noray:main` with ports:
  - `8890/tcp`: registration and connection requests
  - `8891/tcp`: metrics (HTTP; firewall it or bind it to localhost)
  - `8809/udp`: remote port registrar
  - `49152-51200/udp`: relay range
- `server/noray/.env.example` based on the noray repo's `.env.example` (check the current variable names in the repo; don't invent them).
- `server/noray/README.md` for me: rent a small Linux VPS (1 vCPU / 1 GB is plenty to start), **choose a region close to the players** (for the Philippines and Southeast Asia, Singapore), install Docker, open the ports above in the provider firewall **and** `ufw`, `docker compose up -d`, point a domain/subdomain at it (optional), and test with the game's "Online" mode. Also how to read logs (`docker compose logs -f`) and update the image.
- Estimate monthly costs in the README as a range and tell me to check current prices; don't quote exact prices as fact.

**Acceptance (Phase F):** with a noray server running (locally via Docker for testing: `127.0.0.1`), host-by-code and join-by-code work between two instances; forcing NAT to fail (a debug flag that skips `connect_nat`) falls back to relay and still plays; a wrong code gives a clear error within 10 s.

---

## 9. Testing (throughout)

- **Headless network tests** (`tests/net/`): launch a headless host and a headless client as separate processes with the CLI flags from Phase C; the client auto-joins, the host auto-starts, and a test script asserts that: the player count is 2, a host RPC reaches the client, a client request is rejected when invalid (e.g. lighting a candle from 10 m away), and disconnect handling works. Print `PASS`/`FAIL`, exit code 1 on failure.
- **Manual playtest checklist** per phase (as in the gameplay brief).
- **Latency simulation:** a debug setting that delays all incoming packets by 150 ms ± 50 ms jitter (implement in `Net` by queueing; debug builds only) to check that movement stays smooth and catches feel fair.
- **Release checklist** (`docs/RELEASE_CHECKLIST.md`): version bumped, build from clean, solo playthrough, 2-player online playthrough by room code, 4-player LAN test, credits/licenses present, itch page updated, trailer link, butler push, smoke-test the downloaded build from itch.

---

## 10. Phases summary

| Phase | Goal | Done when |
|---|---|---|
| **A** | Export presets, versioning, icon, licenses, `tools/build.*` | One command makes a working Windows exe |
| **B** | butler deploy scripts, itch page kit, screenshots, cover, credits screen | Dry-run push works; page kit complete |
| **C** | `Net` autoload, host/join by IP, host authority, sync | 2 instances play a full catch → anak cycle |
| **D** | Lobby: cousins, ready, chat, kick, scoreboard | 3 instances lobby → start → play |
| **E** | UPnP with clear status and cleanup | UPnP success/failure handled; no UI freeze |
| **F** | noray room codes + relay fallback + server files | Code join works; relay fallback works |

**Recommended order with the gameplay brief:** do **A + B now** (a solo build can go up on itch.io early as a demo). Do **C–F after gameplay Phases 0–3**, because the house, hiding and AI 2.0 change what needs syncing.

---

## 11. Don't

- Don't ship a web/HTML5 build of this game.
- Don't hard-code IPs, server addresses or keys.
- Don't run the demon AI on clients.
- Don't trust clients for catches, items, candles or endings.
- Don't block the main thread on UPnP or network connects.
- Don't add accounts, analytics, telemetry or ads.
- Don't push to itch.io yourself; I run the deploy script.

---

## 12. First steps

1. Read the project, both briefs and the story doc.
2. Run `godot --version` and the headless import; report errors or warnings.
3. Tell me: what (if any) networking code exists now, whether export templates are installed, and your plan for Phase A in 5–8 bullets.
4. Ask me at most 5 blocking questions (for example: my itch.io username, the exact credit name, whether to include Linux).
5. Wait for my answers, then start **Phase A**.
