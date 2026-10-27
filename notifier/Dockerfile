# syntax=docker/dockerfile:1

# Base épinglée et récente, même principe durci que api/Dockerfile.multi
ARG NODE_IMAGE=node:22.23.4-alpine3.24

# --- étape deps : dépendances de prod uniquement ----------------------------
FROM ${NODE_IMAGE} AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# --- étape runtime : minimale, non-root -------------------------------------
FROM ${NODE_IMAGE} AS runtime
# Correctifs OS + retrait de npm/yarn/corepack, inutiles pour exécuter le service
RUN apk upgrade --no-cache \
 && rm -rf /usr/local/lib/node_modules /usr/local/bin/npm /usr/local/bin/npx \
           /usr/local/bin/corepack /opt/yarn* /usr/local/bin/yarn /usr/local/bin/yarnpkg
ENV NODE_ENV=production
WORKDIR /app
COPY --from=deps --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node server.js package.json ./
USER node
EXPOSE 4000
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:'+(process.env.PORT||4000)+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "server.js"]
