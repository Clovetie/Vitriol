# 08 — Client, UX and Mobile

Mobile portrait, one-handed, is the **primary** target. Desktop and browser are
adaptations of it, not the other way round. Most Roblox play is mobile, mobile sessions
run ~40% shorter than desktop, and mobile converts better.

---

## 1. The screens

Six. Anything that does not fit in one of them does not exist.

| Screen | Reached by | Purpose | Time budget |
| --- | --- | --- | --- |
| **World** | default | Walk, comb, dockwork | — |
| **Ledger** | auto on join; tab | The replay of who came | 60–120 s |
| **Post** | tab | Shelves, prices, arrange | 60–180 s |
| **Orders** | from Post | Standing-order editor + live preview | 60–240 s |
| **Chart** | tab | The async map: Currents, inbound, tide curve (doc 03 §11) | 20–60 s |
| **Almanac** | tab | Collection, 48 px grid | 20–90 s |

Four bottom-bar tabs (World / Post / Chart / Almanac). Ledger is a takeover, Orders is a
push from Post. No nested menus deeper than two.

## 2. The first 60 seconds

This is the single most consequential piece of UX in the project. Community retention
data puts first-30-second churn near 45% on a badly-framed spawn, dropping to ~18% with
one clear first action; and shortening a tutorial from 5 steps to 3 moved D1 from 6% to
15%.

```
0:00  Spawn on your pier, facing the post. Tide audible. No UI chrome.
0:02  The Ledger slides up on its own. It is NOT empty — three seeded visits,
      with names, faces and one letter. No "tap to continue".
0:20  Ledger closes to a single highlighted line: "Marren wanted a green float.
      You had none."
0:24  A soft arrow to the flats. The water is out.
0:30  STEP 1/3 — comb one node. One tap. You get a green float.
0:45  STEP 2/3 — put it on the shelf and set a price. Two taps, one slider.
1:05  STEP 3/3 — dispatch your Drifter. One tap.
1:15  Done. "Come back when the water's low." Tutorial never appears again.
```

Three steps, no gates, no dialogue trees, no skippable cutscene, and the player has
already participated in the async loop in 75 seconds. The seeded Ledger at 0:02 is the
hook and it is *the thing no other Roblox game can show you in the first two seconds*.

## 3. The Ledger — the signature screen

Not a list. A paced replay.

- Entries are grouped by tide epoch, each group behind a **tide silhouette** drawn from
  the real `Tide.height` curve for that window (doc 02 §5). The screen *is* a tidal record.
- Each entry animates in with its own small scene: the boat, the figure on the pier, the
  item lifting off the shelf. Reconstructed client-side by re-running `Visit.resolve`
  (doc 04 §7), so it costs no bandwidth.
- Pacing: ~1.6 s per entry, tap to advance, hold to fast-forward. A 12-entry Ledger is
  ~20 s if you let it run and ~4 s if you rush.
- Prose from `templateId + slots` (doc 05 §6) — never stored text, always reconstructed,
  so it can be translated and rewritten without a migration.
- Warmth is shown as **colour temperature on the entry's edge**, never a number.
- The unread count is the only badge in the game.

**Anti-requirement:** the Ledger must be fully readable with sound off. Most mobile play
is muted.

## 4. Mobile layout rules

| Rule | Value |
| --- | --- |
| Minimum touch target | **44 × 44 px** |
| Thumb zone | all primary actions in the bottom 45% of the screen |
| Safe area | respect notch/home indicator via `GuiService:GetGuiInset` and `ScreenInsets` |
| Text | minimum 14 px equivalent; no text below 12 px anywhere |
| One-handed | every core-loop action reachable with a right thumb in portrait |
| Landscape | supported, not optimised |
| Orientation change | must not lose state |
| Colour | never the sole carrier of meaning (warmth also has an icon) |
| Frame budget | **≤ 2.0 ms/frame** of client script time on a mid-tier phone |
| Draw calls | UI ≤ 90 |

## 5. Using the RDC 2026 UI/2D features

Announced at RDC 2026: orthographic camera, animated image containers, direct
sprite-sheet import, UI **blur**, **text shadows**, improved gradients.

| Feature | Where we use it |
| --- | --- |
| Orthographic camera | The Chart screen renders a real 3D scene of the Currents orthographically — a genuine 2D-looking map with 3D lighting. This is the thumbnail shot. |
| Sprite-sheet import | Almanac icons (200 at 128², one sheet), Ledger vignettes |
| Animated image containers | Ledger entry scenes, water in the Chart |
| UI blur | Ledger takeover over the live world; the Orders preview panel |
| Text shadows | Readability over the flats in bright outdoor light |
| Gradients | The tide gauge |

**Contingency:** all six degrade to plain frames. Iteration 4 must ship a fallback path
and a feature flag in `UIConfig`, because betas slip.

## 6. Accessibility

| Need | Provision |
| --- | --- |
| Colour vision | warmth, rarity and Current each carry an icon + a shape, not just hue |
| Low vision | a 1.25× UI scale toggle; no text baked into textures |
| Motor | no timed multi-taps, no drag required (drag-to-reorder has a long-press-then-arrows fallback) |
| Sound off | full parity; the tide countdown is visual and audible |
| Reading age | target 9-year-old reading level in all prose; Ledger templates reviewed for it |
| Motion | "reduce motion" toggle collapses the Ledger replay to static cards |

## 7. Performance budget (client)

| Metric | Target | Measured how |
| --- | --- | --- |
| Time to first interactive | ≤ 6 s on a mid phone | Studio + device |
| Script time/frame | ≤ 2.0 ms | MicroProfiler |
| `Tide.height` per frame | ≤ 6 µs, zero allocation | harness benchmark |
| Ledger replay | ≤ 3.0 ms/frame while animating | MicroProfiler |
| Memory after 20 min | ≤ 40 MB growth | Developer Console |
| Parts rendered | ≤ 1 800 | doc 01 §6 |

The Chart and Almanac screens must **pause** the world render (they are full takeovers)
— this is what buys the frame budget on low-end devices.

## 8. Localisation

- No baked text in any texture.
- All strings are keys; the Ledger's template+slot design (doc 05 §6) is already
  translation-ready and this is one of its main justifications.
- Number and date formatting through `LocalizationService`.
- Tide times shown in the **player's local timezone**, always, with no setting. The whole
  premise is "the water is out after school"; a UTC timestamp would destroy it.
- Launch languages: en, es, pt-BR, id, th, tr, fr, de. Roblox's own real-time
  translation work suggests the platform's growth is not English-first.

### 8.1 As built — iteration 4

The client layer exists as of iteration 4: nine files, eight of them pure modules under
`ReplicatedStorage/Tidekeeper/Client/` and exactly one `LocalScript`
(`StarterPlayerScripts/Tidekeeper/Main.client.luau`). The split is **D25**: the views
are presenters that take data and return a view-model table, and the LocalScript is the
only client file that touches `game`, holds the only client `RunService` connection (the scan counts them game-wide: 2 of a maximum 2, one per side), and
is the only place an Instance is created. The determinism scan enforces this — `Client`
is in the `NO_DATAMODEL` set, so a view that calls `GetService` fails the build.

**No sentence is ever stored, replicated, or sent (D26).** A Ledger entry on the wire is
`(templateId, epoch, actorId, slots[])` — about 24 bytes of integers. `Client/Strings.luau`
holds the prose; `Client/Format.luau` expands it at read time. A translator therefore
edits one file and every historical entry in every save re-renders in the new language,
because the save contains no English. This is the payoff the bullet above promises, and
it is the reason the Ledger format is integers rather than text.

**A variant is chosen by `hash(actorId, epoch)`, never randomly (D27).** Each template
has three or four phrasings so the Ledger does not read like a receipt printer, but the
Ledger is a *replay* (doc 04 §7) — reopening it must produce the same words forever.
Randomising the phrasing would make the game's memory unreliable in a way players
notice and cannot articulate.

**Directives do not nest.** The expander matches `{[^{}]+}`, so a `{1}` written inside a
`{plural:…}` branch is invisible to the outer match and both halves leak to the player
as literal braces. Two variants did exactly this; §8.2 is why they were caught before a
player saw them.

### 8.2 The coverage test

Localisation fails silently. A missing find name renders as `""` and a missing template
renders as nothing at all — the game keeps running and the bug ships. So `Format`
carries five **miss counters** (`find`, `class`, `tide`, `template`, `arity`) rather
than falling back quietly, and session-test scenario 15 runs a 30-day simulation, then
renders every Ledger template at four variants each, and asserts:

- every id in `Ledger.SLOT_COUNT` has prose, and no prose exists for an id the domain
  does not define (**both directions** — orphan prose is how a renamed template rots);
- `Format.totalMisses() == 0` across all five counters;
- no rendered line contains `{` or `}`, is blank, or is shorter than 12 characters;
- a second `LedgerView.build` of the same entries is byte-identical (D27);
- every `Strings.UI` label expands;
- `DispatchView` payloads contain no string fields at all.

It found four real bugs on its first green-to-red run, and the most serious was not a
missing translation: `LedgerService:slotsFor` was filling Ledger slots from a positional
pool `{spent, warmth, noteId, flags}` **regardless of what the template's slots meant**,
so a receipt rendered a coin amount through `{find:1}` and named an object "12". The fix
was structural — receipts now have their own template range (100–105), because a
receipt genuinely does not know which find was on the shelf or what the host's tide was
doing, and forcing it through a visit template was always going to invent facts. That
bug was nine iterations-worth of invisible: nothing rendered those entries until a
client existed.

### 8.3 The client executes — iteration 5

Scenario 16 drives `ClientBootstrap` against the real remote handlers, over the fake
platform, with real server state behind it. The only faked object is a `RemoteFunction`:
a table with an `InvokeServer` method, which is the entire surface
`ClientBootstrap:invoke` touches. That is the dividend of D25 — a presenter layer can be
driven end to end with no engine at all.

What it asserts, beyond "does not crash":

- **every one of the six screens renders**, reports its own id, and carries a tide
  header with a named state. A screen that silently returns an empty model is a black
  rectangle in the player's hands, and that passes a "no error" test;
- the Post and Orders screens **carry their data**, not just a shell — the assertion
  that catches a view wired to a field the snapshot does not have;
- **redraw happens only when dirty.** `step()` returns a model once, then `nil` until
  something changes. A Ledger that rebuilds every frame is 60 string builds a second on
  a phone, for a screen that changes once every 1.6 seconds;
- the **renderer seam** (`renderer:draw(model)`) is called exactly once with a
  well-formed model. `Main.client.luau` is the only file that builds Instances and it
  does so behind this seam, so this is as close to testing that file as is possible
  without an engine — and it is the half worth testing, because the Instance code is
  mechanical and the contract is here;
- a client with **no remote** and a client whose remote **throws** both degrade to a
  human-readable message with no directive in it, and both count the failure. A dropped
  connection is the most common state a mobile client is ever in;
- the client **never reuses a sequence number**, which is its half of the replay
  defence `NetContract` enforces on the server side.

It found two load-time crashes on first run (doc 10 §8.5). Both were in files that had
never been executed by anything.

### 8.4 The client could not do anything — iteration 9

Scenario 16 drove the client through `invoke` and proved the plumbing worked. It never
asked the one question that mattered: **does the client ever call any of this?**

It did not. Six client → server remotes existed; the client invoked exactly one of them
(`RF_Session`) and then listened. Arranging a shelf, combing the beach, setting standing
orders, dispatching a drifter and buying a tier each had a complete, rate-limited,
schema-checked, session-tested server half **and no way for a player to reach it**. The
game was a screensaver with excellent test coverage.

Underneath that, two of the three payload builders the client owned produced payloads
the server would have rejected on arrival — which is only possible because none had ever
been sent:

| builder | sent | `NetContract` wants |
|---|---|---|
| `PostView.arrangePayload` | `find`, price clamped to `4294967295` | `findId`, `EconomyConfig.MAX_PRICE` (`4294967`) — 1000× lower |
| `DispatchView.payload` | `slot`, `phrase`, cargo as `{id, qty}` | `targets` (array), `letterId`, cargo as plain ids |
| `OrdersView.setOrdersPayload` | — | already conformant |

Every spec is a **strict** map, so an extra or misnamed field is a rejection, not a
warning. The builders had round-tripped against *themselves* in tests and agreed with
themselves perfectly. Hence **D45**: a client payload builder is validated against the
server's own schema through `NetContract.accept`, never against its own expectations.

**What iteration 9 added.** One seam, `ClientBootstrap:act(remoteName, payload)` —
invoke, check status, fold the reply into the snapshot, mark dirty — and six verbs on
top of it: `arrange`, `comb`, `setOrders`, `dispatch`, `upgrade`, `upgradeOffer`.

Two rules fell out of it, both about who owns a number:

- **The server owns prices (D46).** `:upgrade()` sends `{seq}` and nothing else; the
  tier and the cost are the server's business. `:upgradeOffer()` *displays*
  `snapshot.nextCost`, which `SessionHandler` now sends. A client that computes a price
  locally will eventually show one number and charge another, and in a cozy game that
  reads as dishonesty rather than as a bug.
- **Only the server's fields are trusted.** `act` folds exactly
  `AUTHORITATIVE_FIELDS = {tier, coin, renown, nextCost, shelfCount, maxShelves, stock}`
  from a reply, so a handler cannot accidentally teach the client a field nobody
  defined.

**`statusText` was lying.** It mapped codes 1 and 2 and sent *everything else* to
`ERR_OFFLINE` — "Can't reach the post right now." So a comb refused because the tide
was wrong (code 3), or a node still regrowing (code 4), told the player their connection
had dropped. Nobody noticed because no client code could reach a remote that returns a 3
or a 4. It now maps 3 and 4 too, and takes the **remote name** with the status, because
code 4 means `E_COOLDOWN` from `PostHandler` and `E_ALREADY_OUT` from `DispatchHandler`
— the same number, two meanings, depending on who answered. That collision is a wart in
the contract rather than in the client, raised as **OD23**.

**The durable part is check 17.** `tidekeeper-remote-scan.js` walks `NetContract.REMOTES`
and requires, per row, that the originating side calls it *and* the receiving side
listens. It has **no allowlist**: a remote nobody speaks is never acceptable, only
unfinished. See doc 09 §7.

`LetterView` joins the client this iteration: 120 letters in 7 categories, chosen by id.
Letter **ids** cross the wire, never player text — the same rule the dispatch spec
enforces with `hasNoStringFields`.

## 9. Safety-shaped UX

Because this game shows players to each other, the UX carries safety weight (doc 13).

- Visitors appear as **display name only**. No profile link, no join, no follow, no DM.
- Letters are **fixed phrases picked from a list** — a composer with categories, not a
  text box. There is no free-text input anywhere in the game.
- A one-tap **"don't show me this post again"** on any Ledger entry, which adds a
  permanent exclusion to the exchange for that pair. No explanation required, no report
  flow needed for the common case.
- Renown boards show the top 100 only, and never a bottom.
- Warmth is never shown as a public number attached to a named player (doc 03 §12 open
  question resolves to: aggregate colour on the Chart, no name).
