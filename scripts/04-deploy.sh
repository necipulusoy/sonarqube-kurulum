#!/bin/bash
# =============================================================================
# SonarQube Enterprise - Docker Compose Deploy Script
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="$(dirname "$SCRIPT_DIR")"

cd "$COMPOSE_DIR"

# .env kontrolü
[[ ! -f ".env" ]] && error ".env dosyası bulunamadı: ${COMPOSE_DIR}/.env"

# -----------------------------------------------------------------------------
# Ön kontroller
# -----------------------------------------------------------------------------
info "Sistem ön kontrolleri yapılıyor..."

MAP_COUNT=$(sysctl -n vm.max_map_count)
if [[ $MAP_COUNT -lt 524288 ]]; then
    error "vm.max_map_count çok düşük: ${MAP_COUNT} (min: 524288). Script 03 çalıştırıldı mı?"
fi

# Docker daemon kontrolü
docker info > /dev/null 2>&1 || error "Docker çalışmıyor. 'systemctl start docker' çalıştırın."

# -----------------------------------------------------------------------------
# Image Pull
# -----------------------------------------------------------------------------
info "Docker image'ları çekiliyor..."
docker compose pull

# -----------------------------------------------------------------------------
# Deploy
# -----------------------------------------------------------------------------
info "SonarQube başlatılıyor..."
docker compose up -d

info "Container durumları:"
docker compose ps

# -----------------------------------------------------------------------------
# Health Check Bekleme
# -----------------------------------------------------------------------------
info "SonarQube ayağa kalkması bekleniyor (max 5 dakika)..."
MAX_WAIT=300
ELAPSED=0
INTERVAL=10

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    STATUS=$(docker compose exec -T sonarqube curl -s http://localhost:9000/api/system/status 2>/dev/null \
             | grep -o '"status":"[^"]*"' | cut -d'"' -f4 || echo "STARTING")

    if [[ "$STATUS" == "UP" ]]; then
        info "SonarQube hazır! Tarayıcıdan erişin: http://$(hostname -I | awk '{print $1}'):9000"
        info "Varsayılan giriş: admin / admin (ilk girişte şifre değiştirin!)"
        exit 0
    fi

    echo "  Durum: ${STATUS} (${ELAPSED}s geçti...)"
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

error "Zaman aşımı. Logları kontrol edin: docker compose logs -f sonarqube"
