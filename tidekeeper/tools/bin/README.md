# `tools/bin/` — the Luau VM

`tidekeeper-luau-bench.js` runs the game's pure modules in a **real Luau VM**
rather than in fengari, and that needs a `luau` binary. It is not committed:
19 MB, platform-specific, and reproducible from source in about four minutes.

## Build it

```bash
git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau
make -C /tmp/luau config=release luau -j$(nproc)
cp /tmp/luau/luau tidekeeper/tools/bin/luau
```

Needs `g++` and `make`; no cmake, no network beyond the clone. Pin the tag —
an unpinned VM makes a performance regression indistinguishable from an
upstream change.

Alternatively set `TIDEKEEPER_LUAU=/path/to/luau`, or put `luau` on `$PATH`.
The bench also looks in `/tmp/luau/luau`.

## Why not Lute?

[Lute](https://lute.luau.org/) is the official standalone Luau runtime and is
the better long-term answer: it has a test runner, a sampling profiler, and a
real standard library. Iteration 4 could not use it because this sandbox
cannot reach `release-assets.githubusercontent.com` and Lute needs itself to
bootstrap its own build. The `luau` CLI has the same VM and no bootstrap
problem, so it is what the bench uses. Iteration 5 should revisit Lute.

## What a number from here means

The `luau` CLI embeds the same language runtime Roblox does, at a pinned
version. It is **not** the Roblox engine: no DataModel, different GC tuning,
different build flags, and `--codegen` may not match what a Roblox server
enables. Doc 09 §4 calls this **L3.5**. It is a real Luau number and a fair
order of magnitude. It is not a number measured on Roblox hardware, and the
report says so every time it prints.
