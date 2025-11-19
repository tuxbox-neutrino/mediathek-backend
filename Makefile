SHELL := /bin/bash

VENDOR_DIR := vendor
MT_API_REPO := https://github.com/tuxbox-neutrino/mt-api-dev.git
DB_IMPORT_REPO := https://github.com/tuxbox-neutrino/db-import.git
COMPOSE ?= docker-compose

.PHONY: vendor vendor-update clean smoke

vendor:
	@mkdir -p "$(VENDOR_DIR)"
	@set -euo pipefail; \
	if [[ ! -d "$(VENDOR_DIR)/mt-api-dev/.git" ]]; then \
		echo "[vendor] Cloning mt-api-dev ..."; \
		git clone --depth=1 "$(MT_API_REPO)" "$(VENDOR_DIR)/mt-api-dev"; \
	else \
		echo "[vendor] mt-api-dev already present."; \
	fi; \
	if [[ ! -d "$(VENDOR_DIR)/db-import/.git" ]]; then \
		echo "[vendor] Cloning db-import ..."; \
		git clone --depth=1 "$(DB_IMPORT_REPO)" "$(VENDOR_DIR)/db-import"; \
	else \
		echo "[vendor] db-import already present."; \
	fi

vendor-update: $(VENDOR_DIR)
	@set -euo pipefail; \
	for repo in mt-api-dev db-import; do \
		if [[ -d "$(VENDOR_DIR)/$$repo/.git" ]]; then \
			echo "[vendor-update] Updating $$repo ..."; \
			git -C "$(VENDOR_DIR)/$$repo" fetch origin --tags; \
			git -C "$(VENDOR_DIR)/$$repo" reset --hard origin/HEAD; \
		else \
			echo "[vendor-update] $$repo missing – run 'make vendor' first." >&2; \
		fi; \
	done

clean:
	@rm -rf "$(VENDOR_DIR)"

smoke:
	@set -euo pipefail; \
	echo "[smoke] Recreating compose stack"; \
	cleanup() { $(COMPOSE) down >/dev/null 2>&1 || true; }; \
	trap cleanup EXIT; \
	$(COMPOSE) down >/dev/null 2>&1 || true; \
	$(COMPOSE) build importer api; \
	$(COMPOSE) up -d db; \
	echo "[smoke] Waiting for MariaDB ..."; \
	for i in {1..30}; do \
		if $(COMPOSE) exec -T db mariadb-admin ping -uroot -pexample-root --silent >/dev/null 2>&1; then \
			echo "[smoke] MariaDB is ready."; \
			break; \
		fi; \
		sleep 1; \
		if [[ $$i -eq 30 ]]; then \
			echo "[smoke] MariaDB did not become ready in time." >&2; \
			exit 1; \
		fi; \
	done; \
	$(COMPOSE) run --rm importer --update; \
	$(COMPOSE) run --rm importer; \
	$(COMPOSE) up -d api; \
	for i in {1..30}; do \
		if curl -fsS http://localhost:18080/mt-api?mode=api\&sub=info >/dev/null 2>&1; then \
			echo "[smoke] API responded with valid JSON."; \
			break; \
		fi; \
		sleep 1; \
		if [[ $$i -eq 30 ]]; then \
			echo "[smoke] API did not become ready in time." >&2; \
			exit 1; \
		fi; \
	done
