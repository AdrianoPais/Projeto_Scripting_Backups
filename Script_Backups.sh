#!/bin/bash
# ============================================================
#   WEB SERVER (DMZ) - ATEC SYSTEM_CORE_2026
#   Configuração: IP Fixo + DuckDNS + LAMP + Cyberpunk UI
# ============================================================

set -euo pipefail

# --- 0. VERIFICAÇÃO DE ROOT (Essencial para configurar rede) ---
if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERRO: Este script tem de ser corrido como root (sudo)."
    exit 1
fi

# [cite_start]--- FUNÇÃO DE CONFIGURAÇÃO DE REDE (IP FIXO) [cite: 15, 46] ---
configurar_rede_interativa() {
    clear
    echo "============================================================"
    echo "   ATEC // SYSTEM_CORE_2026 - CONFIGURAÇÃO DE REDE"
    echo "============================================================"
    
    # Hostname
    read -p "Definir Hostname (Enter para 'webserver-atec'): " HOSTNAME_INPUT
    HOSTNAME_NEW="${HOSTNAME_INPUT:-webserver-atec}"
    hostnamectl set-hostname "$HOSTNAME_NEW"
    
    # Listar interfaces para o utilizador ver
    echo -e "\n[INFO] Interfaces detetadas:"
    nmcli device status | grep -v "DEVICE"
    echo ""

    read -p "Nome da interface (ex: enp0s3): " IFACE
    read -p "Endereço IP/Máscara (ex: 192.168.1.100/24): " IP_ADDR
    read -p "Gateway (IP do Router): " GATEWAY
    read -p "DNS Primário (ex: 8.8.8.8): " DNS1
    
    echo -e "\n[INFO] A aplicar IP Fixo na interface $IFACE..."
    
    # Configuração via nmcli para IP Manual
    nmcli con mod "$IFACE" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore 2>/dev/null || \
    nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore

    # Reiniciar a ligação para aplicar
    nmcli con down "$IFACE" 2>/dev/null || true
    nmcli con up "$IFACE" 2>/dev/null || nmcli con up "Wired connection 1"
    
    echo "[OK] Rede configurada com IP Fixo."
}

# 1. EXECUTAR REDE
configurar_rede_interativa

# [cite_start]--- 2. CONFIGURAÇÃO DUCKDNS [cite: 51] ---
echo -e "\n[INFO] A configurar DuckDNS para acesso externo..."
read -p "Introduza o seu Token do DuckDNS: " DUCK_TOKEN
DUCK_DOMAIN="webserver-atec"

cat > /usr/local/sbin/duckdns_update.sh <<EOF
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=${DUCK_DOMAIN}&token=${DUCK_TOKEN}&ip=" | curl -k -K -
EOF

chmod +x /usr/local/sbin/duckdns_update.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/sbin/duckdns_update.sh >/dev/null 2>&1") | crontab -
echo "[OK] DuckDNS agendado (5 em 5 min)."

# [cite_start]--- 3. INSTALAÇÃO DE SERVIÇOS (LAMP) [cite: 17, 18, 19, 29, 33, 36] ---
echo -e "\n[INFO] A instalar Apache, PHP e MariaDB..."
dnf -y update
dnf -y install httpd php php-mysqlnd mariadb-server firewalld rsync

# [cite_start]--- 4. CONFIGURAÇÃO FIREWALL (DMZ) [cite: 11, 54-58] ---
echo "[INFO] A configurar Firewall..."
systemctl enable --now firewalld
firewall-cmd --permanent --add-service={http,https,ssh}
firewall-cmd --reload

# [cite_start]--- 5. IMPLEMENTAÇÃO DO SITE CYBERPUNK  ---
WEBROOT="/var/www/html"
mkdir -p "$WEBROOT"
cat > "${WEBROOT}/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="pt-pt">
<head>
    <meta charset="UTF-8">
    <title>ATEC // SYSTEM_CORE_2026</title>
    </head>
<body>
    <h1>SISTEMA ONLINE</h1>
</body>
</html>
HTML

chown -R apache:apache "${WEBROOT}"
[cite_start]restorecon -Rv "${WEBROOT}" [cite: 61]

# [cite_start]--- 6. HARDENING MARIADB [cite: 39-44] ---
echo "[INFO] A aplicar hardening do MariaDB..."
systemctl enable --now mariadb
read -s -p "Define a nova password root do MariaDB: " DB_ROOT_PASSWORD
echo ""

mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
SQL

# --- 7. FINALIZAÇÃO ---
systemctl enable --now httpd
echo "============================================================"
echo "   CONFIGURAÇÃO CONCLUÍDA"
echo "   Website: http://${DUCK_DOMAIN}.duckdns.org"
echo "   IP Local: $(hostname -I | awk '{print $1}')"
echo "============================================================"
