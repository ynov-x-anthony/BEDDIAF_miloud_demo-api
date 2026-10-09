# Base Node épinglée sur une version mineure précise
FROM node:22.11-alpine

WORKDIR /app

# Dépendances d'abord (cache), fichiers attribués à l'utilisateur non-root "node"
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Code applicatif ensuite
COPY --chown=node:node server.js db.js ./

# Port non privilégié (>= 1024)
EXPOSE 3000

# Sonde de santé légère sur /health
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://localhost:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

# Bascule en non-root juste avant le CMD
USER node

CMD ["node", "server.js"]
