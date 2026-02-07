#!/bin/bash
# ============================================================
#   ATEC // SYSTEM_CORE_2026 - BACKUP SERVER FINAL
#   Configuração: IP Fixo + RAID 10 + Estrutura PDF + Restic
# ============================================================

set -euo pipefail

# --- 0. VERIFICAÇÃO DE ROOT ---
if [[ "$(id -u)" -ne 0 ]]; then echo "ERRO: Corre como root."; exit 1; fi

# --- 1. CONFIGURAÇÃO DE REDE INTERATIVA (IP FIXO) ---
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
    read -p "IP/Máscara (ex: 192.168.1.200/24): " IP_ADDR
    read -p "Gateway (IP do Router): " GATEWAY
    read -p "DNS Primário (ex: 8.8.8.8): " DNS1
    
    nmcli con mod "$IFACE" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore 2>/dev/null || \
    nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore

    nmcli con down "$IFACE" 2>/dev/null || true
    nmcli con up "$IFACE" 2>/dev/null || nmcli con up "Wired connection 1"
    
    echo "[OK] Rede configurada com IP Fixo."
}

configurar_rede_interativa

# --- 2. DETEÇÃO E CRIAÇÃO DO RAID 10 [: 71-82] ---
echo -e "\n[INFO] A detetar discos para o RAID 10..."
# Deteta discos extras (que não têm partições montadas)
DISCOS_LIVRES=($(lsblk -dn -o NAME,TYPE,MOUNTPOINTS | grep "disk" | grep -v "/" | awk '{print "/dev/"$1}' | grep -v "nvme0n1" | head -n 4))

if [[ ${#DISCOS_LIVRES[@]} -lt 4 ]]; then
    echo "ERRO: Não encontrei 4 discos livres para o RAID. Encontrados: ${DISCOS_LIVRES[*]}"
    exit 1
fi

echo "Discos selecionados para RAID: ${DISCOS_LIVRES[*]}"
# Cria o RAID 10
mdadm --create /dev/md0 --level=10 --raid-devices=4 "${DISCOS_LIVRES[@]}" --force

# Formatação e Montagem Persistente
mkfs.xfs -f /dev/md0
mkdir -p /backup
mount /dev/md0 /backup
UUID_RAID=$(blkid -s UUID -o value /dev/md0)
echo "UUID=$UUID_RAID /backup xfs defaults 0 0" >> /etc/fstab

# --- 3. ESTRUTURA DE DIRETÓRIOS EXIGIDA  ---
echo "[INFO] A criar estrutura de pastas em /backup..."
mkdir -p /backup/web/incremental
mkdir -p /backup/db/incremental
mkdir -p /backup/logs
mkdir -p /backup/restic /backup/backrest

# --- 4. INSTALAÇÃO DE FERRAMENTAS E SEGURANÇA ---
echo "[INFO] A instalar serviços..."
dnf -y install epel-release
dnf -y install restic podman firewalld cronie fail2ban rsync

systemctl enable --now firewalld fail2ban
firewall-cmd --permanent --add-port=8000/tcp
firewall-cmd --reload

# --- 5. INICIALIZAÇÃO DO RESTIC (BACKUP INCREMENTAL) ---
echo "restic_atec_2026" > /backup/backrest/restic-pass
chmod 600 /backup/backrest/restic-pass

if [[ ! -f "/backup/restic/config" ]]; then
    restic init --repo /backup/restic --password-file /backup/backrest/restic-pass
fi

# --- 6. AGENDAMENTO SEMANAL (DOMINGO ÀS 03:00) ---
echo "[INFO] A configurar agendamento (Cron)..."
(crontab -l 2>/dev/null; echo "0 3 * * 0 restic -r /backup/restic backup /var/www/html --password-file /backup/backrest/restic-pass >> /backup/logs/backup_semanal.log 2>&1") | crontab -

# --- 7. INTERFACE GUI (BACKREST) ---
podman run -d --name backrest --restart always -p 8000:9898 \
  -v /backup/backrest:/config:Z -v /backup/restic:/data/restic:Z \
  -e "RESTIC_PASSWORD_FILE=/config/restic-pass" \
  docker.io/garethgeorge/backrest:latest

echo "============================================================"
echo " SERVIDOR DE BACKUPS CONFIGURADO COM SUCESSO"
echo " IP FIXO: $(hostname -I | awk '{print $1}')"
echo " RAID 10: Ativo em /backup"
echo " AGENDAMENTO: Domingos às 03:00 "
echo " GUI: http://$(hostname -I | awk '{print $1}'):8000"
echo "============================================================"
