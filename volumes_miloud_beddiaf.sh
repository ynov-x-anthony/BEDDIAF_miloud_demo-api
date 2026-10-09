#!/usr/bin/env bash
# Fil rouge, étape 2 : persistance de demo-api avec un named volume.
# À lancer depuis la racine du repo demo-api (Linux, macOS, WSL ou Git Bash).
set -euo pipefail

VOLUME=demo_pgdata
NETWORK=demo_net
REPO_DIR="$PWD"

# Git Bash (Windows) : chemin hôte au format C:/... et pas de conversion auto des chemins
if command -v cygpath >/dev/null 2>&1; then
  REPO_DIR="$(cygpath -m "$PWD")"
  export MSYS_NO_PATHCONV=1
fi

start_db() {
  docker run -d --name demo-db --network "$NETWORK" \
    -v "$VOLUME":/var/lib/postgresql/data \
    -v "$REPO_DIR/db/init.sql":/docker-entrypoint-initdb.d/init.sql:ro \
    -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
    postgres:16-alpine >/dev/null
  echo "-> attente de la base..."
  until docker exec demo-db pg_isready -U demo -d demo >/dev/null 2>&1; do sleep 1; done
  # pg_isready peut répondre pendant l'init : on attend que la table soit requêtable
  until docker exec demo-db psql -U demo -d demo -c 'SELECT 1 FROM products LIMIT 1' >/dev/null 2>&1; do sleep 1; done
  echo "-> base prête"
}

start_api() {
  docker run -d --name demo-api --network "$NETWORK" -p 8080:3000 \
    -e PGHOST=demo-db demo-api:1.0 >/dev/null
  until curl -sf localhost:8080/health >/dev/null; do sleep 1; done
  echo "-> API prête"
}

echo "== 0. nettoyage d'un éventuel run précédent (le volume est conservé)"
docker rm -f demo-api demo-db >/dev/null 2>&1 || true
docker network rm "$NETWORK" >/dev/null 2>&1 || true

echo "== 1. build de l'image API"
docker build -q -t demo-api:1.0 ./api

echo "== 2. création du volume et du réseau"
docker volume create "$VOLUME"
docker network create "$NETWORK" >/dev/null

echo "== 3. lancement de la base + de l'API"
start_db
start_api

echo "== 4. ajout d'un produit"
curl -s -X POST -H 'content-type: application/json' \
  -d '{"name":"Casquette D\u00e9mo","price_cents":1200}' localhost:8080/products
echo
echo "-> GET /products AVANT suppression de la base :"
curl -s localhost:8080/products
echo

echo "== 5. suppression du conteneur de base puis recréation sur le même volume"
docker rm -f demo-db demo-api >/dev/null
start_db
start_api

echo "== 6. vérification"
docker volume ls | grep "$VOLUME"
echo "-> GET /products APRÈS recréation de la base :"
PRODUCTS="$(curl -s localhost:8080/products)"
echo "$PRODUCTS"
if echo "$PRODUCTS" | grep -q "Casquette Démo"; then
  echo "OK : « Casquette Démo » a survécu à la recréation du conteneur de base"
else
  echo "ÉCHEC : produit introuvable" >&2
  exit 1
fi

echo "== 7. nettoyage (le volume est gardé pour prouver la persistance)"
docker rm -f demo-api demo-db >/dev/null
docker network rm "$NETWORK" >/dev/null
# Pour tout effacer, données comprises :
# docker volume rm demo_pgdata
