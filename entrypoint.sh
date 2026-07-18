#!/bin/bash
set -e

echo "=== [dbAccess] Iniciando processo de configuração dinâmica ==="

# Normaliza o dicionário de variáveis caso o ecossistema (K8s) envie o padrão universal
DB_NAME="${DB_NAME:-$DB_DATABASE}"
DB_PASS="${DB_PASS:-$DB_PASSWORD}"

# Normaliza a variável DB_TYPE para maiúsculas para evitar quebras se digitado 'postgres' ou 'oracle' no .env
DB_TYPE_NORM=$(echo "$DB_TYPE" | tr '[:lower:]' '[:upper:]')

# 1. Valida o tipo de banco e define o alvo de rede de forma agnóstica (K8s / Compose)
if [ "$DB_TYPE_NORM" = "POSTGRES" ]; then
    TARGET_HOST="${DB_SERVER:-protheus_postgres}"
    TARGET_PORT="${DB_PORT:-5432}"
    CFG_TYPE="POSTGRES"
elif [ "$DB_TYPE_NORM" = "MSSQL" ]; then
    TARGET_HOST="${DB_SERVER:-protheus_mssql}"
    TARGET_PORT="${DB_PORT:-1433}"
    CFG_TYPE="MSSQL"
elif [ "$DB_TYPE_NORM" = "ORACLE" ]; then
    TARGET_HOST="${DB_SERVER:-protheus_oracle}"
    TARGET_PORT="${DB_PORT:-1521}"
    CFG_TYPE="ORACLE"
else
    echo "❌ Tipo de banco desconhecido no .env: $DB_TYPE"
    exit 1
fi

# 2. Loop de resiliência aguardando o banco responder na rede (seja Kubernetes Service ou Docker Network)
echo "⏳ Aguardando conectividade com o banco [${CFG_TYPE}] em ${TARGET_HOST}:${TARGET_PORT}..."
while ! nc -z "$TARGET_HOST" "$TARGET_PORT"; do
    sleep 1
done
echo "✅ Conectividade com o banco de dados estabelecida!"

# Força a criação do diretório de log exigido pelo console do DbAccess
mkdir -p /opt/totvs/dbaccess/log/

# Força a criação e entrada no diretório oficial da subpasta multi
mkdir -p /opt/totvs/dbaccess/multi/
cd /opt/totvs/dbaccess/multi/

# Define o caminho correto do utilitário dbaccesscfg
if [ -f "/opt/totvs/dbaccess/multi/dbaccesscfg" ]; then
    CFG_BIN="/opt/totvs/dbaccess/multi/dbaccesscfg"
else
    CFG_BIN="./dbaccesscfg"
fi

echo "📝 Limpando resíduos e gerando parâmetros de infraestrutura via dbaccesscfg..."

# Remove arquivo anterior se existir para garantir build limpa pelo utilitário
rm -f dbaccess.ini

# Parâmetros puramente globais para a seção [GENERAL]
GEN_OPTS="LicenseServer=${LICENSE_SERVER_HOST};LicensePort=${LICENSE_SERVER_PORT};MaxStringSize=500;UseLargeRecno=1;ConsoleFile=/opt/totvs/dbaccess/log/dbaccess.log;ConsoleLog=1;MemoAsBlob=0"

# 3. Execução do dbaccesscfg com correção de strings para drivers ODBC
if [ "$DB_TYPE_NORM" = "ORACLE" ]; then
    CONN_STR="//${DB_SERVER}:${DB_PORT}/${DB_SERVICE_NAME}"
    
    export ORACLE_HOME=/opt/oracle/instantclient_21_3
    export LD_LIBRARY_PATH=$ORACLE_HOME:$LD_LIBRARY_PATH

    BANK_OPTS="ConnectionMode=2;LogAction=0;MemoAsBlob=1;Disable=0;TableSpace=;IndexSpace="
    
    $CFG_BIN -u "${DB_USER}" -p "${DB_PASS}" -d "${CFG_TYPE}" -a "${DB_NAME}" -o "${BANK_OPTS}" -g "${GEN_OPTS}" -c "/opt/oracle/instantclient_21_3/libclntsh.so"

    sed -i '/ClientLibrary=\/opt\/oracle\/instantclient_21_3\/libclntsh.so/a ORACLE_HOME=/opt/oracle/instantclient_21_3' dbaccess.ini

elif [ "$DB_TYPE_NORM" = "POSTGRES" ]; then
    BANK_OPTS="ConnectionMode=2;UseRowInsDt=1;UseRowsStamp=1"
    
    $CFG_BIN -u "${DB_USER}" -p "${DB_PASS}" -d "${CFG_TYPE}" -a "${DB_NAME}" -o "${BANK_OPTS}" -g "${GEN_OPTS}" -c "/usr/lib/x86_64-linux-gnu/libodbc.so"
    
    CONN_STR="DRIVER={PostgreSQL ANSI};SERVER=${DB_SERVER};PORT=${DB_PORT};DATABASE=${DB_NAME};Uid=${DB_USER};Pwd=${DB_PASS}"
    sed -i "/password=/a ConnectionString=${CONN_STR}" dbaccess.ini
    sed -i '/ClientLibrary=\/usr\/lib\/x86_64-linux-gnu\/libodbc.so/a CodePage=WIN1252' dbaccess.ini
    
    # Limpa chaves vazias ou inválidas herdadas para o Postgres
    sed -i '/^TableSpace=/d' dbaccess.ini
    sed -i '/^IndexSpace=/d' dbaccess.ini

elif [ "$DB_TYPE_NORM" = "MSSQL" ]; then
    BANK_OPTS="ConnectionMode=2;UseRowInsDt=1;UseRowsStamp=1"
    
    $CFG_BIN -u "${DB_USER}" -p "${DB_PASS}" -d "${CFG_TYPE}" -a "${DB_NAME}" -o "${BANK_OPTS}" -g "${GEN_OPTS}" -c "/usr/lib/x86_64-linux-gnu/libodbc.so"
    
    CONN_STR="DRIVER={ODBC Driver 18 for SQL Server};SERVER=${DB_SERVER};PORT=${DB_PORT};DATABASE=${DB_NAME};Uid=${DB_USER};Pwd=${DB_PASS};TrustServerCertificate=yes"
    sed -i "/password=/a ConnectionString=${CONN_STR}" dbaccess.ini
    sed -i '/ClientLibrary=\/usr\/lib\/x86_64-linux-gnu\/libodbc.so/a AutoTranslate=0\ncompression=2' dbaccess.ini

    # Expurgos cirúrgicos para o MSSQL
    sed -i '/^TableSpace=/d' dbaccess.ini
    sed -i '/^IndexSpace=/d' dbaccess.ini
fi

# Remove eventuais linhas em branco duplas geradas no fim do arquivo pelo dbaccesscfg
sed -i '/^$/N;/^\n$/D' dbaccess.ini

echo "✅ [dbAccess] dbaccess.ini gerado e estruturado com sucesso no padrão ideal!"

# --- INJEÇÃO DA VARIÁVEL GLOBAL PARA EXECUÇÃO DO BANCO ORACLE ---
if [ "$DB_TYPE_NORM" = "ORACLE" ]; then
    export ORACLE_HOME=/opt/oracle/instantclient_21_3
    export LD_LIBRARY_PATH=$ORACLE_HOME:$LD_LIBRARY_PATH

    # Passamos os parâmetros estruturais limpos para inicializar a seção do banco
    BANK_OPTS="ConnectionMode=2;LogAction=0;MemoAsBlob=1;Disable=0"
    
    # Executa o utilitário apontando para a biblioteca nativa clntsh
    $CFG_BIN -u "${DB_USER}" -p "${DB_PASS}" -d "${CFG_TYPE}" -a "${DB_NAME}" -o "${BANK_OPTS}" -g "${GEN_OPTS}" -c "/opt/oracle/instantclient_21_3/libclntsh.so"

    # --- INJEÇÃO CIRÚRGICA DA CONNECTION STRING EZCONNECT ---
    # Monta o formato bruto aceito pelo driver: host:porta/servico
    CONN_STR="${DB_SERVER}:${DB_PORT}/${DB_SERVICE_NAME}"
    
    # Injeta a string de conexão e o ORACLE_HOME de forma correta abaixo do password criptografado
    sed -i "/password=/a ConnectionString=${CONN_STR}" dbaccess.ini
    sed -i '/ClientLibrary=\/opt\/oracle\/instantclient_21_3\/libclntsh.so/a ORACLE_HOME=\/opt\/oracle\/instantclient_21_3' dbaccess.ini
    
    # Remove chaves padrão inválidas para o contexto limpo do Oracle se geradas pelo utilitário
    sed -i '/^TableSpace=/d' dbaccess.ini
    sed -i '/^IndexSpace=/d' dbaccess.ini
fi

echo "🚀 Disparando o TOTVS dbAccess..."
if [ -f "/opt/totvs/dbaccess/dbaccess64" ]; then
    exec /opt/totvs/dbaccess/dbaccess64
else
    exec ./dbaccess64
fi