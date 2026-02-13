FROM node:22-alpine AS deps
WORKDIR /app

# Install workspace dependencies using lockfiles for reproducible builds.
COPY package.json package-lock.json ./
COPY packages/shared/package.json packages/shared/package-lock.json ./packages/shared/
COPY packages/web/package.json packages/web/package-lock.json ./packages/web/
RUN npm ci

FROM node:22-alpine AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

RUN npm run build -w @open-inspect/shared \
  && npm run build -w @open-inspect/web

FROM node:22-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

RUN addgroup -S nextjs && adduser -S nextjs -G nextjs

COPY --from=builder --chown=nextjs:nextjs /app/packages/web/.next/standalone ./
COPY --from=builder --chown=nextjs:nextjs /app/packages/web/.next/static ./packages/web/.next/static
COPY --from=builder --chown=nextjs:nextjs /app/packages/web/public ./packages/web/public

USER nextjs

EXPOSE 3000

CMD ["node", "packages/web/server.js"]
