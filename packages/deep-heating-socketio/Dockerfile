### Build Step
FROM node:18.4.0 as builder

WORKDIR /usr/src/app

COPY package.json ./
COPY package-lock.json ./

RUN npm ci
COPY . .

ENV NX_DAEMON=false
ENV CI=true
RUN npx nx run deep-heating-socketio:build

### Serve Step
FROM node:18.4.0-slim

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

WORKDIR /app

COPY --from=builder /usr/src/app/package.json .
COPY --from=builder /usr/src/app/package-lock.json .

RUN npm ci --omit=dev

COPY --from=builder /usr/src/app/dist/packages/deep-heating-socketio .

CMD ["node", "main.js"]
