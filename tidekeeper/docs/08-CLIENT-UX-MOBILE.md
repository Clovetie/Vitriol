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
