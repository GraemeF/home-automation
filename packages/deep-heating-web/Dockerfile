### Build Step
FROM node:lts as builder

WORKDIR /usr/src/app

COPY package.json ./
COPY package-lock.json ./

RUN npm ci
COPY . .

ENV NX_DAEMON=false
ENV CI=true
RUN npx nx run deep-heating-web:build

### Serve Step
FROM node:lts-slim

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

WORKDIR /app

COPY --from=builder /usr/src/app/node_modules .
COPY --from=builder /usr/src/app/package.json .
COPY --from=builder /usr/src/app/package-lock.json .

RUN npm prune --production

COPY --from=builder /usr/src/app/packages/deep-heating-web/package.json .
COPY --from=builder /usr/src/app/dist/packages/deep-heating-web .

CMD ["node", "index.js"]
