#!/bin/bash
# ============================================================
#   ATEC // SYSTEM_CORE_2026 - BACKUP SERVER
#   Configuração: IP Fixo + RAID 10 + Restic + Estrutura PDF
# ============================================================

set -euo pipefail

# --- 0. VERIFICAÇÃO DE ROOT ---
if [[ "$(id -u)" -ne 0 ]]; then echo "ERRO: Corre como root."; exit 1; fi

# --- 1. FUNÇÃO DE CONFIGURAÇÃO DE REDE (IP FIXO) ---
configurar_rede_interativa() {
    clear
    echo "============================================================"
    echo "   ATEC // SYSTEM_CORE_2026 - CONFIGURAÇÃO DE REDE"
    echo "============================================================"
    
    read -p "Definir Hostname (Enter para 'backup-srv'): " HOSTNAME_INPUT
    HOSTNAME_NEW="${HOSTNAME_INPUT:-backup-srv}"
    hostnamectl set-hostname "$HOSTNAME_NEW"
    
    echo -e "\n[INFO] Interfaces detetadas:"
    nmcli device status | grep -v "DEVICE"
    echo ""

    read -p "Nome da interface (ex: enp0s3): " IFACE
    read -p "Endereço IP/Máscara (ex: 192.168.1.200/24): " IP_ADDR
    read -p "Gateway (IP do Router): " GATEWAY
    read -p "DNS Primário (ex: 8.8.8.8): " DNS1
    
    nmcli con mod "$IFACE" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore 2>/dev/null || \
    nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore

    nmcli con down "$IFACE" 2>/dev/null || true
    nmcli con up "$IFACE" 2>/dev/null || nmcli con up "Wired connection 1"
    
    echo "[OK] Rede configurada com IP Fixo."
}

# Executar configuração de rede logo no início
configurar_rede_interativa

echo -e "\n[INFO] A iniciar configuração técnica do servidor..."

# --- 2. CONFIGURAÇÃO DO RAID 10 ---
echo "[INFO] A configurar RAID 10 (Mínimo 4 discos)..."
# Ajusta os nomes dos discos (sdb, sdc, etc.) conforme o teu 'lsblk'
DISCOS_RAID=("/dev/sdb" "/dev/sdc" "/dev/sdd" "/dev/sde")

# Criar o array RAID 10
mdadm --create /dev/md0 --level=10 --raid-devices=4 "${DISCOS_RAID[@]}" --force

# Formatação e Montagem em /backup
mkfs.xfs -f /dev/md0
mkdir -p /backup
mount /dev/md0 /backup

# Garantir Montagem Permanente (fstab)
UUID_RAID=$(blkid -s UUID -o value /dev/md0)
if ! grep -q "$UUID_RAID" /etc/fstab; then
    echo "UUID=$UUID_RAID /backup xfs defaults 0 0" >> /etc/fstab
fi

# --- 3. ESTRUTURA DE DIRETÓRIOS EXIGIDA  ---
echo "[INFO] A criar estrutura de pastas do PDF..."
mkdir -p /backup/web/incremental
mkdir -p /backup/db/incremental
mkdir -p /backup/logs
mkdir -p /backup/restic /backup/backrest

# --- 4. INSTALAÇÃO DE FERRAMENTAS E SEGURANÇA ---
echo "[INFO] A instalar serviços..."
dnf -y install epel-release
dnf -y install restic podman firewalld cronie fail2ban rsync

# Firewall [cite: 53-59]
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=8000/tcp
firewall-cmd --reload

# Fail2ban [cite: 63-66]
systemctl enable --now fail2ban

# --- 5. INICIALIZAÇÃO DO RESTIC (BACKUP INCREMENTAL) ---
echo "minha_password_forte" > /backup/backrest/restic-pass
chmod 600 /backup/backrest/restic-pass

if [[ ! -f "/backup/restic/config" ]]; then
    restic init --repo /backup/restic --password-file /backup/backrest/restic-pass
fi

# --- 6. AGENDAMENTO SEMANAL (DOMINGO) ---
echo "[INFO] A configurar agendamento semanal (Cron)..."
# Adiciona tarefa para correr todos os domingos às 03:00 
(crontab -l 2>/dev/null; echo "0 3 * * 0 restic -r /backup/restic backup /var/www/html --password-file /backup/backrest/restic-pass >> /backup/logs/backup_semanal.log 2>&1") | crontab -

# --- 7. INTERFACE GUI (BACKREST) ---
podman run -d --name backrest --restart always -p 8000:9898 \
  -v /backup/backrest:/config:Z \
  -v /backup/restic:/data/restic:Z \
  -e "RESTIC_PASSWORD_FILE=/config/restic-pass" \
  docker.io/garethgeorge/backrest:latest

echo "============================================================"
echo " SERVIDOR DE BACKUPS PRONTO E EM CONFORMIDADE COM O PDF"
echo " IP CONFIGURADO: $(hostname -I | awk '{print $1}')"
echo " RAID 10: Ativo em /backup"
echo " AGENDAMENTO: Domingos às 03:00"
echo " GUI: http://$(hostname -I | awk '{print $1}'):8000"
echo "============================================================"
