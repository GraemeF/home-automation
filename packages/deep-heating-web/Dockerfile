### Prune Step
FROM node:20.18.3-alpine AS pruner
RUN apk update && apk add --no-cache libc6-compat
WORKDIR /app
RUN npm install -g turbo@^2
COPY . .
RUN turbo prune @home-automation/deep-heating-web --docker

### Build Step
FROM --platform=$BUILDPLATFORM node:20.18.3-alpine as builder
RUN apk update && apk add --no-cache libc6-compat

WORKDIR /app

ARG TARGETOS
ARG TARGETARCH

COPY --from=pruner /app/out/json/ .
RUN npm ci --target_arch=$TARGETARCH --target_platform=$TARGETOS

COPY --from=pruner /app/out/full/ .
RUN npm run build

RUN npm prune --omit=dev

### Serve Step
FROM node:20.18.3-alpine

LABEL org.opencontainers.image.source = "https://github.com/GraemeF/home-automation"

EXPOSE 3000

WORKDIR /app

COPY --from=builder /app/package.json .
COPY --from=builder /app/package-lock.json .
COPY --from=builder /app/node_modules ./node_modules

COPY --from=builder /app/packages/deep-heating-web/package.json .
COPY --from=builder /app/dist/packages/deep-heating-web .

ENV NODE_ENV=production

CMD ["node", "index.js"]
