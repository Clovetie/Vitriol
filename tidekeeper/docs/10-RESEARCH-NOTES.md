# 10 — Research Notes (sourced)

Every non-obvious claim the design depends on, with a source and a date. **Re-verify
before relying on anything here.** The Roblox platform moved substantially between
RDC 2025 and RDC 2026 and will move again.

Research performed: **2026-09-30**.

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
| 3.2 | MemoryStore request quota = `1000 + 100 × CCU` request units/min universe-wide; 100 000 units/min per single structure | ✅ | [Memory Stores Service Quota update](https://devforum.roblox.com/t/memory-stores-service-quota-update/2062296) |
| 3.3 | Sorted map / queue: max **1 000 000 items**, **100 MB** per structure; item value ≤ **32 KB**; key ≤ 128 B | ✅ | creator-docs |
| 3.4 | **HashMap** has **no** item-count or per-structure memory limit (universe quota still applies); per-partition rate limit replaced the per-structure one | ✅ | [MemoryStore HashMap beta](https://devforum.roblox.com/t/memorystore-hashmap-beta/2977379) |
| 3.5 | `GetRangeAsync` / `ReadAsync` consume request units **per item returned**; `HashMap:UpdateAsync` consumes ≥ 2 units; `ListItemsAsync` consumes partitions-scanned + items-returned | ✅ | creator-docs |
| 3.6 | Recommended practices: shard by key prefix, shard hot keys, compress values, use exponential backoff on `DataUpdateConflict`, set the **shortest viable TTL**, delete explicitly | ✅ | creator-docs |
| 3.7 | DataStore baseline storage raised from **100 MB to 500 MB** on **2026-07-29**, plus **1 MB per lifetime user**; in-game and Open Cloud requests moved to **one shared per-experience budget** | 🟡 | [BloxBot summary](https://bloxbot.ai/guide/roblox-datastore-limits-july-2026); the underlying change was announced on the DevForum |
| 3.8 | DataStore: 4 MB per key value, ~60 requests/min/server, 6/s | ✅ | creator-docs |
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

## 6. Known unknowns

Recorded so later iterations do not mistake absence of evidence for evidence.

| ? | Why it matters | How to resolve |
| --- | --- | --- |
| Exact API shape of the Oct 2026 async notification system | doc 03 §10 depends on it | Studio Beta, October 2026. **Check first thing in iteration 3.** |
| Whether the daily notification cap really resets on visit | changes notification design materially | roadmap says yes (1.2); verify against shipped docs |
| Whether Scene Generator ships in 2026 | doc 09 §2 it5 contingency | watch announcements |
| Real `Visit.resolve` cost in Luau on a real server | doc 04 §6 budget of 18 µs is an estimate | measure with MCP `execute_luau` in it4 |
| Whether DataStore `UpdateAsync` contention on a 200-entry pool shard is acceptable at scale | doc 03 §6.2 | load test in it5 |
| Whether MemoryStore keys count toward the memory quota | affects the hot index sizing | DevForum consensus says keys are free for sorted maps; **unverified**. Size assuming they are not free. |
| Roblox's stance on showing other players' display names in an async context to under-13 users | doc 08 §9 | policy review before soft launch |
| Whether `buffer` + base64 round-trips cleanly through DataStore at 6 KB | doc 05 §3.1 | it4, MCP `execute_luau` |
