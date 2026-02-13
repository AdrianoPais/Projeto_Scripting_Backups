#!/bin/bash
# ============================================================
#  BACKUP SERVER - ATEC SYSTEM_CORE_2026
#  SCRIPT 2: GESTOR DE BACKUPS (Menu Grafico) - v2.0
#  NOVA FUNCIONALIDADE: Agendamento Personalizado
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
#  FUNCOES ORIGINAIS
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
    
    # Info sobre agendamentos
    local num_agendamentos=0
    num_agendamentos=$(crontab -l 2>/dev/null | grep -c "backup-auto.sh" || echo 0)
    
    info="\n  ESTADO DO SISTEMA\n"
    info+="  ================================\n\n"
    info+="  WebServer:     ${WEBSERVER_USER}@${WEBSERVER_IP}\n"
    info+="  SSH:           ${ssh_status}\n"
    info+="  Backup atual:  ${backup_size}\n"
    info+="  Versoes:       ${versoes} incrementais\n"
    info+="  Ultimo backup: ${ultimo}\n"
    info+="  Agendamentos:  ${num_agendamentos} ativos\n"
    info+="  Disco RAID:    ${disco}\n"
    info+="  Estado RAID:   ${raid_status}\n"
    dialog --title " Estado do Sistema " --msgbox "$info" 18 55
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
#  NOVAS FUNCOES - AGENDAMENTO
# ============================================================

ver_agendamentos() {
    local info="\n  AGENDAMENTOS DE BACKUP AUTOMATICO\n"
    info+="  ========================================\n\n"
    
    # Obter lista de cron jobs relacionados com backup
    local cron_list=$(crontab -l 2>/dev/null | grep "backup-auto.sh")
    
    if [[ -z "$cron_list" ]]; then
        info+="  Nenhum agendamento configurado.\n\n"
        info+="  Usa a opcao 11 para criar um agendamento.\n"
    else
        info+="  AGENDAMENTOS ATIVOS:\n"
        info+="  ----------------------------------------\n"
        local i=1
        while IFS= read -r linha; do
            # Parse cron format: min hora dia mes diasemana comando
            local minuto=$(echo "$linha" | awk '{print $1}')
            local hora=$(echo "$linha" | awk '{print $2}')
            local dia=$(echo "$linha" | awk '{print $3}')
            local mes=$(echo "$linha" | awk '{print $4}')
            local diasemana=$(echo "$linha" | awk '{print $5}')
            
            # Interpretar o agendamento
            local descricao=""
            
            # Verifica se é de X em X horas
            if [[ "$hora" == *"/"* ]]; then
                local intervalo=$(echo "$hora" | cut -d'/' -f2)
                descricao="A cada ${intervalo} horas"
            # Verifica se é diário
            elif [[ "$dia" == "*" ]] && [[ "$diasemana" == "*" ]]; then
                descricao="Diariamente as ${hora}:${minuto}"
            # Verifica se é semanal
            elif [[ "$diasemana" != "*" ]]; then
                local dia_nome=""
                case $diasemana in
                    0) dia_nome="Domingo" ;;
                    1) dia_nome="Segunda" ;;
                    2) dia_nome="Terca" ;;
                    3) dia_nome="Quarta" ;;
                    4) dia_nome="Quinta" ;;
                    5) dia_nome="Sexta" ;;
                    6) dia_nome="Sabado" ;;
                esac
                descricao="${dia_nome}s as ${hora}:${minuto}"
            # Verifica se é mensal
            elif [[ "$dia" != "*" ]]; then
                descricao="Dia ${dia} de cada mes as ${hora}:${minuto}"
            else
                descricao="Personalizado: ${minuto} ${hora} ${dia} ${mes} ${diasemana}"
            fi
            
            info+="  ${i}. ${descricao}\n"
            info+="     Cron: ${minuto} ${hora} ${dia} ${mes} ${diasemana}\n\n"
            i=$((i + 1))
        done <<< "$cron_list"
    fi
    
    # Proximo backup estimado
    local proximo_backup=$(crontab -l 2>/dev/null | grep "backup-auto.sh" | head -1)
    if [[ -n "$proximo_backup" ]]; then
        info+="  ----------------------------------------\n"
        info+="  Usa 'systemctl status crond' para verificar\n"
        info+="  se o servico cron esta ativo.\n"
    fi
    
    dialog --title " Agendamentos de Backup " --msgbox "$info" 22 60
}

criar_agendamento() {
    # Menu de escolha do tipo de agendamento
    dialog --title " Novo Agendamento " \
        --menu "\nEscolhe o tipo de agendamento:" 15 55 5 \
        1 "Diario (todos os dias)" \
        2 "Semanal (escolher dia)" \
        3 "De X em X horas" \
        4 "Mensal (escolher dia do mes)" \
        5 "Cancelar" \
        2>"$TEMP_FILE"
    
    [[ $? -ne 0 ]] && return
    local tipo=$(cat "$TEMP_FILE")
    
    case $tipo in
        1) criar_agendamento_diario ;;
        2) criar_agendamento_semanal ;;
        3) criar_agendamento_horas ;;
        4) criar_agendamento_mensal ;;
        5) return ;;
    esac
}

criar_agendamento_diario() {
    # Escolher hora
    dialog --title " Backup Diario " \
        --inputbox "\nA que horas fazer o backup?\n(formato 24h, ex: 03 para 3h, 14 para 14h)" 10 50 "03" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return
    
    local hora=$(cat "$TEMP_FILE")
    
    # Validar hora
    if ! [[ "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
        dialog --title " Erro " --msgbox "\nHora invalida! Use 0-23." 7 35
        return
    fi
    
    # Escolher minuto
    dialog --title " Backup Diario " \
        --inputbox "\nEm que minuto?\n(0-59, recomendado: 0)" 9 40 "0" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return
    
    local minuto=$(cat "$TEMP_FILE")
    
    # Validar minuto
    if ! [[ "$minuto" =~ ^[0-9]+$ ]] || [ "$minuto" -lt 0 ] || [ "$minuto" -gt 59 ]; then
        dialog --title " Erro " --msgbox "\nMinuto invalido! Use 0-59." 7 35
        return
    fi
    
    # Confirmar
    dialog --title " Confirmar Agendamento " --yesno \
        "\nCriar backup DIARIO?\n\nHora: ${hora}:$(printf "%02d" $minuto)\n\nIsso significa que o backup sera feito\ntodos os dias a essa hora." 12 50
    [[ $? -ne 0 ]] && return
    
    # Adicionar ao cron
    local nova_linha="${minuto} ${hora} * * * /usr/local/sbin/backup-auto.sh"
    adicionar_cron "$nova_linha"
    
    dialog --title " Sucesso " --msgbox \
        "\nAgendamento criado!\n\nBackup diario as ${hora}:$(printf "%02d" $minuto)" 9 45
}

criar_agendamento_semanal() {
    # Escolher dia da semana
    dialog --title " Backup Semanal " \
        --menu "\nEm que dia da semana?" 15 45 7 \
        0 "Domingo" \
        1 "Segunda-feira" \
        2 "Terca-feira" \
        3 "Quarta-feira" \
        4 "Quinta-feira" \
        5 "Sexta-feira" \
        6 "Sabado" \
        2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return
    
    local diasemana=$(cat "$TEMP_FILE")
    local dia_nome=""
    case $diasemana in
        0) dia_nome="Domingo" ;;
        1) dia_nome="Segunda-feira" ;;
        2) dia_nome="Terca-feira" ;;
        3) dia_nome="Quarta-feira" ;;
        4) dia_nome="Quinta-feira" ;;
        5) dia_nome="Sexta-feira" ;;
        6) dia_nome="Sabado" ;;
    esac
    
    # Escolher hora
    dialog --title " Backup Semanal " \
        --inputbox "\nA que horas?\n(formato 24h, ex: 03)" 9 40 "03" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return
    
    local hora=$(cat "$TEMP_FILE")
    
    if ! [[ "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
        dialog --title " Erro " --msgbox "\nHora invalida!" 7 35
        return
    fi
    
    # Escolher minuto
    dialog --title " Backup Semanal " \
        --inputbox "\nEm que minuto?\n(0-59)" 8 35 "0" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return
    
    local minuto=$(cat "$TEMP_FILE")
    
    if ! [[ "$minuto" =~ ^[0-9]+$ ]] || [ "$minuto" -lt 0 ] || [ "$minuto" -gt 59 ]; then
        dialog --title " Erro " --msgbox "\nMinuto invalido!" 7 35
        return
    fi
    
    # Confirmar
    dialog --title " Confirmar Agendamento " --yesno \
        "\nCriar backup SEMANAL?\n\nDia: ${dia_nome}\nHora: ${hora}:$(printf "%02d" $minuto)" 10 45
    [[ $? -ne 0 ]] && return
    
    # Adicionar ao cron
    local nova_linha="${minuto} ${hora} * * ${diasemana} /usr/local/sbin/backup-auto.sh"
    adicionar_cron "$nova_linha"
    
    dialog --title " Sucesso " --msgbox \
        "\nAgendamento criado!\n\nBackup todas as ${dia_nome}s\nas ${hora}:$(printf "%02d" $minuto)" 10 45
}

criar_agendamento_horas() {
    # Escolher intervalo
    dialog --title " Backup Periodico " \
        --menu "\nDe quantas em quantas horas?" 14 45 6 \
        1 "A cada 1 hora" \
        2 "A cada 2 horas" \
        3 "A cada 3 horas" \
        4 "A cada 4 horas" \
        6 "A cada 6 horas" \
        12 "A cada 12 horas" \
        2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return
    
    local intervalo=$(cat "$TEMP_FILE")
    
    # Aviso sobre backups frequentes
    if [ "$intervalo" -le 2 ]; then
        dialog --title " Atencao " --yesno \
            "\nBackups muito frequentes podem:\n\n- Ocupar muito espaco em disco\n- Sobrecarregar o servidor web\n- Gerar muitos logs\n\nRecomendacao: 4-6 horas no minimo.\n\nContinuar mesmo assim?" 15 50
        [[ $? -ne 0 ]] && return
    fi
    
    # Confirmar
    dialog --title " Confirmar Agendamento " --yesno \
        "\nCriar backup a cada ${intervalo} horas?\n\nO backup sera executado automaticamente\nde ${intervalo} em ${intervalo} horas." 11 50
    [[ $? -ne 0 ]] && return
    
    # Adicionar ao cron (executa no minuto 0 de cada X horas)
    local nova_linha="0 */${intervalo} * * * /usr/local/sbin/backup-auto.sh"
    adicionar_cron "$nova_linha"
    
    dialog --title " Sucesso " --msgbox \
        "\nAgendamento criado!\n\nBackup automatico a cada ${intervalo} horas" 9 45
}

criar_agendamento_mensal() {
    # Escolher dia do mes
    dialog --title " Backup Mensal " \
        --inputbox "\nEm que dia do mes?\n(1-28, recomendado ate 28 para garantir\nque existe em todos os meses)" 10 50 "1" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return
    
    local dia=$(cat "$TEMP_FILE")
    
    if ! [[ "$dia" =~ ^[0-9]+$ ]] || [ "$dia" -lt 1 ] || [ "$dia" -gt 31 ]; then
        dialog --title " Erro " --msgbox "\nDia invalido! Use 1-31." 7 35
        return
    fi
    
    # Aviso para dias > 28
    if [ "$dia" -gt 28 ]; then
        dialog --title " Aviso " --msgbox \
            "\nDia ${dia} pode nao existir em todos os meses!\n\nEx: Fevereiro so tem 28/29 dias.\n\nRecomendacao: Usa dia 1-28." 10 50
    fi
    
    # Escolher hora
    dialog --title " Backup Mensal " \
        --inputbox "\nA que horas?\n(formato 24h)" 8 35 "03" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return
    
    local hora=$(cat "$TEMP_FILE")
    
    if ! [[ "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
        dialog --title " Erro " --msgbox "\nHora invalida!" 7 35
        return
    fi
    
    # Escolher minuto
    dialog --title " Backup Mensal " \
        --inputbox "\nEm que minuto?" 7 35 "0" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return
    
    local minuto=$(cat "$TEMP_FILE")
    
    if ! [[ "$minuto" =~ ^[0-9]+$ ]] || [ "$minuto" -lt 0 ] || [ "$minuto" -gt 59 ]; then
        dialog --title " Erro " --msgbox "\nMinuto invalido!" 7 35
        return
    fi
    
    # Confirmar
    dialog --title " Confirmar Agendamento " --yesno \
        "\nCriar backup MENSAL?\n\nDia: ${dia} de cada mes\nHora: ${hora}:$(printf "%02d" $minuto)" 10 45
    [[ $? -ne 0 ]] && return
    
    # Adicionar ao cron
    local nova_linha="${minuto} ${hora} ${dia} * * /usr/local/sbin/backup-auto.sh"
    adicionar_cron "$nova_linha"
    
    dialog --title " Sucesso " --msgbox \
        "\nAgendamento criado!\n\nBackup dia ${dia} de cada mes\nas ${hora}:$(printf "%02d" $minuto)" 10 45
}

adicionar_cron() {
    local nova_linha="$1"
    
    # Obter cron atual
    local cron_tmp=$(mktemp)
    crontab -l > "$cron_tmp" 2>/dev/null || true
    
    # Verificar se ja existe agendamento identico
    if grep -Fq "$nova_linha" "$cron_tmp"; then
        dialog --title " Aviso " --msgbox \
            "\nEste agendamento ja existe!" 7 40
        rm -f "$cron_tmp"
        return 1
    fi
    
    # Adicionar nova linha
    echo "$nova_linha" >> "$cron_tmp"
    
    # Aplicar
    crontab "$cron_tmp"
    rm -f "$cron_tmp"
    
    # Garantir que crond esta ativo
    systemctl enable --now crond 2>/dev/null || true
    
    return 0
}

remover_agendamento() {
    # Listar agendamentos atuais
    local cron_list=$(crontab -l 2>/dev/null | grep "backup-auto.sh")
    
    if [[ -z "$cron_list" ]]; then
        dialog --title " Info " --msgbox \
            "\nNenhum agendamento para remover." 7 40
        return
    fi
    
    # Criar menu com agendamentos
    local menu_items=()
    local i=1
    local -a linhas_cron=()
    
    while IFS= read -r linha; do
        linhas_cron+=("$linha")
        
        # Parse para mostrar descrição amigável
        local minuto=$(echo "$linha" | awk '{print $1}')
        local hora=$(echo "$linha" | awk '{print $2}')
        local dia=$(echo "$linha" | awk '{print $3}')
        local mes=$(echo "$linha" | awk '{print $4}')
        local diasemana=$(echo "$linha" | awk '{print $5}')
        
        local descricao=""
        if [[ "$hora" == *"/"* ]]; then
            local intervalo=$(echo "$hora" | cut -d'/' -f2)
            descricao="A cada ${intervalo}h"
        elif [[ "$dia" == "*" ]] && [[ "$diasemana" == "*" ]]; then
            descricao="Diario ${hora}:${minuto}"
        elif [[ "$diasemana" != "*" ]]; then
            local dia_nome=""
            case $diasemana in
                0) dia_nome="Dom" ;;
                1) dia_nome="Seg" ;;
                2) dia_nome="Ter" ;;
                3) dia_nome="Qua" ;;
                4) dia_nome="Qui" ;;
                5) dia_nome="Sex" ;;
                6) dia_nome="Sab" ;;
            esac
            descricao="${dia_nome} ${hora}:${minuto}"
        elif [[ "$dia" != "*" ]]; then
            descricao="Mensal dia ${dia} ${hora}:${minuto}"
        else
            descricao="${minuto} ${hora} ${dia} ${mes} ${diasemana}"
        fi
        
        menu_items+=("$i" "$descricao")
        i=$((i + 1))
    done <<< "$cron_list"
    
    menu_items+=("0" "Cancelar")
    
    dialog --title " Remover Agendamento " \
        --menu "\nEscolhe o agendamento a remover:" 15 50 $((i-1)) \
        "${menu_items[@]}" 2>"$TEMP_FILE"
    
    [[ $? -ne 0 ]] && return
    local escolha=$(cat "$TEMP_FILE")
    
    if [[ "$escolha" == "0" ]]; then
        return
    fi
    
    # Obter a linha correspondente
    local linha_remover="${linhas_cron[$((escolha-1))]}"
    
    # Confirmar
    dialog --title " Confirmar Remocao " --yesno \
        "\nRemover este agendamento?\n\n${linha_remover}" 10 60
    [[ $? -ne 0 ]] && return
    
    # Remover do cron
    local cron_tmp=$(mktemp)
    crontab -l 2>/dev/null | grep -v "backup-auto.sh" > "$cron_tmp" || true
    
    # Re-adicionar todas menos a escolhida
    local j=1
    while IFS= read -r linha; do
        if [ "$j" -ne "$escolha" ]; then
            echo "$linha" >> "$cron_tmp"
        fi
        j=$((j + 1))
    done <<< "$cron_list"
    
    crontab "$cron_tmp"
    rm -f "$cron_tmp"
    
    dialog --title " Sucesso " --msgbox \
        "\nAgendamento removido!" 7 35
}

limpar_todos_agendamentos() {
    # Verificar se existem agendamentos
    local num_agendamentos=$(crontab -l 2>/dev/null | grep -c "backup-auto.sh" || echo 0)
    
    if [ "$num_agendamentos" -eq 0 ]; then
        dialog --title " Info " --msgbox \
            "\nNenhum agendamento configurado." 7 40
        return
    fi
    
    # Confirmar
    dialog --title " ATENCAO " --yesno \
        "\nRemover TODOS os ${num_agendamentos} agendamentos?\n\nIsso vai desativar os backups automaticos!" 10 50
    [[ $? -ne 0 ]] && return
    
    # Confirmacao extra
    dialog --title " Confirmacao Final " --inputbox \
        "\nPara confirmar, escreve LIMPAR:" 9 45 2>"$TEMP_FILE"
    local confirm=$(cat "$TEMP_FILE")
    
    if [[ "$confirm" != "LIMPAR" ]]; then
        dialog --title " Cancelado " --msgbox "\nOperacao cancelada." 7 30
        return
    fi
    
    # Remover todos os agendamentos de backup
    local cron_tmp=$(mktemp)
    crontab -l 2>/dev/null | grep -v "backup-auto.sh" > "$cron_tmp" || true
    crontab "$cron_tmp"
    rm -f "$cron_tmp"
    
    dialog --title " Concluido " --msgbox \
        "\nTodos os agendamentos foram removidos.\n\nBackups automaticos desativados." 9 45
}


# ============================================================
#  SUBMENU DE AGENDAMENTOS
# ============================================================

menu_agendamentos() {
    while true; do
        dialog --title " AGENDAMENTOS DE BACKUP " \
            --cancel-label "Voltar" \
            --menu "\nGestao de backups automaticos:\n" 16 55 6 \
            1 "Ver Agendamentos Ativos" \
            2 "Criar Novo Agendamento" \
            3 "Remover Agendamento" \
            4 "Limpar Todos os Agendamentos" \
            2>"$TEMP_FILE"
        
        if [[ $? -ne 0 ]]; then
            return
        fi
        
        escolha_sub=$(cat "$TEMP_FILE")
        
        case $escolha_sub in
            1) ver_agendamentos ;;
            2) criar_agendamento ;;
            3) remover_agendamento ;;
            4) limpar_todos_agendamentos ;;
        esac
    done
}


# ============================================================
#  MENU PRINCIPAL
# ============================================================

while true; do
    dialog --title " ATEC // GESTOR DE BACKUPS v2.0 " \
        --cancel-label "Sair" \
        --menu "\n  BackupServer -> WebServer (${WEBSERVER_IP})\n" 21 62 11 \
        1  "Ver Estado do Sistema" \
        2  "Fazer Backup AGORA" \
        3  "Listar Backups Disponiveis" \
        4  "Ver Conteudo do Backup" \
        5  "Restaurar Backup no WebServer" \
        6  "Apagar Site do WebServer" \
        7  "Testar Ligacao SSH" \
        8  "Ver Logs" \
        9  "Estado do RAID 10" \
        "\Z110\Zn" "Agendamentos" \
        "\Z111\Zn" "Reconfigurar" \
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
        "\Z110\Zn") menu_agendamentos ;;
        "\Z111\Zn") dialog --title " Reconfigurar " --editbox "$CONF_FILE" 12 55 2>"$TEMP_FILE"
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
