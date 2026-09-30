# 10 — Research Notes (sourced)

Every non-obvious claim the design depends on, with a source and a date. **Re-verify
before relying on anything here.** The Roblox platform moved substantially between
RDC 2025 and RDC 2026 and will move again.

Research performed: **2026-09-30** (iteration 1) and **2026-10-01** (iteration 3
re-verification pass, §6).

Legend: ✅ verified against a primary source · 🟡 verified against secondary reporting ·
⚠️ announced but not shipped · ❓ unverified, treated as an assumption

---

## 1. Platform capabilities and roadmap

| # | Fact | Conf. | Source |
| --- | --- | --- | --- |
| 1.1 | A **notification system for turn-based, asynchronous multiplayer** enters Studio Beta **October 2026**, full release by end of 2026 | ✅ | [RDC 2026 newsroom](https://about.roblox.com/newsroom/2026/09/rdc-2026-the-world-needs-more-play) |
| 1.2 | The creator roadmap lists **Developer Push Notification Support** (late 2026): push for opted-in users, receiver/mentioned user no longer need to be friends, **daily send cap resets when the user visits the game**, plus an additional silent notification after the cap | ✅ | [Creator Roadmap](https://create.roblox.com/updates/roadmap) |
| 1.3 | Experience Notifications require the user to be **13+ and opted in**; cap relaxed from 1/3 days to **1 per day per user per experience** | ✅ | [Updates to Notification Rate Limits](https://devforum.roblox.com/t/updates-to-notification-rate-limits/3007106) |
| 1.4 | **Browser play in Chrome** by end of 2026; **offline solo play** early access soon, wide **mid-2027**; **Roblox Everywhere** standalone apps | ✅ | [RDC 2026 IR release](https://ir.roblox.com/news/news-details/2026/Roblox-Unveils-New-Ways-to-Play-Build-and-Grow-at-the-Roblox-Developers-Conference-RDC/default.aspx) |
| 1.5 | Engine gains **orthographic camera**, **animated image containers**, **direct sprite-sheet import**, and UI **blur / text shadows / improved gradients** | ✅ | [RDC 2026 IR release](https://ir.roblox.com/news/news-details/2026/Roblox-Unveils-New-Ways-to-Play-Build-and-Grow-at-the-Roblox-Developers-Conference-RDC/default.aspx) |
| 1.6 | **Scene Generator** (prompt + reference image → functional editable layout) arriving "later this year" in Build and Studio | ⚠️ | same |
| 1.7 | **Build** (mobile prompt-to-game) in public alpha in NZ, Serbia, Singapore; **~9 000 games published**; **71%** of Build creators had never used Studio | ✅ | same |
| 1.8 | **Roblox Wallet**: daily real-currency payouts, US 18+ creators, later 2026; Roblox Card 2027; >$5 bn DevEx lifetime, ~$1.7 bn in the last 12 months | ✅ | same |
| 1.9 | Discovery ranking is being updated to account for **younger players preferring shorter games** and **older players engaging deeper experiences**, plus testing ranking on new-player acquisition | ✅ | [PocketGamer.biz RDC 2026](https://www.pocketgamer.biz/roblox-unveils-new-play-creation-and-monetisation-tools-at-rdc-2026/) |
| 1.10 | RDC 2025 shipped **server authority** and **custom matchmaking**, and raised DevEx from $0.0035 to $0.0038/Robux | ✅ | [RDC 2025](https://about.roblox.com/newsroom/2025/09/roblox-rdc-2025) |

**Design impact:** 1.1/1.2 are the reason this concept is being built now. 1.3 is the
constraint we design against (doc 03 §10). 1.4 makes resolve-on-read a strategic asset,
not just an optimisation. 1.5 gives the Chart screen its look. 1.9 is a real risk —
shorter-game preference among young players argues for our 3–12 min session, which is
where we already are.

## 2. Generative AI tooling

| # | Fact | Conf. | Source |
| --- | --- | --- | --- |
| 2.1 | **Cube 3D**: 1.8 B-parameter 3D foundation model, trained on 1.5 M assets, open-sourced Mar 2025 (GitHub + HuggingFace); `/generate` in Assistant; in-experience Mesh Generation API | ✅ | [Cube 3D beta announcement](https://devforum.roblox.com/t/beta-cube-3d-generation-tools-and-apis-for-creators/3558947) |
| 2.2 | In-experience Cube generation was limited to **5 generations/min/experience** at beta; requires EditableMesh/EditableImage enabled in Game Settings → Security; in-experience assets do **not** persist to inventory or Marketplace | ✅ | same |
| 2.3 | **4D generation** open beta Feb 2026: functional objects, initially two schemas (drivable four-wheeled car, single-mesh object); >160 000 objects generated in early access; Wish Master reported **+64% play time** for users of the feature | ✅ | [gamesindustry.biz](https://www.gamesindustry.biz/roblox-debuts-tool-for-players-to-ai-generate-interactive-in-game-objects-promises-full-scene-generation-is-coming) |
| 2.4 | Cube had generated **>1.8 M objects** since launch as of Feb 2026 | 🟡 | [AI Trace profile](https://www.aitrace.org/company/roblox-corporation/practice/959bdd90-c6af-4e6d-bc35-d47a68343ef0) |
| 2.5 | Assistant received an **agentic update April 2026** with Planning Mode and automated playtesting, integrating Mesh Generation and Procedural Model Generation | 🟡 | same |
| 2.6 | The **Studio MCP server is built into Studio**. Enable: Assistant → … → Manage MCP Servers → Enable Studio as MCP server. Quick-connect clients: Antigravity, Codex CLI, Claude Code, Claude Desktop, Cursor, Gemini CLI, VS Code | ✅ | [create.roblox.com/docs/studio/mcp](https://create.roblox.com/docs/studio/mcp) |
| 2.7 | Every MCP tool call takes a **`studio_id`** parameter; `list_roblox_studios` enumerates instances. An Aug 2026 update introduced this explicit routing | ✅ | same |
| 2.8 | MCP exposes `execute_luau` in **Edit, Client and Server** DataModel contexts, plus playtests, console output, screenshots and input simulation | 🟡 | [Claude+Studio MCP guide, Aug 2026](https://backyarddrunkard.com/game-guides/connect-claude-to-roblox-studio-mcp-guide/) |
| 2.9 | Roblox's own docs recommend the built-in server over community MCP projects | ✅ | [create.roblox.com/docs/studio/mcp](https://create.roblox.com/docs/studio/mcp) |
| 2.10 | Assistant became an **MCP client** via RDC 2025, able to orchestrate third-party MCP apps (e.g. Figma, Blockade Labs) | ✅ | [RDC 2025](https://about.roblox.com/newsroom/2025/09/roblox-rdc-2025) |
| 2.11 | Roblox humanoid character body assets are capped at **10 742 triangles** total | 🟡 | Nilo/Meshy docs citing Roblox limits |
| 2.12 | Meshy provides a native Roblox Bridge (GLB), remesh-to-limit, PBR maps; 20 MB upload limit | 🟡 | [Meshy Roblox page](https://www.meshy.ai/use-cases/free-game-assets/roblox-developers) |
| 2.13 | Roblox's Terms permit AI-generated content in experiences | 🟡 | same |

**Design impact:** see [`09-AI-BUILD-PIPELINE.md`](09-AI-BUILD-PIPELINE.md). The headline
is 2.6–2.9: the official MCP server is what lets iterations 4–5 make *verified* claims
about engine behaviour instead of asserted ones.

## 3. Data services — the numbers the architecture is built on

| # | Fact | Conf. | Source |
| --- | --- | --- | --- |
| 3.1 | **MemoryStore memory quota = `64 KB + 1.2 KB × [number of users]`**, applied at the **universe** level, not per server | ✅ | [creator-docs memory-stores](https://github.com/Roblox/creator-docs/blob/main/content/en-us/cloud-services/memory-stores/index.md) |
| 3.2 | MemoryStore request quota = **`1000 + 120 × CCU`** request units/min universe-wide. *(Corrected 2026-10-01 — it was `100 × CCU` when this row was written; see §6.2.)* Per-structure limit 100 000 units/min; per-partition throttling begins ≈30 000 units/min; hash-map per-key ≈5 000 write / 15 000 read units/min | ✅ | [creator-docs memory-stores](https://create.roblox.com/docs/cloud-services/memory-stores) (last_updated 2026-09-29) |
| 3.3 | Sorted map / queue: max **1 000 000 items**, **100 MB** per structure; item value ≤ **32 KB**; key ≤ 128 B | ✅ | creator-docs |
| 3.4 | **HashMap** has **no** item-count or per-structure memory limit (universe quota still applies); per-partition rate limit replaced the per-structure one | ✅ | [MemoryStore HashMap beta](https://devforum.roblox.com/t/memorystore-hashmap-beta/2977379) |
| 3.5 | `GetRangeAsync` / `ReadAsync` consume request units **per item returned**; `HashMap:UpdateAsync` consumes ≥ 2 units; `ListItemsAsync` consumes partitions-scanned + items-returned | ✅ | creator-docs |
| 3.6 | Recommended practices: shard by key prefix, shard hot keys, compress values, use exponential backoff on `DataUpdateConflict`, set the **shortest viable TTL**, delete explicitly | ✅ | creator-docs |
| 3.7 | DataStore storage limit = **`500 MB + 1 MB × lifetime user count`**, measured on the **compressed** size of the latest version of each key only; in-game and Open Cloud share **one** per-experience request budget. Confirmed against primary docs on 2026-10-01 (confidence raised from 🟡). | ✅ | [error codes and limits § Storage limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits) |
| 3.8 | DataStore: 4 MB per key value. Per-server **default** rate limits are `60 + numPlayers × 40`/min for standard read, write and remove and `5 + numPlayers × 2`/min for list — **not** a flat 60/min/server, and they are creator-configurable with `SetRateLimitForRequestType`. *(Corrected 2026-10-01; see §6.2.)* | ✅ | [error codes and limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits) (last_updated 2026-09-29) |
| 3.9 | Open Cloud **Luau Execution**: **5 minutes** per task (raised from 30 s), **10 concurrent tasks per place** (raised from 2), engine API restrictions since lifted; place changes are not saved | ✅ | [Luau Execution docs](https://create.roblox.com/docs/cloud/reference/features/luau-execution) + [beta thread](https://devforum.roblox.com/t/beta-open-cloud-engine-api-for-executing-luau/3172185) |
| 3.10 | HttpService can call a subset of Open Cloud endpoints; **2 500 OC requests/min per game server**, separate from the 500/min general HTTP limit | ✅ | [In-game HTTP requests](https://create.roblox.com/docs/cloud-services/http-service) |
| 3.11 | Open Cloud DataStore read limit ~**300 requests/min/universe** — a developer measured **5.5 hours** to scan 100 000 entries for notification targeting | ✅ | [devforum](https://devforum.roblox.com/t/experience-notifications-and-rate-limits/4615621) |
| 3.12 | `BadgeService:AwardBadgeAsync` rate limit is `50 + 35 × users` per minute | ✅ | [BadgeService reference](https://robloxapi.github.io/ref/class/BadgeService.html) |

**Design impact — the three findings that shape this architecture:**

> **Finding A. MemoryStore is a coordination cache, not storage.** At 1 000 CCU the
> universe-wide quota is ~1.2 MB (3.1). Any design that pools async player data there
> dies at the moment of success. The Drifter pool therefore lives in DataStore and
> MemoryStore holds only a shard-fill index — ~17 KB total (doc 03 §6).

> **Finding B. There is no way to run a server for an absent player, and you should not
> want one.** Luau Execution is 5 min / 10 concurrent per place (3.9) — one global tick,
> not N posts. Hence resolve-on-read, whose cost scales with *sessions*, not with
> population × time (doc 04 §1).

> **Finding C. Notification targeting must be computed at logout, not by scanning.**
> Scanning DataStore for eligible users is ~5.5 h per 100 k users (3.11). Because the
> tide is a pure function (doc 02), the exact second of the next notable event is known
> the moment the player leaves — so the notification is scheduled then, from data
> already in hand (doc 03 §10).

## 4. Market and genre

| # | Fact | Conf. | Source |
| --- | --- | --- | --- |
| 4.1 | Grow a Garden: released 26 Mar 2025, peaked **22.3 M CCU** (23 Aug 2025), fastest to 1 bn visits (33 days); built in ~3 days by a 16-year-old | 🟡 | [Wikipedia](https://en.wikipedia.org/wiki/Grow_a_Garden) |
| 4.2 | Grow a Garden tracked at ~**35.95 bn lifetime visits**, **~15.7–17.6 min** average session, ~90% rating | 🟡 | [RoMonitor](https://romonitorstats.com/experience/126884695634066/) |
| 4.3 | Steal a Brainrot holds the all-time CCU record (~**25 M**) | 🟡 | multiple 2026 chart roundups |
| 4.4 | 99 Nights in the Forest: ~**442 K CCU**, the clearest horror/survival breakout of 2026 | 🟡 | [LootBar chart](https://www.lootbar.com/blog/en/roblox-best-games-to-play-in-2026-top-picks-across-every-genre.html) |
| 4.5 | Brookhaven ~**600–700 K CCU**, >69 bn lifetime visits; Adopt Me ~**531 K CCU** sustained since 2017, driven by its trading economy | 🟡 | [StudioKrew May 2026](https://studiokrew.com/blog/top-roblox-games-may-2026/) |
| 4.6 | Dress to Impress ~**73–100 K CCU** with one of the platform's highest approval ratings, on pure social judgement | 🟡 | same |
| 4.7 | Cozy/idle and player-driven-economy games are the dominant retention shape of 2026; simulators are described as the most reliably profitable genre | 🟡 | [kitsblox genre analysis](https://kitsblox.com/blog/popular-roblox-game-genres-2026) |
| 4.8 | A developer-reported teardown: **45%** of players left within **30 seconds** before a spawn redesign, dropping to **18%** after; tutorial 5→3 steps moved **D1 from 6% to 15%**; daily login rewards ≈ **3× D7**; mobile sessions **~40% shorter** than desktop but higher payer conversion | 🟡 | [r/robloxgamedev](https://www.reddit.com/r/robloxgamedev/comments/1sakqj4/i_tracked_retention_on_my_roblox_game_for_3/) — single-developer anecdote, directionally useful, not authoritative |

**Design impact:** 4.8 drives doc 08 §2 directly. 4.5/4.6 are the evidence that the
async social layer is aiming at real, proven demand. 4.1 is the cautionary tale: a
three-day build took the crown, so systems depth alone is not a moat — the first 60
seconds matter at least as much.

## 5. Policy and compliance

| # | Fact | Conf. | Source |
| --- | --- | --- | --- |
| 5.1 | Platform-level trading covers **avatar Limiteds only**, requires **Premium on both sides**, 30% Robux fee, Robux capped at 50% of offered item value, 4 items/side, holds of up to 2 d (7 d on resale), irreversible, unavailable in some regions | 🟡 | [ProfitBlox](https://www.profitblox.org/guides/roblox-trade-limits-and-holds), [Mythras](https://gamertagmythras.com/blog/roblox/roblox-trading-limiteds-guide) |
| 5.2 | **In-experience** item trading is a separate thing governed by the experience (Adopt Me model) and is permitted | 🟡 | same |
| 5.3 | Selling in-experience items to other players **for Robux** is not permitted; Robux/virtual content may not be sold, traded or given away except through official channels | 🟡 | ToS §4 as quoted in the [California AB587 transparency report](https://oag.ca.gov/sites/default/files/Roblox%202025%20H2%20California%20AB587%20Terms%20of%20Service%20Report.pdf/Roblox%202025%20H2%20California%20AB587%20Terms%20of%20Service%20Report.pdf); DevForum consensus |
| 5.4 | **Paid Random Items** are heavily regulated: `PolicyService:GetPolicyInfoForPlayerAsync` must be honoured for `ArePaidRandomItemsRestricted`; **numerical odds disclosed pre-purchase** for every outcome, including purchases made with in-game currency bought with Robux; must be declared in the Content Maturity questionnaire | ✅ | [Clarifying Requirements for Paid Random Items, May 2026](https://devforum.roblox.com/t/clarifying-requirements-for-paid-random-items/4654622) |
| 5.5 | If an experience allows trading of Paid Random Items it must use `PolicyService`'s **`IsPaidItemTradingAllowed`** — a *separate* eligibility check from acquisition | ✅ | same |
| 5.6 | Studio's **Player Emulator** can toggle `ArePaidRandomItemsRestricted` and `IsPaidItemTradingAllowed` for testing without being in a regulated region | ✅ | same |
| 5.7 | Experience Rules are creator-authored and creator-enforced; violations are not reportable through Roblox's Report Abuse | ✅ | AB587 report |

**Design impact:** see [`13-RISKS-AND-COMPLIANCE.md`](13-RISKS-AND-COMPLIANCE.md). The
short version: no paid random items at all (sidesteps 5.4–5.6 entirely), no
Robux-for-item peer trading (5.3), barter is a claim not a transfer, and `PolicyService`
is still wired from day one because a future change could make it load-bearing.

## 6. Iteration-3 verification pass — 2026-10-01

Iteration 3's first task was to re-verify, not re-assume. Three questions were asked;
all three produced a change to this project.

### 6.1 The async / turn-based notification API — **it has not shipped**

| Fact | Conf. | Source |
| --- | --- | --- |
| RDC 2026 (2026-09-11): "A new notification system will alert players when it's their turn, **arriving in Studio Beta in October, and in full release by the end of the year**." | ✅ | [RDC 2026 newsroom post](https://about.roblox.com/newsroom/2026/09/rdc-2026-the-world-needs-more-play) |
| The same commitment, from the creator-facing recap: "**Developer Push Notification Support (Late 2026)** — Turn on push notifications for opted-in players to alert when it's their turn, enabling new cases like async turn-based play." | ✅ | [RDC26: What We Announced](https://devforum.roblox.com/t/rdc26-what-we-announced/4865880) |
| As of **2026-10-01** the DevForum Announcements feed contains no such beta. The most recent items are the Sept 21–25 weekly recap, Frustum Streaming, the Transaction Refunded webhook, EditableMesh quad support and the new texture-generation tools. | ✅ | [Updates/Announcements, latest](https://devforum.roblox.com/c/updates/announcements/36/l/latest) |
| `ExperienceNotificationService` still exposes exactly three members — `CanPromptOptInAsync()`, `PromptOptIn()`, `OptInPromptClosed` — in the API reference generated **2026-09-30**. There is no turn/async member. | ✅ | [ExperienceNotificationService](https://create.roblox.com/docs/reference/engine/classes/ExperienceNotificationService) |

**Verdict: ⚠️ announced, dated, not shipped.** Studio Beta is due this month. It is not
here today, and `NotifyService` is therefore built against what exists.

**What exists today**, verified the same day:

- **Sending** is `OpenCloud.V2.UserNotification.createUserNotification(userId, payload)` —
  a Luau package obtained from the Creator Store and parented under `ServerScriptService`.
  The payload is `{ messageId, type = "MOMENT", parameters, joinExperience.launchData,
  analyticsData }`.
- `messageId` is the asset id of a **notification string authored in the Creator
  Dashboard**, ≤ 99 characters, with named parameters substituted at send time.
  **There is no free-text notification body.**
- Eligibility: the experience needs ≥ 100 visits, must not be under moderation.
  Recipients must be **13+ and opted in**.
- **One notification per user per day per experience**, a static throttle, and delivery
  is explicitly *not guaranteed* — a spam-prevention system weights reach by engagement.
- Roblox's own guideline: "Games should **not** require users to turn on notifications
  in order to participate or advance in gameplay."

  ✅ [Experience notifications](https://create.roblox.com/docs/production/promotion/experience-notifications) (last_updated 2026-09-30)

**Design consequences, all implemented in iteration 3:**

1. `NotifyAdapter` resolves the Open Cloud package with `FindFirstChild` and, when it is
   absent, reports `disabled` and returns `false` forever after. The adapter never
   errors and never yields the caller into a failure path.
2. Notification *content* is a `messageId` plus a parameter table, which is a perfect
   fit for a game that already forbids free text (doc 13 §2). `Config/NotifyConfig`
   holds one row per notification kind with its dashboard asset id, its priority and its
   parameter names. The ids are placeholders until the experience exists.
3. The 1/user/day cap is enforced **locally as well**, in `NotifyService`, because a
   rejected send still costs a request and because the cap is the design (doc 03 §10).
4. Nothing in the game reads a notification's success. `tidekeeper-session-test.js`
   runs its entire 30-day lifetime with the notifier **disabled** and asserts the
   economy invariants are unchanged — that is the mechanical form of "fully playable
   with zero notifications" (risk R5).

### 6.2 DataStore and MemoryStore quotas — two numbers had moved

Re-checked against the primary creator docs (both pages `last_updated 2026-09-29`).

| Row | Was in doc 10 | Is, 2026-10-01 | Effect |
| --- | --- | --- | --- |
| 3.1 MemoryStore memory | `64 KB + 1.2 KB × users`, universe-wide | **unchanged**, and now also documented as having an **eight-day traceback** before the quota falls after users leave | none |
| 3.2 MemoryStore requests | `1000 + 100 × CCU` /min | **`1000 + 120 × CCU`** /min | 20% more headroom; `MemoryAdapter`'s budget model uses the new figure |
| 3.8 DataStore per-server | "~60 requests/min/server, 6/s" | **`60 + numPlayers × 40`** per minute for read, write and remove; `5 + numPlayers × 2` for list | the old figure understated a 30-player server's budget by ~20× |
| new | experience-level DataStore limits | read `300 + CCU × 40`, write `300 + CCU × 20`, list `300 + CCU × 2`, remove `300 + CCU × 40`, **shared with Open Cloud** | this, not the per-server figure, is the real ceiling |
| new | per-key DataStore throughput | read **25 MB/min**, write **4 MB/min**, rounded up to the next KB per request | a 4.4 KB post blob costs 5 KB of the per-key write budget |
| 3.7 DataStore storage | `500 MB + 1 MB × lifetime users` (🟡 secondary source) | **confirmed ✅** against the primary doc, and measured on the **compressed** size of the latest version only | doc 05 §2's footprint estimates are conservative |
| new | Extended Services | storage and request quotas can be raised by onboarding | recorded as an escape hatch, not a plan |

Sources: [data store error codes and limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits),
[memory stores](https://create.roblox.com/docs/cloud-services/memory-stores).

**One new finding, and it contradicts an iteration-1 instinct.** The storage docs now
say plainly: *"Data stores automatically compress your data before storage, so avoid
pre-compressing it yourself. Pre-compression adds unnecessary CPU overhead and may
reduce the effectiveness of data stores' built-in compression."* TIDEKEEPER's post blob
is bit-packed and then base64'd, and base64 of packed binary is close to incompressible.
This does **not** make the design wrong — the packing exists to fit the 32 KB MemoryStore
value ceiling and to keep the ledger entry at 24 bytes, and the measured blob is 4 416
base64 bytes against a 4 MB key limit — but it does mean the *storage* argument for
packing is weaker than doc 05 §3.1 claims. Recorded as **OD15**; it is a question for
iteration 5 load testing, not a reason to rewrite a codec with 122 passing assertions.

**OD9 answered, partially.** The memory-quota question ("do keys count?") has a
documented answer for sorted maps — the per-structure limit is *"Maximum total size
**including keys** for sorted map: 100 MB"* — and no explicit statement for hash maps.
The design continues to size as though keys count, which is now the conservative reading
of a documented fact rather than a guess. `MemoryAdapter` charges `#key + #value + 16`
bytes of per-item overhead to its own accounting.

### 6.3 The Studio MCP server — same shape, substantially more tools

The API reference page (`last_updated 2026-09-30`) confirms everything doc 09 §2 relies
on and adds tools that change how iteration 4 should be planned.

- Still built into Studio; still `stdio` transport; still enabled via
  **Assistant ⟩ … ⟩ Manage MCP Servers ⟩ Enable Studio as MCP server**.
- Every tool call still takes a **`studio_id`**; `list_roblox_studios` enumerates them.
- Quick connect: Antigravity, Codex CLI, Claude Code, Claude Desktop, Cursor, Gemini CLI,
  Visual Studio Code.
- `execute_luau` (Edit / Client / Server) and `get_console_output` are present — the two
  tools OD12 needs.
- **New since doc 09 was written:** `subagent` with `explore` and `playtest` types
  (the playtest agent is itself a Studio Beta feature, announced 2026-04-09);
  `generate_procedural_model` + `wait_job_finished`; `store_image` / `upload_image`;
  `character_navigation`, `user_keyboard_input`, `user_mouse_input`; `screen_capture`;
  `http_get` against allow-listed Roblox docs; and `skill`.

  ✅ [Connect to the Roblox Studio MCP server](https://create.roblox.com/docs/studio/mcp) ·
  ✅ [Studio Assistant & MCP Playtest Agent](https://devforum.roblox.com/t/studio-beta-studio-assistant-mcp-playtest-agent/4566767)

**Consequence for iteration 4:** the input-simulation and playtest-subagent tools make
the R1 "is the Ledger fun" experiment partly mechanisable — an agent can drive the
screen and screenshot it. It still cannot tell you whether it *felt* good, so doc 09 §2's
statement stands unchanged.

**Consequence for iteration 3 (OD12): none, and this is stated plainly.** This iteration
ran in a sandbox with no Roblox Studio process and therefore no MCP server to connect to.
`Visit.resolve` was **not** measured in Luau. OD12 stays open and no estimate has been
substituted for it.

### 6.4 What the session harness proved about the platform, by contradiction

Three facts about the MemoryStore and DataStore APIs were *assumed correctly in prose*
and *implemented incorrectly in code* in the first draft of iteration 3, and the only
thing that caught them was running the real adapters against a fake DataModel.
Recorded here because they are platform behaviour, not TIDEKEEPER behaviour, and the
next person to write a Roblox persistence layer needs them:

1. **Returning `nil` from an `UpdateAsync` transform aborts the update. It does not
   delete the key.** This is true for DataStore and MemoryStore alike. "Transform the
   value into nothing" is not how deletion is expressed; `RemoveAsync` is. Two separate
   bugs in this codebase were this one fact:
   - the session lock was never released, only TTL-expired;
   - an emptied Drifter-pool shard cancelled its own removal, so every record in it was
     delivered to a resolve *and* left in place for the next claimant.
2. **There is no atomic compare-and-delete.** A lock protocol therefore cannot release
   safely in one request; it must either spend a read first or trust locally recorded
   ownership plus a TTL. We chose the latter and documented the residual race
   ([`05-PERSISTENCE.md`](05-PERSISTENCE.md) §7.1).
3. **A request budget that counts only the expensive-looking call is not a budget.**
   The claim path's per-request cap covered DataStore claims but not the MemoryStore
   index probes that drive them, and a sparse exchange promptly walked backwards
   through six epochs probing the index for each. Measured cost went from 6.24 to 5.24
   MemoryStore requests per session once probes were charged.

**OD16 (new, open):** `S.publishedAt` — the tide epoch a post last sent its Drifter out —
is currently held in memory per server and is *not* in `PostCodec`, so it does not
survive a save. A Drifter's id is `makeId(owner, epoch)`, so two publications by the
same post in one epoch collide, and the second is refused by the at-most-once gate
(a dropped visitor, not corrupt history). The same-server case is covered; the
cross-server case is not. Resolve in iteration 4 by adding the field in schema v2 with
a migration, which is cheap because [`Shared/Version.luau`](../code/ReplicatedStorage/Tidekeeper/Shared/Version.luau)
already exists for exactly this.

## 7. Known unknowns

Recorded so later iterations do not mistake absence of evidence for evidence.

| ? | Why it matters | How to resolve |
| --- | --- | --- |
| ~~Exact API shape of the Oct 2026 async notification system~~ | doc 03 §10 depends on it | **Answered 2026-10-01 (§6.1): it has not shipped.** Re-check monthly; the commitment is "full release by end of 2026". |
| Whether the daily notification cap really resets on visit | changes notification design materially | roadmap says yes (1.2); the **shipped** docs still describe a flat 1/user/day static throttle (§6.1). Unresolved until the beta lands. |
| Whether Scene Generator ships in 2026 | doc 09 §2 it5 contingency | watch announcements |
| Real `Visit.resolve` cost in Luau on a real server | doc 04 §6 budget of 18 µs is an estimate | **Still open (OD12).** Iteration 3 had no Studio to connect to (§6.3); measure with MCP `execute_luau` in it4 |
| Whether DataStore `UpdateAsync` contention on a 200-entry pool shard is acceptable at scale | doc 03 §6.2 | load test in it5 |
| Whether MemoryStore keys count toward the memory quota | affects the hot index sizing | **Partly answered (§6.2):** documented as counting for sorted maps, unstated for hash maps. `MemoryAdapter` charges for them. |
| Roblox's stance on showing other players' display names in an async context to under-13 users | doc 08 §9 | policy review before soft launch |
| Whether `buffer` + base64 round-trips cleanly through DataStore at 6 KB | doc 05 §3.1 | it4, MCP `execute_luau` |
| Whether `S.publishedAt` must be persisted to make one-Drifter-per-epoch hold across servers | doc 03 §3, §6.3 | **OD16, open (§6.4).** Schema v2 + migration in it4 |
| Whether the measured 5.64 DataStore / 5.24 MemoryStore per session holds at real CCU | doc 03 §6.3 | the fake models per-server budgets but not cross-server contention; load test in it5 |
