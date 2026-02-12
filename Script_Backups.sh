#!/bin/bash
# ============================================================
#   ATEC // SYSTEM_CORE_2026 - BACKUP SERVER MASTER SCRIPT
#   Configuração: IP Fixo + RAID 10 + Restic + Disaster Recovery
# ============================================================

set -euo pipefail

# --- 0. VERIFICAÇÃO DE ROOT ---
if [[ "$(id -u)" -ne 0 ]]; then echo "ERRO: Corre como root."; exit 1; fi

# --- 1. CONFIGURAÇÃO DE REDE INTERATIVA ---
configurar_rede_interativa() {
    clear
    echo "============================================================"
    echo "    ATEC // SYSTEM_CORE_2026 - CONFIGURAÇÃO DE REDE"
    echo "============================================================"
    read -p "Definir Hostname (Enter para 'backup-srv'): " HOSTNAME_INPUT
    HOSTNAME_NEW="${HOSTNAME_INPUT:-backup-srv}"
    hostnamectl set-hostname "$HOSTNAME_NEW"
    
    nmcli device status | grep -v "DEVICE"
    read -p "Interface (ex: enp0s3): " IFACE
    read -p "IP/Máscara (ex: 192.168.1.200/24): " IP_ADDR
    read -p "Gateway: " GATEWAY
    read -p "DNS Primário: " DNS1
    
    nmcli con mod "$IFACE" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore
    nmcli con up "$IFACE"
    echo "[OK] Rede configurada."
}

configurar_rede_interativa

# --- 2. CRIAÇÃO DO RAID 10 (CORRIGIDO) ---
# Excluímos o sda (sistema) e usamos sdb, sdc, sdd, sde (20G cada)
echo -e "\n[INFO] A configurar RAID 10..."
DISCOS_RAID=("/dev/sdb" "/dev/sdc" "/dev/sdd" "/dev/sde")

mdadm --create /dev/md0 --level=10 --raid-devices=4 "${DISCOS_RAID[@]}" --force
mkfs.xfs -f /dev/md0
mkdir -p /backup
mount /dev/md0 /backup
echo "UUID=$(blkid -s UUID -o value /dev/md0) /backup xfs defaults 0 0" >> /etc/fstab

# --- 3. ESTRUTURA E SEGURANÇA ---
mkdir -p /backup/{web,db}/incremental /backup/{logs,restic,backrest,ssh_keys}
mkdir -p /mnt/webserver_db

# --- 4. INSTALAÇÃO DE FERRAMENTAS ---
dnf -y install epel-release
dnf -y install restic podman firewalld fuse-sshfs
systemctl enable --now firewalld
firewall-cmd --permanent --add-port=8000/tcp --reload

# --- 5. INICIALIZAÇÃO DO RESTIC ---
echo "restic_atec_2026" > /backup/backrest/restic-pass
chmod 600 /backup/backrest/restic-pass
if [[ ! -f "/backup/restic/config" ]]; then
    restic init --repo /backup/restic --password-file /backup/backrest/restic-pass
fi

# --- 6. CRIAÇÃO DO SCRIPT DE DISASTER RECOVERY ---
# Resolve os erros de diretoria e conexão automaticamente
cat << 'EOF' > /usr/local/bin/restauro_dr
#!/bin/bash
REPO="/data/restic"
WEB_SERVER="192.168.1.100"
STAGING="/backup/backrest/RESTAURO_AUTO"
SSH_KEY="/backup/ssh_keys/id_rsa"

echo "--- Desbloqueando Repositório ---"
sudo podman exec backrest restic -r $REPO unlock
mkdir -p $STAGING
sudo podman exec backrest restic -r $REPO restore latest --target /config/RESTAURO_AUTO

echo "--- Repondo dados no Web Server ---"
ssh -i $SSH_KEY root@$WEB_SERVER "mkdir -p /backup_db"
FICHEIRO=$(find $STAGING -name "*.sql.gz" | head -n 1)
scp -i $SSH_KEY $FICHEIRO root@$WEB_SERVER:/backup_db/db_backup_recuperado.sql.gz
echo "--- Disaster Recovery Concluído ---"
EOF
chmod +x /usr/local/bin/restauro_dr

# --- 7. ARRANQUE DO BACKREST (GUI) ---
# Adicionados volumes para chaves e permissão RW para restauro
podman stop backrest || true && podman rm backrest || true
podman run -d --name backrest --restart always -p 8000:9898 \
  -v /backup/backrest:/config:Z \
  -v /backup/restic:/data/restic:Z \
  -v /backup/ssh_keys:/root/.ssh:Z \
  -v /mnt/webserver_db:/source_data:rw,z \
  --privileged \
  -e "RESTIC_PASSWORD_FILE=/config/restic-pass" \
  docker.io/garethgeorge/backrest:latest

echo "============================================================"
echo " SERVIDOR CONFIGURADO: http://$(hostname -I | awk '{print $1}'):8000"
echo " RAID 10 ATIVO: /backup"
echo " COMANDO DE EMERGÊNCIA: restauro_dr"
echo "============================================================"
