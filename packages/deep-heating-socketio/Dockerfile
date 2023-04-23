### Build Step
FROM node:20.0.0 as builder

RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

COPY package.json ./
COPY package-lock.json ./

RUN npm ci
COPY . .

ENV NX_DAEMON=false
ENV CI=true
RUN npx nx run deep-heating-socketio:build

### Serve Step
FROM node:20.0.0-slim

RUN apt-get update && apt-get install -y \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

WORKDIR /app

COPY --from=builder /usr/src/app/node_modules .
COPY --from=builder /usr/src/app/package.json .
COPY --from=builder /usr/src/app/package-lock.json .

RUN npm prune --omit=dev

COPY --from=builder /usr/src/app/dist/packages/deep-heating-socketio .

CMD ["node", "main.js"]
