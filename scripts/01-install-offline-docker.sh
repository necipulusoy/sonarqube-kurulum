#!/bin/bash
# Air-gap RHEL 9 x86_64 makinede repo içindeki RPM'lerden kurulum yapar.
set -euo pipefail

info()  { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Root olarak çalıştırın: sudo bash $0"
[[ -r /etc/os-release ]] || error "/etc/os-release okunamıyor."
source /etc/os-release
[[ "${ID:-}" == "rhel" && "${VERSION_ID%%.*}" == "9" ]] || \
  error "Bu paket yalnızca RHEL 9 içindir. Algılanan: ${PRETTY_NAME:-bilinmiyor}"
[[ "$(uname -m)" == "x86_64" ]] || error "Bu paket x86_64 içindir. Algılanan: $(uname -m)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGE_DIR="${REPO_DIR}/packages"
RPM_DIR="${PACKAGE_DIR}/rhel9-x86_64"

[[ -f "${PACKAGE_DIR}/SHA256SUMS" ]] || error "Checksum manifest bulunamadı: packages/SHA256SUMS"
[[ -f "${PACKAGE_DIR}/docker-rhel-gpg" ]] || error "Docker GPG anahtarı bulunamadı."
find "$RPM_DIR" -maxdepth 1 -type f -name '*.rpm' -print -quit | grep -q . || \
  error "Offline RPM bulunamadı: ${RPM_DIR}"

info "Paket bütünlüğü doğrulanıyor..."
(cd "$PACKAGE_DIR" && sha256sum --check SHA256SUMS)

info "Docker GPG anahtarı içe aktarılıyor..."
rpm --import "${PACKAGE_DIR}/docker-rhel-gpg"

info "Docker Engine ve Compose V2 offline kuruluyor..."
dnf install -y \
  --disablerepo='*' \
  --setopt=install_weak_deps=False \
  "$RPM_DIR"/*.rpm

systemctl enable --now docker
docker --version
docker compose version
docker info >/dev/null

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  usermod -aG docker "$SUDO_USER"
  info "${SUDO_USER} kullanıcısı docker grubuna eklendi."
  info "Grup yetkisinin etkinleşmesi için SSH oturumunu kapatıp yeniden bağlanın."
fi

info "Offline Docker kurulumu tamamlandı."
info "Sonraki adım: bash scripts/02-prerequisites.sh"
