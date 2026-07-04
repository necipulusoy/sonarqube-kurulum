#!/bin/bash
# İnternet erişimli RHEL 9 x86_64 makinede çalıştırılır.
# Docker Engine, Compose V2, Git ve OpenSSH RPM'lerini packages/ dizinine indirir.
set -euo pipefail

info()  { printf '[INFO] %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || error "Root olarak çalıştırın: sudo bash $0"
[[ -r /etc/os-release ]] || error "/etc/os-release okunamıyor."
source /etc/os-release
[[ "${ID:-}" == "rhel" && "${VERSION_ID%%.*}" == "9" ]] || \
  error "Bu script yalnızca RHEL 9 üzerinde çalıştırılmalıdır. Algılanan: ${PRETTY_NAME:-bilinmiyor}"
[[ "$(uname -m)" == "x86_64" ]] || error "Yalnızca x86_64 destekleniyor. Algılanan: $(uname -m)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGE_DIR="${REPO_DIR}/packages"
RPM_DIR="${PACKAGE_DIR}/rhel9-x86_64"
DOCKER_REPO_FILE="/etc/yum.repos.d/docker-ce.repo"

info "dnf download eklentisi kuruluyor..."
dnf install -y dnf-plugins-core

if [[ ! -f "$DOCKER_REPO_FILE" ]]; then
  info "Docker CE repository tanımı ekleniyor..."
  dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
fi

mkdir -p "$RPM_DIR"
find "$RPM_DIR" -maxdepth 1 -type f -name '*.rpm' -delete

info "Docker Engine, Compose V2, Git/SSH ve tüm RPM bağımlılıkları indiriliyor..."
dnf download \
  --resolve \
  --alldeps \
  --destdir "$RPM_DIR" \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin \
  git \
  openssh-clients

info "Docker repository GPG anahtarı indiriliyor..."
curl --fail --silent --show-error --location \
  https://download.docker.com/linux/rhel/gpg \
  --output "${PACKAGE_DIR}/docker-rhel-gpg"

RPM_COUNT=$(find "$RPM_DIR" -maxdepth 1 -type f -name '*.rpm' | wc -l)
[[ "$RPM_COUNT" -gt 0 ]] || error "Hiç RPM indirilemedi. RHEL subscription ve repository erişimini kontrol edin."

info "SHA-256 manifest oluşturuluyor..."
(
  cd "$PACKAGE_DIR"
  find docker-rhel-gpg rhel9-x86_64 -type f -print0 \
    | sort -z \
    | xargs -0 sha256sum > SHA256SUMS
)

cat > "${PACKAGE_DIR}/BUNDLE-INFO.txt" <<EOF
Hazırlama tarihi: $(date --iso-8601=seconds)
Hazırlayan sistem: ${PRETTY_NAME}
Mimari: $(uname -m)
RPM sayısı: ${RPM_COUNT}
EOF

# Script sudo ile çağrıldıysa oluşan bundle'ı repo sahibine geri ver.
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  chown -R "${SUDO_USER}" "$PACKAGE_DIR"
fi

info "Offline paket hazırlandı: ${PACKAGE_DIR}"
info "Bu repo dizinini air-gap ortama aktarın veya oluşan packages/ dizinini ana repoya kopyalayın."
info "Air-gap kurulum komutu: sudo bash scripts/01-install-offline-docker.sh"
