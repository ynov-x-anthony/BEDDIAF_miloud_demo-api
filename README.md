# demo-api

Mini-API "catalogue" (`Node` + `Express` + `PostgreSQL`) conteneurisée, servant de fil rouge aux quêtes Docker.

## Lancer la stack avec Docker Compose

La stack contient 2 services métier (`api`, `notifier`), une base et un client SQL :

| Service | Image | Rôle | Réseaux | Accès |
|---|---|---|---|---|
| `api` | construite depuis `./api` (`Dockerfile.multi`) | l'API demo-api | `front` + `back` | http://localhost:8080 |
| `notifier` | construite depuis `./notifier` | reçoit les événements « produit créé » et logge une notification | `back` | **non publié**, appelé seulement par `api` |
| `db` | `postgres:16-alpine` | base PostgreSQL (volume `pgdata`, healthcheck `pg_isready`) | `back` | **non publiée** |
| `adminer` | `adminer:4` | client SQL web | `front` + `back` | http://localhost:8081 |

### Prérequis

- Docker Engine ou Docker Desktop avec **Compose v2** (`docker compose version`)
- Sous Windows : WSL ou Git Bash

### Démarrage

```bash
# 1. variables d'environnement (interpolées dans compose.yml)
cp .env.example .env

# 2. mot de passe de la base (Docker Secrets, jamais commité)
mkdir -p secrets
printf '%s' 'un-mot-de-passe-solide' > secrets/db_password.txt

# 3. build + démarrage en arrière-plan
docker compose up -d --build
```

### Variables (`.env`)

| Variable | Défaut | Rôle |
|---|---|---|
| `POSTGRES_USER` | `demo` | utilisateur PostgreSQL (db et api) |
| `POSTGRES_DB` | `demo` | nom de la base |
| `API_PORT` | `8080` | port hôte de l'API |
| `ADMINER_PORT` | `8081` | port hôte d'Adminer |
| `IMAGE_PREFIX` | `ghcr.io/ynov-x-anthony/beddiaf_miloud_demo-api` | registre des images `api` et `notifier` |
| `TAG` | `local` | version des images (en déploiement : le tag Git, ex. `v1.5.0`) |

`.env` est ignoré par Git, seul `.env.example` est commité.

### Gestion du mot de passe (Docker Secrets)

Le mot de passe n'apparaît ni dans `compose.yml`, ni dans `.env`, ni dans les variables d'environnement des conteneurs :

- `secrets/db_password.txt` (dossier ignoré par Git) est déclaré comme secret `db_password` ;
- `db` le lit via `POSTGRES_PASSWORD_FILE=/run/secrets/db_password` ;
- `api` le charge au démarrage depuis `/run/secrets/db_password` dans `PGPASSWORD`.

### URLs

- API : http://localhost:8080 (`/health`, `/ready`, `/products`)
- Adminer : http://localhost:8081 (système PostgreSQL, serveur `db`, utilisateur `demo`, base `demo`, mot de passe = contenu de `secrets/db_password.txt`)

### Commandes utiles

```bash
docker compose ps              # état des services
docker compose logs -f api     # logs de l'API
docker compose down            # arrête et supprime conteneurs + réseau (GARDE les données)
docker compose up -d           # relance : les données sont toujours là
```

### Repartir de zéro

```bash
docker compose down -v         # supprime aussi le volume pgdata : données perdues, init.sql rejoué au prochain up
```

### Test réalisé

Commande testée : `docker compose up -d --build`, puis :

```text
$ docker compose ps
SERVICE   STATUS                    PORTS
adminer   Up 11 seconds             0.0.0.0:8081->8080/tcp
api       Up 6 seconds (healthy)    0.0.0.0:8080->3000/tcp
db        Up 12 seconds (healthy)   5432/tcp

$ curl -s localhost:8080/products
[{"id":3,"name":"T-shirt conteneur",...},{"id":2,"name":"Mug Docker",...},{"id":1,"name":"Sticker Demo",...}]

$ curl -s -X POST -H 'content-type: application/json' -d '{"name":"Gourde","price_cents":900}' localhost:8080/products
{"id":4,"name":"Gourde","price_cents":900,...}

$ docker compose down && docker compose up -d
$ curl -s localhost:8080/products
[{"id":4,"name":"Gourde","price_cents":900,...},{"id":3,"name":"T-shirt conteneur",...},...]
```

« Gourde » survit au `down` puis `up` : les données sont dans le volume nommé `pgdata`.

## Microservices : le service `notifier`

`notifier` est un service métier à part entière : son propre dossier, son propre `package.json`,
son propre `Dockerfile` durci (base épinglée, non-root, `HEALTHCHECK`) et sa propre image.
`api` ne connaît de lui que son contrat réseau : `POST http://notifier:4000/notify`.

- Après chaque `POST /products` réussi, `api` appelle `notifier` en **best-effort** : l'appel part
  après la réponse, avec un timeout de 2 s, et une erreur est seulement loggée. Une panne de
  `notifier` ne fait jamais échouer la création d'un produit.
- `notifier` est sur le réseau `back` uniquement, sans `ports:` : il est injoignable depuis l'extérieur
  et depuis le réseau `front`.

Test local :

```text
$ docker compose up -d --build
$ curl -s -X POST localhost:8080/products -H "Content-Type: application/json" -d '{"name":"Clavier meca","price_cents":5900}'
{"id":4,"name":"Clavier meca","price_cents":5900,...}
$ docker compose logs notifier | tail -5
notifier-1  | {"level":"info","msg":"notifier started","port":4000}
notifier-1  | [notifier] nouveau produit : {"id":4,"name":"Clavier meca","price_cents":5900}

$ docker compose stop notifier
$ curl -s -w "\nHTTP %{http_code}\n" -X POST localhost:8080/products -H "Content-Type: application/json" -d '{"name":"Souris","price_cents":2500}'
{"id":5,"name":"Souris","price_cents":2500,...}
HTTP 201
api-1  | {"level":"warn","msg":"notify failed","err":"The operation was aborted due to timeout"}
```

## CI/CD (`.github/workflows/ci.yml`)

- **Job `image`** en `matrix` (`api`, `notifier`) : chaque service est buildé, scanné par Trivy
  (HIGH/CRITICAL, `ignore-unfixed`, gate `exit-code: 1` sur les tags `v*`), puis l'image scannée
  est publiée sur `ghcr.io/ynov-x-anthony/beddiaf_miloud_demo-api/<service>:<tag>`.
- **Job `deploy`** (après `image`, seulement sur les tags `v*`) : `docker compose pull` puis
  `docker compose up -d --no-build`, smoke test (`POST /products` puis notification dans les logs de
  `notifier`) et test de panne de `notifier` (`POST /products` reste en 201).

> **Cible de déploiement simulée** : faute de VM, le job `deploy` s'exécute sur le runner GitHub
> (variante autorisée par la quête). La mécanique est celle d'un vrai serveur : aucune image n'est
> reconstruite, ce sont celles publiées sur GHCR. Sur un vrai serveur, les mêmes commandes seraient
> lancées en SSH : `cd /opt/demo-api && git pull && docker compose pull && docker compose up -d`.

Publier une version :

```bash
git tag v1.5.0 && git push origin v1.5.0
```

---

## Point de départ

Ce dossier est ce que tu clones **avant ta première quête Docker**. Il n'y a
volontairement **aucun fichier Docker** dedans, ni `Dockerfile`, ni
`compose.yml` : ce sont précisément les fichiers que tu vas écrire, quête
après quête, en faisant grossir ce dépôt.

Sans conteneur, cette API ne démarre pas telle quelle : elle a besoin d'un
PostgreSQL joignable pour répondre. C'est normal, et c'est tout le sujet de
la première quête que de la faire tourner dans Docker.

## Récupérer ce starter dans ton propre repo

Ce dépôt est un **starter en lecture seule** : tu ne pousses jamais
directement ici. Avant de démarrer la première quête :

1. **Clone** ce repo starter :
   ```bash
   git clone git@github.com:ynov-x-anthony/docker-demo-api-starter.git NOM_prenom_demo-api
   cd NOM_prenom_demo-api
   ```
2. **Supprime le remote `origin`** (il pointe vers le starter, pas vers toi) :
   ```bash
   git remote remove origin
   ```
3. **Crée ton propre repo** sur GitHub, dans l'organisation `ynov-x-anthony`,
   en respectant la nomenclature **`NOM_prenom_demo-api`** (ex. :
   `DUPONT_jean_demo-api`), puis ajoute-le comme nouveau remote et pousse :
   ```bash
   git remote add origin git@github.com:ynov-x-anthony/NOM_prenom_demo-api.git
   git push -u origin main
   ```

À partir de là, c'est **ton** repo : chaque quête s'y ajoute par des commits,
et c'est lui qui sera évalué, pas le starter.

## Ce que contient le repo

| Fichier | Rôle |
|---|---|
| `api/server.js` | l'API Express (`/`, `/version`, `/health`, `/ready`, `/products`) |
| `api/db.js` | connexion PostgreSQL, entièrement pilotée par des variables d'environnement |
| `api/package.json`, `api/package-lock.json` | dépendances (`express`, `pg`) |
| `db/init.sql` | création de la table `products` + quelques données de démo |

## Les routes de l'API

| Méthode | Route | Effet |
|---|---|---|
| `GET` | `/` | infos application + version |
| `GET` | `/version` | numéro de version courant |
| `GET` | `/health` | liveness, ne touche pas la base |
| `GET` | `/ready` | readiness, teste la connexion à la base |
| `GET` | `/products` | liste des produits |
| `POST` | `/products` | crée un produit : `{ "name": "...", "price_cents": 1234 }` |

## Ta progression, quête après quête

| Quête | Ce que tu ajoutes au repo |
|---|---|
| Découverte de Docker | rien ici, tu manipules des images publiques et un `psql` en conteneur |
| Le Dockerfile | `api/Dockerfile`, `api/.dockerignore` : l'API tourne enfin dans un conteneur |
| Les volumes | un volume nommé pour la persistance de PostgreSQL |
| Les réseaux | des réseaux dédiés, la base jamais exposée directement |
| Compose | `compose.yml`, `.env.example` : tous les services démarrent ensemble |
| Dockerfile et sécurité | ton `Dockerfile` durci : utilisateur non-root, `HEALTHCHECK` |
| Builds multi-étapes et gestion des secrets | `api/Dockerfile.multi` : image allégée, secrets hors de l'image |
| Analyse de vulnérabilité avec Trivy | un pipeline CI qui scanne ton image et bloque sur les failles critiques |

## Prérequis machine (macOS / Linux / Windows)

- **Docker Engine + Compose v2** : le plugin intégré, invoqué en deux mots
  `docker compose` (pas l'ancien binaire autonome `docker-compose` v1).
  `docker compose version` doit répondre `v2.x` ou une version supérieure
  (v3, v4, v5…). Ce qui compte, c'est que ce ne soit pas du v1 legacy.
- macOS / Windows : **Docker Desktop** (ou Colima / Rancher Desktop).
  Sous Windows, backend **WSL 2** : travaille depuis un terminal **WSL**.
- `git`, `curl`. Node est nécessaire **seulement** si tu régénères
  `package-lock.json` (`cd api && npm install`, déjà commité ici).
