#!/bin/bash
# ============================================================
#  BACKUP SERVER - ATEC SYSTEM_CORE_2026
#  SCRIPT 2: GESTOR DE BACKUPS (Retro-Futurista Edition)
#  Executar: sudo bash /usr/local/sbin/backup-gestor.sh
# ============================================================

# --- CORES NEON CYBERPUNK ---
CYAN='\033[1;36m'        # Ciano brilhante
MAGENTA='\033[1;35m'     # Magenta brilhante
BLUE='\033[1;34m'        # Azul brilhante
GREEN='\033[1;32m'       # Verde brilhante
RED='\033[1;31m'         # Vermelho brilhante
YELLOW='\033[1;33m'      # Amarelo brilhante
WHITE='\033[1;37m'       # Branco brilhante
GRAY='\033[0;37m'        # Cinza
DIM='\033[2m'            # Texto escuro
BOLD='\033[1m'           # Negrito
BLINK='\033[5m'          # Piscante
NC='\033[0m'             # Reset

# --- VERIFICACOES ---
if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}[ERRO]${NC} Corre como root."
    echo -e "  ${CYAN}Usa:${NC} sudo bash $0"
    exit 1
fi

command -v dialog &>/dev/null || dnf -y install dialog

CONF_FILE="/etc/backup-atec.conf"
if [[ ! -f "$CONF_FILE" ]]; then
    clear
    echo -e "${RED}"
    echo "  ╔════════════════════════════════════════╗"
    echo "  ║           ERRO CRITICO                 ║"
    echo "  ╚════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  ${YELLOW}Ficheiro de configuracao nao encontrado!${NC}"
    echo ""
    echo -e "  ${CYAN}Corre primeiro:${NC}"
    echo -e "  ${WHITE}sudo bash Script_BackupServer_INSTALACAO.sh${NC}"
    echo ""
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
#  FUNCOES DE UI RETRO-FUTURISTA
# ============================================================

clear_screen() {
    clear
    # Simula scan de tela
    echo -e "${DIM}${CYAN}[SYSTEM] Initializing display...${NC}"
    sleep 0.1
}

print_header() {
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════════════════════════╗"
    echo "  ║                                                              ║"
    echo "  ║     █████╗ ████████╗███████╗ ██████╗                        ║"
    echo "  ║    ██╔══██╗╚══██╔══╝██╔════╝██╔════╝                        ║"
    echo "  ║    ███████║   ██║   █████╗  ██║                             ║"
    echo "  ║    ██╔══██║   ██║   ██╔══╝  ██║                             ║"
    echo "  ║    ██║  ██║   ██║   ███████╗╚██████╗                        ║"
    echo "  ║    ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝                        ║"
    echo "  ║                                                              ║"
    echo -e "  ║              ${MAGENTA}ACADEMIA_DE_FORMAÇÃO // 2026${CYAN}                 ║"
    echo "  ║                                                              ║"
    echo "  ╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "${MAGENTA}  ══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  // BACKUP_MANAGEMENT_SYSTEM v2.0${NC}"
    echo -e "${MAGENTA}  ══════════════════════════════════════════════════════════════${NC}"
    echo ""
}

print_line() {
    echo -e "${CYAN}  ┌────────────────────────────────────────────────────────────┐${NC}"
}

print_line_end() {
    echo -e "${CYAN}  └────────────────────────────────────────────────────────────┘${NC}"
}

print_separator() {
    echo -e "${MAGENTA}  ══════════════════════════════════════════════════════════════${NC}"
}

pause_prompt() {
    echo ""
    echo -e "${CYAN}  ┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC}  ${YELLOW}[ENTER]${NC} ${GRAY}Pressiona ENTER para continuar...${NC}              ${CYAN}│${NC}"
    echo -e "${CYAN}  └────────────────────────────────────────────────────────────┘${NC}"
    read -r
}

show_loading() {
    local msg="$1"
    echo -e "${CYAN}  [${YELLOW}●${CYAN}]${NC} ${msg}"
}

show_success() {
    local msg="$1"
    echo -e "${CYAN}  [${GREEN}✓${CYAN}]${NC} ${msg}"
}

show_error() {
    local msg="$1"
    echo -e "${CYAN}  [${RED}✗${CYAN}]${NC} ${msg}"
}

show_info() {
    local msg="$1"
    echo -e "${CYAN}  [${BLUE}i${CYAN}]${NC} ${msg}"
}


# ============================================================
#  MENU PRINCIPAL RETRO
# ============================================================

menu_principal() {
    while true; do
        clear_screen
        print_header
        
        echo -e "${CYAN}  > ${WHITE}WebServer Target${CYAN}: ${MAGENTA}${WEBSERVER_USER}@${WEBSERVER_IP}${NC}"
        echo ""
        print_separator
        echo -e "${CYAN}  // MENU_PRINCIPAL${NC}"
        print_separator
        echo ""
        echo -e "  ${CYAN}[${MAGENTA}01${CYAN}]${NC} ${WHITE}►${NC} Ver Estado do Sistema"
        echo -e "  ${CYAN}[${MAGENTA}02${CYAN}]${NC} ${WHITE}►${NC} Fazer Backup ${GREEN}AGORA${NC}"
        echo -e "  ${CYAN}[${MAGENTA}03${CYAN}]${NC} ${WHITE}►${NC} Listar Backups Disponiveis"
        echo -e "  ${CYAN}[${MAGENTA}04${CYAN}]${NC} ${WHITE}►${NC} Ver Conteudo do Backup"
        echo -e "  ${CYAN}[${MAGENTA}05${CYAN}]${NC} ${WHITE}►${NC} Restaurar Backup no WebServer"
        echo -e "  ${CYAN}[${MAGENTA}06${CYAN}]${NC} ${WHITE}►${NC} ${RED}Apagar Site do WebServer${NC}"
        echo -e "  ${CYAN}[${MAGENTA}07${CYAN}]${NC} ${WHITE}►${NC} Testar Ligacao SSH"
        echo -e "  ${CYAN}[${MAGENTA}08${CYAN}]${NC} ${WHITE}►${NC} Ver Logs"
        echo -e "  ${CYAN}[${MAGENTA}09${CYAN}]${NC} ${WHITE}►${NC} Estado do RAID 10"
        echo ""
        echo -e "  ${CYAN}[${MAGENTA}10${CYAN}]${NC} ${WHITE}►${NC} ${YELLOW}Agendamentos Automaticos${NC}"
        echo ""
        echo -e "  ${CYAN}[${MAGENTA}11${CYAN}]${NC} ${WHITE}►${NC} Reconfigurar Sistema"
        echo -e "  ${CYAN}[${MAGENTA}00${CYAN}]${NC} ${WHITE}►${NC} ${RED}Sair${NC}"
        echo ""
        print_separator
        echo -e -n "${CYAN}  > ${WHITE}Escolha${CYAN}: ${MAGENTA}"
        read -r escolha
        echo -e "${NC}"
        
        case $escolha in
            1|01) mostrar_estado ;;
            2|02) fazer_backup ;;
            3|03) listar_backups ;;
            4|04) ver_conteudo ;;
            5|05) restaurar_backup ;;
            6|06) apagar_site_remoto ;;
            7|07) testar_ligacao ;;
            8|08) ver_logs ;;
            9|09) estado_raid ;;
            10) menu_agendamentos ;;
            11) reconfigurar ;;
            0|00) 
                clear_screen
                print_header
                echo -e "${CYAN}  [${GREEN}✓${CYAN}]${NC} Sistema encerrado."
                echo -e "${GRAY}  Ate breve, operador.${NC}"
                echo ""
                exit 0
                ;;
            *) 
                echo -e "${RED}  [ERRO]${NC} Opcao invalida!"
                sleep 1
                ;;
        esac
    done
}


# ============================================================
#  SUBMENU AGENDAMENTOS
# ============================================================

menu_agendamentos() {
    while true; do
        clear_screen
        print_header
        
        print_separator
        echo -e "${CYAN}  // AGENDAMENTOS_AUTOMATICOS${NC}"
        print_separator
        echo ""
        
        # Mostrar número de agendamentos ativos
        local num_agendamentos=$(crontab -l 2>/dev/null | grep -c "backup-auto.sh" || echo 0)
        echo -e "  ${CYAN}[${YELLOW}●${CYAN}]${NC} Agendamentos ativos: ${MAGENTA}${num_agendamentos}${NC}"
        echo ""
        
        echo -e "  ${CYAN}[${MAGENTA}01${CYAN}]${NC} ${WHITE}►${NC} Ver Agendamentos Ativos"
        echo -e "  ${CYAN}[${MAGENTA}02${CYAN}]${NC} ${WHITE}►${NC} ${GREEN}Criar Novo Agendamento${NC}"
        echo -e "  ${CYAN}[${MAGENTA}03${CYAN}]${NC} ${WHITE}►${NC} Remover Agendamento"
        echo -e "  ${CYAN}[${MAGENTA}04${CYAN}]${NC} ${WHITE}►${NC} ${RED}Limpar Todos os Agendamentos${NC}"
        echo -e "  ${CYAN}[${MAGENTA}00${CYAN}]${NC} ${WHITE}►${NC} Voltar"
        echo ""
        print_separator
        echo -e -n "${CYAN}  > ${WHITE}Escolha${CYAN}: ${MAGENTA}"
        read -r escolha_sub
        echo -e "${NC}"
        
        case $escolha_sub in
            1|01) ver_agendamentos ;;
            2|02) criar_agendamento ;;
            3|03) remover_agendamento ;;
            4|04) limpar_todos_agendamentos ;;
            0|00) return ;;
            *) 
                echo -e "${RED}  [ERRO]${NC} Opcao invalida!"
                sleep 1
                ;;
        esac
    done
}


# ============================================================
#  FUNCOES PRINCIPAIS
# ============================================================

mostrar_estado() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // ESTADO_DO_SISTEMA${NC}"
    print_separator
    echo ""
    
    show_loading "A analisar sistema..."
    sleep 0.3
    
    # Teste SSH
    if ssh -o BatchMode=yes -o ConnectTimeout=3 "${WEBSERVER_USER}@${WEBSERVER_IP}" "echo ok" &>/dev/null; then
        local ssh_status="${GREEN}ONLINE${NC}"
    else
        local ssh_status="${RED}OFFLINE${NC}"
    fi
    
    # Tamanho backup
    local backup_size="${GRAY}Sem backup${NC}"
    if [[ -d "$BACKUP_CURRENT" ]] && [[ -n "$(ls -A "$BACKUP_CURRENT" 2>/dev/null)" ]]; then
        backup_size="${GREEN}$(du -sh "$BACKUP_CURRENT" 2>/dev/null | awk '{print $1}')${NC}"
    fi
    
    # Versões incrementais
    local versoes=$(find "$BACKUP_WEB" -maxdepth 1 -name "changed_*" -type d 2>/dev/null | wc -l)
    
    # Último backup
    local ultimo="${GRAY}Nunca${NC}"
    local ultimo_log=$(ls -t "${LOG_DIR}"/backup_*.log 2>/dev/null | head -1)
    if [[ -n "$ultimo_log" ]]; then
        ultimo="${CYAN}$(stat -c '%y' "$ultimo_log" 2>/dev/null | cut -d'.' -f1)${NC}"
    fi
    
    # Disco
    local disco=$(df -h /backup 2>/dev/null | tail -1 | awk '{print $4 " livres de " $2}')
    
    # RAID
    local raid_status="${GRAY}N/A${NC}"
    if [[ -e /dev/md0 ]]; then
        local raid_state=$(mdadm --detail /dev/md0 2>/dev/null | grep "State :" | awk -F: '{print $2}' | xargs)
        if [[ "$raid_state" == *"clean"* ]]; then
            raid_status="${GREEN}${raid_state}${NC}"
        else
            raid_status="${YELLOW}${raid_state}${NC}"
        fi
    fi
    
    # Agendamentos
    local num_agendamentos=$(crontab -l 2>/dev/null | grep -c "backup-auto.sh" || echo 0)
    
    echo -e "${CYAN}  ┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC} ${YELLOW}WebServer${NC}      ${MAGENTA}${WEBSERVER_USER}@${WEBSERVER_IP}${NC}"
    echo -e "${CYAN}  │${NC} ${YELLOW}SSH Status${NC}     ${ssh_status}"
    echo -e "${CYAN}  │${NC}"
    echo -e "${CYAN}  │${NC} ${YELLOW}Backup Atual${NC}   ${backup_size}"
    echo -e "${CYAN}  │${NC} ${YELLOW}Versoes${NC}        ${MAGENTA}${versoes}${NC} incrementais"
    echo -e "${CYAN}  │${NC} ${YELLOW}Ultimo Backup${NC}  ${ultimo}"
    echo -e "${CYAN}  │${NC} ${YELLOW}Agendamentos${NC}   ${MAGENTA}${num_agendamentos}${NC} ativos"
    echo -e "${CYAN}  │${NC}"
    echo -e "${CYAN}  │${NC} ${YELLOW}Disco RAID${NC}     ${CYAN}${disco}${NC}"
    echo -e "${CYAN}  │${NC} ${YELLOW}Estado RAID${NC}    ${raid_status}"
    echo -e "${CYAN}  └────────────────────────────────────────────────────────────┘${NC}"
    
    pause_prompt
}

fazer_backup() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // EXECUTAR_BACKUP${NC}"
    print_separator
    echo ""
    
    echo -e "${CYAN}  ┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC} ${YELLOW}Origem${NC}:  ${MAGENTA}${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/${NC}"
    echo -e "${CYAN}  │${NC} ${YELLOW}Destino${NC}: ${CYAN}${BACKUP_CURRENT}/${NC}"
    echo -e "${CYAN}  └────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e -n "${YELLOW}  Confirmar operacao?${NC} ${GRAY}[s/N]${NC}: "
    read -r confirm
    
    if [[ "$confirm" != "s" ]] && [[ "$confirm" != "S" ]]; then
        echo -e "${RED}  [CANCELADO]${NC} Operacao cancelada."
        sleep 1
        return
    fi
    
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local LOG_FILE="${LOG_DIR}/backup_${TIMESTAMP}.log"
    mkdir -p "$BACKUP_CURRENT"
    
    echo ""
    show_loading "A iniciar backup..."
    echo "=== BACKUP MANUAL: ${TIMESTAMP} ===" > "$LOG_FILE"
    
    show_loading "A ligar ao WebServer..."
    sleep 0.5
    
    show_loading "A copiar ficheiros (rsync)..."
    rsync -avz --delete \
        --backup --backup-dir="${BACKUP_WEB}/changed_${TIMESTAMP}" \
        "${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/" \
        "${BACKUP_CURRENT}/" >> "$LOG_FILE" 2>&1
    RESULT=$?
    
    echo ""
    if [ $RESULT -eq 0 ]; then
        echo "[OK] Backup concluido: ${TIMESTAMP}" >> "$LOG_FILE"
        show_success "Backup concluido com sucesso!"
        
        local total_files=$(find "$BACKUP_CURRENT" -type f 2>/dev/null | wc -l)
        local total_size=$(du -sh "$BACKUP_CURRENT" 2>/dev/null | awk '{print $1}')
        
        echo ""
        echo -e "${CYAN}  ┌────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}  │${NC} ${YELLOW}Ficheiros${NC}: ${MAGENTA}${total_files}${NC}"
        echo -e "${CYAN}  │${NC} ${YELLOW}Tamanho${NC}:   ${MAGENTA}${total_size}${NC}"
        echo -e "${CYAN}  │${NC} ${YELLOW}Log${NC}:       ${CYAN}${LOG_FILE}${NC}"
        echo -e "${CYAN}  └────────────────────────────────────────────────────────────┘${NC}"
    else
        echo "[ERRO] Falha (codigo: $RESULT)" >> "$LOG_FILE"
        show_error "Erro no backup! Verifica o log."
        echo -e "  ${CYAN}Log: ${LOG_FILE}${NC}"
    fi
    
    pause_prompt
}

listar_backups() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // BACKUPS_DISPONIVEIS${NC}"
    print_separator
    echo ""
    
    echo -e "${YELLOW}  BACKUP_ATUAL:${NC}"
    print_line
    
    if [[ -d "$BACKUP_CURRENT" ]] && [[ -n "$(ls -A "$BACKUP_CURRENT" 2>/dev/null)" ]]; then
        local size=$(du -sh "$BACKUP_CURRENT" 2>/dev/null | awk '{print $1}')
        local data=$(stat -c '%y' "$BACKUP_CURRENT" 2>/dev/null | cut -d'.' -f1)
        local nfiles=$(find "$BACKUP_CURRENT" -type f 2>/dev/null | wc -l)
        echo -e "${CYAN}  │${NC} ${MAGENTA}${size}${NC} ${GRAY}|${NC} ${CYAN}${nfiles}${NC} ficheiros ${GRAY}|${NC} ${data}"
    else
        echo -e "${CYAN}  │${NC} ${GRAY}(nenhum backup disponivel)${NC}"
    fi
    
    print_line_end
    echo ""
    
    echo -e "${YELLOW}  VERSOES_INCREMENTAIS:${NC}"
    print_line
    
    local i=1
    local encontrou=0
    for dir in $(ls -dt "${BACKUP_WEB}"/changed_* 2>/dev/null | head -10); do
        local nome=$(basename "$dir")
        local timestamp=${nome#changed_}
        local size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        local nf=$(find "$dir" -type f 2>/dev/null | wc -l)
        echo -e "${CYAN}  │${NC} ${MAGENTA}${i}.${NC} ${timestamp} ${GRAY}|${NC} ${CYAN}${size}${NC} ${GRAY}|${NC} ${nf} fich."
        i=$((i + 1))
        encontrou=1
    done
    
    if [[ $encontrou -eq 0 ]]; then
        echo -e "${CYAN}  │${NC} ${GRAY}(nenhuma versao incremental)${NC}"
    fi
    
    print_line_end
    
    pause_prompt
}

ver_conteudo() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // CONTEUDO_DO_BACKUP${NC}"
    print_separator
    echo ""
    
    if [[ ! -d "$BACKUP_CURRENT" ]] || [[ -z "$(ls -A "$BACKUP_CURRENT" 2>/dev/null)" ]]; then
        show_error "Nenhum backup disponivel."
        pause_prompt
        return
    fi
    
    local total=$(find "$BACKUP_CURRENT" -type f 2>/dev/null | wc -l)
    local size=$(du -sh "$BACKUP_CURRENT" 2>/dev/null | awk '{print $1}')
    
    echo -e "${CYAN}  ┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC} ${YELLOW}Tamanho${NC}: ${MAGENTA}${size}${NC} ${GRAY}|${NC} ${YELLOW}Ficheiros${NC}: ${MAGENTA}${total}${NC}"
    echo -e "${CYAN}  └────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    local count=0
    while IFS= read -r file && [ $count -lt 30 ]; do
        local rel=${file#$BACKUP_CURRENT/}
        local fsize=$(du -h "$file" 2>/dev/null | awk '{print $1}')
        echo -e "${CYAN}  ►${NC} ${rel} ${GRAY}(${fsize})${NC}"
        count=$((count + 1))
    done < <(find "$BACKUP_CURRENT" -type f 2>/dev/null | sort)
    
    if [[ $total -gt 30 ]]; then
        echo -e "${GRAY}  ... e mais $(($total - 30)) ficheiros${NC}"
    fi
    
    pause_prompt
}

restaurar_backup() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // ${YELLOW}RESTAURAR_BACKUP${NC}"
    print_separator
    echo ""
    
    if [[ ! -d "$BACKUP_CURRENT" ]] || [[ -z "$(ls -A "$BACKUP_CURRENT" 2>/dev/null)" ]]; then
        show_error "Nenhum backup para restaurar!"
        echo -e "  ${GRAY}Faz primeiro um backup (opcao 2)${NC}"
        pause_prompt
        return
    fi
    
    local size=$(du -sh "$BACKUP_CURRENT" 2>/dev/null | awk '{print $1}')
    local nfiles=$(find "$BACKUP_CURRENT" -type f 2>/dev/null | wc -l)
    
    echo -e "${RED}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}  ║  ${BLINK}ATENCAO${NC}${RED}: O conteudo atual do WebServer        ║${NC}"
    echo -e "${RED}  ║          sera SUBSTITUIDO pelo backup!              ║${NC}"
    echo -e "${RED}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}  ┌────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}  │${NC} ${YELLOW}Origem${NC}:  ${CYAN}${BACKUP_CURRENT}/${NC}"
    echo -e "${CYAN}  │${NC}          ${GRAY}(${size}, ${nfiles} ficheiros)${NC}"
    echo -e "${CYAN}  │${NC} ${YELLOW}Destino${NC}: ${MAGENTA}${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/${NC}"
    echo -e "${CYAN}  └────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    echo -e -n "${YELLOW}  Continuar?${NC} ${GRAY}[s/N]${NC}: "
    read -r confirm1
    
    if [[ "$confirm1" != "s" ]] && [[ "$confirm1" != "S" ]]; then
        echo -e "${RED}  [CANCELADO]${NC}"
        sleep 1
        return
    fi
    
    echo ""
    echo -e "${RED}  TEM A CERTEZA?${NC}"
    echo -e -n "${YELLOW}  Digite 'RESTAURAR' para confirmar${NC}: "
    read -r confirm2
    
    if [[ "$confirm2" != "RESTAURAR" ]]; then
        echo -e "${RED}  [CANCELADO]${NC}"
        sleep 1
        return
    fi
    
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local LOG_FILE="${LOG_DIR}/restore_${TIMESTAMP}.log"
    
    echo ""
    echo "=== RESTAURO: ${TIMESTAMP} ===" > "$LOG_FILE"
    
    show_loading "A ligar ao WebServer..."
    sleep 0.5
    
    show_loading "A enviar ficheiros..."
    rsync -avz --delete \
        "${BACKUP_CURRENT}/" \
        "${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/" >> "$LOG_FILE" 2>&1
    RESULT=$?
    
    show_loading "A corrigir permissoes e SELinux..."
    ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" \
        "chown -R apache:apache ${WEBROOT_REMOTE} && restorecon -Rv ${WEBROOT_REMOTE}" >> "$LOG_FILE" 2>&1
    
    show_loading "A reiniciar Apache..."
    ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "systemctl restart httpd" >> "$LOG_FILE" 2>&1
    
    echo ""
    if [ $RESULT -eq 0 ]; then
        show_success "Restauro concluido com sucesso!"
        echo ""
        echo -e "${CYAN}  ┌────────────────────────────────────────────────────────────┐${NC}"
        echo -e "${CYAN}  │${NC} ${YELLOW}Verifica${NC}: ${MAGENTA}http://${WEBSERVER_IP}${NC}"
        echo -e "${CYAN}  │${NC} ${YELLOW}Log${NC}:      ${CYAN}${LOG_FILE}${NC}"
        echo -e "${CYAN}  └────────────────────────────────────────────────────────────┘${NC}"
    else
        show_error "Erro no restauro!"
    fi
    
    pause_prompt
}

apagar_site_remoto() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${RED}  // ${BLINK}APAGAR_SITE_REMOTO${NC}"
    print_separator
    echo ""
    
    echo -e "${RED}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}  ║  ${BLINK}PERIGO${NC}${RED}: Isto vai APAGAR todo o conteudo       ║${NC}"
    echo -e "${RED}  ║          de ${WEBROOT_REMOTE}/ no WebServer!    ║${NC}"
    echo -e "${RED}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}  Target: ${MAGENTA}${WEBSERVER_IP}${NC}"
    echo ""
    echo -e -n "${YELLOW}  Continuar?${NC} ${GRAY}[s/N]${NC}: "
    read -r confirm1
    
    if [[ "$confirm1" != "s" ]] && [[ "$confirm1" != "S" ]]; then
        echo -e "${RED}  [CANCELADO]${NC}"
        sleep 1
        return
    fi
    
    # Verificar backup
    if [[ ! -d "$BACKUP_CURRENT" ]] || [[ -z "$(ls -A "$BACKUP_CURRENT" 2>/dev/null)" ]]; then
        echo ""
        echo -e "${RED}  [AVISO]${NC} ${YELLOW}NAO tens backup!${NC}"
        echo -e "  ${GRAY}Se apagares, nao podes recuperar.${NC}"
        echo ""
        echo -e -n "${YELLOW}  Fazer backup ANTES de apagar?${NC} ${GRAY}[S/n]${NC}: "
        read -r backup_confirm
        
        if [[ "$backup_confirm" != "n" ]] && [[ "$backup_confirm" != "N" ]]; then
            mkdir -p "$BACKUP_CURRENT"
            show_loading "A fazer backup de seguranca..."
            rsync -avz "${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/" "${BACKUP_CURRENT}/" 2>/dev/null
            show_success "Backup de seguranca concluido!"
            sleep 1
        fi
    fi
    
    echo ""
    echo -e "${RED}  Para confirmar, digite 'APAGAR':${NC} "
    echo -e -n "${YELLOW}  > ${NC}"
    read -r confirm_text
    
    if [[ "$confirm_text" != "APAGAR" ]]; then
        echo -e "${RED}  [CANCELADO]${NC}"
        sleep 1
        return
    fi
    
    local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    local LOG_FILE="${LOG_DIR}/delete_${TIMESTAMP}.log"
    
    echo ""
    show_loading "A apagar conteudo do WebServer..."
    ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "rm -rf ${WEBROOT_REMOTE}/*" >> "$LOG_FILE" 2>&1
    
    show_loading "A verificar..."
    local restantes=$(ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "find ${WEBROOT_REMOTE}/ -type f 2>/dev/null | wc -l")
    echo "Ficheiros restantes: ${restantes}" >> "$LOG_FILE"
    
    show_loading "A reiniciar Apache..."
    ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "systemctl restart httpd" >> "$LOG_FILE" 2>&1
    
    echo ""
    show_success "Site apagado!"
    echo -e "  ${GRAY}Para restaurar, usa a opcao 5${NC}"
    
    pause_prompt
}

testar_ligacao() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // TESTE_DE_LIGACAO${NC}"
    print_separator
    echo ""
    
    echo -e "${CYAN}  Target: ${MAGENTA}${WEBSERVER_USER}@${WEBSERVER_IP}${NC}"
    echo ""
    
    show_loading "A testar ligacao SSH..."
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${WEBSERVER_USER}@${WEBSERVER_IP}" "echo ok" &>/dev/null; then
        echo ""
        show_success "SSH: ONLINE"
        
        local remote_files=$(ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "find ${WEBROOT_REMOTE}/ -type f 2>/dev/null | wc -l")
        show_info "Website: ${MAGENTA}${remote_files}${NC} ficheiros em ${WEBROOT_REMOTE}/"
        
        local apache=$(ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "systemctl is-active httpd 2>/dev/null")
        if [[ "$apache" == "active" ]]; then
            show_success "Apache: ${GREEN}${apache}${NC}"
        else
            show_error "Apache: ${RED}${apache}${NC}"
        fi
        
        local disco=$(ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "df -h /var/www 2>/dev/null | tail -1 | awk '{print \$4}'" 2>/dev/null)
        show_info "Disco: ${CYAN}${disco}${NC} livres"
    else
        echo ""
        show_error "SSH: FALHA"
        echo ""
        echo -e "${YELLOW}  Causas possiveis:${NC}"
        echo -e "${GRAY}  • WebServer desligado${NC}"
        echo -e "${GRAY}  • Chave SSH nao configurada${NC}"
        echo -e "${GRAY}  • Firewall porta 22 bloqueada${NC}"
    fi
    
    pause_prompt
}

ver_logs() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // LOGS_DE_BACKUP${NC}"
    print_separator
    echo ""
    
    local logs=$(ls -t "${LOG_DIR}"/*.log 2>/dev/null | head -15)
    
    if [[ -z "$logs" ]]; then
        show_error "Nenhum log encontrado."
        pause_prompt
        return
    fi
    
    echo -e "${YELLOW}  LOGS_DISPONIVEIS:${NC}"
    print_line
    
    local i=1
    while IFS= read -r log; do
        local nome=$(basename "$log")
        local size=$(du -h "$log" 2>/dev/null | awk '{print $1}')
        local data=$(stat -c '%y' "$log" 2>/dev/null | cut -d' ' -f1)
        echo -e "${CYAN}  │${NC} ${MAGENTA}${i}.${NC} ${nome} ${GRAY}(${size}, ${data})${NC}"
        i=$((i + 1))
    done <<< "$logs"
    
    print_line_end
    echo ""
    echo -e -n "${YELLOW}  Numero do log para ver${NC} ${GRAY}(0 para voltar)${NC}: "
    read -r escolha_log
    
    if [[ "$escolha_log" =~ ^[0-9]+$ ]] && [ "$escolha_log" -gt 0 ] && [ "$escolha_log" -lt "$i" ]; then
        local log_file=$(echo "$logs" | sed -n "${escolha_log}p")
        clear_screen
        print_header
        echo -e "${CYAN}  // LOG: $(basename "$log_file")${NC}"
        print_separator
        echo ""
        cat "$log_file"
        echo ""
        pause_prompt
    fi
}

estado_raid() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // ESTADO_RAID_10${NC}"
    print_separator
    echo ""
    
    if [[ ! -e /dev/md0 ]]; then
        show_error "Nenhum RAID detetado."
        pause_prompt
        return
    fi
    
    mdadm --detail /dev/md0 2>&1 | while IFS= read -r line; do
        if [[ "$line" == *"State :"* ]] && [[ "$line" == *"clean"* ]]; then
            echo -e "${CYAN}  │${NC} $line ${GREEN}✓${NC}"
        elif [[ "$line" == *"Active Devices"* ]]; then
            echo -e "${CYAN}  │${NC} $line"
        elif [[ "$line" == *"/"* ]] && [[ "$line" == *"dev"* ]]; then
            echo -e "${CYAN}  │${NC}   ${MAGENTA}►${NC} $line"
        else
            echo -e "${GRAY}  │ $line${NC}"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}  /proc/mdstat:${NC}"
    print_line
    cat /proc/mdstat | while IFS= read -r line; do
        echo -e "${CYAN}  │${NC} ${GRAY}$line${NC}"
    done
    print_line_end
    
    pause_prompt
}

reconfigurar() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // RECONFIGURAR_SISTEMA${NC}"
    print_separator
    echo ""
    
    echo -e "${YELLOW}  Configuracao atual:${NC}"
    echo ""
    cat "$CONF_FILE" | while IFS= read -r line; do
        echo -e "${CYAN}  ►${NC} ${GRAY}$line${NC}"
    done
    echo ""
    echo -e "${GRAY}  Para editar, usa: nano /etc/backup-atec.conf${NC}"
    
    pause_prompt
}


# ============================================================
#  FUNCOES DE AGENDAMENTO
# ============================================================

ver_agendamentos() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // AGENDAMENTOS_ATIVOS${NC}"
    print_separator
    echo ""
    
    local cron_list=$(crontab -l 2>/dev/null | grep "backup-auto.sh")
    
    if [[ -z "$cron_list" ]]; then
        show_info "Nenhum agendamento configurado."
        echo ""
        echo -e "${GRAY}  Usa a opcao 2 para criar um agendamento.${NC}"
    else
        echo -e "${YELLOW}  AGENDAMENTOS:${NC}"
        print_line
        
        local i=1
        while IFS= read -r linha; do
            local minuto=$(echo "$linha" | awk '{print $1}')
            local hora=$(echo "$linha" | awk '{print $2}')
            local dia=$(echo "$linha" | awk '{print $3}')
            local mes=$(echo "$linha" | awk '{print $4}')
            local diasemana=$(echo "$linha" | awk '{print $5}')
            
            local descricao=""
            if [[ "$hora" == *"/"* ]]; then
                local intervalo=$(echo "$hora" | cut -d'/' -f2)
                descricao="A cada ${intervalo} horas"
            elif [[ "$dia" == "*" ]] && [[ "$diasemana" == "*" ]]; then
                descricao="Diariamente as ${hora}:$(printf "%02d" $minuto)"
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
                descricao="${dia_nome}s as ${hora}:$(printf "%02d" $minuto)"
            elif [[ "$dia" != "*" ]]; then
                descricao="Dia ${dia} de cada mes as ${hora}:$(printf "%02d" $minuto)"
            else
                descricao="Personalizado"
            fi
            
            echo -e "${CYAN}  │${NC} ${MAGENTA}${i}.${NC} ${WHITE}${descricao}${NC}"
            echo -e "${CYAN}  │${NC}    ${GRAY}Cron: ${minuto} ${hora} ${dia} ${mes} ${diasemana}${NC}"
            i=$((i + 1))
        done <<< "$cron_list"
        
        print_line_end
    fi
    
    pause_prompt
}

criar_agendamento() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // CRIAR_AGENDAMENTO${NC}"
    print_separator
    echo ""
    
    echo -e "  ${CYAN}[${MAGENTA}01${CYAN}]${NC} ${WHITE}►${NC} Diario (todos os dias)"
    echo -e "  ${CYAN}[${MAGENTA}02${CYAN}]${NC} ${WHITE}►${NC} Semanal (escolher dia)"
    echo -e "  ${CYAN}[${MAGENTA}03${CYAN}]${NC} ${WHITE}►${NC} De X em X horas"
    echo -e "  ${CYAN}[${MAGENTA}04${CYAN}]${NC} ${WHITE}►${NC} Mensal (escolher dia do mes)"
    echo -e "  ${CYAN}[${MAGENTA}00${CYAN}]${NC} ${WHITE}►${NC} Cancelar"
    echo ""
    echo -e -n "${CYAN}  > ${WHITE}Tipo${CYAN}: ${MAGENTA}"
    read -r tipo
    echo -e "${NC}"
    
    case $tipo in
        1|01) criar_agendamento_diario ;;
        2|02) criar_agendamento_semanal ;;
        3|03) criar_agendamento_horas ;;
        4|04) criar_agendamento_mensal ;;
        0|00) return ;;
        *) 
            show_error "Opcao invalida!"
            sleep 1
            ;;
    esac
}

criar_agendamento_diario() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // AGENDAMENTO_DIARIO${NC}"
    print_separator
    echo ""
    
    echo -e -n "${YELLOW}  Hora${NC} ${GRAY}(0-23)${NC}: "
    read -r hora
    
    if ! [[ "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
        show_error "Hora invalida!"
        sleep 1
        return
    fi
    
    echo -e -n "${YELLOW}  Minuto${NC} ${GRAY}(0-59)${NC}: "
    read -r minuto
    
    if ! [[ "$minuto" =~ ^[0-9]+$ ]] || [ "$minuto" -lt 0 ] || [ "$minuto" -gt 59 ]; then
        show_error "Minuto invalido!"
        sleep 1
        return
    fi
    
    echo ""
    echo -e "${CYAN}  Backup diario as ${MAGENTA}${hora}:$(printf "%02d" $minuto)${NC}"
    echo -e -n "${YELLOW}  Confirmar?${NC} ${GRAY}[s/N]${NC}: "
    read -r confirm
    
    if [[ "$confirm" != "s" ]] && [[ "$confirm" != "S" ]]; then
        show_error "Cancelado."
        sleep 1
        return
    fi
    
    local nova_linha="${minuto} ${hora} * * * /usr/local/sbin/backup-auto.sh"
    if adicionar_cron "$nova_linha"; then
        show_success "Agendamento criado!"
        sleep 1
    fi
}

criar_agendamento_semanal() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // AGENDAMENTO_SEMANAL${NC}"
    print_separator
    echo ""
    
    echo -e "  ${CYAN}[${MAGENTA}0${CYAN}]${NC} Domingo"
    echo -e "  ${CYAN}[${MAGENTA}1${CYAN}]${NC} Segunda-feira"
    echo -e "  ${CYAN}[${MAGENTA}2${CYAN}]${NC} Terca-feira"
    echo -e "  ${CYAN}[${MAGENTA}3${CYAN}]${NC} Quarta-feira"
    echo -e "  ${CYAN}[${MAGENTA}4${CYAN}]${NC} Quinta-feira"
    echo -e "  ${CYAN}[${MAGENTA}5${CYAN}]${NC} Sexta-feira"
    echo -e "  ${CYAN}[${MAGENTA}6${CYAN}]${NC} Sabado"
    echo ""
    echo -e -n "${YELLOW}  Dia da semana${NC}: "
    read -r diasemana
    
    local dia_nome=""
    case $diasemana in
        0) dia_nome="Domingo" ;;
        1) dia_nome="Segunda-feira" ;;
        2) dia_nome="Terca-feira" ;;
        3) dia_nome="Quarta-feira" ;;
        4) dia_nome="Quinta-feira" ;;
        5) dia_nome="Sexta-feira" ;;
        6) dia_nome="Sabado" ;;
        *)
            show_error "Dia invalido!"
            sleep 1
            return
            ;;
    esac
    
    echo -e -n "${YELLOW}  Hora${NC} ${GRAY}(0-23)${NC}: "
    read -r hora
    
    if ! [[ "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
        show_error "Hora invalida!"
        sleep 1
        return
    fi
    
    echo -e -n "${YELLOW}  Minuto${NC} ${GRAY}(0-59)${NC}: "
    read -r minuto
    
    if ! [[ "$minuto" =~ ^[0-9]+$ ]] || [ "$minuto" -lt 0 ] || [ "$minuto" -gt 59 ]; then
        show_error "Minuto invalido!"
        sleep 1
        return
    fi
    
    echo ""
    echo -e "${CYAN}  Backup todas as ${MAGENTA}${dia_nome}s${CYAN} as ${MAGENTA}${hora}:$(printf "%02d" $minuto)${NC}"
    echo -e -n "${YELLOW}  Confirmar?${NC} ${GRAY}[s/N]${NC}: "
    read -r confirm
    
    if [[ "$confirm" != "s" ]] && [[ "$confirm" != "S" ]]; then
        show_error "Cancelado."
        sleep 1
        return
    fi
    
    local nova_linha="${minuto} ${hora} * * ${diasemana} /usr/local/sbin/backup-auto.sh"
    if adicionar_cron "$nova_linha"; then
        show_success "Agendamento criado!"
        sleep 1
    fi
}

criar_agendamento_horas() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // AGENDAMENTO_PERIODICO${NC}"
    print_separator
    echo ""
    
    echo -e "  ${CYAN}[${MAGENTA}1${CYAN}]${NC}  A cada 1 hora"
    echo -e "  ${CYAN}[${MAGENTA}2${CYAN}]${NC}  A cada 2 horas"
    echo -e "  ${CYAN}[${MAGENTA}3${CYAN}]${NC}  A cada 3 horas"
    echo -e "  ${CYAN}[${MAGENTA}4${CYAN}]${NC}  A cada 4 horas"
    echo -e "  ${CYAN}[${MAGENTA}6${CYAN}]${NC}  A cada 6 horas"
    echo -e "  ${CYAN}[${MAGENTA}12${CYAN}]${NC} A cada 12 horas"
    echo ""
    echo -e -n "${YELLOW}  Intervalo (horas)${NC}: "
    read -r intervalo
    
    case $intervalo in
        1|2|3|4|6|12) ;;
        *)
            show_error "Intervalo invalido!"
            sleep 1
            return
            ;;
    esac
    
    if [ "$intervalo" -le 2 ]; then
        echo ""
        echo -e "${YELLOW}  [AVISO]${NC} Backups muito frequentes podem:"
        echo -e "${GRAY}  • Ocupar muito espaco em disco${NC}"
        echo -e "${GRAY}  • Sobrecarregar o servidor web${NC}"
        echo -e "${GRAY}  Recomendacao: 4-6 horas no minimo${NC}"
        echo ""
        echo -e -n "${YELLOW}  Continuar mesmo assim?${NC} ${GRAY}[s/N]${NC}: "
        read -r confirm_aviso
        
        if [[ "$confirm_aviso" != "s" ]] && [[ "$confirm_aviso" != "S" ]]; then
            show_error "Cancelado."
            sleep 1
            return
        fi
    fi
    
    echo ""
    echo -e "${CYAN}  Backup a cada ${MAGENTA}${intervalo}${CYAN} horas${NC}"
    echo -e -n "${YELLOW}  Confirmar?${NC} ${GRAY}[s/N]${NC}: "
    read -r confirm
    
    if [[ "$confirm" != "s" ]] && [[ "$confirm" != "S" ]]; then
        show_error "Cancelado."
        sleep 1
        return
    fi
    
    local nova_linha="0 */${intervalo} * * * /usr/local/sbin/backup-auto.sh"
    if adicionar_cron "$nova_linha"; then
        show_success "Agendamento criado!"
        sleep 1
    fi
}

criar_agendamento_mensal() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // AGENDAMENTO_MENSAL${NC}"
    print_separator
    echo ""
    
    echo -e -n "${YELLOW}  Dia do mes${NC} ${GRAY}(1-31)${NC}: "
    read -r dia
    
    if ! [[ "$dia" =~ ^[0-9]+$ ]] || [ "$dia" -lt 1 ] || [ "$dia" -gt 31 ]; then
        show_error "Dia invalido!"
        sleep 1
        return
    fi
    
    if [ "$dia" -gt 28 ]; then
        echo ""
        echo -e "${YELLOW}  [AVISO]${NC} Dia ${dia} pode nao existir em todos os meses!"
        echo -e "${GRAY}  Ex: Fevereiro so tem 28/29 dias${NC}"
        echo -e "${GRAY}  Recomendacao: Usa dia 1-28${NC}"
        echo ""
    fi
    
    echo -e -n "${YELLOW}  Hora${NC} ${GRAY}(0-23)${NC}: "
    read -r hora
    
    if ! [[ "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
        show_error "Hora invalida!"
        sleep 1
        return
    fi
    
    echo -e -n "${YELLOW}  Minuto${NC} ${GRAY}(0-59)${NC}: "
    read -r minuto
    
    if ! [[ "$minuto" =~ ^[0-9]+$ ]] || [ "$minuto" -lt 0 ] || [ "$minuto" -gt 59 ]; then
        show_error "Minuto invalido!"
        sleep 1
        return
    fi
    
    echo ""
    echo -e "${CYAN}  Backup dia ${MAGENTA}${dia}${CYAN} de cada mes as ${MAGENTA}${hora}:$(printf "%02d" $minuto)${NC}"
    echo -e -n "${YELLOW}  Confirmar?${NC} ${GRAY}[s/N]${NC}: "
    read -r confirm
    
    if [[ "$confirm" != "s" ]] && [[ "$confirm" != "S" ]]; then
        show_error "Cancelado."
        sleep 1
        return
    fi
    
    local nova_linha="${minuto} ${hora} ${dia} * * /usr/local/sbin/backup-auto.sh"
    if adicionar_cron "$nova_linha"; then
        show_success "Agendamento criado!"
        sleep 1
    fi
}

adicionar_cron() {
    local nova_linha="$1"
    
    local cron_tmp=$(mktemp)
    crontab -l > "$cron_tmp" 2>/dev/null || true
    
    if grep -Fq "$nova_linha" "$cron_tmp"; then
        show_error "Este agendamento ja existe!"
        rm -f "$cron_tmp"
        sleep 1
        return 1
    fi
    
    echo "$nova_linha" >> "$cron_tmp"
    crontab "$cron_tmp"
    rm -f "$cron_tmp"
    
    systemctl enable --now crond 2>/dev/null || true
    
    return 0
}

remover_agendamento() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${CYAN}  // REMOVER_AGENDAMENTO${NC}"
    print_separator
    echo ""
    
    local cron_list=$(crontab -l 2>/dev/null | grep "backup-auto.sh")
    
    if [[ -z "$cron_list" ]]; then
        show_info "Nenhum agendamento para remover."
        pause_prompt
        return
    fi
    
    declare -a linhas_cron=()
    local i=1
    
    while IFS= read -r linha; do
        linhas_cron+=("$linha")
        
        local minuto=$(echo "$linha" | awk '{print $1}')
        local hora=$(echo "$linha" | awk '{print $2}')
        local dia=$(echo "$linha" | awk '{print $3}')
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
            descricao="${minuto} ${hora} ${dia}"
        fi
        
        echo -e "  ${CYAN}[${MAGENTA}${i}${CYAN}]${NC} ${WHITE}${descricao}${NC}"
        i=$((i + 1))
    done <<< "$cron_list"
    
    echo -e "  ${CYAN}[${MAGENTA}0${CYAN}]${NC} ${GRAY}Cancelar${NC}"
    echo ""
    echo -e -n "${CYAN}  > ${WHITE}Numero${CYAN}: ${MAGENTA}"
    read -r escolha
    echo -e "${NC}"
    
    if [[ "$escolha" == "0" ]]; then
        return
    fi
    
    if ! [[ "$escolha" =~ ^[0-9]+$ ]] || [ "$escolha" -lt 1 ] || [ "$escolha" -ge "$i" ]; then
        show_error "Escolha invalida!"
        sleep 1
        return
    fi
    
    local linha_remover="${linhas_cron[$((escolha-1))]}"
    
    echo -e "${YELLOW}  Remover:${NC} ${linha_remover}"
    echo -e -n "${YELLOW}  Confirmar?${NC} ${GRAY}[s/N]${NC}: "
    read -r confirm
    
    if [[ "$confirm" != "s" ]] && [[ "$confirm" != "S" ]]; then
        show_error "Cancelado."
        sleep 1
        return
    fi
    
    local cron_tmp=$(mktemp)
    crontab -l 2>/dev/null | grep -v "backup-auto.sh" > "$cron_tmp" || true
    
    local j=1
    while IFS= read -r linha; do
        if [ "$j" -ne "$escolha" ]; then
            echo "$linha" >> "$cron_tmp"
        fi
        j=$((j + 1))
    done <<< "$cron_list"
    
    crontab "$cron_tmp"
    rm -f "$cron_tmp"
    
    show_success "Agendamento removido!"
    sleep 1
}

limpar_todos_agendamentos() {
    clear_screen
    print_header
    
    print_separator
    echo -e "${RED}  // ${BLINK}LIMPAR_TODOS_AGENDAMENTOS${NC}"
    print_separator
    echo ""
    
    local num_agendamentos=$(crontab -l 2>/dev/null | grep -c "backup-auto.sh" || echo 0)
    
    if [ "$num_agendamentos" -eq 0 ]; then
        show_info "Nenhum agendamento configurado."
        pause_prompt
        return
    fi
    
    echo -e "${RED}  [ATENCAO]${NC} Remover ${YELLOW}TODOS${NC} os ${num_agendamentos} agendamentos?"
    echo -e "${GRAY}  Isso vai desativar os backups automaticos!${NC}"
    echo ""
    echo -e -n "${YELLOW}  Continuar?${NC} ${GRAY}[s/N]${NC}: "
    read -r confirm1
    
    if [[ "$confirm1" != "s" ]] && [[ "$confirm1" != "S" ]]; then
        show_error "Cancelado."
        sleep 1
        return
    fi
    
    echo ""
    echo -e "${RED}  Digite 'LIMPAR' para confirmar:${NC} "
    echo -e -n "${YELLOW}  > ${NC}"
    read -r confirm_text
    
    if [[ "$confirm_text" != "LIMPAR" ]]; then
        show_error "Cancelado."
        sleep 1
        return
    fi
    
    local cron_tmp=$(mktemp)
    crontab -l 2>/dev/null | grep -v "backup-auto.sh" > "$cron_tmp" || true
    crontab "$cron_tmp"
    rm -f "$cron_tmp"
    
    show_success "Todos os agendamentos foram removidos."
    echo -e "${GRAY}  Backups automaticos desativados.${NC}"
    sleep 2
}


# ============================================================
#  INICIO DO PROGRAMA
# ============================================================

menu_principal
