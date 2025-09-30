### Prune Step
FROM node:20.18.3-alpine AS pruner
RUN apk update && apk add --no-cache libc6-compat
WORKDIR /app
RUN npm install -g turbo@^2
COPY . .
RUN turbo prune deep-heating-socketio --docker

### Build Step
FROM --platform=$BUILDPLATFORM node:20.18.3-alpine as builder
RUN apk update && apk add --no-cache libc6-compat python3 make g++

WORKDIR /app

ARG TARGETOS
ARG TARGETARCH

COPY --from=pruner /app/out/json/ .
RUN npm install --target_arch=$TARGETARCH --target_platform=$TARGETOS

COPY --from=pruner /app/out/full/ .
COPY --from=pruner /app/tsconfig.base.json .
RUN npm run build

RUN npm prune --omit=dev

### Serve Step
FROM node:20.18.3-alpine

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json .
COPY --from=builder /app/package-lock.json .

COPY --from=builder /app/dist/out-tsc/packages/deep-heating-socketio/src .

ENV NODE_ENV=production

CMD ["node", "main.js"]
