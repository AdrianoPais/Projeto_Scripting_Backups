#!/bin/bash
# ============================================================
#  BACKUP SERVER - ATEC SYSTEM_CORE_2026
#  SCRIPT 1: INSTALAÇÃO E CONFIGURAÇÃO COMPLETA
#  Rede + Pacotes + RAID 10 + SSH + Cron + Primeiro Backup
# ============================================================

# --- CORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "\n${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
warn()  { echo -e "${YELLOW}[AVISO]${NC} $*"; }
fail()  { echo -e "${RED}[ERRO]${NC} $*"; exit 1; }

# --- VERIFICAÇÃO DE ROOT ---
if [[ "$(id -u)" -ne 0 ]]; then
    fail "Este script tem de ser corrido como root.\n\n  Usa:  sudo bash $0"
fi

clear
echo "============================================================"
echo "   ATEC // BACKUP_SERVER - INSTALACAO COMPLETA"
echo "============================================================"
echo ""
echo "  Este script configura TUDO de uma vez:"
echo ""
echo "  FASE 1 - SISTEMA"
echo "    1. Hostname e Rede (IP fixo)"
echo "    2. Pacotes (rsync, mdadm, dialog, etc.)"
echo "    3. Firewall"
echo ""
echo "  FASE 2 - RAID 10"
echo "    4. Detetar discos disponiveis"
echo "    5. Criar array RAID 10"
echo "    6. Formatar e montar em /backup"
echo ""
echo "  FASE 3 - BACKUPS"
echo "    7. Chaves SSH para o WebServer"
echo "    8. Scripts de backup + Gestor grafico"
echo "    9. Agendamento automatico (cron)"
echo "   10. Primeiro backup"
echo ""
echo "============================================================"
echo ""
read -p "Iniciar instalacao? (s/n): " iniciar
[[ "$iniciar" != "s" ]] && exit 0


# ############################################################
#  FASE 1: SISTEMA (Rede, Pacotes, Firewall)
# ############################################################

echo ""
echo -e "${BOLD}========== FASE 1: SISTEMA ==========${NC}"

# --- 1. REDE ---
echo ""
echo "------------------------------------------------------------"
echo "  PASSO 1: CONFIGURACAO DE REDE"
echo "------------------------------------------------------------"
echo ""
read -p "A rede ja esta configurada? Saltar? (s/n): " saltar_rede

if [[ "$saltar_rede" != "s" ]]; then
    read -p "Hostname (Enter para 'backupserver-atec'): " HOSTNAME_INPUT
    HOSTNAME_NEW="${HOSTNAME_INPUT:-backupserver-atec}"

    echo ""
    info "Interfaces detetadas:"
    nmcli device status
    echo ""

    read -p "Interface (ex: ens160, enp0s3): " IFACE
    read -p "IP (Enter para 192.168.1.110/24): " IP_INPUT
    IP_ADDR="${IP_INPUT:-192.168.1.110/24}"
    read -p "Gateway (Enter para 192.168.1.1): " GW_INPUT
    GATEWAY="${GW_INPUT:-192.168.1.1}"
    read -p "DNS (Enter para 1.1.1.1): " DNS_INPUT
    DNS1="${DNS_INPUT:-1.1.1.1}"

    echo ""
    echo "  Hostname:  $HOSTNAME_NEW"
    echo "  Interface: $IFACE | IP: $IP_ADDR"
    echo "  Gateway:   $GATEWAY | DNS: $DNS1"
    echo ""
    read -p "Confirmar? (s/n): " confirmar
    [[ "$confirmar" != "s" ]] && fail "Cancelado."

    info "A aplicar..."
    hostnamectl set-hostname "$HOSTNAME_NEW"
    nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore 2>/dev/null || \
    nmcli con mod "$IFACE" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore 2>/dev/null || \
    nmcli con mod "System $IFACE" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore 2>/dev/null || \
    warn "Configura manualmente com nmtui."
    nmcli con down "$IFACE" 2>/dev/null || true
    nmcli con up "$IFACE" 2>/dev/null || nmcli con up "Wired connection 1" 2>/dev/null || true
    ok "Rede configurada."
else
    ok "Rede ja configurada. IP: $(hostname -I | awk '{print $1}')"
fi

# --- 2. PACOTES ---
echo ""
echo "------------------------------------------------------------"
echo "  PASSO 2: INSTALACAO DE PACOTES"
echo "------------------------------------------------------------"
info "A instalar pacotes..."
dnf -y install rsync openssh-clients dialog cronie firewalld mdadm bc 2>&1 | tail -5
ok "Pacotes instalados."

# --- 3. FIREWALL ---
echo ""
echo "------------------------------------------------------------"
echo "  PASSO 3: FIREWALL"
echo "------------------------------------------------------------"
systemctl enable --now crond 2>/dev/null || true
systemctl enable --now firewalld 2>/dev/null || true
firewall-cmd --permanent --add-service=ssh 2>/dev/null || true
firewall-cmd --reload 2>/dev/null || true
ok "Firewall configurada (SSH aberto)."


# ############################################################
#  FASE 2: RAID 10
# ############################################################

echo ""
echo -e "${BOLD}========== FASE 2: RAID 10 ==========${NC}"

# Verificar se ja existe RAID montado em /backup
if mountpoint -q /backup 2>/dev/null && [[ -e /dev/md0 ]]; then
    echo ""
    warn "RAID ja existe e esta montado em /backup!"
    mdadm --detail /dev/md0 2>/dev/null | head -15
    echo ""
    read -p "Saltar configuracao RAID? (s/n): " saltar_raid
    if [[ "$saltar_raid" == "s" ]]; then
        ok "RAID existente mantido."
        SKIP_RAID=1
    else
        SKIP_RAID=0
    fi
else
    SKIP_RAID=0
fi

if [[ "${SKIP_RAID:-0}" -eq 0 ]]; then

    # Destruir RAID antigo se existir
    if [[ -e /dev/md0 ]] || [[ -e /dev/md/atec_raid10 ]]; then
        warn "A limpar RAID antigo..."
        umount /dev/md0 2>/dev/null || true
        mdadm --stop /dev/md0 2>/dev/null || true
        mdadm --stop /dev/md/atec_raid10 2>/dev/null || true
        for dev in $(cat /proc/mdstat 2>/dev/null | grep -oP 'nvme\S+|sd\S+|vd\S+' | sed 's/\[.*//'); do
            mdadm --zero-superblock "/dev/${dev}" 2>/dev/null || true
        done
        sed -i '/md0\|atec_raid10/d' /etc/mdadm.conf 2>/dev/null || true
        sed -i '/md0\|atec_raid10/d' /etc/fstab 2>/dev/null || true
        sed -i '/\/backup/d' /etc/fstab 2>/dev/null || true
        ok "RAID antigo removido."
    fi

    # --- DETETAR DISCOS ---
    echo ""
    echo "------------------------------------------------------------"
    echo "  PASSO 4: DETECAO DE DISCOS"
    echo "------------------------------------------------------------"

    # Descobrir discos do SO
    declare -A DISCOS_SO=()
    # Via mountpoints
    while IFS= read -r mounted_dev; do
        parent=$(lsblk -ndo PKNAME "$mounted_dev" 2>/dev/null | head -1)
        [[ -n "$parent" ]] && DISCOS_SO["$parent"]=1
    done < <(findmnt -n -o SOURCE 2>/dev/null | grep "^/dev/" | sort -u)
    # Via LVM
    while IFS= read -r pv; do
        pv=$(echo "$pv" | xargs)
        parent=$(lsblk -ndo PKNAME "$pv" 2>/dev/null | head -1)
        [[ -n "$parent" ]] && DISCOS_SO["$parent"]=1
    done < <(pvs --noheadings -o pv_name 2>/dev/null)

    info "Discos do SO (protegidos):"
    for d in "${!DISCOS_SO[@]}"; do
        echo "      /dev/${d}"
    done

    # Listar discos disponiveis
    declare -a DISCOS_DISPONIVEIS=()
    declare -a DISCOS_INFO=()

    while IFS= read -r NOME; do
        [[ -z "$NOME" ]] && continue
        case "$NOME" in loop*|sr*|ram*|zram*|md*) continue ;; esac
        [[ -n "${DISCOS_SO[$NOME]+x}" ]] && continue

        TAMANHO=$(lsblk -ndo SIZE "/dev/${NOME}" 2>/dev/null || echo "?")
        MODELO=$(lsblk -ndo MODEL "/dev/${NOME}" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -z "$MODELO" ]] && MODELO="Disco Virtual"

        # Verificar estado (seguro para pipefail)
        MONTADO=$(lsblk -n "/dev/${NOME}" 2>/dev/null | grep "part.*/" | wc -l)
        MONTADO=$((MONTADO + 0))
        EM_RAID=$(mdadm --examine "/dev/${NOME}" 2>/dev/null | grep "Array" | wc -l)
        EM_RAID=$((EM_RAID + 0))
        NUM_PARTS=$(lsblk -n "/dev/${NOME}" 2>/dev/null | grep "part" | wc -l)
        NUM_PARTS=$((NUM_PARTS + 0))

        if [[ $MONTADO -gt 0 ]]; then
            STATUS="${RED}[MONTADO]${NC}"
        elif [[ $EM_RAID -gt 0 ]]; then
            STATUS="${YELLOW}[EM RAID]${NC}"
        elif [[ $NUM_PARTS -gt 0 ]]; then
            STATUS="${YELLOW}[TEM PARTICOES]${NC}"
        else
            STATUS="${GREEN}[DISPONIVEL]${NC}"
        fi

        DISCOS_DISPONIVEIS+=("$NOME")
        DISCOS_INFO+=("${TAMANHO}|${MODELO}|${STATUS}")
    done < <(lsblk -ndo NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}')

    if [[ ${#DISCOS_DISPONIVEIS[@]} -eq 0 ]]; then
        fail "Nenhum disco disponivel! Adiciona pelo menos 4 discos a VM."
    fi

    echo ""
    echo -e "${BOLD}  #   DISCO           TAMANHO  MODELO               ESTADO${NC}"
    echo "  --- --------------- -------- -------------------- ---------------"
    for i in "${!DISCOS_DISPONIVEIS[@]}"; do
        IFS='|' read -r tam modelo status <<< "${DISCOS_INFO[$i]}"
        printf "  %-3s /dev/%-11s %-8s %-20s %b\n" "$((i+1))" "${DISCOS_DISPONIVEIS[$i]}" "$tam" "$modelo" "$status"
    done
    echo ""
    echo "  Total: ${#DISCOS_DISPONIVEIS[@]} discos disponiveis"

    # --- SELECIONAR DISCOS ---
    echo ""
    echo "------------------------------------------------------------"
    echo "  PASSO 5: SELECAO DE DISCOS PARA RAID 10"
    echo "------------------------------------------------------------"
    echo ""
    echo "  RAID 10: minimo 4 discos, numero PAR."
    echo ""

    if [[ ${#DISCOS_DISPONIVEIS[@]} -lt 4 ]]; then
        fail "Precisas de minimo 4 discos! So tens ${#DISCOS_DISPONIVEIS[@]}."
    fi

    # Se tem 5 discos, sugerir usar 4
    if [[ $((${#DISCOS_DISPONIVEIS[@]} % 2)) -ne 0 ]]; then
        echo -e "  ${YELLOW}Tens ${#DISCOS_DISPONIVEIS[@]} discos (impar). RAID 10 precisa de par.${NC}"
        echo "  Escolhe manualmente quais usar (4 discos recomendado)."
        echo ""
        MODO_SELECAO="M"
    else
        echo "  [A] Usar TODOS os ${#DISCOS_DISPONIVEIS[@]} discos (recomendado)"
        echo "  [M] Escolher manualmente"
        echo ""
        read -p "  Escolha (A/M): " MODO_SELECAO
    fi

    declare -a DISCOS_SELECIONADOS=()

    if [[ "${MODO_SELECAO^^}" == "A" ]]; then
        DISCOS_SELECIONADOS=("${DISCOS_DISPONIVEIS[@]}")
    else
        echo ""
        echo "  Numeros dos discos separados por espaco (ex: 2 3 4 5):"
        read -p "  > " -a escolhas_disco
        for num in "${escolhas_disco[@]}"; do
            idx=$((num - 1))
            if [[ $idx -ge 0 && $idx -lt ${#DISCOS_DISPONIVEIS[@]} ]]; then
                DISCOS_SELECIONADOS+=("${DISCOS_DISPONIVEIS[$idx]}")
            else
                warn "Numero $num invalido, ignorado."
            fi
        done
    fi

    NUM_DISCOS=${#DISCOS_SELECIONADOS[@]}

    if [[ $NUM_DISCOS -lt 4 ]]; then
        fail "Minimo 4 discos! Selecionaste ${NUM_DISCOS}."
    fi
    if [[ $((NUM_DISCOS % 2)) -ne 0 ]]; then
        fail "Precisa de numero PAR! Selecionaste ${NUM_DISCOS}."
    fi

    # Construir devices
    declare -a RAID_DEVICES=()
    for disco in "${DISCOS_SELECIONADOS[@]}"; do
        RAID_DEVICES+=("/dev/${disco}")
    done

    # Calcular capacidade
    TAM_BYTES=$(lsblk -bndo SIZE "${RAID_DEVICES[0]}" 2>/dev/null)
    TAM_GB=$(echo "scale=1; ${TAM_BYTES}/1024/1024/1024" | bc 2>/dev/null || echo "?")
    CAP_UTIL=$(echo "scale=1; ${TAM_GB} * ${NUM_DISCOS} / 2" | bc 2>/dev/null || echo "?")

    echo ""
    echo "============================================================"
    echo "  RESUMO RAID 10"
    echo "============================================================"
    for dev in "${RAID_DEVICES[@]}"; do
        echo "    -> ${dev} ($(lsblk -ndo SIZE "$dev" 2>/dev/null))"
    done
    echo ""
    echo "  Capacidade util: ~${CAP_UTIL} GB"
    echo "  Montagem: /backup"
    echo ""
    echo -e "  ${RED}TODOS OS DADOS NESTES DISCOS SERAO APAGADOS!${NC}"
    echo ""
    read -p "  Confirmar? (escreve SIM): " confirmar_raid
    [[ "$confirmar_raid" != "SIM" ]] && fail "Cancelado."

    # --- PREPARAR DISCOS ---
    echo ""
    echo "------------------------------------------------------------"
    echo "  PASSO 6: A CRIAR RAID 10..."
    echo "------------------------------------------------------------"

    for dev in "${RAID_DEVICES[@]}"; do
        info "A preparar ${dev}..."
        umount "${dev}"* 2>/dev/null || true
        mdadm --zero-superblock "$dev" 2>/dev/null || true
        wipefs -a "$dev" 2>/dev/null || true
        dd if=/dev/zero of="$dev" bs=1M count=10 2>/dev/null || true
        # Criar particao RAID
        (echo o; echo n; echo p; echo 1; echo; echo; echo t; echo fd; echo w) | fdisk "$dev" 2>/dev/null || true
        partprobe "$dev" 2>/dev/null || true
        ok "${dev} preparado."
    done

    sleep 2
    partprobe 2>/dev/null || true
    sleep 1

    # Detetar particoes
    declare -a RAID_PARTITIONS=()
    for dev in "${RAID_DEVICES[@]}"; do
        PART=""
        if [[ -b "${dev}p1" ]]; then
            PART="${dev}p1"
        elif [[ -b "${dev}1" ]]; then
            PART="${dev}1"
        else
            sleep 2; partprobe "$dev" 2>/dev/null; sleep 1
            if [[ -b "${dev}p1" ]]; then PART="${dev}p1"
            elif [[ -b "${dev}1" ]]; then PART="${dev}1"
            else PART="$dev"; warn "A usar disco inteiro: ${dev}"
            fi
        fi
        RAID_PARTITIONS+=("$PART")
        info "Particao: ${PART}"
    done

    # Criar RAID
    info "A criar array RAID 10..."
    mdadm --create /dev/md0 \
        --level=10 \
        --raid-devices="${NUM_DISCOS}" \
        --metadata=1.2 \
        --name=atec_raid10 \
        "${RAID_PARTITIONS[@]}" <<< "y"

    if [[ $? -ne 0 ]]; then
        fail "Erro ao criar RAID 10!"
    fi
    ok "Array RAID 10 criado!"
    cat /proc/mdstat

    # Formatar
    info "A formatar com ext4..."
    mkfs.ext4 -F -L "ATEC_BACKUP" /dev/md0
    ok "Formatado."

    # Montar
    mkdir -p /backup
    sed -i '/\/backup/d' /etc/fstab 2>/dev/null || true
    sed -i '/md0/d' /etc/fstab 2>/dev/null || true
    UUID_RAID=$(blkid -s UUID -o value /dev/md0)
    mount /dev/md0 /backup
    echo "UUID=${UUID_RAID}  /backup  ext4  defaults,nofail  0  2" >> /etc/fstab
    ok "Montado em /backup (permanente via fstab)"

    # Guardar config RAID
    mdadm --detail --scan >> /etc/mdadm.conf 2>/dev/null || true
    info "A atualizar initramfs (pode demorar 1-2 min)..."
    dracut --force 2>/dev/null &
    DRACUT_PID=$!
    # Nao esperar - continuar com o resto
    warn "dracut a correr em background (PID: $DRACUT_PID)"

fi  # fim do if SKIP_RAID

# Criar estrutura de diretorios
mkdir -p /backup/web/incremental
mkdir -p /backup/db/incremental
mkdir -p /backup/logs
chmod 700 /backup

ok "Estrutura de backup criada em /backup"


# ############################################################
#  FASE 3: BACKUPS (SSH, Scripts, Cron)
# ############################################################

echo ""
echo -e "${BOLD}========== FASE 3: BACKUPS ==========${NC}"

# --- 7. SSH ---
echo ""
echo "------------------------------------------------------------"
echo "  PASSO 7: ACESSO SSH AO WEBSERVER"
echo "------------------------------------------------------------"
echo ""

read -p "IP do WebServer (Enter para 192.168.1.100): " WS_IP_INPUT
WEBSERVER_IP="${WS_IP_INPUT:-192.168.1.100}"

read -p "Utilizador SSH (Enter para root): " WS_USER_INPUT
WEBSERVER_USER="${WS_USER_INPUT:-root}"

# Guardar config
cat > /etc/backup-atec.conf <<CONFEOF
WEBSERVER_IP="${WEBSERVER_IP}"
WEBSERVER_USER="${WEBSERVER_USER}"
WEBROOT_REMOTE="/var/www/html"
BACKUP_BASE="/backup"
CONFEOF
chmod 600 /etc/backup-atec.conf
ok "Configuracao guardada em /etc/backup-atec.conf"

# Chave SSH
mkdir -p /root/.ssh && chmod 700 /root/.ssh
if [[ ! -f /root/.ssh/id_rsa ]]; then
    info "A gerar chave SSH..."
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
    ok "Chave gerada."
else
    warn "Chave SSH ja existe."
fi

info "A testar ligacao..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 "${WEBSERVER_USER}@${WEBSERVER_IP}" "echo ok" &>/dev/null; then
    ok "SSH ja funciona sem password!"
else
    echo ""
    echo "  Preciso da PASSWORD de ${WEBSERVER_USER}@${WEBSERVER_IP} (so 1 vez)"
    echo ""
    ssh-copy-id -o StrictHostKeyChecking=no "${WEBSERVER_USER}@${WEBSERVER_IP}"
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${WEBSERVER_USER}@${WEBSERVER_IP}" "echo ok" &>/dev/null; then
        ok "SSH configurado com sucesso!"
    else
        warn "SSH falhou. Configura depois: ssh-copy-id ${WEBSERVER_USER}@${WEBSERVER_IP}"
    fi
fi

# --- 8. SCRIPTS ---
echo ""
echo "------------------------------------------------------------"
echo "  PASSO 8: INSTALACAO DOS SCRIPTS"
echo "------------------------------------------------------------"

# Script de backup automatico
info "A instalar script de backup automatico..."
cat > /usr/local/sbin/backup-auto.sh <<'AUTOEOF'
#!/bin/bash
source /etc/backup-atec.conf
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${BACKUP_BASE}/logs/backup_${TIMESTAMP}.log"
DEST="${BACKUP_BASE}/web/incremental"
echo "=== BACKUP AUTO: ${TIMESTAMP} ===" >> "$LOG_FILE"
mkdir -p "${DEST}/current"
rsync -avz --delete --backup --backup-dir="${DEST}/changed_${TIMESTAMP}" \
    "${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/" \
    "${DEST}/current/" >> "$LOG_FILE" 2>&1
RET=$?
[ $RET -eq 0 ] && echo "[OK] Concluido." >> "$LOG_FILE" || echo "[ERRO] Codigo: $RET" >> "$LOG_FILE"
find "${DEST}" -maxdepth 1 -name "changed_*" -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null
echo "=== FIM ===" >> "$LOG_FILE"
AUTOEOF
chmod +x /usr/local/sbin/backup-auto.sh
ok "backup-auto.sh instalado."

# Gestor grafico - sera instalado pelo Script 2 (GESTOR)
# Mas tambem o criamos aqui para conveniencia
info "A instalar gestor grafico..."
GESTOR_PATH="/usr/local/sbin/backup-gestor.sh"

# Copiar o Script_BackupServer_GESTOR.sh se existir na mesma pasta
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [[ -f "${SCRIPT_DIR}/Script_BackupServer_GESTOR.sh" ]]; then
    cp "${SCRIPT_DIR}/Script_BackupServer_GESTOR.sh" "$GESTOR_PATH"
    chmod +x "$GESTOR_PATH"
    ok "Gestor copiado de ${SCRIPT_DIR}/Script_BackupServer_GESTOR.sh"
elif [[ -f "$GESTOR_PATH" ]]; then
    ok "Gestor ja instalado em ${GESTOR_PATH}"
else
    warn "Script_BackupServer_GESTOR.sh nao encontrado na mesma pasta."
    warn "Copia-o manualmente para ${GESTOR_PATH} ou coloca-o junto deste script."
fi

# --- 9. CRON ---
echo ""
echo "------------------------------------------------------------"
echo "  PASSO 9: AGENDAMENTO AUTOMATICO"
echo "------------------------------------------------------------"

CRON_TMP=$(mktemp)
crontab -l > "$CRON_TMP" 2>/dev/null || true
grep -v "backup-auto.sh" "$CRON_TMP" > "${CRON_TMP}.clean" 2>/dev/null || true
echo "0 3 * * 0 /usr/local/sbin/backup-auto.sh" >> "${CRON_TMP}.clean"
crontab "${CRON_TMP}.clean"
rm -f "$CRON_TMP" "${CRON_TMP}.clean"
ok "Cron: Domingos as 03:00"
crontab -l 2>/dev/null

# --- 10. PRIMEIRO BACKUP ---
echo ""
echo "------------------------------------------------------------"
echo "  PASSO 10: PRIMEIRO BACKUP"
echo "------------------------------------------------------------"
read -p "Fazer backup agora? (s/n): " primeiro
if [[ "$primeiro" == "s" ]]; then
    info "A fazer backup do website..."
    mkdir -p /backup/web/incremental/current
    rsync -avz --progress \
        "${WEBSERVER_USER}@${WEBSERVER_IP}:/var/www/html/" \
        "/backup/web/incremental/current/"
    if [[ $? -eq 0 ]]; then
        ok "Backup concluido!"
        ls -la /backup/web/incremental/current/
    else
        warn "Falhou. Faz depois pelo gestor."
    fi
fi

# Esperar pelo dracut se ainda estiver a correr
if [[ -n "${DRACUT_PID:-}" ]] && kill -0 "$DRACUT_PID" 2>/dev/null; then
    info "A aguardar que o dracut termine..."
    wait "$DRACUT_PID" 2>/dev/null || true
    ok "dracut concluido."
fi


# ############################################################
#  RESUMO FINAL
# ############################################################

CURRENT_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "============================================================"
echo "   INSTALACAO COMPLETA - BACKUP SERVER ATEC"
echo "============================================================"
echo ""
echo "  Servidor:  $(hostname) (${CURRENT_IP})"
echo "  WebServer: ${WEBSERVER_USER}@${WEBSERVER_IP}"
echo ""
if [[ -e /dev/md0 ]]; then
    DF_INFO=$(df -h /backup | tail -1)
    echo "  RAID 10:   /dev/md0 -> /backup"
    echo "  Espaco:    $(echo "$DF_INFO" | awk '{print $4}') livres de $(echo "$DF_INFO" | awk '{print $2}')"
fi
echo ""
echo "  Cron:      Domingos as 03:00"
echo ""
echo "  GESTOR GRAFICO:"
echo "  sudo bash /usr/local/sbin/backup-gestor.sh"
echo ""
echo "============================================================"
