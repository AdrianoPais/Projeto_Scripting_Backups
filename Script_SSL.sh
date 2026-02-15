#!/bin/bash
# ============================================================
# Script: setup_https_FINAL.sh
# Objetivo: Instalação Apache + HTTPS DuckDNS (Com correção ssl.conf)
# ============================================================

set -euo pipefail

# --- CORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

info() { echo -e "\n${YELLOW}[INFO] $*${NC}"; }
ok()   { echo -e "${GREEN}[OK]   $*${NC}"; }
warn() { echo -e "${YELLOW}[AVISO] $*${NC}"; }
fail() { echo -e "${RED}[ERRO] $*${NC}"; exit 1; }

# -----------------------------
# 0) VALIDAÇÕES
# -----------------------------
if [ "${EUID}" -eq 0 ]; then
  fail "Não corras como root. Corre como utilizador normal."
fi

# -----------------------------
# 1) DADOS
# -----------------------------
clear
echo "=============================================="
echo "Configurador HTTPS FINAL (Com correção ssl.conf)"
echo "=============================================="

read -r -p "Domínio DuckDNS (ex: webserver-atec.duckdns.org): " DOMAIN
DOMAIN="${DOMAIN// /}"
[[ -z "${DOMAIN}" ]] && fail "Domínio vazio."

read -r -p "Token DuckDNS: " DUCKDNS_TOKEN
DUCKDNS_TOKEN="${DUCKDNS_TOKEN// /}"
[[ -z "${DUCKDNS_TOKEN}" ]] && fail "Token vazio."

read -r -p "Email (ex: exemplo@gmail.com): " LE_EMAIL
LE_EMAIL="${LE_EMAIL// /}"

WEBROOT="/var/www/html"
SUBDOMAIN="${DOMAIN%.duckdns.org}"
SYS_CERT_DIR="/etc/pki/tls/certs"
SYS_KEY_DIR="/etc/pki/tls/private"
FINAL_CERT="${SYS_CERT_DIR}/${DOMAIN}.crt"
FINAL_KEY="${SYS_KEY_DIR}/${DOMAIN}.key"
FINAL_CHAIN="${SYS_CERT_DIR}/${DOMAIN}.chain.crt"
ACME_BIN="$HOME/.acme.sh/acme.sh"

# -----------------------------
# 2) PREPARAÇÃO
# -----------------------------
info "A pedir sudo..."
sudo -v

info "A instalar pacotes..."
sudo dnf -y install httpd mod_ssl firewalld curl socat >/dev/null

info "A limpar configs antigas..."
sudo rm -f "/etc/httpd/conf.d/${SUBDOMAIN}-ssl.conf"
sudo rm -f "/etc/httpd/conf.d/${SUBDOMAIN}-redirect.conf"

# -----------------------------
# 3) CORREÇÃO CRÍTICA DO SSL.CONF (A parte que faltava)
# -----------------------------
info "A corrigir ssl.conf para evitar conflitos..."

# Substitui o ssl.conf original por um limpo que não pede o certificado 'localhost'
sudo tee /etc/httpd/conf.d/ssl.conf > /dev/null <<EOF
# ================================================================
# Configuração SSL Base (Minimal) - Gerada pelo Script
# ================================================================
Listen 443 https
SSLPassPhraseDialog exec:/usr/libexec/httpd-ssl-pass-dialog
SSLSessionCache shmcb:/run/httpd/sslcache(512000)
SSLSessionCacheTimeout 300
SSLCryptoDevice builtin
SSLCipherSuite PROFILE=SYSTEM
SSLProxyCipherSuite PROFILE=SYSTEM
EOF
ok "Ficheiro ssl.conf corrigido."

# -----------------------------
# 4) DUCKDNS & ACME
# -----------------------------
info "A verificar acme.sh..."
if [ ! -f "$ACME_BIN" ]; then
    curl https://get.acme.sh | sh -s email="${LE_EMAIL}" >/dev/null
fi
"$ACME_BIN" --set-default-ca --server letsencrypt >/dev/null

info "A emitir certificado (Pode demorar 60s)..."
export DuckDNS_Token="${DUCKDNS_TOKEN}"

# Tenta emitir. Se der erro, tenta continuar caso o cert já exista.
set +e
"$ACME_BIN" --issue --dns dns_duckdns -d "${DOMAIN}" --ecc --dnssleep 60
RET=$?
set -e

if [ $RET -ne 0 ]; then
    warn "A emissão reportou erro. Vou verificar se o certificado já existe..."
fi

# -----------------------------
# 5) INSTALAR NO SISTEMA
# -----------------------------
info "A copiar certificados..."
CERT_HOME="$HOME/.acme.sh/${DOMAIN}_ecc"

# Verifica se os ficheiros existem antes de copiar
if [ ! -f "${CERT_HOME}/${DOMAIN}.key" ]; then
    fail "Certificados não encontrados em ${CERT_HOME}. A emissão falhou."
fi

sudo cp "${CERT_HOME}/${DOMAIN}.key" "${FINAL_KEY}"
sudo cp "${CERT_HOME}/${DOMAIN}.cer" "${FINAL_CERT}"
sudo cp "${CERT_HOME}/fullchain.cer" "${FINAL_CHAIN}"

sudo chmod 600 "${FINAL_KEY}"
sudo chmod 644 "${FINAL_CERT}" "${FINAL_CHAIN}"
sudo restorecon -v "${FINAL_KEY}" "${FINAL_CERT}" "${FINAL_CHAIN}" || true
ok "Certificados instalados."

# -----------------------------
# 6) CONFIGURAR APACHE
# -----------------------------
info "A criar VirtualHost SSL..."

cat <<EOF | sudo tee "/etc/httpd/conf.d/${SUBDOMAIN}-ssl.conf"
<VirtualHost *:443>
    ServerName ${DOMAIN}
    DocumentRoot "${WEBROOT}"
    SSLEngine on
    SSLCertificateFile "${FINAL_CHAIN}"
    SSLCertificateKeyFile "${FINAL_KEY}"
    <Directory "${WEBROOT}">
        AllowOverride All
        Require all granted
    </Directory>
    ErrorLog logs/${SUBDOMAIN}_ssl_error_log
    CustomLog logs/${SUBDOMAIN}_ssl_access_log combined
</VirtualHost>
EOF

cat <<EOF | sudo tee "/etc/httpd/conf.d/${SUBDOMAIN}-redirect.conf"
<VirtualHost *:80>
    ServerName ${DOMAIN}
    Redirect permanent / https://${DOMAIN}/
</VirtualHost>
EOF

# -----------------------------
# 7) FINALIZAR
# -----------------------------
info "A reiniciar Apache..."
if sudo apachectl configtest; then
    sudo systemctl restart httpd
    echo ""
    ok "SUCESSO! Site seguro em https://${DOMAIN}"
else
    fail "Configuração inválida. Verifica os logs."
fi
