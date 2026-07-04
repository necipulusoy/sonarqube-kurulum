#!/bin/bash
# =============================================================================
# Red Hat Enterprise Linux 9 - SonarQube Sistem Konfigürasyonu
# Kernel parametreleri, ulimits ve bağlantı kontrolleri
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

[[ $EUID -ne 0 ]] && error "Bu script root yetkisiyle çalıştırılmalıdır: sudo $0"

info "=== RHEL 9 - SonarQube Sistem Konfigürasyonu ==="

# -----------------------------------------------------------------------------
# 1. Kernel Parametreleri (Elasticsearch gereksinimi)
# -----------------------------------------------------------------------------
info "Kernel parametreleri ayarlanıyor..."

SYSCTL_CONF="/etc/sysctl.d/99-sonarqube.conf"
cat > "$SYSCTL_CONF" << 'EOF'
# SonarQube / Elasticsearch için gerekli kernel parametreleri
vm.max_map_count=524288
fs.file-max=131072
EOF

sysctl --system
info "vm.max_map_count: $(sysctl -n vm.max_map_count)"
info "fs.file-max: $(sysctl -n fs.file-max)"

# -----------------------------------------------------------------------------
# 2. Sistem Genelinde ulimit Ayarları
# -----------------------------------------------------------------------------
info "ulimit ayarları yapılıyor..."

LIMITS_CONF="/etc/security/limits.d/99-sonarqube.conf"
cat > "$LIMITS_CONF" << 'EOF'
# SonarQube için ulimit ayarları
*    soft    nofile    131072
*    hard    nofile    131072
*    soft    nproc     8192
*    hard    nproc     8192
EOF

# SELinux yalnızca raporlanır. Named volume için global boolean değişikliği gerekmez.
SELINUX_STATUS=$(getenforce 2>/dev/null || echo "Unknown")
info "SELinux durumu: $SELINUX_STATUS"

if systemctl is-active --quiet firewalld; then
    info "Firewall açık. Port otomatik açılmadı; müşteri kaynak subnet kuralı uygulamalıdır."
    info "Mevcut açık portlar: $(firewall-cmd --list-ports)"
else
    warn "firewalld çalışmıyor. Host güvenlik politikası müşteri tarafından doğrulanmalıdır."
fi

# -----------------------------------------------------------------------------
# External Veritabanı Bağlantı Testi (PostgreSQL veya MSSQL)
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$(dirname "$SCRIPT_DIR")/.env"

if [[ -f "$ENV_FILE" ]]; then
    # .env bir shell scripti değildir; root yetkisiyle source edilmez.
    JDBC_URL=$(sed -n 's/^[[:space:]]*SONAR_JDBC_URL[[:space:]]*=[[:space:]]*//p' "$ENV_FILE" | tail -n 1)
    JDBC_URL="${JDBC_URL%\"}"; JDBC_URL="${JDBC_URL#\"}"
    JDBC_URL="${JDBC_URL%\'}"; JDBC_URL="${JDBC_URL#\'}"

    if [[ "$JDBC_URL" == *"DB_SUNUCU_IP_VEYA_HOSTNAME"* || -z "$JDBC_URL" ]]; then
        warn "External DB henüz yapılandırılmamış. .env dosyasındaki SONAR_JDBC_URL'i güncelleyin."
    else
        # DB tipini ve host:port'u JDBC URL'den ayıkla
        if [[ "$JDBC_URL" == jdbc:postgresql://* ]]; then
            DB_TYPE="PostgreSQL"
            DB_HOST=$(printf '%s' "$JDBC_URL" | sed -E 's#^jdbc:postgresql://([^:/]+).*#\1#')
            DB_PORT=$(printf '%s' "$JDBC_URL" | sed -nE 's#^jdbc:postgresql://[^/:]+:([0-9]+).*#\1#p')
            DB_PORT="${DB_PORT:-5432}"

        elif [[ "$JDBC_URL" == jdbc:sqlserver://* ]]; then
            DB_TYPE="MSSQL"
            DB_HOST=$(printf '%s' "$JDBC_URL" | sed -E 's#^jdbc:sqlserver://([^:;\\]+).*#\1#')
            DB_PORT=$(printf '%s' "$JDBC_URL" | sed -nE 's#^jdbc:sqlserver://[^:;\\]+:([0-9]+).*#\1#p')
            DB_PORT="${DB_PORT:-1433}"
        else
            warn "Tanımsız JDBC URL formatı: ${JDBC_URL}"
            DB_TYPE=""; DB_HOST=""; DB_PORT=""
        fi

        if [[ -n "$DB_HOST" ]]; then
            info "External ${DB_TYPE} bağlantısı test ediliyor: ${DB_HOST}:${DB_PORT} ..."
            if timeout 5 bash -c "echo >/dev/tcp/${DB_HOST}/${DB_PORT}" 2>/dev/null; then
                info "${DB_TYPE} portu erişilebilir: ${DB_HOST}:${DB_PORT}"
            else
                warn "${DB_TYPE} portuna ulaşılamıyor: ${DB_HOST}:${DB_PORT}"
                warn "Güvenlik duvarı kurallarını ve DB sunucu erişimini kontrol edin."
            fi
        fi
    fi
else
    warn ".env dosyası bulunamadı, DB testi atlanıyor."
fi

# -----------------------------------------------------------------------------
# Doğrulama
# -----------------------------------------------------------------------------
info "=== Sistem Konfigürasyonu Doğrulama ==="
echo "  vm.max_map_count : $(sysctl -n vm.max_map_count)  (min: 524288)"
echo "  fs.file-max      : $(sysctl -n fs.file-max)  (min: 131072)"
echo "  SELinux          : $(getenforce 2>/dev/null || echo N/A)"
echo "  Firewall 9000    : $(firewall-cmd --list-ports 2>/dev/null | grep -o '9000/tcp' || echo 'firewalld inactive')"

info "=== Sistem konfigürasyonu tamamlandı. ==="
info "Sonraki adım: sonarqube/ dizininde 'docker compose up -d' çalıştırın."
