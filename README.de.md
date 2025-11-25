# Mediathek Backend

Vollständige Umgebung, um das Neutrino-Mediathek-Backend selbst zu betreiben.
Sie ersetzt die ehemalige Coolithek-Infrastruktur und besteht aus:

1. **MariaDB** – persistente Datenbank mit dem MediathekView-Katalog.
2. **Importer (`mv2mariadb`)** – lädt die Filmliste und füllt MariaDB.
3. **API (`mt-api`)** – stellt die JSON/HTML-Endpunkte für das Neutrino-Plugin
   bereit.

Dieses Repository enthält die Dockerfiles, Compose-Datei und Dokumentation.
Die eigentlichen Quellen liegen im Ordner `vendor/`.

---

## Inhaltsverzeichnis

1. [Was ist enthalten?](#was-ist-enthalten)
2. [Weg zur eigenen Installation](#weg-zur-eigenen-installation)
   - [Quickstart-Skript](#quickstart-skript)
   - [Manueller Compose-Weg](#manueller-compose-weg)
   - [Ergebnis prüfen & Plugin konfigurieren](#ergebnis-prüfen--plugin-konfigurieren)
3. [Betrieb im Alltag](#betrieb-im-alltag)
4. [Docker-Images selbst bauen & veröffentlichen](#docker-images-selbst-bauen--veröffentlichen)
5. [Repository-Struktur & Hinweise für Entwickler](#repository-struktur--hinweise-für-entwickler)
6. [Weitere Informationen](#weitere-informationen)

---

## Was ist enthalten?

```
mediathek-backend/
├── docker/               # Dockerfiles & EntryPoints für Importer + API
├── docker-compose.yml    # sofort nutzbarer Stack
├── vendor/
│   ├── db-import         # mv2mariadb (per `make vendor`)
│   └── mt-api-dev        # API-Quellen
└── config/, data/        # Konfigurations- und Datenverzeichnisse
```

Die Upstream-Projekte werden nicht eingecheckt. Einmalig `make vendor` ausführen
und sie landen unter `vendor/...`.

---

## Weg zur eigenen Installation

Es gibt zwei Möglichkeiten: das **interaktive Quickstart-Skript** (ideal für
Einsteiger) oder den **manuellen Compose-Weg** (mehr Kontrolle).

### Quickstart-Skript

```bash
curl -fsSL https://raw.githubusercontent.com/tuxbox-neutrino/mediathek-backend/master/scripts/quickstart.sh -o quickstart.sh
chmod +x quickstart.sh
./quickstart.sh
```

Das Skript erledigt:

1. Pull der aktuellen Importer-/API-Images.
2. Start einer lokalen MariaDB (`mediathek-db`).
3. Abfrage bzw. Setzen der Zugangsdaten (Standard: `root/example-root`).
4. Schreiben der Konfigurationsdateien in `config/importer/` und `config/api/`.
5. Zwei Importläufe (`--update`, `--force-convert`).
6. Start der Dauerläufer `mediathek-importer` und `mediathek-api`.

Am Ende erscheint die URL `http://localhost:18080/mt-api`. Stoppen lässt sich
alles mit:

```bash
docker rm -f mediathek-api mediathek-importer mediathek-db
docker volume rm mediathek-backend_mt-api-data mediathek-backend_mt-api-log mediathek-backend_db-import mediathek-backend_mariadb
```

### Manueller Compose-Weg

```bash
git clone https://github.com/tuxbox-neutrino/mediathek-backend.git
cd mediathek-backend
make vendor

docker compose up -d db                 # MariaDB (Volume: mediathek-backend_db_data)
docker compose build importer api       # Images aus den aktuellen Quellen
docker compose run --rm importer --update
docker compose run --rm importer        # kompletten Import durchführen
docker compose up -d api importer       # API + Cron-Importer starten
```

Wichtige Pfade:

- `config/importer/` – Einstellungen (`mv2mariadb.conf`, `pw_mariadb`)
- `data/importer/` – heruntergeladene Listen (können gelöscht werden)
- `config/api/sqlpasswd` – Zugangsdaten für die API

### Ergebnis prüfen & Plugin konfigurieren

*Status prüfen*:

```bash
curl http://localhost:18080/mt-api?mode=api&sub=info
```

*Neutrino-Plugin*: Basis-URL auf `http://<host>:18080/mt-api` setzen, danach
liest das Plugin automatisch die lokale Datenbank.

---

## Betrieb im Alltag

### Verwendete Volumes

| Volume                             | Pfad im Container            | Zweck                      |
|------------------------------------|------------------------------|----------------------------|
| `mediathek-backend_mariadb`        | `/var/lib/mysql`             | MariaDB-Daten              |
| `mediathek-backend_db-import`      | `/opt/importer/bin/dl`       | Cache der Filmlisten       |
| `mediathek-backend_mt-api-data`    | `/opt/api/data`              | API-Daten & .passwd        |
| `mediathek-backend_mt-api-log`     | `/opt/api/log`               | API-Logs                   |

### Container aktualisieren

```bash
IMAGE_TAG=v0.2.6-0-ga1b2c3d   # oder 'latest'

docker pull dbt1/mediathek-importer:${IMAGE_TAG}
docker stop mediathek-importer && docker rm mediathek-importer
docker run -d --name mediathek-importer \
  --network mediathek-net \
  -v "$PWD/config/importer:/opt/importer/config" \
  -v mediathek-backend_db-import:/opt/importer/bin/dl \
  dbt1/mediathek-importer:${IMAGE_TAG} \
  --cron-mode 120 --cron-mode-echo
```

Für die API entsprechend (`dbt1/mt-api-dev:${API_TAG}`) zwei Volumes plus
`config/api` mounten.

### Importer selbst schedulen

```bash
0 * * * * docker run --rm --network mediathek-net \
  -v "$PWD/config/importer:/opt/importer/config" \
  -v mediathek-backend_db-import:/opt/importer/bin/dl \
  dbt1/mediathek-importer:latest
```

---

## Docker-Images selbst bauen & veröffentlichen

```bash
cd mediathek-backend
make vendor

IMPORTER_VERSION=$(git -C vendor/db-import describe --tags --long --abbrev=7)
API_VERSION=$(git -C vendor/mt-api-dev describe --tags --long --abbrev=7)

docker buildx build --platform linux/amd64,linux/arm64 \
  -t dbt1/mediathek-importer:${IMPORTER_VERSION} \
  -t dbt1/mediathek-importer:latest \
  -f docker/importer/Dockerfile \
  --push .

docker buildx build --platform linux/amd64,linux/arm64 \
  -t dbt1/mt-api-dev:${API_VERSION} \
  -t dbt1/mt-api-dev:latest \
  -f docker/api/Dockerfile \
  --push .
```

Der GitHub-Workflow
[`Build Docker Images`](.github/workflows/docker-images.yml) macht genau das,
wenn er manuell gestartet wird (`workflow_dispatch`).

---

## Repository-Struktur & Hinweise für Entwickler

- `docker/` – Dockerfiles und EntryPoints.
- `config/`, `data/` – werden direkt in die Container gemountet.
- `vendor/` – enthält die echten Quelltexte (nicht im Repo versioniert).
- `Makefile` – hilfreiche Targets (`make vendor`, `make smoke`).

Nützliche Befehle:

```bash
make vendor
make smoke
docker compose logs -f importer api db
```

---

## Weitere Informationen

- **Importer-Doku**: [`vendor/db-import/README.de.md`](vendor/db-import/README.de.md)
- **API-Doku**: [`vendor/mt-api-dev/README.de.md`](vendor/mt-api-dev/README.de.md)
- **Quickstart-Skript**:
  [`scripts/quickstart.sh`](scripts/quickstart.sh)

Bitte Änderungen am Betrieb zuerst hier dokumentieren – so haben Anwender eine
einheitliche Anlaufstelle.
