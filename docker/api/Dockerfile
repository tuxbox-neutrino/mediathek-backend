FROM debian:12-slim AS build

ARG SRC_DIR=/opt/src

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      build-essential \
      pkg-config \
      git \
      ca-certificates \
      python3 \
      libmariadb-dev \
      libcurl4-openssl-dev \
      libfcgi-dev \
      libssl-dev \
      rapidjson-dev \
      libtidy-dev \
      libjsoncpp-dev \
      libboost-system-dev \
      sassc \
      && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash builder

# Provide a minimal wrapper so the project's Makefile can call "sass" while we
# rely on the sassc CLI available in Debian.
RUN cat <<'EOF' >/usr/local/bin/sass && chmod +x /usr/local/bin/sass
#!/usr/bin/env bash
set -euo pipefail

style="compressed"
input=""
output=""

while (($#)); do
  case "$1" in
    --sourcemap=none|--default-encoding=*)
      shift
      ;;
    --style=*)
      style="${1#*=}"
      shift
      ;;
    *)
      if [[ -z "$input" ]]; then
        input="$1"
      elif [[ -z "$output" ]]; then
        output="$1"
      else
        echo "[sass-wrapper] Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$input" || -z "$output" ]]; then
  echo "Usage: sass [options] input.scss output.css" >&2
  exit 1
fi

sassc --style "$style" "$input" "$output"
EOF

WORKDIR ${SRC_DIR}

COPY vendor/mt-api-dev ${SRC_DIR}/mt-api-dev

RUN chown -R builder:builder ${SRC_DIR}

USER builder

WORKDIR ${SRC_DIR}/mt-api-dev

RUN cp doc/config.mk.sample config.mk && \
    sed -i 's/USE_COMPILER\t\t= CLANG/USE_COMPILER\t\t= GCC/' config.mk && \
    sed -i 's/COMPILER_VER\t= clang50/COMPILER_VER\t= gcc/' config.mk && \
    sed -i 's/COMPILER_VER\t= gcc7/COMPILER_VER\t= gcc/' config.mk && \
    sed -i 's/ENABLE_SANITIZER\t= 1/ENABLE_SANITIZER\t= 0/' config.mk && \
    echo 'STDC++ = -std=c++14' >> config.mk && \
    echo 'EXTRA_CXXFLAGS += -Wno-error=ignored-qualifiers' >> config.mk && \
    bash -lc 'set -euo pipefail; \
      echo "root:example-root" > sqlpasswd; \
      SASS=/usr/local/bin/sass EXTRA_INCLUDES="-I/usr/include/jsoncpp" make -j"$(nproc)"'

USER root

RUN mkdir -p /opt/pkg/www /opt/pkg/bin /opt/pkg/data/.passwd && \
    cp -a /opt/src/mt-api-dev/build/mt-api /opt/pkg/bin/mt-api && \
    cp -a /opt/src/mt-api-dev/build/src/css /opt/pkg/www/ && \
    cp -a /opt/src/mt-api-dev/src/web/www/. /opt/pkg/www/ && \
    cp -a /opt/src/mt-api-dev/src/web/data/. /opt/pkg/data/ && \
    cp /opt/src/mt-api-dev/sqlpasswd /opt/pkg/data/.passwd/sqlpasswd && \
    (cd /opt/src/mt-api-dev && git describe --tags --always --dirty 2>/dev/null > /opt/pkg/VERSION || echo "unknown" > /opt/pkg/VERSION) && \
    cat <<'EOF' > /opt/pkg/www/mt-api.cgi && \
    chmod +x /opt/pkg/www/mt-api.cgi && \
    chown -R root:root /opt/pkg
#!/bin/sh
SCRIPT_DIR="$(dirname "$0")"
REQUEST_URI="${REQUEST_URI:-}"
PATH_INFO="${PATH_INFO:-}"
QUERY_STRING="${QUERY_STRING:-}"

prepend_query() {
	if [ -n "$QUERY_STRING" ]; then
		QUERY_STRING="$1&$QUERY_STRING"
	else
		QUERY_STRING="$1"
	fi
}

normalize_path() {
	case "$1" in
		*/api.html) echo "/api.html" ;;
		*/api/listChannels) echo "/listChannels" ;;
		*/api/listLivestream*) echo "/listLivestream" ;;
		*/api/info) echo "/info" ;;
		*/api) echo "/" ;;
		*) echo "" ;;
	esac
}

for candidate in "$PATH_INFO" "$(normalize_path "$REQUEST_URI")"; do
	case "$candidate" in
		"/api.html")
			if [ -z "$QUERY_STRING" ]; then
				QUERY_STRING="mode=api"
			fi
			;;
		"/listChannels")
			prepend_query "mode=api&sub=listChannels"
			;;
		"/listLivestream")
			prepend_query "mode=api&sub=listLivestream"
			;;
		"/info")
			prepend_query "mode=api&sub=info"
			;;
		"/")
			prepend_query "mode=api"
			;;
	esac
done

export QUERY_STRING
export DOCUMENT_ROOT="${SCRIPT_DIR}"
export HOME="/opt/api"
exec /opt/api/bin/mt-api "$@"
EOF

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    API_HOME=/opt/api

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      libmariadb3 \
      libcurl4 \
      libtidy5deb1 \
      libjsoncpp25 \
      libboost-system1.74.0 \
      spawn-fcgi \
      lighttpd \
      && rm -rf /var/lib/apt/lists/*

RUN mkdir -p ${API_HOME}/config ${API_HOME}/www ${API_HOME}/data ${API_HOME}/log

COPY --from=build /opt/pkg/www /opt/api.dist/www
COPY --from=build /opt/pkg/data /opt/api.dist/data
COPY --from=build /opt/pkg/bin /opt/api.dist/bin

COPY docker/api/entrypoint.sh /usr/local/bin/api-entrypoint
COPY docker/api/lighttpd.conf /etc/lighttpd/lighttpd.conf

RUN chmod +x /usr/local/bin/api-entrypoint

WORKDIR ${API_HOME}

ENV API_DIST_DIR=/opt/api.dist

VOLUME ["/opt/api/data", "/opt/api/log", "/opt/api/config"]

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/api-entrypoint"]
