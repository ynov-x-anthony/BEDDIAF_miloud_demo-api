# Base Node légère et épinglée
FROM node:22-alpine

WORKDIR /app

# Dépendances d'abord : cette couche reste en cache tant que les manifestes ne changent pas
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Code applicatif ensuite
COPY server.js db.js ./

EXPOSE 3000

CMD ["node", "server.js"]
