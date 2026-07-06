# ==============================================================================
# ESTÁGIO 1: Builder (Download de Drivers com SSL Validado)
# ==============================================================================
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp/build

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    unzip \
    tar \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && wget https://download.oracle.com/otn_software/linux/instantclient/213000/instantclient-basiclite-linux.x64-21.3.0.0.0.zip \
    && unzip instantclient-basiclite-linux.x64-21.3.0.0.0.zip

COPY ./dbaccess.tar.gz .
RUN mkdir -p dbaccess_extracao /tmp/out_dbaccess \
    && tar -xzf dbaccess.tar.gz -C dbaccess_extracao/ \
    && (cp -R dbaccess_extracao/*/* /tmp/out_dbaccess/ 2>/dev/null || cp -R dbaccess_extracao/* /tmp/out_dbaccess/)

# ==============================================================================
# ESTÁGIO 2: Runner (Imagem Otimizada e Dinâmica)
# ==============================================================================
FROM ubuntu:22.04 AS runner
LABEL maintainer="Rodrigo dos Santos Brandão <rodrigomicrosiga>"
LABEL version="24.1.1.3"


ENV DEBIAN_FRONTEND=noninteractive \
    ORACLE_HOME=/opt/oracle/instantclient_21_3 \
    LD_LIBRARY_PATH=/opt/oracle/instantclient_21_3:$LD_LIBRARY_PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl ca-certificates gnupg2 gettext-base netcat-openbsd \
    unixodbc unixodbc-dev odbc-postgresql libc6 libtinfo5 libstdc++6 libaio1 \
    && curl https://packages.microsoft.com/keys/microsoft.asc | apt-key add - \
    && curl https://packages.microsoft.com/config/ubuntu/22.04/prod.list > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y msodbcsql18 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /tmp/build/instantclient_21_3 /opt/oracle/instantclient_21_3
COPY --from=builder /tmp/out_dbaccess /opt/totvs/dbaccess/multi/
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

RUN echo /opt/oracle/instantclient_21_3 > /etc/ld.so.conf.d/oracle-instantclient.conf \
    && ldconfig \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && (chmod +x /opt/totvs/dbaccess/multi/dbaccess64 2>/dev/null || true) \
    && chmod -R 755 /opt/totvs/dbaccess/multi/

WORKDIR /opt/totvs/dbaccess/multi
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]