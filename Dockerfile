# ==============================================================================
# ESTÁGIO 1: Builder (Download de Drivers e Extração Limpa)
# ==============================================================================
FROM debian:bookworm-slim AS builder
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /tmp/build

# Verificação de integridade do Oracle Instant Client: a Oracle não publica mais
# checksum para essa versão (pacote parado desde 2021, fora da página oficial de
# downloads atuais), então o hash abaixo foi capturado de um download verificado
# do domínio oficial da Oracle. Protege builds futuros contra corrupção/adulteração
# do artefato em trânsito.
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    unzip \
    tar \
    ca-certificates \
    binutils \
    && rm -rf /var/lib/apt/lists/* \
    && wget https://download.oracle.com/otn_software/linux/instantclient/213000/instantclient-basiclite-linux.x64-21.3.0.0.0.zip \
    && echo "ddbe84d7b96927a6a1de25d88c2d49e00eed6d43793000eeffde693840ff82c1  instantclient-basiclite-linux.x64-21.3.0.0.0.zip" | sha256sum -c - \
    && unzip instantclient-basiclite-linux.x64-21.3.0.0.0.zip

# Copia dinamicamente qualquer arquivo tar.gz/TAR.GZ vindo do portal da TOTVS
COPY ./*.[tT][aA][rR].[gG][zZ] ./dbaccess.tar.gz

RUN mkdir -p dbaccess_extracao /tmp/out_dbaccess \
    && tar -xzf dbaccess.tar.gz -C dbaccess_extracao/ \
    && (cp -R dbaccess_extracao/*/* /tmp/out_dbaccess/ 2>/dev/null || cp -R dbaccess_extracao/* /tmp/out_dbaccess/)

# 🧹 1. Faxina de pastas pesadas de desenvolvimento e debug da TOTVS
RUN rm -rf /tmp/out_dbaccess/debug \
           /tmp/out_dbaccess/dbtools \
           /tmp/out_dbaccess/*.log \
           /tmp/out_dbaccess/*.pdf

# ⚡ 2. Remoção de símbolos de debug dos executáveis e bibliotecas do DbAccess
RUN find /tmp/out_dbaccess/ -type f -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true
RUN strip --strip-unneeded /tmp/out_dbaccess/dbaccess64 2>/dev/null || true
RUN strip --strip-unneeded /tmp/out_dbaccess/dbaccesscfg 2>/dev/null || true

# ==============================================================================
# ESTÁGIO 2: Runner (Imagem Otimizada e Dinâmica)
# ==============================================================================
FROM debian:bookworm-slim AS runner
LABEL maintainer="Rodrigo dos Santos Brandão <rodrigomicrosiga>"
LABEL version="24.1.1.3"
LABEL description="TOTVS DBAccess 24.1.1.3 - Ultra Light"

# Ajuste seguro da definição das variáveis sem tentar concatenar com $LD_LIBRARY_PATH inexistente
ENV DEBIAN_FRONTEND=noninteractive \
    ORACLE_HOME=/opt/oracle/instantclient_21_3 \
    LD_LIBRARY_PATH=/opt/oracle/instantclient_21_3

# OTIMIZAÇÃO: Trocado 'unixodbc-dev' por apenas 'unixodbc' para economizar dezenas de megabytes
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg2 \
    gettext-base \
    netcat-openbsd \
    unixodbc \
    odbc-postgresql \
    libc6 \
    libtinfo6 \
    libstdc++6 \
    libaio1 \
    && curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y msodbcsql18 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 🚀 LINK SIMBÓLICO CIRÚRGICO: Cria o ponteiro libodbc.so exigido pelo binário do DbAccess
RUN ln -sf /usr/lib/x86_64-linux-gnu/libodbc.so.2 /usr/lib/x86_64-linux-gnu/libodbc.so

# Usuário não-root: porta 7890 (não-privilegiada) e nenhum acesso especial ao
# host é necessário -- só precisa de escrita em /opt/totvs/dbaccess (log/ e
# multi/dbaccess.ini, gerados em runtime pelo entrypoint).
RUN useradd -r -M -d /opt/totvs/dbaccess -s /usr/sbin/nologin dbaccess

# Copia os diretórios limpos e preparados do builder
COPY --from=builder /tmp/build/instantclient_21_3 /opt/oracle/instantclient_21_3
COPY --from=builder --chown=dbaccess:dbaccess /tmp/out_dbaccess /opt/totvs/dbaccess/multi/
COPY ./entrypoint.sh /usr/local/bin/entrypoint.sh

RUN echo /opt/oracle/instantclient_21_3 > /etc/ld.so.conf.d/oracle-instantclient.conf \
    && ldconfig \
    && chmod +x /usr/local/bin/entrypoint.sh \
    && (chmod +x /opt/totvs/dbaccess/multi/dbaccess64 2>/dev/null || true) \
    && chmod -R 755 /opt/totvs/dbaccess/multi/ \
    && mkdir -p /opt/totvs/dbaccess/log \
    && chown -R dbaccess:dbaccess /opt/totvs/dbaccess

WORKDIR /opt/totvs/dbaccess/multi
USER dbaccess
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]