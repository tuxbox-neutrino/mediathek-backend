# Mediathek Backend Sandbox

This directory is a fresh sandbox to rebuild the former Coolithek backend
under our own control. It is composed of three building blocks:

1. **MariaDB** – stores the normalized MediathekView data.
2. **Importer (`mv2mariadb`)** – downloads the movie list from
   `res.mediathekview.de`, converts it and updates the database.
3. **API (`mt-api`)** – exposes the JSON/HTML endpoints consumed by the
   Neutrino Mediathek plugin.

The previously operated infrastructure is no longer available; credentials and
servers cannot be used. This sandbox packages the components into containers so
they can be tested locally and later published via GitHub Actions.

## Layout

```
.
├── Makefile              # helpers to mirror the upstream repositories
├── docker/               # Dockerfiles & entrypoints for importer/API
├── docker-compose.yml    # local compose stack (work in progress)
├── docs/                 # WIP notes
└── vendor/               # (gitignored) clones of mt-api-dev & db-import
```

The upstream projects are not committed to this repository. Instead, run
`make vendor` to clone them into `vendor/`, keeping their histories intact and
making future updates trivial.

## Getting Started

> Prefer a one-shot helper? The
> [mt-api-dev repository](https://github.com/tuxbox-neutrino/mt-api-dev) ships
> [scripts/quickstart.sh](https://github.com/tuxbox-neutrino/mt-api-dev/blob/master/scripts/quickstart.sh)
> which clones this backend, pulls the vendor repos and boots the compose stack
automatically.

```bash
# Clone this repository (includes the docker-compose setup)
git clone https://github.com/tuxbox-neutrino/mediathek-backend.git
cd mediathek-backend

# Clone the upstream importer/API repositories (once)
make vendor

# Start MariaDB (persistent volume: docker volume mediathek-backend_db_data)
docker-compose up -d db

# Build the importer image
docker-compose build importer

# Prepare the template database (creates mediathek_1_template)
docker-compose run --rm importer --update

# Run the first full conversion
docker-compose run --rm importer
```

Importer configuration is stored in `config/importer/`. By default the
`pw_mariadb` file uses the MariaDB root account (`root:example-root`) so that
schemas such as `mediathek_1_tmp1` and `mediathek_1` can be created. For a
production deployment you should switch to a dedicated account with the proper
permissions.

All intermediate artifacts (movie lists, unpacked JSON files, …) land in
`data/importer/` and are `.gitignore`d.

Subsequent importer runs update the existing database and currently take about
80 seconds on modern hardware for ~685k entries.

### API Container

```bash
# Build the API image
docker-compose build api

# Start the API service (host port 18080 -> container 8080)
docker-compose up -d api

# Quick check
curl http://localhost:18080/mt-api?mode=api&sub=info
```

On the first start the API container copies static assets from `/opt/api.dist`
into the persistent `api_data` and `api_log` volumes (see `docker-compose.yml`).
Custom database credentials can be placed in `config/api/sqlpasswd`; the
entrypoint copies the file to `/opt/api/data/.passwd`. HTTP responses now carry
plain JSON (no URL encoding), which makes inspection via `curl` or browser
devtools straightforward.

### Automated Smoke Test

```bash
make smoke
```

The smoke test builds both images, boots MariaDB+API, executes the importer
(including the template update) and finally uses `curl` to request
`mode=api&sub=info`. The compose stack is cleaned up automatically afterwards.

### Wiring the Neutrino Plugin

Once importer and API have finished, the API exposes the same endpoints the
Neutrino Mediathek plugin expects. For local tests simply set the plugin base
URL to `http://localhost:18080/mt-api` (or the host's IP). The plugin will then
receive fresh data from the locally populated database.

## Manually building & pushing Docker images

Automated Docker builds are currently disabled. To publish new images yourself,
build them locally with both the explicit version tag and `latest`. The version
numbers come straight from the upstream repositories:

Importer (`dbt1/mediathek-importer`, version read from `vendor/db-import/VERSION`;
run from the repository root):

```bash
IMPORTER_VERSION=$(grep -Po '(?<=VERSION=")[^"]+' vendor/db-import/VERSION)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t dbt1/mediathek-importer:${IMPORTER_VERSION} \
  -t dbt1/mediathek-importer:latest \
  -f docker/importer/Dockerfile \
  --push .
```

API (`dbt1/mt-api-dev`, version via Git tag; also from the repository root):

```bash
API_VERSION=$(git -C vendor/mt-api-dev describe --tags --abbrev=0)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t dbt1/mt-api-dev:${API_VERSION} \
  -t dbt1/mt-api-dev:latest \
  -f docker/api/Dockerfile \
  --push .
```

This ensures the Docker Hub always carries both the exact release tag and `latest`.

### Updating a running setup

Once the new image is published, refresh your containers either to `latest` or a
specific tag. Example for the importer:

```bash
# choose the desired tag
IMAGE_TAG=0.2.4    # or 'latest'

docker pull dbt1/mediathek-importer:${IMAGE_TAG}
docker stop mediathek-importer && docker rm mediathek-importer
docker run -d --name mediathek-importer \
  --network mediathek-net \
  -v "$PWD/config/importer:/opt/importer/config" \
  -v "$PWD/data/importer:/opt/importer/data" \
  dbt1/mediathek-importer:${IMAGE_TAG}
```

Do the same for the API container (`dbt1/mt-api-dev:${API_TAG}`), adjusting the
network/volume settings to your environment.

## Open Tasks

- Harden the API stack: HTTPS/reverse proxy, optional auth, health checks for
  the FastCGI worker.
- Automation: cron-like importer execution via Compose or GitHub Actions and
  publication of the generated dumps/JSON feeds.
- Security hardening: run the database with a dedicated user and manage secrets
  via environment/secret files.
- End-to-end smoke test that exercises the Neutrino plugin against the local
  API.

Feedback is welcome!
