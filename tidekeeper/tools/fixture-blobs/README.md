# `fixture-blobs/` — captured save payloads

Real, byte-exact blobs produced by a previous version of the game, kept
forever so that every future version must still be able to load them.

This is the only kind of test that can catch a migration that was never
written. A round-trip test encodes and decodes with the *same* code, so it
agrees with itself by construction and will happily agree with itself after a
format change that orphans every live player's save.

| File | Schema | Bytes | Captured |
| --- | --- | --- | --- |
| `post-v1.b64` | 1 | 249 | iteration 4, from the iteration-2 layout |
| `post-v2.b64` | 2 | 238 | iteration 8, from commit `4e8b1a1` — the last code that could write v2 |

`post-v1.b64` is base64 of the v1 `PostCodec` layout: the blob the game wrote
before `publishedAt` existed (OD16). It is loaded by the `PostCodec` section of
`tools/tests/pure-tests.lua`, which asserts it migrates to the current schema
with `publishedAt = 0` and every other field intact.

`post-v2.b64` is the v2 layout: six lifetime counters and `publishedAt`, before
schema v3 added six more counters and the 40-bit badge mask. It was captured
from a git worktree at `4e8b1a1` **in the same session that raised
`SCHEMA_VERSION` to 3**, because that is the last moment it could be captured
at all — once the encoder moves, the old bytes can only be hand-forged, and a
hand-forged fixture proves nothing about what the old code really wrote.

If you are about to change the schema: capture the outgoing version's blob
*first*, from the code that still writes it.

## Rules

1. **Never edit or regenerate a fixture.** Its value is that it is old. If a
   fixture stops loading, the bug is in the migration, not the fixture.
2. **Add one whenever `SCHEMA_VERSION` increases**, capturing the format you
   are migrating *away* from, before you change the writer.
3. Keep them small and text (base64), so a diff is reviewable and the repo
   stays light.
