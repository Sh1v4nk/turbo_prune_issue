# Same failure inside Docker: build MUST fail at the frozen step.
# When turbo fixes prune, this build goes green unchanged.
FROM oven/bun:1.4.2-alpine AS pruner
WORKDIR /app

COPY turbo.json .
COPY package.json .
COPY bun.lock .
COPY apps ./apps
COPY packages ./packages
RUN bunx turbo@2.10.11 prune web --docker

FROM oven/bun:1.4.2-alpine AS installer
WORKDIR /app

COPY --from=pruner /app/out/json/ .
RUN bun install --frozen-lockfile --ignore-scripts
