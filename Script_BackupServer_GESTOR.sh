#!/bin/bash
# ============================================================
#  BACKUP SERVER - ATEC SYSTEM_CORE_2026
#  SCRIPT 2: GESTOR DE BACKUPS (Menu Grafico)
#  Executar: sudo bash /usr/local/sbin/backup-gestor.sh
# ============================================================

# --- VERIFICACOES ---
if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERRO: Corre como root."
    echo "  Usa: sudo bash $0"
    exit 1
fi

command -v dialog &>/dev/null || dnf -y install dialog

CONF_FILE="/etc/backup-atec.conf"
if [[ ! -f "$CONF_FILE" ]]; then
    dialog --title " ERRO " --msgbox \
        "\nFicheiro de configuracao nao encontrado!\n\nCorre primeiro:\n  sudo bash Script_BackupServer_INSTALACAO.sh" 11 55
    exit 1
fi
source "$CONF_FILE"

# --- VARIAVEIS ---
BACKUP_WEB="${BACKUP_BASE}/web/incremental"
BACKUP_CURRENT="${BACKUP_WEB}/current"
LOG_DIR="${BACKUP_BASE}/logs"
TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT


# ============================================================
#  FUNCOES
# ============================================================

mostrar_estado() {
    local info=""
    if ssh -o BatchMode=yes -o ConnectTimeout=3 "${WEBSERVER_USER}@${WEBSERVER_IP}" "echo ok" &>/dev/null; then
        local ssh_status="ONLINE"
    else
        local ssh_status="OFFLINE"
    fi
    local backup_size="Sem backup"
    if [[ -d "$BACKUP_CURRENT" ]] && [[ -n "$(ls -A "$BACKUP_CURRENT" 2>/dev/null)" ]]; then
        backup_size=$(du -sh "$BACKUP_CURRENT" 2>/dev/null | awk '{print $1}')
    fi
    local versoes=0
    versoes=$(find "$BACKUP_WEB" -maxdepth 1 -name "changed_*" -type d 2>/dev/null | wc -l)
    local ultimo="Nunca"
    local ultimo_log=""
    ultimo_log=$(ls -t "${LOG_DIR}"/backup_*.log 2>/dev/null | head -1)
    if [[ -n "$ultimo_log" ]]; then
        ultimo=$(stat -c '%y' "$ultimo_log" 2>/dev/null | cut -d'.' -f1)
    fi
    local disco="N/A"
    disco=$(df -h /backup 2>/dev/null | tail -1 | awk '{print $4 " livres de " $2}')
    local raid_status="N/A"
    if [[ -e /dev/md0 ]]; then
        raid_status=$(mdadm --detail /dev/md0 2>/dev/null | grep "State :" | awk -F: '{print $2}' | xargs)
    fi
    info="\n  ESTADO DO SISTEMA\n"
    info+="  ================================\n\n"
    info+="  WebServer:     ${WEBSERVER_USER}@${WEBSERVER_IP}\n"
    info+="  SSH:           ${ssh_status}\n"
    info+="  Backup atual:  ${backup_size}\n"
    info+="  Versoes:       ${versoes} incrementais\n"
    info+="  Ultimo backup: ${ultimo}\n"
    info+="  Disco RAID:    ${disco}\n"
    info+="  Estado RAID:   ${raid_status}\n"
    dialog --title " Estado do Sistema " --msgbox "$info" 17 55
}

fazer_backup() {
    dialog --title " Fazer Backup " --yesno \
        "\nFazer backup AGORA do website?\n\nOrigem:  ${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/\nDestino: ${BACKUP_CURRENT}/" 11 62
    [[ $? -ne 0 ]] && return
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"
    mkdir -p "$BACKUP_CURRENT"
    echo "=== BACKUP MANUAL: ${TIMESTAMP} ===" > "$LOG_FILE"
    (
        echo "10"; echo "# A ligar ao WebServer..."
        sleep 1
        echo "30"; echo "# A copiar ficheiros (rsync)..."
        rsync -avz --delete \
            --backup --backup-dir="${BACKUP_WEB}/changed_${TIMESTAMP}" \
            "${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/" \
            "${BACKUP_CURRENT}/" >> "$LOG_FILE" 2>&1
        RESULT=$?
        echo "90"; echo "# A finalizar..."
        sleep 1
        if [ $RESULT -eq 0 ]; then
            echo "[OK] Backup concluido: ${TIMESTAMP}" >> "$LOG_FILE"
            echo "100"; echo "# Concluido com sucesso!"
        else
            echo "[ERRO] Falha (codigo: $RESULT)" >> "$LOG_FILE"
            echo "100"; echo "# ERRO! Verifica o log."
        fi
    ) | dialog --title " Backup em Progresso " --gauge "\n  A iniciar..." 9 55 0
    local total_files=$(find "$BACKUP_CURRENT" -type f 2>/dev/null | wc -l)
    local total_size=$(du -sh "$BACKUP_CURRENT" 2>/dev/null | awk '{print $1}')
    local resultado=$(tail -1 "$LOG_FILE")
    dialog --title " Resultado " --msgbox \
        "\nBackup: ${TIMESTAMP}\nFicheiros: ${total_files}\nTamanho: ${total_size}\n\n${resultado}\n\nLog: ${LOG_FILE}" 14 58
}

listar_backups() {
    local lista="\n  BACKUP ATUAL:\n"
    if [[ -d "$BACKUP_CURRENT" ]] && [[ -n "$(ls -A "$BACKUP_CURRENT" 2>/dev/null)" ]]; then
        local size=$(du -sh "$BACKUP_CURRENT" 2>/dev/null | awk '{print $1}')
        local data=$(stat -c '%y' "$BACKUP_CURRENT" 2>/dev/null | cut -d'.' -f1)
        local nfiles=$(find "$BACKUP_CURRENT" -type f 2>/dev/null | wc -l)
        lista+="    ${size} | ${nfiles} ficheiros | ${data}\n"
    else
        lista+="    (nenhum)\n"
    fi
    lista+="\n  VERSOES INCREMENTAIS:\n"
    lista+="  ----------------------------------------\n"
    local i=1
    local encontrou=0
    for dir in $(ls -dt "${BACKUP_WEB}"/changed_* 2>/dev/null); do
        local nome=$(basename "$dir")
        local timestamp=${nome#changed_}
        local size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        local nf=$(find "$dir" -type f 2>/dev/null | wc -l)
        lista+="    ${i}. ${timestamp} | ${size} | ${nf} fich.\n"
        i=$((i + 1))
        encontrou=1
    done
    [[ $encontrou -eq 0 ]] && lista+="    (nenhuma)\n"
    dialog --title " Backups Disponiveis " --msgbox "$lista" 20 62
}

ver_conteudo() {
    if [[ ! -d "$BACKUP_CURRENT" ]] || [[ -z "$(ls -A "$BACKUP_CURRENT" 2>/dev/null)" ]]; then
        dialog --title " Info " --msgbox "\nNenhum backup disponivel." 7 35
        return
    fi
    local total=$(find "$BACKUP_CURRENT" -type f 2>/dev/null | wc -l)
    local size=$(du -sh "$BACKUP_CURRENT" 2>/dev/null | awk '{print $1}')
    local lista="Tamanho: ${size} | Ficheiros: ${total}\n\n"
    while IFS= read -r file; do
        local rel=${file#$BACKUP_CURRENT/}
        local fsize=$(du -h "$file" 2>/dev/null | awk '{print $1}')
        lista+="  ${rel}  (${fsize})\n"
    done < <(find "$BACKUP_CURRENT" -type f 2>/dev/null | sort | head -40)
    [[ $total -gt 40 ]] && lista+="\n  ... e mais $(($total - 40)) ficheiros"
    dialog --title " Conteudo do Backup " --msgbox "$lista" 22 70
}

restaurar_backup() {
    if [[ ! -d "$BACKUP_CURRENT" ]] || [[ -z "$(ls -A "$BACKUP_CURRENT" 2>/dev/null)" ]]; then
        dialog --title " Erro " --msgbox "\nNenhum backup para restaurar!\nFaz primeiro um backup (opcao 2)." 9 48
        return
    fi
    local size=$(du -sh "$BACKUP_CURRENT" 2>/dev/null | awk '{print $1}')
    local nfiles=$(find "$BACKUP_CURRENT" -type f 2>/dev/null | wc -l)
    dialog --title " Restaurar Backup " --yesno \
        "\nATENCAO: O conteudo atual do WebServer\nsera substituido pelo backup!\n\nOrigem:  ${BACKUP_CURRENT}/ (${size}, ${nfiles} fich.)\nDestino: ${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/\n\nContinuar?" 14 62
    [[ $? -ne 0 ]] && return
    dialog --title " Confirmacao Final " --yesno \
        "\nTEM A CERTEZA?\nO site do WebServer vai ser substituido." 9 50
    [[ $? -ne 0 ]] && return
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local LOG_FILE="${LOG_DIR}/restore_${TIMESTAMP}.log"
    echo "=== RESTAURO: ${TIMESTAMP} ===" > "$LOG_FILE"
    (
        echo "10"; echo "# A ligar ao WebServer..."
        sleep 1
        echo "30"; echo "# A enviar ficheiros..."
        rsync -avz --delete \
            "${BACKUP_CURRENT}/" \
            "${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/" >> "$LOG_FILE" 2>&1
        RESULT=$?
        echo "70"; echo "# A corrigir permissoes e SELinux..."
        ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" \
            "chown -R apache:apache ${WEBROOT_REMOTE} && restorecon -Rv ${WEBROOT_REMOTE}" >> "$LOG_FILE" 2>&1
        echo "90"; echo "# A reiniciar Apache..."
        ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "systemctl restart httpd" >> "$LOG_FILE" 2>&1
        if [ $RESULT -eq 0 ]; then
            echo "100"; echo "# Restauro concluido!"
        else
            echo "100"; echo "# ERRO no restauro!"
        fi
    ) | dialog --title " Restauro em Progresso " --gauge "\n  A iniciar..." 9 55 0
    dialog --title " Concluido " --msgbox \
        "\nWebsite restaurado com sucesso!\n\nVerifica: http://${WEBSERVER_IP}\nLog: ${LOG_FILE}" 11 55
}

apagar_site_remoto() {
    dialog --title " APAGAR SITE " --yesno \
        "\nPERIGO! Isto vai APAGAR todo o conteudo\nde ${WEBROOT_REMOTE}/ no WebServer!\n\nIP: ${WEBSERVER_IP}\n\nContinuar?" 13 55
    [[ $? -ne 0 ]] && return
    # Verificar se tem backup
    if [[ ! -d "$BACKUP_CURRENT" ]] || [[ -z "$(ls -A "$BACKUP_CURRENT" 2>/dev/null)" ]]; then
        dialog --title " SEM BACKUP! " --yesno \
            "\nNAO tens backup!\nSe apagares, nao podes recuperar.\n\nFazer backup ANTES de apagar?" 10 50
        if [[ $? -eq 0 ]]; then
            mkdir -p "$BACKUP_CURRENT"
            rsync -avz "${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/" "${BACKUP_CURRENT}/" 2>/dev/null
            dialog --title " OK " --msgbox "\nBackup de seguranca feito!" 7 38
        fi
    fi
    # Confirmacao final
    dialog --title " Confirmacao " --inputbox "\nPara confirmar, escreve APAGAR:" 9 45 2>"$TEMP_FILE"
    local confirm=$(cat "$TEMP_FILE")
    if [[ "$confirm" != "APAGAR" ]]; then
        dialog --title " Cancelado " --msgbox "\nOperacao cancelada." 7 30
        return
    fi
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local LOG_FILE="${LOG_DIR}/delete_${TIMESTAMP}.log"
    (
        echo "20"; echo "# A apagar conteudo do WebServer..."
        ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "rm -rf ${WEBROOT_REMOTE}/*" >> "$LOG_FILE" 2>&1
        echo "60"; echo "# A verificar..."
        local restantes=$(ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "find ${WEBROOT_REMOTE}/ -type f 2>/dev/null | wc -l")
        echo "Ficheiros restantes: ${restantes}" >> "$LOG_FILE"
        echo "80"; echo "# A reiniciar Apache..."
        ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "systemctl restart httpd" >> "$LOG_FILE" 2>&1
        echo "100"; echo "# Concluido."
    ) | dialog --title " A Apagar... " --gauge "\n  A processar..." 9 55 0
    dialog --title " Site Apagado " --msgbox \
        "\nConteudo de ${WEBROOT_REMOTE}/ foi apagado\nno WebServer (${WEBSERVER_IP}).\n\nPara restaurar, usa a opcao 5 do menu." 11 55
}

testar_ligacao() {
    local resultado="\n  A testar ligacao ao WebServer...\n"
    resultado+="  Destino: ${WEBSERVER_USER}@${WEBSERVER_IP}\n\n"
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${WEBSERVER_USER}@${WEBSERVER_IP}" "echo ok" &>/dev/null; then
        resultado+="  SSH:      OK\n"
        local remote_files=$(ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "find ${WEBROOT_REMOTE}/ -type f 2>/dev/null | wc -l")
        resultado+="  Website:  ${remote_files} ficheiros em ${WEBROOT_REMOTE}/\n"
        local apache=$(ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "systemctl is-active httpd 2>/dev/null")
        resultado+="  Apache:   ${apache}\n"
        local disco=$(ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "df -h /var/www 2>/dev/null | tail -1 | awk '{print \$4}'" 2>/dev/null)
        resultado+="  Disco:    ${disco} livres\n"
    else
        resultado+="  SSH:      FALHA\n\n"
        resultado+="  Causas possiveis:\n"
        resultado+="  - WebServer desligado\n"
        resultado+="  - Chave SSH nao configurada\n"
        resultado+="  - Firewall porta 22 bloqueada\n"
    fi
    dialog --title " Teste de Ligacao " --msgbox "$resultado" 16 55
}

ver_logs() {
    local logs=""
    logs=$(ls -t "${LOG_DIR}"/*.log 2>/dev/null | head -10)
    if [[ -z "$logs" ]]; then
        dialog --title " Logs " --msgbox "\nNenhum log encontrado." 7 35
        return
    fi
    local menu_items=()
    local i=1
    while IFS= read -r log; do
        local nome=$(basename "$log")
        menu_items+=("$i" "$nome")
        i=$((i + 1))
    done <<< "$logs"
    dialog --title " Logs de Backup " --menu "\nSeleciona um log:" 16 60 8 \
        "${menu_items[@]}" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return
    local escolha=$(cat "$TEMP_FILE")
    local log_file=$(echo "$logs" | sed -n "${escolha}p")
    [[ -f "$log_file" ]] && dialog --title " $(basename "$log_file") " --textbox "$log_file" 20 75
}

estado_raid() {
    if [[ ! -e /dev/md0 ]]; then
        dialog --title " RAID " --msgbox "\nNenhum RAID detetado." 7 35
        return
    fi
    local tmp_raid=$(mktemp)
    mdadm --detail /dev/md0 > "$tmp_raid" 2>&1
    echo "" >> "$tmp_raid"
    echo "--- /proc/mdstat ---" >> "$tmp_raid"
    cat /proc/mdstat >> "$tmp_raid" 2>&1
    dialog --title " Estado do RAID 10 " --textbox "$tmp_raid" 25 75
    rm -f "$tmp_raid"
}


# ============================================================
#  MENU PRINCIPAL
# ============================================================

while true; do
    dialog --title " ATEC // GESTOR DE BACKUPS " \
        --cancel-label "Sair" \
        --menu "\n  BackupServer -> WebServer (${WEBSERVER_IP})\n" 22 58 10 \
        1  "Ver Estado do Sistema" \
        2  "Fazer Backup AGORA" \
        3  "Listar Backups Disponiveis" \
        4  "Ver Conteudo do Backup" \
        5  "Restaurar Backup no WebServer" \
        6  "Apagar Site do WebServer" \
        7  "Testar Ligacao SSH" \
        8  "Ver Logs" \
        9  "Estado do RAID 10" \
        10 "Reconfigurar" \
        2>"$TEMP_FILE"

    if [[ $? -ne 0 ]]; then
        rm -f "$TEMP_FILE"
        clear
        echo "Gestor de Backups encerrado."
        exit 0
    fi

    escolha=$(cat "$TEMP_FILE")

    case $escolha in
        1)  mostrar_estado ;;
        2)  fazer_backup ;;
        3)  listar_backups ;;
        4)  ver_conteudo ;;
        5)  restaurar_backup ;;
        6)  apagar_site_remoto ;;
        7)  testar_ligacao ;;
        8)  ver_logs ;;
        9)  estado_raid ;;
        10) dialog --title " Reconfigurar " --editbox "$CONF_FILE" 12 55 2>"$TEMP_FILE"
            if [[ $? -eq 0 ]]; then
                cp "$TEMP_FILE" "$CONF_FILE"
                source "$CONF_FILE"
                BACKUP_WEB="${BACKUP_BASE}/web/incremental"
                BACKUP_CURRENT="${BACKUP_WEB}/current"
                LOG_DIR="${BACKUP_BASE}/logs"
                dialog --title " OK " --msgbox "\nConfiguracao atualizada!" 7 35
            fi ;;
    esac
done
