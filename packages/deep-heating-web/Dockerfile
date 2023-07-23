### Build Step
FROM --platform=$BUILDPLATFORM node:20.5.0 as builder

WORKDIR /usr/src/app

COPY package.json ./
COPY package-lock.json ./

ARG TARGETOS
ARG TARGETARCH

RUN npm ci --target_arch=$TARGETARCH --target_platform=$TARGETOS
COPY . .

RUN npx nx run deep-heating-web:build

RUN npm prune --omit=dev

### Serve Step
FROM node:20.5.0-slim

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

EXPOSE 3000

WORKDIR /app

COPY --from=builder /usr/src/app/package.json .
COPY --from=builder /usr/src/app/package-lock.json .
COPY --from=builder /usr/src/app/node_modules ./node_modules

COPY --from=builder /usr/src/app/packages/deep-heating-web/package.json .
COPY --from=builder /usr/src/app/dist/packages/deep-heating-web .

CMD ["node", "index.js"]
