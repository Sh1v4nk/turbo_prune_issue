# Repro: `turbo prune --docker` emits invalid `bun.lock`

Minimal Bun monorepo where `turbo prune --docker` produces a lockfile
that `bun install --frozen-lockfile` rejects. Full write-up: [`ISSUE.md`](./ISSUE.md).

## Shape

- `apps/web` depends on `@repo/shared`
- `apps/ws` (workspace named `ws`) depends on `@repo/shared` and `ioredis`
- `packages/shared` depends on npm `ws`

## Run

```bash
bun install
bun install --frozen-lockfile                       # control: passes
bunx turbo@2.10.11 prune web --docker --out-dir out-web
bun install --frozen-lockfile --cwd out-web/json    # fails, see ISSUE.md
```

Docker path (fails at the frozen step):

```bash
docker build -t prune-repro .
```

## Files

| File | Purpose |
|---|---|
| `ISSUE.md` | Step-by-step report (post to `vercel/turborepo`) |
| `Dockerfile` | Same failure inside Docker |
| `package.json`, `bun.lock`, `turbo.json`, `apps/`, `packages/` | Minimal repo |
