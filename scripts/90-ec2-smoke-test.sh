#!/bin/bash
set -euo pipefail

info()  { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
cd "$REPO_DIR"

[[ -f .env ]] || error ".env bulunamadı. Önce .env.ec2.example dosyasını kopyalayıp doldurun."
command -v docker >/dev/null || error "Docker bulunamadı."
docker compose version >/dev/null 2>&1 || error "Docker Compose V2 bulunamadı."

SERVICES=$(docker compose config --services)
[[ "$SERVICES" == "sonarqube" ]] || error "Beklenmeyen Compose servisleri: ${SERVICES}"

CONTAINER_ID=$(docker compose ps -q sonarqube)
[[ -n "$CONTAINER_ID" ]] || error "SonarQube container bulunamadı."
[[ "$(docker inspect --format '{{.State.Running}}' "$CONTAINER_ID")" == "true" ]] || \
  error "SonarQube container çalışmıyor."

HOST_PORT=$(docker compose port sonarqube 9000 | head -n 1 | awk -F: '{print $NF}')
[[ "$HOST_PORT" =~ ^[0-9]+$ ]] || error "SonarQube host portu belirlenemedi."

STATUS=$(curl --fail --silent --show-error \
  "http://127.0.0.1:${HOST_PORT}/api/system/status" \
  | sed -nE 's/.*"status":"([^"]+)".*/\1/p')
[[ "$STATUS" == "UP" ]] || error "SonarQube API durumu UP değil: ${STATUS:-yanıt yok}"

HEALTH=""
for _ in {1..12}; do
  HEALTH=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}tanimsiz{{end}}' "$CONTAINER_ID")
  [[ "$HEALTH" == "healthy" ]] && break
  sleep 5
done
[[ "$HEALTH" == "healthy" ]] || error "Container health durumu healthy değil: ${HEALTH}"

if docker compose logs --no-color sonarqube 2>&1 \
  | grep -qiE 'cannot open database|login failed|bootstrap check failure|outofmemoryerror'; then
  error "Loglarda kritik DB/Elasticsearch/JVM hatası bulundu."
fi

info "SonarQube status: ${STATUS}"
info "Container health: ${HEALTH}"
info "EC2 smoke test başarılı."
