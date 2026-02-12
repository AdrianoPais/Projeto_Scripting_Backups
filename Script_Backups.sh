#!/bin/bash
# ============================================================
#   ATEC // SYSTEM_CORE_2026 - MASTER STARTUP SCRIPT
#   RAID 10 + Restic + Disaster Recovery Automático
# ============================================================

set -euo pipefail

# --- 1. CONFIGURAÇÃO DE REDE ---
configurar_rede() {
    echo "[INFO] A configurar rede fixa..."
    # Ajusta os valores conforme a tua rede ATEC
    nmcli con mod "enp0s3" ipv4.method manual ipv4.addresses 192.168.1.200/24 ipv4.gateway 192.168.1.1 ipv4.dns 8.8.8.8
    nmcli con up "enp0s3"
}

# --- 2. CONFIGURAÇÃO DO RAID 10 (CORRIGIDO) ---
configurar_raid() {
    echo "[INFO] A criar RAID 10 com sdb, sdc, sdd, sde..."
    # Excluímos o sda (40G sistema) e usamos os 4 discos de 20G
    DISCOS=("/dev/sdb" "/dev/sdc" "/dev/sdd" "/dev/sde")
    mdadm --create /dev/md0 --level=10 --raid-devices=4 "${DISCOS[@]}" --force
    mkfs.xfs -f /dev/md0
    mkdir -p /backup
    mount /dev/md0 /backup
    echo "UUID=$(blkid -s UUID -o value /dev/md0) /backup xfs defaults 0 0" >> /etc/fstab
}

# --- 3. ESTRUTURA E FERRAMENTAS ---
instalar_base() {
    mkdir -p /backup/{web,db,restic,backrest,ssh_keys}
    mkdir -p /mnt/webserver_db
    dnf -y install restic podman fuse-sshfs
}

# --- 4. SCRIPT DE DISASTER RECOVERY (SOLUÇÃO PARA ERROS ANTERIORES) ---
criar_ferramenta_dr() {
    cat << 'EOF' > /usr/local/bin/restauro_dr
#!/bin/bash
# Resolve erros de "No such file" e "Is a directory"
WEB_SERVER="192.168.1.100"
STAGING="/backup/backrest/RESTAURO_FINAL"

echo "[DR] A desbloquear repositório..."
sudo podman exec backrest restic -r /data/restic unlock

echo "[DR] A extrair do RAID 10..."
mkdir -p $STAGING
sudo podman exec backrest restic -r /data/restic restore latest --target /config/RESTAURO_FINAL

echo "[DR] A repor no Web Server..."
# Força a criação da pasta de destino no Web Server
ssh -i /backup/ssh_keys/id_rsa root@$WEB_SERVER "mkdir -p /backup_db"
FICHEIRO=$(find $STAGING -name "*.sql.gz" | head -n 1)
scp -i /backup/ssh_keys/id_rsa $FICHEIRO root@$WEB_SERVER:/backup_db/db_backup_recuperado.sql.gz
EOF
    chmod +x /usr/local/bin/restauro_dr
}

# --- 5. INÍCIO DO CONTENTOR ---
iniciar_backrest() {
    podman stop backrest || true && podman rm backrest || true
    podman run -d --name backrest --restart always -p 8000:9898 \
      -v /backup/backrest:/config:Z \
      -v /backup/restic:/data/restic:Z \
      -v /backup/ssh_keys:/root/.ssh:Z \
      -v /mnt/webserver_db:/source_data:rw,z \
      --privileged \
      -e "RESTIC_PASSWORD_FILE=/config/restic-pass" \
      docker.io/garethgeorge/backrest:latest
}

# Execução
configurar_rede
configurar_raid
instalar_base
criar_ferramenta_dr
iniciar_backrest

echo "--- SISTEMA PRONTO EM http://192.168.1.200:8000 ---"
