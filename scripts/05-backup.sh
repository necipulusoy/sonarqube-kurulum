#!/bin/bash
# Harici veritabanının yedeğini ALMAZ. DB backup/restore müşteri DBA ekibindedir.
set -euo pipefail

info()  { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="${BACKUP_DIR:-${COMPOSE_DIR}/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

command -v docker >/dev/null || error "Docker bulunamadı."
mkdir -p "$BACKUP_DIR"

info "DB yedeği kapsam dışı; external DB müşterinin DBA süreciyle yedeklenmelidir."
cd "$COMPOSE_DIR"
docker compose ps --status running -q sonarqube | grep -q . || error "SonarQube container çalışmıyor."
docker compose exec -T sonarqube \
  tar czf - -C /opt/sonarqube/extensions . \
  > "${BACKUP_DIR}/sonarqube_extensions_${TIMESTAMP}.tar.gz"

find "$BACKUP_DIR" -type f -mtime +30 -delete
info "Uygulama dosyası yedeği tamamlandı: ${BACKUP_DIR}"
