### Build Step
FROM --platform=$BUILDPLATFORM node:20.8.1 as builder

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

RUN npm prune --omit=dev

### Serve Step
FROM node:20.8.1-slim

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

WORKDIR /app

COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/package.json .
COPY --from=builder /usr/src/app/package-lock.json .

COPY --from=builder /usr/src/app/dist/packages/deep-heating-socketio .

CMD ["node", "main.js"]
