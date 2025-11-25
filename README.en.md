# Mediathek Backend

End-to-end environment to run the Neutrino Mediathek backend yourself. It
contains everything that used to live on the Coolithek servers:

1. **MariaDB** – persistent storage for the MediathekView catalogue.
2. **Importer (`mv2mariadb`)** – downloads the movie lists and fills MariaDB.
3. **API (`mt-api`)** – the FastCGI/HTTP endpoints consumed by the Neutrino
   plugin.

This repository keeps the glue code (Dockerfiles, compose file, docs). The
actual importer and API sources live in the `vendor/` directory.

---

## Table of contents

1. [What is included?](#what-is-included)
2. [Pick your setup path](#pick-your-setup-path)
   - [Quickstart script (single command)](#quickstart-script-single-command)
   - [Manual compose path](#manual-compose-path)
   - [Verifying & configuring the plugin](#verifying--configuring-the-plugin)
3. [Daily operation](#daily-operation)
4. [Building & publishing Docker images](#building--publishing-docker-images)
5. [Repository layout & developer notes](#repository-layout--developer-notes)
6. [Where to find more details](#where-to-find-more-details)

---

## What is included?

```
mediathek-backend/
├── docker/               # Dockerfiles & entrypoints for importer + API
├── docker-compose.yml    # ready-to-use stack
├── vendor/
│   ├── db-import         # mv2mariadb (cloned via `make vendor`)
│   └── mt-api-dev        # API sources (same)
└── config/, data/        # runtime configs & persistent data
```

The repository does **not** commit the third-party source trees. Run
`make vendor` once to clone them into `vendor/…`.

---

## Pick your setup path

Most users either run the **interactive quickstart script** (all-in-one
workflow) or manage the stack via **docker compose**. Both land at the same
result: MariaDB + Importer + API in Docker containers with named volumes.

### Quickstart script (single command)

Use this whenever you just want a working backend on one host.

```bash
curl -fsSL https://raw.githubusercontent.com/tuxbox-neutrino/mediathek-backend/master/scripts/quickstart.sh -o quickstart.sh
chmod +x quickstart.sh
./quickstart.sh
```

The helper will:

1. Pull the current importer/API images.
2. Start a local MariaDB container (`mediathek-db`).
3. Ask for DB credentials (defaults `root/example-root` for tests).
4. Create config files in `config/importer/` and `config/api/`.
5. Run the importer twice (`--update`, `--force-convert`).
6. Launch long-running importer (`--cron-mode`) and API containers.

The script prints the URL of the API (`http://localhost:18080/mt-api`) at the
end. To stop/remove everything later:

```bash
docker rm -f mediathek-api mediathek-importer mediathek-db
docker volume rm mediathek-backend_mt-api-data mediathek-backend_mt-api-log mediathek-backend_db-import mediathek-backend_mariadb
```

### Manual compose path

Need more control or want to hack on the sources? Clone this repository and
bring the stack up manually.

```bash
# 1) Get the repo + vendor sources
git clone https://github.com/tuxbox-neutrino/mediathek-backend.git
cd mediathek-backend
make vendor          # clones vendor/db-import + vendor/mt-api-dev

# 2) Start MariaDB (persistent volume: mediathek-backend_db_data)
docker compose up -d db

# 3) Build importer & API images from the checked-out sources
docker compose build importer api

# 4) Seed the database
docker compose run --rm importer --update
docker compose run --rm importer    # imports the current movie list

# 5) Launch API + importer cron service
docker compose up -d api importer
```

Directory hints:

- `config/importer/` → importer config (`mv2mariadb.conf`, `pw_mariadb`)
- `data/importer/` → downloaded film lists (safe to delete)
- `config/api/sqlpasswd` → API DB credentials copied to `/opt/api/data/.passwd`

### Verifying & configuring the plugin

*Check status*:

```bash
curl http://localhost:18080/mt-api?mode=api&sub=info
```

You should see JSON with database stats. If the importer is running in cron
mode it refreshes the database roughly every two hours (change
`--cron-mode 120` if needed).

*Use it from Neutrino*: set the plugin base URL to
`http://<host>:18080/mt-api`. The plugin will immediately pick up the locally
populated catalogue.

---

## Daily operation

### Named volumes

The compose file and quickstart script create descriptive volumes so you can
back them up or inspect them easily:

| Volume name                         | Path in container              | Purpose                    |
|------------------------------------|--------------------------------|----------------------------|
| `mediathek-backend_mariadb`        | `/var/lib/mysql`               | MariaDB tables             |
| `mediathek-backend_db-import`      | `/opt/importer/bin/dl`         | Cached film lists          |
| `mediathek-backend_mt-api-data`    | `/opt/api/data`                | API data + passwd file     |
| `mediathek-backend_mt-api-log`     | `/opt/api/log`                 | API access/error logs      |

### Updating containers

Pull the desired tag (or `latest`) and restart the container. Example for the
importer:

```bash
IMAGE_TAG=v0.2.6-0-ga1b2c3d   # or 'latest'

docker pull dbt1/mediathek-importer:${IMAGE_TAG}
docker stop mediathek-importer && docker rm mediathek-importer
docker run -d --name mediathek-importer \
  --network mediathek-net \
  -v "$PWD/config/importer:/opt/importer/config" \
  -v mediathek-backend_db-import:/opt/importer/bin/dl \
  dbt1/mediathek-importer:${IMAGE_TAG} \
  --cron-mode 120 --cron-mode-echo
```

Repeat the same steps for `dbt1/mt-api-dev:${API_TAG}` (mount the two API
volumes plus `config/api`).

### Scheduling the importer yourself

If you prefer cron/systemd on the host:

```bash
0 * * * * docker run --rm --network mediathek-net \
  -v "$PWD/config/importer:/opt/importer/config" \
  -v mediathek-backend_db-import:/opt/importer/bin/dl \
  dbt1/mediathek-importer:latest
```

This launches a one-shot importer once per hour.

---

## Building & publishing Docker images

Automated publishing is disabled by default. To release a new version manually
you only need the backend repo with its vendor checkouts.

```bash
cd mediathek-backend
make vendor   # refresh vendor repos if necessary

# Derive tag+commit-count strings
IMPORTER_VERSION=$(git -C vendor/db-import describe --tags --long --abbrev=7)
API_VERSION=$(git -C vendor/mt-api-dev describe --tags --long --abbrev=7)

# Build multi-arch importer image
docker buildx build --platform linux/amd64,linux/arm64 \
  -t <YOUR_ACCOUNT_NAME>/mediathek-importer:${IMPORTER_VERSION} \
  -t <YOUR_ACCOUNT_NAME>/mediathek-importer:latest \
  -f docker/importer/Dockerfile \
  --push .

# Build multi-arch API image
docker buildx build --platform linux/amd64,linux/arm64 \
  -t <YOUR_ACCOUNT_NAME>/mt-api-dev:${API_VERSION} \
  -t <YOUR_ACCOUNT_NAME>/mt-api-dev:latest \
  -f docker/api/Dockerfile \
  --push .
```

You can also trigger the GitHub workflow
[`Build Docker Images`](.github/workflows/docker-images.yml) manually. It checks
out the repo, runs `make vendor`, reads the tags using the same `git describe`
logic and pushes both images.

---

## Repository layout & developer notes

- `docker/` – Dockerfiles + entrypoints. The importer image compiles
  `mv2mariadb`; the API image builds `mt-api` and copies assets into
  `/opt/api.dist`.
- `config/` / `data/` – host-side directories bind-mounted into the containers.
- `Makefile` – helper targets (`make vendor`, `make smoke`).
- `docs/` – scratchpad for future architecture notes.

Handy commands for contributors:

```bash
make vendor        # clone/refresh vendor repos
make smoke         # run importer + API once and hit /mt-api?mode=api&sub=info
docker compose logs -f importer api db
```

---

## Where to find more details

- **Importer specific docs** –
  [`vendor/db-import/README.en.md`](https://github.com/tuxbox-neutrino/mediathek-backend/blob/master/vendor/db-import/README.en.md)
  (build flags, CLI options, data format).
- **API specific docs** –
  [`vendor/mt-api-dev/README.en.md`](https://github.com/tuxbox-neutrino/mediathek-backend/blob/master/vendor/mt-api-dev/README.en.md)
  (FastCGI endpoints, configuration variables).
- **Quickstart script** – described inside
  [`scripts/quickstart.sh`](https://github.com/tuxbox-neutrino/mediathek-backend/blob/master/scripts/quickstart.sh)
  and referenced above.

If you update any operational detail, please edit this README first so users
have a single up-to-date entry point.
