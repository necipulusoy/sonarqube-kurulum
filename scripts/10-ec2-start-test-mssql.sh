#!/bin/bash
# Yalnızca ayrı EC2 test DB makinesinde çalıştırılır.
set -euo pipefail

info()  { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
MSSQL_DIR="${REPO_DIR}/test/mssql"
ENV_FILE="${MSSQL_DIR}/.env"
COMPOSE=(docker compose --env-file "$ENV_FILE" -f "${MSSQL_DIR}/docker-compose.yml")

command -v docker >/dev/null || error "Docker bulunamadı."
docker compose version >/dev/null 2>&1 || error "Docker Compose V2 bulunamadı."
[[ -f "$ENV_FILE" ]] || error "${ENV_FILE} bulunamadı. .env.example dosyasını kopyalayıp parolaları değiştirin."

if grep -q 'ChangeThis-' "$ENV_FILE"; then
  error "Örnek parolalar değiştirilmemiş. test/mssql/.env dosyasını güncelleyin."
fi

info "SQL Server 2022 Developer başlatılıyor..."
"${COMPOSE[@]}" pull
"${COMPOSE[@]}" up -d --wait --wait-timeout 240

info "SonarQube test database ve kullanıcısı oluşturuluyor..."
"${COMPOSE[@]}" exec -T mssql bash -c \
  '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b -v SONAR_PASSWORD="$SONAR_DB_PASSWORD" -i /config/init-sonarqube.sql'

info "Database doğrulanıyor..."
"${COMPOSE[@]}" exec -T mssql bash -c \
  '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sonarqube_test -P "$SONAR_DB_PASSWORD" -C -b -d sonarqube_test -Q "SELECT DB_NAME() AS database_name, USER_NAME() AS database_user"'

info "External test MSSQL hazır. SonarQube EC2 security group'undan TCP/1433 erişimini açın."
