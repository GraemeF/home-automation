### Build Step
FROM node:lts as builder

WORKDIR /usr/src/app

COPY package.json ./
COPY package-lock.json ./

RUN npm ci
COPY . .

RUN npx nx run deep-heating:build

### Serve Step
FROM node:lts-slim

WORKDIR /app

COPY --from=builder /usr/src/app/package.json .
COPY --from=builder /usr/src/app/package-lock.json .

RUN npm ci --production

COPY --from=builder /usr/src/app/packages/deep-heating/package.json .
COPY --from=builder /usr/src/app/dist/packages/deep-heating .

CMD ["node", "index.js"]
