# `turbo prune --docker` emits invalid `bun.lock`: flattened keys collide with workspace names + ghost stanzas dangle deps

## Summary

`turbo prune --docker` produces a `bun.lock` that `bun install --frozen-lockfile` rejects, in **two distinct ways**. Root `bun.lock` is valid; only the pruned `out/json/bun.lock` breaks. Trigger shape: **a workspace named identically to a transitive npm package** (here workspace `ws` + npm `ws` via `@repo/shared`), plus any pruned-out workspace.

## Environment

- turbo 2.10.11 (`bunx turbo@2.10.11`, banner confirms)
- bun 1.4.2
- Linux x64 (also reproduced inside `oven/bun:1.4.2-alpine` Docker builder)
- Repro repo: linked in this issue (root + `apps/web`, `apps/ws`, `packages/shared`)
- Verified on canary: `2.10.13-canary.4` still fails with the same `Duplicate package path` error

`turbo info` output:

```text
CLI:
   Version: 2.10.13-canary.4
   Daemon status: Not running
   Package manager: bun

Platform:
   Architecture: x86_64
   Operating system: linux
   WSL: false
   Available memory (MB): 5572
   Available CPU cores: 16

Environment:
   CI: None
   Terminal (TERM): xterm-256color
   Shell (SHELL): /bin/bash
   Node.js version: v24.13.0
```

## Step-by-step reproduction

### Step 0: setup

```bash
git clone <repro-link> && cd turbo_prune
bun install
```

### Step 1: control (root lockfile is valid)

```bash
bun install --frozen-lockfile
```

Expected and actual: install succeeds without touching the lockfile (`(no changes)`).

### Step 2: defect 1 (pruned web lockfile, duplicate path)

```bash
bunx turbo@2.10.11 prune web --docker --out-dir out-web
bun install --frozen-lockfile --cwd out-web/json
```

Expected: install succeeds, lockfile untouched.
Actual:

```text
bun install v1.4.2 (744846f84)
96 |     "ws": ["ws@8.21.3", "", { "peerDependencies": { ... } ...
          ^
error: Duplicate package path
    at bun.lock:96:5
InvalidLockfile: failed to parse lockfile: 'bun.lock'

warn: Ignoring lockfile
error: lockfile had changes, but lockfile is frozen
```

### Step 3: defect 2 (ghost stanza dangles a dep)

Work around defect 1 by restoring bun's nested key, then rerun:

```bash
sed -i 's|^    "ws": \["ws@|    "@repo/shared/ws": ["ws@|' out-web/json/bun.lock
bun install --frozen-lockfile --cwd out-web/json
```

Expected: install succeeds.
Actual:

```text
5 |     "": {
          ^
error: Failed to resolve prod dependency 'ioredis' for package 'ws'
    at bun.lock:5:9
InvalidLockfile: failed to parse lockfile: 'bun.lock'

warn: Ignoring lockfile
error: lockfile had changes, but lockfile is frozen
```

### Step 4: same collision on the other scope (no sed involved)

```bash
bunx turbo@2.10.11 prune ws --docker --out-dir out-ws
bun install --frozen-lockfile --cwd out-ws/json
```

Expected: install succeeds.
Actual: `error: Duplicate package path` (same as step 2).

## Root cause (root vs pruned lockfile diff)

Root `bun.lock` (valid) keeps the two concepts apart:

```text
"ws": ["ws@workspace:apps/ws"],          # workspace link
"@repo/shared/ws": ["ws@8.21.3", ...],   # nested npm package
```

Pruned `out/json/bun.lock`:

1. **Drops the workspace-link entry and flattens the npm package to top-level** `"ws"`, which now collides with the workspace *name* `ws` (retained via the `apps/ws` stanza) → `Duplicate package path`.
2. **Retains the ghost `apps/ws` workspace stanza** (with its `ioredis` dep) even though `apps/ws` is out of scope and its packages were pruned, while `package.json` workspaces correctly list only `["packages/shared", "apps/web"]` → dangling `ioredis` ref.

## Expected

Pruned lockfile either keeps bun's nested key (`"@repo/shared/ws"`) or drops out-of-scope workspace stanzas with their deps, so `--frozen-lockfile` passes for the documented Docker pattern.

## Workaround (current, in production Dockerfiles)

```dockerfile
RUN sed -i '/^    "apps\/ws": {$/,/^    },$/d; s|^    "ws": \["ws@|    "@repo/shared/ws": ["ws@|' bun.lock
RUN bun install --frozen-lockfile --ignore-scripts
```

Happy to verify any fix against this repro (stable and canary).

## Related (checked, different defects)

- #12156 (fixed #12228): turbo *added* nested entries bun never wrote; here it *flattens* bun's nested key into a collision. Opposite direction.
- #12653 (fixed #12686): silent frozen drift (`lockfile had changes`, no parse error); here bun names two structural errors.
- #12744 (fixed #12754): dropped a nested dep entry for a *kept* package (`InvalidPackageInfo`); here defect 2 keeps a *ghost out-of-scope workspace stanza*. Same error class, different mechanism.
- #13204 (fixed #13207): dangling `webpack` for `@types/webpack` (`InvalidPackageInfo`); no workspace involved.
- #13233 (fixed #13236): nested version conflict (`@floating-ui/*` resolved multiple times, `InvalidPackageInfo`); here every package resolves once (single `ws@8.18.3`), the conflict is key-vs-workspace-name.
- #13310 (fixed #13317): silent frozen drift (`extraneous-entries`); no parse error.

Defect 1 fails as `InvalidLockfile: Duplicate package path`; none of the above report that error. All six closed before `2.10.13-canary.4`, which still reproduces this report, so it is an uncovered shape, not a regression of a fixed one.
