FROM node:20.18.3-alpine AS base
RUN apk update && apk add --no-cache libc6-compat
WORKDIR /app

### Prune Step
FROM base AS pruner
RUN npm install -g turbo@^2
COPY . .
RUN turbo prune deep-heating-socketio @home-automation/deep-heating-web --docker

### Build Step
FROM base AS builder
RUN apk add --no-cache python3 make g++

COPY --from=pruner /app/out/json/ .
RUN npm install

COPY --from=pruner /app/out/full/ .
COPY --from=pruner /app/tsconfig.base.json .
RUN npm run build

# Copy built outputs back to package directories for proper module resolution
RUN mkdir -p /app/packages/deep-heating-types/dist && cp -r /app/dist/out-tsc/packages/deep-heating-types/* /app/packages/deep-heating-types/dist/ && \
    mkdir -p /app/packages/deep-heating-rx/dist && cp -r /app/dist/out-tsc/packages/deep-heating-rx/* /app/packages/deep-heating-rx/dist/ && \
    mkdir -p /app/packages/deep-heating-home-assistant/dist && cp -r /app/dist/out-tsc/packages/deep-heating-home-assistant/* /app/packages/deep-heating-home-assistant/dist/ && \
    mkdir -p /app/packages/deep-heating-state/dist && cp -r /app/dist/out-tsc/packages/deep-heating-state/* /app/packages/deep-heating-state/dist/ && \
    mkdir -p /app/packages/rxx/dist && cp -r /app/dist/out-tsc/packages/rxx/* /app/packages/rxx/dist/

### Production dependencies
FROM base AS prod-deps
COPY --from=pruner /app/out/json/ .
RUN npm install --omit=dev

### Serve Step
FROM node:20.18.3-alpine AS runner

RUN apk update && apk add --no-cache nginx
RUN mkdir -p /run/nginx

RUN npm i -g pm2

LABEL org.opencontainers.image.source="https://github.com/GraemeF/home-automation"

WORKDIR /app

# Copy the entire built workspace structure from builder
# This preserves workspace symlinks and package structure
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/package-lock.json ./package-lock.json

# Copy built outputs for socketio
COPY --from=builder /app/dist ./dist

# Copy built SvelteKit output for web
COPY --from=builder /app/packages/deep-heating-web/.svelte-kit/output ./packages/deep-heating-web/.svelte-kit/output
COPY --from=builder /app/packages/deep-heating-web/package.json ./packages/deep-heating-web/package.json

# Copy nginx config and PM2 process file
COPY --from=pruner /app/packages/deep-heating/assets/ingress.conf /etc/nginx/nginx.conf
COPY --from=pruner /app/packages/deep-heating/assets/process.json .

ENV NODE_ENV=production

CMD ["pm2", "start", "--no-daemon", "process.json"]