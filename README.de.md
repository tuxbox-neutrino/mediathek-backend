# Mediathek Backend Sandbox

Dies ist ein neuer Sandbox-Bereich, um das ehemalige Coolithek‑Backend unter
eigener Kontrolle aufzubauen. Er besteht aus drei Bausteinen:

1. **MariaDB** – hält die aufbereiteten MediathekView‑Daten.
2. **Importer (`mv2mariadb`)** – lädt die Filmliste von `res.mediathekview.de`,
   wandelt sie um und aktualisiert die Datenbank.
3. **API (`mt-api`)** – stellt die JSON/HTML‑Endpunkte für das Neutrino‑Plugin
   bereit.

Die ursprünglich betriebene Infrastruktur steht nicht mehr zur Verfügung;
Passwörter und Server sind nicht erreichbar. Dieses Verzeichnis dient deshalb
als neutraler Startpunkt, um die Komponenten als Container zu paketieren,
lokal zu testen und später per GitHub Actions automatisiert zu veröffentlichen.

## Verzeichnisstruktur

```
.
├── Makefile              # Helfer, um die Upstream-Repositories zu spiegeln
├── docker/               # Dockerfiles & Entrypoints für Importer/API
├── docker-compose.yml    # Lokales Compose-Setup (Work in Progress)
├── docs/                 # WIP: zusätzliche Architektur-Notizen
└── vendor/               # (gitignored) Klone von mt-api-dev & db-import
```

Die eigentlichen Upstream-Projekte werden nicht eingecheckt, sondern in
`vendor/` abgelegt. Damit bleiben die Lizenzhistorien unangetastet und Updates
lassen sich jederzeit nachziehen.

## Erste Schritte

> Komfortabler geht es mit dem
> [mt-api-dev-Repository](https://github.com/tuxbox-neutrino/mt-api-dev):
> [Quickstart-Skript](https://github.com/tuxbox-neutrino/mt-api-dev/blob/master/scripts/quickstart.sh):
> Es klont dieses Backend, zieht die Vendor-Repos und startet
> das Compose-Setup automatisch.

```bash
# Dieses Repository (Compose-Setup) klonen
git clone https://github.com/tuxbox-neutrino/mediathek-backend.git
cd mediathek-backend

# Upstream-Repositories für Importer & API klonen (einmalig)
make vendor

# MariaDB starten (Persistentes Volume: docker volume mediathek-backend_db_data)
docker-compose up -d db

# Importer-Image bauen
docker-compose build importer

# Template-Database anlegen (erzeugt mediathek_1_template)
docker-compose run --rm importer --update

# Erste vollständige Konvertierung durchführen
docker-compose run --rm importer
```

Die Konfiguration des Importers liegt unter `config/importer/`. Standardmäßig
nutzt `pw_mariadb` den MariaDB-Root-Account (`root:example-root`), damit neue
Schemas wie `mediathek_1_tmp1` und `mediathek_1` angelegt werden können. Für
eine produktive Umgebung sollte hier mittelfristig ein dedizierter Benutzer mit
den notwendigen Rechten zum Einsatz kommen.

Alle Zwischendateien (Film-Listen, entpackte JSONs) landen unter
`data/importer/` und werden vom Repository per `.gitignore` ausgeschlossen.

Nachfolgende Läufe des Importers aktualisieren die bereits vorhandene Datenbank
und kosten auf aktueller Hardware ~80 Sekunden für ~685.000 Einträge.

### API-Container

```bash
# API-Image bauen
docker-compose build api

# API-Service starten (host-Port 18080 -> Container 8080)
docker-compose up -d api

# Funktionscheck
curl http://localhost:18080/mt-api?mode=api&sub=info
```

Der API-Container initialisiert unter `/opt/api.dist` eine Referenzkopie der
Web-Ressourcen und Templates. Beim ersten Start werden diese Inhalte in die
Volumes `api_data` und `api_log` (siehe `docker-compose.yml`) kopiert. Eigene
Datenbank-Zugangsdaten können via `config/api/sqlpasswd` hinterlegt werden; das
Entry-Script schreibt die Datei automatisch nach `/opt/api/data/.passwd`.
Die HTTP-Antworten enthalten unverändertes JSON (kein URL-Encoding mehr), was
die Verwendung mit `curl` oder Browser-Entwicklertools vereinfacht.

### Automatisierter Smoke-Test

```bash
make smoke
```

Der Smoke-Test baut beide Images, startet MariaDB/API einmal komplett durch,
führt den Importer (inklusive Template-Update) aus und prüft mit `curl`, ob der
Endpoint `mode=api&sub=info` gültiges JSON liefert. Nach Abschluss räumt er die
Compose-Umgebung automatisch wieder auf.

### Neutrino-Plugin anbinden

Sobald Importer und API durchgelaufen sind, stellt die API die gleichen
Endpunkte bereit, die das Neutrino-Mediathek-Plugin erwartet. Für lokale Tests
genügt es, in den Plugin-Einstellungen die Basis-URL auf
`http://localhost:18080/mt-api` zu setzen (bzw. die IP des Hosts). Das Plugin
erhält damit wieder aktuelle Daten aus der frisch befüllten Datenbank.

## Docker-Images manuell bauen & veröffentlichen

Der automatische Workflow ist aktuell deaktiviert. Um neue Images zu veröffentlichen,
baue sie lokal mit der jeweils getaggtet Version und `latest`. Die Versionsnummern
kommen direkt aus den Upstream-Repositories:

Importer (`dbt1/mediathek-importer`, Version aus `vendor/db-import/VERSION`;
vom Repository-Wurzelverzeichnis aus):

```bash
IMPORTER_VERSION=$(grep -Po '(?<=VERSION=")[^"]+' vendor/db-import/VERSION)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t dbt1/mediathek-importer:${IMPORTER_VERSION} \
  -t dbt1/mediathek-importer:latest \
  -f docker/importer/Dockerfile \
  --push .
```

API (`dbt1/mt-api-dev`, Version per Git-Tag; ebenfalls aus dem Projektwurzelverzeichnis):

```bash
API_VERSION=$(git -C vendor/mt-api-dev describe --tags --abbrev=0)
docker buildx build --platform linux/amd64,linux/arm64 \
  -t dbt1/mt-api-dev:${API_VERSION} \
  -t dbt1/mt-api-dev:latest \
  -f docker/api/Dockerfile \
  --push .
```

Damit landen immer sowohl der konkrete Release-Tag als auch `latest` im Docker Hub.

### Lokale Umgebung aktualisieren

Sobald das neue Image online ist, kannst du deine laufenden Container entweder
auf `latest` oder einen konkreten Tag aktualisieren. Beispiel für den Importer:

```bash
# gewünschte Version auswählen
IMAGE_TAG=0.2.4    # oder 'latest'

docker pull dbt1/mediathek-importer:${IMAGE_TAG}
docker stop mediathek-importer && docker rm mediathek-importer
docker run -d --name mediathek-importer \
  --network mediathek-net \
  -v "$PWD/config/importer:/opt/importer/config" \
  -v "$PWD/data/importer:/opt/importer/data" \
  dbt1/mediathek-importer:${IMAGE_TAG}
```

Analog funktioniert das mit dem API-Container (`dbt1/mt-api-dev:${API_TAG}`).
Passe Netzwerk/Volumes an deine lokale Umgebung an.

## Offene Aufgaben

- API-Stack härten: HTTPS/Reverse-Proxy, optionaler Authentifizierungsschutz
  sowie Healthchecks für den FastCGI-Worker ergänzen.
- Automatisierung: Cron-ähnliche Ausführung des Importers in Compose oder via
  GitHub Actions, Upload der erzeugten Datenbank-Dumps/JSONs.
- Sicherheitsfeinschliff: dedizierten MariaDB-User mit minimalen Rechten
  definieren und Zugangsdaten aus Secrets speisen.
- End-to-End-Smoke-Test, der das Neutrino-Plugin gegen die lokale API
  validiert.

Diese Datei dient als wachsende Dokumentation für alle Beteiligten in der
Community. Feedback willkommen!
