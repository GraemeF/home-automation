### Prune Step
FROM node:20.19.5-alpine AS pruner
RUN apk update && apk add --no-cache libc6-compat
WORKDIR /app
RUN npm install -g turbo@^2
COPY . .
RUN turbo prune deep-heating-socketio --docker

### Build Step
FROM --platform=$BUILDPLATFORM node:20.19.5-alpine as builder
RUN apk update && apk add --no-cache libc6-compat python3 make g++

WORKDIR /app

ARG TARGETOS
ARG TARGETARCH

COPY --from=pruner /app/out/json/ .
RUN npm install --target_arch=$TARGETARCH --target_platform=$TARGETOS

COPY --from=pruner /app/out/full/ .
COPY --from=pruner /app/tsconfig.base.json .
RUN npm run build

# Copy built outputs back to package directories for proper module resolution
RUN mkdir -p /app/packages/deep-heating-types/dist && cp -r /app/dist/out-tsc/packages/deep-heating-types/* /app/packages/deep-heating-types/dist/ && \
    mkdir -p /app/packages/deep-heating-rx/dist && cp -r /app/dist/out-tsc/packages/deep-heating-rx/* /app/packages/deep-heating-rx/dist/ && \
    mkdir -p /app/packages/deep-heating-home-assistant/dist && cp -r /app/dist/out-tsc/packages/deep-heating-home-assistant/* /app/packages/deep-heating-home-assistant/dist/ && \
    mkdir -p /app/packages/deep-heating-state/dist && cp -r /app/dist/out-tsc/packages/deep-heating-state/* /app/packages/deep-heating-state/dist/ && \
    mkdir -p /app/packages/rxx/dist && cp -r /app/dist/out-tsc/packages/rxx/* /app/packages/rxx/dist/

RUN npm prune --omit=dev

### Serve Step
FROM node:20.19.5-alpine

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

WORKDIR /app

# Copy the entire built workspace structure from builder
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/package.json .
COPY --from=builder /app/package-lock.json .

# Copy built socketio output
COPY --from=builder /app/dist/out-tsc/packages/deep-heating-socketio/src .

ENV NODE_ENV=production

CMD ["node", "main.js"]
