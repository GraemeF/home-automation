### Prune Step
FROM node:20.18.3-alpine AS pruner
RUN apk update && apk add --no-cache libc6-compat
WORKDIR /app
RUN npm install -g turbo@^2
COPY . .
RUN turbo prune deep-heating-socketio @home-automation/deep-heating-web --docker

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

# Add nginx and create the run folder for nginx.
RUN apk update && apk add --no-cache nginx

RUN mkdir -p /run/nginx

RUN npm i -g pm2

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json .
COPY --from=builder /app/package-lock.json .

COPY --from=builder /app/packages/deep-heating-web/.svelte-kit/output ./deep-heating-web
COPY --from=builder /app/packages/deep-heating-web/package.json ./deep-heating-web

COPY --from=builder /app/dist/out-tsc/packages/deep-heating-socketio/src ./deep-heating-socketio
COPY --from=builder /app/package.json ./deep-heating-socketio

COPY --from=pruner /app/packages/deep-heating/assets/ingress.conf /etc/nginx/nginx.conf
COPY --from=pruner /app/packages/deep-heating/assets/process.json .

ENV NODE_ENV=production

CMD ["pm2", "start", "--no-daemon", "process.json"]
