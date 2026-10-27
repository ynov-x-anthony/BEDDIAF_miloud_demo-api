#!/usr/bin/env bash
# Fil rouge, étape 3 : isoler la base derrière l'API avec deux réseaux personnalisés.
# À lancer depuis la racine du repo demo-api (Linux, macOS, WSL ou Git Bash).
set -euo pipefail

FRONT=demo_front
BACK=demo_back
REPO_DIR="$PWD"

# Git Bash (Windows) : chemin hôte au format C:/... et pas de conversion auto des chemins
if command -v cygpath >/dev/null 2>&1; then
  REPO_DIR="$(cygpath -m "$PWD")"
  export MSYS_NO_PATHCONV=1
fi

show_ips() {
  echo "-> $1 :"
  docker inspect -f '{{range $net, $conf := .NetworkSettings.Networks}}   {{$net}} : IPv4={{$conf.IPAddress}}{{"\n"}}{{end}}' "$1"
}

echo "== 0. nettoyage d'un éventuel run précédent"
docker rm -f demo-api demo-db >/dev/null 2>&1 || true
docker network rm "$FRONT" "$BACK" >/dev/null 2>&1 || true

echo "== 1. build de l'image API"
docker build -q -t demo-api:1.0 ./api

echo "== 2. création des réseaux personnalisés (pas le bridge par défaut)"
docker network create "$FRONT"
docker network create "$BACK"

echo "== 3. base demo-db : réseau demo_back UNIQUEMENT, aucun port publié"
docker run -d --name demo-db --network "$BACK" \
  -v "$REPO_DIR/db/init.sql":/docker-entrypoint-initdb.d/init.sql:ro \
  -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
  postgres:16-alpine >/dev/null
until docker exec demo-db pg_isready -U demo -d demo >/dev/null 2>&1; do sleep 1; done
until docker exec demo-db psql -U demo -d demo -c 'SELECT 1 FROM products LIMIT 1' >/dev/null 2>&1; do sleep 1; done
echo "-> base prête"

echo "== 4. API demo-api : demo_front + demo_back, publiée sur 8080"
docker run -d --name demo-api --network "$FRONT" -p 8080:3000 \
  -e PGHOST=demo-db demo-api:1.0 >/dev/null
docker network connect "$BACK" demo-api
until curl -sf localhost:8080/health >/dev/null; do sleep 1; done
echo "-> API prête"

echo "== 5. vérifications"
echo "-> ports publiés sur l'hôte (HostConfig.PortBindings) :"
for c in demo-db demo-api; do
  printf "   %s : %s
" "$c" "$(docker inspect -f '{{if .HostConfig.PortBindings}}{{json .HostConfig.PortBindings}}{{else}}aucun{{end}}' "$c")"
done

echo "-> résolution de demo-db depuis demo-api (docker exec demo-api getent hosts demo-db) :"
docker exec demo-api getent hosts demo-db

docker pull -q alpine:3.20 >/dev/null
echo "-> conteneur tiers sur demo_front SEULEMENT (docker run --rm --network demo_front alpine nc -zv demo-db 5432) :"
if docker run --rm --network "$FRONT" alpine:3.20 nc -zv -w 3 demo-db 5432 2>&1; then
  echo "ÉCHEC : demo-db est joignable depuis demo_front" >&2
  exit 1
else
  echo "OK : demo-db injoignable depuis demo_front (aucun réseau commun)"
fi

echo "-> adresses IPv4 par réseau :"
show_ips demo-db
show_ips demo-api

echo "-> curl -s localhost:8080/products :"
curl -s localhost:8080/products
echo

echo "== 6. nettoyage"
docker rm -f demo-api demo-db >/dev/null
docker network rm "$FRONT" "$BACK" >/dev/null
echo "-> conteneurs et réseaux supprimés"
