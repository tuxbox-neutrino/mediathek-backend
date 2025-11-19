FROM debian:12-slim AS build

ARG SRC_DIR=/opt/src

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      pkg-config \
      git \
      ca-certificates \
      libmariadb-dev \
      libmariadb-dev-compat \
      libcurl4-openssl-dev \
      liblzma-dev \
      libexpat1-dev \
      && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 --branch v1.0.2 https://github.com/Tencent/rapidjson.git /tmp/rapidjson && \
    cp -r /tmp/rapidjson/include/rapidjson /usr/local/include/ && \
    rm -rf /tmp/rapidjson

WORKDIR /work

COPY vendor/db-import ${SRC_DIR}/db-import

WORKDIR ${SRC_DIR}/db-import

RUN cp doc/config.mk.sample config.mk && \
    sed -i 's/USE_COMPILER\t\t= CLANG/USE_COMPILER\t\t= GCC/' config.mk && \
    sed -i 's/COMPILER_VER\t= clang50/COMPILER_VER\t= gcc/' config.mk && \
    sed -i 's/COMPILER_VER\t= gcc7/COMPILER_VER\t= gcc/' config.mk && \
    sed -i 's/ENABLE_SANITIZER\t= 1/ENABLE_SANITIZER\t= 0/' config.mk && \
    echo 'EXTRA_CXXFLAGS += -Wno-error=deprecated-declarations -Wno-error=unused-value' >> config.mk && \
    CXX=g++ LD=g++ make -j"$(nproc)"

FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive \
    IMPORTER_HOME=/opt/importer

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      libmariadb3 \
      libcurl4 \
      liblzma5 \
      libexpat1 \
      && rm -rf /var/lib/apt/lists/*

RUN mkdir -p ${IMPORTER_HOME}/bin ${IMPORTER_HOME}/bin/dl ${IMPORTER_HOME}/config ${IMPORTER_HOME}/work

COPY --from=build /opt/src/db-import/build/mv2mariadb ${IMPORTER_HOME}/bin/mv2mariadb
COPY --from=build /opt/src/db-import/src/sql ${IMPORTER_HOME}/bin/sql
COPY docker/importer/entrypoint.sh /usr/local/bin/importer-entrypoint

RUN chmod +x /usr/local/bin/importer-entrypoint

WORKDIR ${IMPORTER_HOME}

VOLUME ["/opt/importer/bin/dl", "/opt/importer/config"]

ENTRYPOINT ["/usr/local/bin/importer-entrypoint"]
