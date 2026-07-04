#!/bin/bash
set -euo pipefail

info()  { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

info "Air-gap SonarQube host ön kontrolleri başlatılıyor."

[[ -r /etc/os-release ]] || error "/etc/os-release okunamıyor."
source /etc/os-release
[[ "${ID:-}" == "rhel" && "${VERSION_ID%%.*}" == "9" ]] || \
  info "Uyarı: hedef platform RHEL 9; algılanan sistem ${PRETTY_NAME:-bilinmiyor}."

command -v docker >/dev/null || error "Docker Engine kurulu değil. Müşteri iç paket kaynağından kurulmalıdır."
docker compose version >/dev/null 2>&1 || error "Docker Compose V2 plugin kurulu değil."
docker info >/dev/null 2>&1 || error "Docker daemon çalışmıyor veya kullanıcı Docker'a erişemiyor."
command -v curl >/dev/null || error "curl kurulu değil."
command -v git >/dev/null || error "git kurulu değil. Offline bundle yeniden hazırlanmalıdır."
command -v ssh >/dev/null || error "OpenSSH istemcisi kurulu değil. Offline bundle yeniden hazırlanmalıdır."

info "Docker: $(docker --version)"
info "Compose: $(docker compose version)"
info "Git: $(git --version)"
info "vm.max_map_count: $(sysctl -n vm.max_map_count 2>/dev/null || echo bilinmiyor)"
info "Ön kontroller tamamlandı. Bu script internetten paket veya binary indirmez."
info "Sonraki adım: sudo bash scripts/03-configure-system.sh"
