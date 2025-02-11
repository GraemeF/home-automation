### Build Step
FROM --platform=$BUILDPLATFORM node:20.18.3 as builder

WORKDIR /usr/src/app

COPY package.json ./
COPY package-lock.json ./

ARG TARGETOS
ARG TARGETARCH

RUN npm ci --target_arch=$TARGETARCH --target_platform=$TARGETOS
COPY . .

ENV NX_DAEMON=false
ENV CI=true
RUN npx nx run deep-heating-socketio:build
RUN npx nx run deep-heating-web:build

RUN npm prune --omit=dev

### Serve Step
FROM node:20.18.3-slim

# Add nginx and create the run folder for nginx.
RUN apt-get update && apt-get install -y \
  nginx \
  && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /run/nginx

RUN npm i -g pm2

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

WORKDIR /app

COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/package.json .
COPY --from=builder /usr/src/app/package-lock.json .

COPY --from=builder /usr/src/app/dist/packages/deep-heating-web ./deep-heating-web
COPY --from=builder /usr/src/app/packages/deep-heating-web/package.json ./deep-heating-web

COPY --from=builder /usr/src/app/dist/packages/deep-heating-socketio ./deep-heating-socketio
COPY --from=builder /usr/src/app/package.json ./deep-heating-socketio

COPY --from=builder /usr/src/app/packages/deep-heating/assets/ingress.conf /etc/nginx/nginx.conf
COPY --from=builder /usr/src/app/packages/deep-heating/assets/process.json .

CMD ["pm2", "start", "--no-daemon", "process.json"]
