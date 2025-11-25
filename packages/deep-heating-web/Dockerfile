### Prune Step
FROM node:20.19.5-alpine AS pruner
RUN apk update && apk add --no-cache libc6-compat bash curl unzip
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"
WORKDIR /app
RUN bun add -g turbo@^2
COPY . .
RUN turbo prune @home-automation/deep-heating-web --docker

### Build Step
FROM --platform=$BUILDPLATFORM node:20.19.5-alpine as builder
RUN apk update && apk add --no-cache libc6-compat python3 make g++ bash curl unzip
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"

WORKDIR /app

ARG TARGETOS
ARG TARGETARCH

COPY --from=pruner /app/out/json/ .
RUN bun install

COPY --from=pruner /app/out/full/ .
COPY --from=pruner /app/tsconfig.base.json .
RUN bun run build

# Copy built outputs back to package directories for proper module resolution
RUN mkdir -p /app/packages/deep-heating-types/dist && cp -r /app/dist/out-tsc/packages/deep-heating-types/* /app/packages/deep-heating-types/dist/

RUN bun install --production

### Serve Step
FROM node:20.19.5-alpine

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

EXPOSE 3000

WORKDIR /app

# Copy the entire built workspace structure from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/package.json .
COPY --from=builder /app/bun.lock .

# Copy built SvelteKit output
COPY --from=builder /app/packages/deep-heating-web/package.json .
COPY --from=builder /app/packages/deep-heating-web/.svelte-kit/output .

ENV NODE_ENV=production

CMD ["node", "server/index.js"]
