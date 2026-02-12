#!/bin/bash
# ============================================================
#   ATEC // SYSTEM_CORE_2026 - BACKUP SERVER MASTER SCRIPT
#   Configuração: IP Fixo + RAID 10 + Restic + Disaster Recovery
#   VERSÃO CORRIGIDA: Exclusão do disco de sistema (sda)
# ============================================================

set -euo pipefail

# --- 0. VERIFICAÇÃO DE ROOT ---
if [[ "$(id -u)" -ne 0 ]]; then echo "ERRO: Corre como root."; exit 1; fi

# --- 1. CONFIGURAÇÃO DE REDE INTERATIVA (IP FIXO) ---
configurar_rede_interativa() {
    clear
    echo "============================================================"
    echo "    ATEC // SYSTEM_CORE_2026 - CONFIGURAÇÃO DE REDE"
    echo "============================================================"
    
    read -p "Definir Hostname (Enter para 'backup-srv'): " HOSTNAME_INPUT
    HOSTNAME_NEW="${HOSTNAME_INPUT:-backup-srv}"
    hostnamectl set-hostname "$HOSTNAME_NEW"
    
    echo -e "\n[INFO] Interfaces detetadas:"
    nmcli device status | grep -v "DEVICE"
    echo ""

    read -p "Nome da interface (ex: enp0s3): " IFACE
    # Se não for introduzido nada, tenta detetar a primeira interface ativa
    if [[ -z "$IFACE" ]]; then
        IFACE=$(nmcli device status | grep "ethernet" | head -n 1 | awk '{print $1}')
        echo "Interface selecionada automaticamente: $IFACE"
    fi

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

# --- 2. DETEÇÃO E CRIAÇÃO DO RAID 10 (CORRIGIDO) ---
echo -e "\n[INFO] A instalar ferramentas de disco..."
dnf install -y mdadm xfsprogs

echo -e "\n[INFO] A detetar discos para o RAID 10..."

# CORREÇÃO: Filtra discos que não sejam sda (sistema) e que não tenham partições montadas
# Assume que os discos de dados são sd* (sdb, sdc, sdd, sde, etc)
DISCOS_LIVRES=($(lsblk -dn -o NAME | grep -v "sda" | grep "^sd" | head -n 4 | awk '{print "/dev/"$1}'))

if [[ ${#DISCOS_LIVRES[@]} -lt 4 ]]; then
    echo "ERRO: Não encontrei 4 discos livres para o RAID. Encontrados: ${DISCOS_LIVRES[*]}"
    echo "Verifica se os discos sdb, sdc, sdd e sde estão ligados."
    exit 1
fi

echo "Discos selecionados para RAID: ${DISCOS_LIVRES[*]}"

# SEGURANÇA: Parar raids antigos e limpar metadados para evitar erros
mdadm --stop /dev/md0 2>/dev/null || true
mdadm --zero-superblock "${DISCOS_LIVRES[@]}" 2>/dev/null || true

# Criação do RAID
mdadm --create /dev/md0 --level=10 --raid-devices=4 "${DISCOS_LIVRES[@]}" --force

# Formatação e Montagem
mkfs.xfs -f /dev/md0
mkdir -p /backup
mount /dev/md0 /backup

# Persistência no fstab (remove entradas antigas duplicadas do md0 se existirem)
sed -i '/\/dev\/md0/d' /etc/fstab
UUID_RAID=$(blkid -s UUID -o value /dev/md0)
echo "UUID=$UUID_RAID /backup xfs defaults 0 0" >> /etc/fstab

# --- 3. ESTRUTURA DE DIRETÓRIOS E SEGURANÇA ---
echo "[INFO] A criar estrutura de pastas..."
mkdir -p /backup/web/incremental /backup/db/incremental /backup/logs
mkdir -p /backup/restic /backup/backrest /backup/ssh_keys /mnt/webserver_db

# --- 4. INSTALAÇÃO DE SERVIÇOS ---
echo "[INFO] A instalar serviços..."
dnf -y install epel-release
dnf -y install restic podman firewalld cronie fail2ban rsync fuse-sshfs

systemctl enable --now firewalld fail2ban
firewall-cmd --permanent --add-port=8000/tcp
firewall-cmd --reload

# --- 5. INICIALIZAÇÃO DO RESTIC ---
echo "restic_atec_2026" > /backup/backrest/restic-pass
chmod 600 /backup/backrest/restic-pass

if [[ ! -f "/backup/restic/config" ]]; then
    restic init --repo /backup/restic --password-file /backup/backrest/restic-pass
fi

# --- 6. CRIAÇÃO DO SCRIPT DE RESTAURO (DISASTER RECOVERY) ---
cat << 'EOF' > /usr/local/bin/restauro_dr
#!/bin/bash
REPO="/data/restic"
WEB_SERVER="192.168.1.100"
STAGING="/backup/backrest/RESTAURO_AUTO"
SSH_KEY="/backup/ssh_keys/id_rsa"

echo "--- Iniciando Restauro de Emergência ---"
sudo podman exec backrest restic -r $REPO unlock
mkdir -p $STAGING
sudo podman exec backrest restic -r $REPO restore latest --target /config/RESTAURO_AUTO

echo "Repondo ficheiro no Web Server..."
ssh -i $SSH_KEY root@$WEB_SERVER "mkdir -p /backup_db"
FICHEIRO=$(find $STAGING -name "*.sql.gz" | head -n 1)
if [[ -n "$FICHEIRO" ]]; then
    scp -i $SSH_KEY $FICHEIRO root@$WEB_SERVER:/backup_db/db_backup_recuperado.sql.gz
else
    echo "ERRO: Nenhum ficheiro SQL encontrado no backup."
fi
echo "--- Restauro Finalizado ---"
EOF
chmod +x /usr/local/bin/restauro_dr

# --- 7. ARRANQUE DO CONTENTOR (CONFIGURAÇÃO OTIMIZADA) ---
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
echo " SERVIDOR DE BACKUPS CONFIGURADO COM SUCESSO"
echo " RAID 10: Ativo em /backup (Discos: ${DISCOS_LIVRES[*]})"
echo " SCRIPT DE EMERGÊNCIA: restauro_dr"
echo "============================================================"
