# ==============================================================================
# ESTÁGIO 1: Builder
# ==============================================================================
FROM ubuntu:22.04 AS builder
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    tar \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/totvs_dbaccess

# Copia o instalador de forma relativa
COPY ./dbaccess.tar.gz .

RUN tar -xzf dbaccess.tar.gz \
    && rm dbaccess.tar.gz

# ==============================================================================
# ESTÁGIO 2: Final Runtime (64 bits Puro)
# ==============================================================================
FROM ubuntu:22.04
ENV DEBIAN_FRONTEND=noninteractive

LABEL maintainer="Rodrigo dos Santos Brandão <rodrigomicrosiga>"
LABEL version="24.1.1"
LABEL description="TOTVS DBAccess 24.1.1"

WORKDIR /totvs/dbaccess

# Copia os binários de 64 bits do estágio de build
COPY --from=builder /tmp/totvs_dbaccess/dbaccess .

# Instala apenas as dependências essenciais de sistema em 64 bits
RUN apt-get update && apt-get install -y --no-install-recommends \
    libuuid1 \
    && rm -rf /var/lib/apt/lists/*

EXPOSE 7890

CMD ["./dbaccess"]