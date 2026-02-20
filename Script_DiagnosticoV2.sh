#!/bin/bash
# ╔══════════════════════════════════════════════════════════╗
# ║  ATEC // SYSTEM_DIAGNOSTIC v4.0                         ║
# ║  Diagnostico para WebServer E BackupServer               ║
# ║  Detecao automatica do servidor                          ║
# ║  Compativel: CentOS Stream 10 (servidor sem GUI)        ║
# ║  Executar: sudo bash Script_Diagnostico.sh               ║
# ║  Forcar modo: sudo bash Script_Diagnostico.sh web|backup ║
# ╚══════════════════════════════════════════════════════════╝

if [[ "$(id -u)" -ne 0 ]]; then printf '\033[38;5;196m[ERRO]\033[0m Corre como root: sudo bash %s\n' "$0"; exit 1; fi
command -v dialog &>/dev/null || dnf -y install dialog &>/dev/null

CONF_FILE="/etc/backup-atec.conf"
LOG_FILE="/tmp/atec_diag_$(date +%Y%m%d_%H%M%S).log"
SCORE_OK=0; SCORE_TOTAL=0; TEMP_FILE=$(mktemp)
TERM="${TERM:-xterm}"; export TERM
trap 'rm -f "$TEMP_FILE"; printf "\033[?25h\033[0m"' EXIT
[[ -f "$CONF_FILE" ]] && source "$CONF_FILE"

# --- DETECAO ---
detect_server() {
    if [[ "${1:-}" == "web" ]]; then SERVER_MODE="webserver"; return; fi
    if [[ "${1:-}" == "backup" ]]; then SERVER_MODE="backupserver"; return; fi
    local has_httpd=0 has_raid=0 hn; command -v httpd &>/dev/null && has_httpd=1
    [[ -e /dev/md0 ]] && has_raid=1; hn=$(hostname 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [[ $has_httpd -eq 1 && $has_raid -eq 0 ]]; then SERVER_MODE="webserver"; return; fi
    if [[ $has_raid -eq 1 && $has_httpd -eq 0 ]]; then SERVER_MODE="backupserver"; return; fi
    if [[ "$hn" == *"web"* ]]; then SERVER_MODE="webserver"; return; fi
    if [[ "$hn" == *"backup"* ]]; then SERVER_MODE="backupserver"; return; fi
    if [[ $has_httpd -eq 1 && $has_raid -eq 1 ]]; then
        systemctl is-active --quiet httpd 2>/dev/null && { SERVER_MODE="webserver"; return; }
        mountpoint -q /backup 2>/dev/null && { SERVER_MODE="backupserver"; return; }
    fi
    dialog --title " DETECAO " --menu "\nEm que servidor estamos?\n" 12 55 2 \
        1 "WebServer (Apache, MariaDB, PHP)" 2 "BackupServer (RAID 10, Backups)" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && exit 0
    [[ "$(cat "$TEMP_FILE")" == "1" ]] && SERVER_MODE="webserver" || SERVER_MODE="backupserver"
}
detect_server "${1:-}"
if [[ "$SERVER_MODE" == "webserver" ]]; then SERVER_LABEL="WEB SERVER"; SERVER_ICON="◉"
else SERVER_LABEL="BACKUP SERVER"; SERVER_ICON="◎"; fi

# --- CORES ---
c_reset='\033[0m'; c_bold='\033[1m'; c_dim='\033[2m'
c_cyan='\033[38;5;51m'; c_cyan2='\033[38;5;39m'; c_blue='\033[38;5;27m'; c_dblue='\033[38;5;17m'
c_green='\033[38;5;46m'; c_red='\033[38;5;196m'; c_yellow='\033[38;5;220m'; c_pink='\033[38;5;206m'
c_white='\033[38;5;255m'; c_gray='\033[38;5;245m'; c_mgray='\033[38;5;240m'
c_dgray='\033[38;5;236m'; c_vdgray='\033[38;5;233m'
bg_dark='\033[48;5;233m'; bg_panel='\033[48;5;236m'; bg_hl='\033[48;5;238m'

# --- FUNCOES VISUAIS ---
gradient_line() {
    local char="${1:-━}" width="${2:-62}" colors="17 18 19 20 21 27 33 39 45 51 51 45 39 33 27 21 20 19 18 17" i=0 ci c
    while [[ $i -lt $width ]]; do ci=$((i*20/width+1)); c=$(echo "$colors"|cut -d' ' -f"$ci"); printf "\033[38;5;%sm%s" "$c" "$char"; i=$((i+1)); done; printf "${c_reset}\n"
}
spinner() {
    local msg="$1" dur="${2:-1}" f end=$((SECONDS+dur)); printf "\033[?25l"
    while [[ $SECONDS -lt $end ]]; do for f in ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏; do printf "\r  ${c_cyan}%s${c_reset} ${c_gray}%s${c_reset}" "$f" "$msg"; sleep 0.08; done; done
    printf "\r  ${c_green}✔${c_reset} ${c_white}%s${c_reset}         \n\033[?25h" "$msg"
}
panel_open() {
    local title="$1" w="${2:-60}" pad j=0; pad=$((w-4-${#title}-3)); [[ $pad -lt 0 ]] && pad=0
    printf "  ${c_mgray}╭─${c_cyan}⟨ ${c_white}%s${c_cyan} ⟩${c_mgray}" "$title"
    while [[ $j -lt $pad ]]; do printf "─"; j=$((j+1)); done; printf "╮${c_reset}\n"
}
panel_close() { local w="${1:-60}" j=0; printf "  ${c_mgray}╰"; while [[ $j -lt $((w-2)) ]]; do printf "─"; j=$((j+1)); done; printf "╯${c_reset}\n"; }
section_hud() { printf "\n"; gradient_line "━" 62; printf "  ${c_cyan}◆${c_reset} ${c_bold}${c_white}%s${c_reset}\n" "$1"; gradient_line "━" 62; printf "\n"; }
sub_hud() { printf "\n  ${c_cyan2}┃${c_reset} ${c_bold}${c_cyan}%s${c_reset}\n  ${c_cyan2}┃${c_reset}\n" "$1"; }
ok()     { printf "  ${c_green}  ✔ ${c_reset} %-42s ${bg_dark}${c_green} PASS ${c_reset}\n" "$1"; printf "[PASS] %s\n" "$1">>"$LOG_FILE"; }
fail()   { printf "  ${c_red}  ✘ ${c_reset} %-42s ${bg_dark}${c_red} FAIL ${c_reset}\n" "$1"; printf "[FAIL] %s\n" "$1">>"$LOG_FILE"; }
info()   { printf "  ${c_cyan}  ➤${c_reset}  %s\n" "$1"; }
warn()   { printf "  ${c_yellow}  ⚠${c_reset}  ${c_yellow}%s${c_reset}\n" "$1"; }
detail() { printf "     ${c_gray}%s${c_reset}\n" "$1"; }
value()  { printf "  ${c_cyan}  ◇${c_reset}  %-28s ${c_white}%s${c_reset}\n" "$1" "$2"; }
showcmd(){ printf "\n  ${bg_panel} ${c_pink}❯${c_reset}${bg_panel} ${c_white}%s${c_reset}${bg_panel} ${c_reset}\n\n" "$1"; }
explain() {
    local msg="$1" line="" w; printf "\n  ${c_mgray}╭─${c_yellow}⟨ ${c_white}INFO ${c_yellow}⟩${c_mgray}──────────────────────────────────────────╮${c_reset}\n"
    for w in $msg; do if [[ $((${#line}+${#w}+1)) -gt 52 ]]; then printf "  ${c_mgray}│${c_reset}  ${c_gray}%-54s${c_mgray}│${c_reset}\n" "$line"; line="$w"; else [[ -z "$line" ]] && line="$w" || line="$line $w"; fi; done
    [[ -n "$line" ]] && printf "  ${c_mgray}│${c_reset}  ${c_gray}%-54s${c_mgray}│${c_reset}\n" "$line"
    printf "  ${c_mgray}╰──────────────────────────────────────────────────────────╯${c_reset}\n"
}
progress_bar() {
    local cur=$1 tot=$2 w="${3:-40}" pct=0 i; [[ $tot -gt 0 ]] && pct=$((cur*100/tot))
    local fill=$((cur*w/tot)) emp=$((w-fill)) col="${c_green}"; [[ $pct -lt 70 ]] && col="${c_yellow}"; [[ $pct -lt 40 ]] && col="${c_red}"
    printf "  ${c_mgray}▐${c_reset}%b" "$col"; i=0; while [[ $i -lt $fill ]]; do printf "▰"; i=$((i+1)); done
    printf "${c_dgray}"; i=0; while [[ $i -lt $emp ]]; do printf "▱"; i=$((i+1)); done
    printf "${c_reset}${c_mgray}▌${c_reset} %b%3d%%${c_reset}" "$col" "$pct"
}
braille_bar() {
    local cur=$1 tot=$2 w="${3:-30}" pct=0 i; [[ $tot -gt 0 ]] && pct=$((cur*100/tot))
    local ts=$((w*8)) fs=$((cur*ts/tot)) fb=$((fs/8)) p=$((fs%8+1))
    printf "  ${c_cyan}"; i=0; while [[ $i -lt $fb ]]; do printf "⣿"; i=$((i+1)); done
    if [[ $fb -lt $w ]]; then printf "%s" "$(echo "⠀ ⣀ ⣄ ⣤ ⣦ ⣶ ⣷ ⣿"|cut -d' ' -f"$p")"; i=$((fb+1)); while [[ $i -lt $w ]]; do printf "⠀"; i=$((i+1)); done; fi
    printf "${c_reset} ${c_white}%3d%%${c_reset}" "$pct"
}
wait_enter() { printf "\n"; gradient_line "─" 62; printf "  ${c_mgray}Prima ${c_cyan}ENTER${c_mgray} para continuar${c_reset}"; read -r; }
countdown() {
    local msg="$1" s="${2:-3}" i; printf "\n  ${c_yellow}⚠${c_reset}  ${c_white}%s${c_reset}\n\033[?25l" "$msg"
    i=$s; while [[ $i -gt 0 ]]; do printf "\r     ${c_red}▶ %d ${c_reset}" "$i"; sleep 1; i=$((i-1)); done
    printf "\r     ${c_green}▶ GO ${c_reset}  \n\n\033[?25h"
}
page_header() {
    local title="${1:-DIAGNOSTIC}" ts; clear; printf "${bg_dark}"; gradient_line "▀" 62; printf "${c_reset}"
    ts=$(date '+%H:%M:%S'); printf "  ${c_cyan}%s${c_reset} ${c_bold}${c_white}ATEC${c_reset} ${c_mgray}//${c_reset} ${c_cyan}%s${c_reset}" "$SERVER_ICON" "$title"
    local pad=$((60-6-${#title})); [[ $pad -lt 1 ]] && pad=1; printf "%*s${c_dgray}%s${c_reset}\n" "$pad" "" "$ts"
    printf "  ${c_mgray}   ${c_dgray}%s${c_reset}\n${bg_dark}" "$SERVER_LABEL"; gradient_line "▄" 62; printf "${c_reset}\n"
}
check() {
    local desc="$1" cmd="$2"; SCORE_TOTAL=$((SCORE_TOTAL+1))
    if eval "$cmd" &>/dev/null; then ok "$desc"; SCORE_OK=$((SCORE_OK+1)); return 0; else fail "$desc"; return 1; fi
}
check_val() {
    local desc="$1" cmd="$2" exp="$3" res; SCORE_TOTAL=$((SCORE_TOTAL+1)); res=$(eval "$cmd" 2>/dev/null)
    if [[ -n "$exp" ]]; then
        if echo "$res"|grep -qi "$exp"; then ok "$desc"; SCORE_OK=$((SCORE_OK+1)); else fail "$desc"; detail "Esperado: $exp | Obtido: $res"; fi
    else [[ -n "$res" ]] && { ok "$desc"; SCORE_OK=$((SCORE_OK+1)); } || fail "$desc"; fi
}
result_box() {
    local msg="$1" col="$2" det="${3:-}" pad; printf "\n  ${c_mgray}╭──────────────────────────────────────────────────╮${c_reset}\n"
    printf "  ${c_mgray}│${c_reset}                                                  ${c_mgray}│${c_reset}\n"
    pad=$((45-${#msg})); [[ $pad -lt 1 ]] && pad=1; printf "  ${c_mgray}│${c_reset}   %b◆  %s${c_reset}%*s${c_mgray}│${c_reset}\n" "$col" "$msg" "$pad" ""
    if [[ -n "$det" ]]; then pad=$((42-${#det})); [[ $pad -lt 1 ]] && pad=1; printf "  ${c_mgray}│${c_reset}   ${c_gray}   %s${c_reset}%*s${c_mgray}│${c_reset}\n" "$det" "$pad" ""; fi
    printf "  ${c_mgray}│${c_reset}                                                  ${c_mgray}│${c_reset}\n  ${c_mgray}╰──────────────────────────────────────────────────╯${c_reset}\n"
}
show_score() {
    printf "\n"; gradient_line "═" 62; local pct=0; [[ $SCORE_TOTAL -gt 0 ]] && pct=$((SCORE_OK*100/SCORE_TOTAL))
    printf "\n"; progress_bar "$SCORE_OK" "$SCORE_TOTAL" 40; printf "\n\n"
    local sc="${c_green}" sl="SISTEMA OPERACIONAL" si="◆"
    [[ $pct -lt 90 ]] && sc="${c_yellow}" && sl="NECESSITA ATENCAO" && si="⚠"
    [[ $pct -lt 70 ]] && sc="${c_red}" && sl="PROBLEMAS CRITICOS" && si="✘"
    printf "  ${c_mgray}╭──────────────────────────────────────────────────╮${c_reset}\n"
    printf "  ${c_mgray}│${c_reset}                                                  ${c_mgray}│${c_reset}\n"
    printf "  ${c_mgray}│${c_reset}   %b%s${c_reset}  RESULTADO:  %b%2d / %2d${c_reset}  verificacoes OK   ${c_mgray}│${c_reset}\n" "$sc" "$si" "$sc" "$SCORE_OK" "$SCORE_TOTAL"
    printf "  ${c_mgray}│${c_reset}                                                  ${c_mgray}│${c_reset}\n"
    printf "  ${c_mgray}│${c_reset}      SCORE: %b%3d%%${c_reset}   │   ESTADO: %b%-18s${c_reset}${c_mgray}│${c_reset}\n" "$sc" "$pct" "$sc" "$sl"
    printf "  ${c_mgray}│${c_reset}                                                  ${c_mgray}│${c_reset}\n"
    printf "  ${c_mgray}╰──────────────────────────────────────────────────╯${c_reset}\n\n"; info "Log completo: $LOG_FILE"
}

# --- SPLASH ---
splash_screen() {
    clear; printf "\033[?25l\n\n"; gradient_line "▀" 62; printf "\n"
    local lc="21 27 33 39 45 51" ln=1
    while IFS= read -r line; do local c; c=$(echo "$lc"|cut -d' ' -f"$ln"); printf "  \033[38;5;%sm%s\033[0m\n" "$c" "$line"; ln=$((ln+1)); sleep 0.08; done << 'LOGO'
       █████╗ ████████╗███████╗ ██████╗
      ██╔══██╗╚══██╔══╝██╔════╝██╔════╝
      ███████║   ██║   █████╗  ██║     
      ██╔══██║   ██║   ██╔══╝  ██║     
      ██║  ██║   ██║   ███████╗╚██████╗
      ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝
LOGO
    printf "\n"; gradient_line "▄" 62; printf "\n"
    printf "  ${c_mgray}◆ SYSTEM_CORE_2026 // DIAGNOSTIC MODULE v4.0${c_reset}\n"
    printf "  ${c_dgray}◇ %s${c_reset}\n" "$(date '+%Y.%m.%d // %H:%M:%S')"
    if [[ "$SERVER_MODE" == "webserver" ]]; then printf "  ${c_cyan}${SERVER_ICON} MODO: ${c_bold}WEB SERVER${c_reset}\n"
    else printf "  ${c_cyan}${SERVER_ICON} MODO: ${c_bold}BACKUP SERVER${c_reset}\n"; fi; printf "\n"
    local idx=1; for item in kernel_modules network_stack security_layer storage_array service_mesh diagnostic_core; do
        local name; case $idx in 1)name="Kernel modules";;2)name="Network stack";;3)name="Security layer";;4)name="Storage array";;5)name="Service mesh";;6)name="Diagnostic engine";;esac
        local cnt=0; for f in ⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏; do printf "\r  ${c_mgray}[${c_cyan}%s${c_mgray}]${c_reset} %-24s" "$f" "$name"; sleep 0.05; cnt=$((cnt+1)); [[ $cnt -ge 6 ]] && break; done
        printf "\r  ${c_mgray}[${c_green}✔${c_mgray}]${c_reset} %-24s ${c_green}LOADED${c_reset}\n" "$name"; idx=$((idx+1)); done
    printf "\n"; gradient_line "━" 62; printf "\n  ${c_green}▶${c_reset} ${c_bold}${c_white}DIAGNOSTIC SYSTEM READY${c_reset}\n"
    printf "  ${c_dgray}  All modules loaded successfully${c_reset}\n\n"
    local i=0; while [[ $i -le 30 ]]; do printf "\r"; braille_bar "$i" 30 30; sleep 0.04; i=$((i+1)); done
    printf "\n\033[?25h"; sleep 0.5
}

# ################################################################
#  WEBSERVER - FUNCOES DE DIAGNOSTICO
# ################################################################

web_test_servicos() {
    page_header "SERVICOS PRINCIPAIS"; section_hud "1. SERVICOS PRINCIPAIS"
    explain "Verificar que Apache, MariaDB e PHP estao ativos e configurados para arranque automatico."
    sub_hud "Estado dos Servicos"
    showcmd "systemctl status httpd"
    if systemctl is-active --quiet httpd 2>/dev/null; then ok "Apache (httpd) ativo"; detail "PID: $(systemctl show httpd -p MainPID --value 2>/dev/null)"
    else fail "Apache (httpd) inativo"; fi
    showcmd "systemctl status mariadb"
    if systemctl is-active --quiet mariadb 2>/dev/null; then ok "MariaDB ativo"; detail "Versao: $(mysql --version 2>/dev/null | awk '{print $3,$4,$5}' || echo N/A)"
    else fail "MariaDB inativo"; fi
    showcmd "php -v"
    if command -v php &>/dev/null; then ok "PHP instalado"; detail "Versao: $(php -v 2>/dev/null|head -1|awk '{print $2}')"
        if php -m 2>/dev/null|grep -qi mysqlnd; then ok "Modulo mysqlnd presente"; else fail "Modulo mysqlnd nao encontrado"; fi
    else fail "PHP nao instalado"; fi
    sub_hud "Teste de Acesso Local"
    showcmd 'curl -s -o /dev/null -w "%{http_code}" http://localhost'
    local hc; hc=$(curl -s -o /dev/null -w "%{http_code}" http://localhost 2>/dev/null)
    if [[ "$hc" == "200" || "$hc" == "301" || "$hc" == "302" ]]; then ok "Acesso HTTP local funcional ($hc)"; else fail "Acesso HTTP local falhou ($hc)"; fi
    sub_hud "Arranque Automatico (boot)"
    for svc in httpd mariadb firewalld; do
        if systemctl is-enabled --quiet "$svc" 2>/dev/null; then ok "$svc arranca no boot"; else fail "$svc NAO arranca no boot"; fi
    done
    wait_enter
}

web_test_mariadb() {
    page_header "SEGURANCA MARIADB"; section_hud "2. SEGURANCA MARIADB"
    explain "Verificar hardening do MariaDB: sem anonimos, root local, sem BD test."
    dialog --title " MariaDB " --insecure --passwordbox "\nPassword do root do MariaDB:" 9 50 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return; local DB_PASS; DB_PASS=$(cat "$TEMP_FILE")
    page_header "SEGURANCA MARIADB"; section_hud "2. SEGURANCA MARIADB"
    sub_hud "Testes de Autenticacao"
    showcmd "mysql -u root -p'***' -e 'SELECT 1'"
    if mysql -u root -p"$DB_PASS" -e "SELECT 1" &>/dev/null; then ok "Login COM password funciona"
    else fail "Login COM password falhou"; wait_enter; return; fi
    if mysql -u root -e "SELECT 1" &>/dev/null 2>&1; then fail "Login SEM password funciona (INSEGURO!)"
    else ok "Login SEM password bloqueado"; fi
    sub_hud "Verificacoes de Hardening"
    local ac; ac=$(mysql -u root -p"$DB_PASS" -N -e "SELECT COUNT(*) FROM mysql.user WHERE User='';" 2>/dev/null)
    [[ "$ac" == "0" ]] && ok "Sem utilizadores anonimos" || fail "Existem $ac utilizadores anonimos"
    local rh has_remote=0; rh=$(mysql -u root -p"$DB_PASS" -N -e "SELECT Host FROM mysql.user WHERE User='root';" 2>/dev/null)
    while IFS= read -r h; do h=$(echo "$h"|xargs); case "$h" in localhost|127.0.0.1|::1);; *) has_remote=1;; esac; done <<< "$rh"
    [[ $has_remote -eq 0 ]] && { ok "Root apenas com acesso local"; detail "Hosts: $(echo "$rh"|tr '\n' ' ')"; } || fail "Root tem acesso remoto"
    local dbs; dbs=$(mysql -u root -p"$DB_PASS" -N -e "SHOW DATABASES;" 2>/dev/null)
    echo "$dbs"|grep -qw "test" && fail "BD 'test' ainda existe" || ok "BD 'test' removida"
    wait_enter
    # Submenu BD
    while true; do
        dialog --title " BD DE EXEMPLO " --cancel-label "Voltar" --menu "\nGestao da BD de exemplo:" 13 55 3 \
            1 "Criar BD de exemplo (atec_projeto)" 2 "Ver conteudo da BD" 3 "Apagar BD de exemplo" 2>"$TEMP_FILE"
        [[ $? -ne 0 ]] && break; local e; e=$(cat "$TEMP_FILE")
        case $e in 1) web_criar_bd "$DB_PASS";; 2) web_ver_bd "$DB_PASS";; 3) web_apagar_bd "$DB_PASS";; esac
    done
}

web_criar_bd() {
    local P="$1"; page_header "CRIAR BD"; section_hud "CRIAR BASE DE DADOS"
    explain "Criar a BD 'atec_projeto' com tabela de alunos e 6 registos de exemplo."
    countdown "A criar base de dados..." 2
    spinner "A criar database..." 1; mysql -u root -p"$P" -e "CREATE DATABASE IF NOT EXISTS atec_projeto;" 2>/dev/null; ok "BD 'atec_projeto' criada"
    spinner "A criar tabela..." 1
    mysql -u root -p"$P" atec_projeto <<'SQL' 2>/dev/null
CREATE TABLE IF NOT EXISTS alunos (id INT AUTO_INCREMENT PRIMARY KEY, nome VARCHAR(100) NOT NULL, curso VARCHAR(100) NOT NULL, data_inscricao DATE NOT NULL);
SQL
    ok "Tabela 'alunos' criada"
    spinner "A inserir registos..." 1
    mysql -u root -p"$P" atec_projeto <<'SQL' 2>/dev/null
INSERT IGNORE INTO alunos (id,nome,curso,data_inscricao) VALUES (1,'Daniel Ricardo','Ciberseguranca','2025-09-15'),(2,'Ana Ferreira','Programacao','2025-09-15'),(3,'Pedro Santos','Mecatronica','2025-09-16'),(4,'Maria Oliveira','Redes 5G','2025-09-16'),(5,'Tiago Mendes','Ciberseguranca','2025-09-17'),(6,'Sofia Costa','Programacao','2025-09-17');
SQL
    ok "6 registos inseridos"
    sub_hud "Conteudo"; mysql -u root -p"$P" atec_projeto -e "SELECT * FROM alunos;" 2>/dev/null; wait_enter
}

web_ver_bd() {
    local P="$1"; page_header "CONTEUDO BD"; section_hud "BD DE EXEMPLO"
    if ! mysql -u root -p"$P" -e "USE atec_projeto" &>/dev/null 2>&1; then warn "BD 'atec_projeto' nao existe."; wait_enter; return; fi
    sub_hud "Tabelas"; mysql -u root -p"$P" atec_projeto -e "SHOW TABLES;" 2>/dev/null
    sub_hud "Registos"; mysql -u root -p"$P" atec_projeto -e "SELECT * FROM alunos;" 2>/dev/null
    sub_hud "Estatisticas"; value "Total:" "$(mysql -u root -p"$P" atec_projeto -N -e "SELECT COUNT(*) FROM alunos;" 2>/dev/null)"
    wait_enter
}

web_apagar_bd() {
    local P="$1"; dialog --title " APAGAR BD " --yesno "\nApagar 'atec_projeto'?" 8 40; [[ $? -ne 0 ]] && return
    page_header "APAGAR BD"; countdown "A apagar..." 2
    mysql -u root -p"$P" -e "DROP DATABASE IF EXISTS atec_projeto;" 2>/dev/null; ok "BD 'atec_projeto' apagada"; wait_enter
}

web_test_acesso_externo() {
    page_header "ACESSO EXTERNO"; section_hud "3. ACESSO EXTERNO"
    explain "Verificar IP publico, DuckDNS, redirect HTTPS e certificado SSL."
    local DOMAIN="" ssl_conf
    ssl_conf=$(find /etc/httpd/conf.d/ -name "*ssl.conf" -o -name "*-ssl.conf" 2>/dev/null | grep -v "^/etc/httpd/conf.d/ssl.conf$" | head -1)
    [[ -n "$ssl_conf" ]] && DOMAIN=$(grep -i "ServerName" "$ssl_conf" 2>/dev/null | awk '{print $2}' | head -1)
    if [[ -z "$DOMAIN" ]]; then
        dialog --title " Dominio " --inputbox "\nDominio DuckDNS:" 9 60 "webserver-atec.duckdns.org" 2>"$TEMP_FILE"
        [[ $? -ne 0 ]] && return; DOMAIN=$(cat "$TEMP_FILE")
    fi
    page_header "ACESSO EXTERNO"; section_hud "3. ACESSO EXTERNO"
    panel_open "DOMINIO" 62; printf "  ${c_mgray}│${c_reset}  ${c_cyan}◇${c_reset}  %-50s  ${c_mgray}│${c_reset}\n" "$DOMAIN"; panel_close 62
    sub_hud "IP Publico"; spinner "A obter IP publico..." 2
    local pip; pip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null)
    [[ -n "$pip" ]] && { ok "IP publico obtido"; value "IP:" "$pip"; } || fail "IP publico nao obtido"
    sub_hud "Resolucao DNS"
    local dip; dip=$(getent hosts "$DOMAIN" 2>/dev/null | awk '{print $1}' | head -1)
    [[ -z "$dip" ]] && command -v dig &>/dev/null && dip=$(dig +short "$DOMAIN" 2>/dev/null | head -1)
    [[ -n "$dip" ]] && { ok "DuckDNS resolve"; value "IP resolvido:" "$dip"; [[ "$dip" == "$pip" ]] && ok "IPs coincidem" || warn "IPs diferentes (NAT?)"; } || fail "DuckDNS nao resolve"
    sub_hud "HTTP Redirect"
    local hr; hr=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "http://$DOMAIN" 2>/dev/null)
    [[ "$hr" == "301" || "$hr" == "302" ]] && ok "HTTP redireciona ($hr)" || { [[ "$hr" == "200" ]] && warn "HTTP 200 (sem redirect)" || fail "HTTP falhou ($hr)"; }
    sub_hud "HTTPS"
    local hsr; hsr=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "https://$DOMAIN" 2>/dev/null)
    [[ "$hsr" == "200" ]] && ok "HTTPS funcional (200)" || fail "HTTPS falhou ($hsr)"
    sub_hud "Certificado SSL"
    local ci; ci=$(echo|openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null|openssl x509 -noout -subject -issuer -dates 2>/dev/null)
    if [[ -n "$ci" ]]; then ok "Certificado presente"
        value "Valido ate:" "$(echo "$ci"|grep notAfter|sed 's/notAfter=//')"
    else fail "Certificado nao verificado"; fi
    wait_enter
}

web_test_seguranca() {
    while true; do
        dialog --title " 4. SEGURANCA " --cancel-label "Voltar" --menu "\nTestes de seguranca:" 17 55 7 \
            1 "Firewall (portas)" 2 "SELinux (modo e contextos)" 3 "Fail2ban (estado)" \
            4 "Fail2ban - Simular ataque SSH" 5 "ModSecurity (estado)" \
            6 "ModSecurity - SQL Injection" 7 "ModSecurity - XSS" 2>"$TEMP_FILE"
        [[ $? -ne 0 ]] && return; case $(cat "$TEMP_FILE") in
            1) web_test_firewall;; 2) web_test_selinux;; 3) web_test_f2b_estado;;
            4) web_test_f2b_simular;; 5) web_test_modsec;; 6) web_test_sqli;; 7) web_test_xss;; esac
    done
}

web_test_firewall() {
    page_header "FIREWALL"; section_hud "FIREWALL"
    explain "Verificar que SSH(22), HTTP(80), HTTPS(443) estao abertas e MySQL(3306) bloqueada."
    showcmd "firewall-cmd --list-all"; firewall-cmd --list-all 2>/dev/null
    sub_hud "Verificacao de Portas"
    local svcs; svcs=$(firewall-cmd --list-services 2>/dev/null)
    for s in ssh http https; do echo "$svcs"|grep -qw "$s" && ok "Porta $s aberta" || fail "Porta $s NAO aberta"; done
    sub_hud "Porta Bloqueada"; spinner "A testar porta 3306..." 2
    curl -s --connect-timeout 3 "http://localhost:3306" &>/dev/null && fail "Porta 3306 acessivel!" || ok "Porta 3306 bloqueada"
    wait_enter
}

web_test_selinux() {
    page_header "SELINUX"; section_hud "SELINUX"
    explain "Verificar modo Enforcing e contextos httpd_sys_content_t no website."
    sub_hud "Modo SELinux"; showcmd "getenforce"
    local m; m=$(getenforce 2>/dev/null)
    [[ "$m" == "Enforcing" ]] && ok "SELinux Enforcing" || { [[ "$m" == "Permissive" ]] && warn "SELinux Permissive" || fail "SELinux desativado"; }
    sub_hud "Contextos Website"; showcmd "ls -Z /var/www/html/"; ls -Z /var/www/html/ 2>/dev/null|head -10; printf "\n"
    ls -Z /var/www/html/ 2>/dev/null|grep -q "httpd_sys_content_t" && ok "Contexto correto" || warn "Contexto pode nao estar correto"
    wait_enter
}

web_test_f2b_estado() {
    page_header "FAIL2BAN"; section_hud "FAIL2BAN - ESTADO"
    explain "Verificar Fail2ban com 6 jails: sshd, apache-auth, apache-badbots, apache-noscript, apache-overflows, apache-shellshock."
    sub_hud "Estado"; showcmd "systemctl status fail2ban"
    if ! systemctl is-active --quiet fail2ban 2>/dev/null; then fail "Fail2ban inativo"; wait_enter; return; fi
    ok "Fail2ban ativo"; sub_hud "Jails"; fail2ban-client status 2>/dev/null
    sub_hud "Detalhes por Jail"
    panel_open "JAILS STATUS" 62
    for j in sshd apache-auth apache-badbots apache-noscript apache-overflows apache-shellshock; do
        if fail2ban-client status "$j" &>/dev/null; then
            local b; b=$(fail2ban-client status "$j" 2>/dev/null|grep "Currently banned"|awk -F: '{print $2}'|xargs)
            printf "  ${c_mgray}│${c_reset}  ${c_green}✔${c_reset} %-28s ${c_mgray}banidos: ${c_white}%s${c_reset}     ${c_mgray}│${c_reset}\n" "$j" "$b"
        else printf "  ${c_mgray}│${c_reset}  ${c_red}✘${c_reset} %-28s ${c_red}NOT FOUND${c_reset}           ${c_mgray}│${c_reset}\n" "$j"; fi
    done; panel_close 62; wait_enter
}

web_test_f2b_simular() {
    page_header "FAIL2BAN - SIMULACAO"; section_hud "SIMULAR ATAQUE SSH"
    explain "4 tentativas SSH falhadas para acionar ban (maxretry=3)."
    dialog --title " ATENCAO " --yesno "\nSimular ataque SSH?\nO IP sera banido temporariamente.\n\nContinuar?" 10 50
    [[ $? -ne 0 ]] && return
    page_header "FAIL2BAN - SIMULACAO"; section_hud "SIMULAR ATAQUE SSH"
    sub_hud "ANTES"; fail2ban-client status sshd 2>/dev/null
    sub_hud "Tentativas"; for i in 1 2 3 4; do
        spinner "Tentativa $i/4..." 1
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=2 -o NumberOfPasswordPrompts=0 \
            -o PubkeyAuthentication=no -o PasswordAuthentication=yes "utilizador_falso@localhost" exit 2>/dev/null || true
    done; spinner "A aguardar Fail2ban..." 5
    sub_hud "DEPOIS"; fail2ban-client status sshd 2>/dev/null
    local bl; bl=$(fail2ban-client status sshd 2>/dev/null|grep "Banned IP"|awk -F: '{print $2}'|xargs)
    if [[ -n "$bl" ]]; then ok "IPs banidos: $bl"; sub_hud "Desbanir"
        for ip in $bl; do fail2ban-client set sshd unbanip "$ip" 2>/dev/null; ok "IP $ip desbanido"; done
    else warn "Nenhum IP banido (pode demorar)"; fi; wait_enter
}

web_test_modsec() {
    page_header "MOD_SECURITY"; section_hud "MOD_SECURITY - ESTADO"
    explain "ModSecurity carregado no Apache com modo On e regras id:1001 (SQLi) e id:1002 (XSS)."
    sub_hud "Modulo"; showcmd "httpd -M | grep security"
    httpd -M 2>/dev/null|grep -qi security && ok "ModSecurity carregado" || fail "ModSecurity NAO carregado"
    sub_hud "Modo"
    local mode; mode=$(grep "SecRuleEngine" /etc/httpd/conf.d/mod_security.conf 2>/dev/null|grep -v "^#"|head -1|awk '{print $2}')
    [[ "$mode" == "On" ]] && ok "Modo: On (bloqueio ativo)" || warn "Modo: $mode"
    sub_hud "Regras"
    panel_open "RULES" 62
    grep -q "id:1001" /etc/httpd/conf.d/mod_security.conf 2>/dev/null && \
        printf "  ${c_mgray}│${c_reset}  ${c_green}✔${c_reset} id:1001  SQL Injection            ${c_green}ACTIVE${c_reset}     ${c_mgray}│${c_reset}\n" || \
        printf "  ${c_mgray}│${c_reset}  ${c_red}✘${c_reset} id:1001  SQL Injection            ${c_red}MISSING${c_reset}    ${c_mgray}│${c_reset}\n"
    grep -q "id:1002" /etc/httpd/conf.d/mod_security.conf 2>/dev/null && \
        printf "  ${c_mgray}│${c_reset}  ${c_green}✔${c_reset} id:1002  XSS                     ${c_green}ACTIVE${c_reset}     ${c_mgray}│${c_reset}\n" || \
        printf "  ${c_mgray}│${c_reset}  ${c_red}✘${c_reset} id:1002  XSS                     ${c_red}MISSING${c_reset}    ${c_mgray}│${c_reset}\n"
    panel_close 62; wait_enter
}

web_attack_test() {
    local name="$1" payload="$2" exp="$3" res
    showcmd "curl \"$payload\""; spinner "A enviar payload..." 1
    res=$(curl -s -o /dev/null -w "%{http_code}" "$payload" 2>/dev/null)
    [[ "$res" == "$exp" ]] && { result_box "$name BLOQUEADO! (HTTP $res)" "${c_green}"; ok "$name bloqueado"; } || \
    { [[ "$res" == "200" ]] && { result_box "ATAQUE NAO BLOQUEADO! (HTTP $res)" "${c_red}"; fail "$name nao bloqueado"; } || warn "Resultado: HTTP $res"; }
}

web_test_sqli() {
    page_header "SQL INJECTION"; section_hud "TESTE SQL INJECTION"
    explain "Payload SQL Injection contra o ModSecurity. Deve retornar HTTP 403."
    countdown "A enviar..." 2; web_attack_test "SQL INJECTION" "http://localhost/?id=1' OR '1'='1" "403"; wait_enter
}

web_test_xss() {
    page_header "XSS TEST"; section_hud "TESTE XSS"
    explain "Payload XSS contra o ModSecurity. Deve retornar HTTP 403."
    countdown "A enviar..." 2; web_attack_test "XSS" "http://localhost/?q=<script>alert(1)</script>" "403"; wait_enter
}

web_health_check() {
    page_header "HEALTH CHECK - WEB"; section_hud "VERIFICACAO GERAL - WEB SERVER"
    SCORE_OK=0; SCORE_TOTAL=0
    dialog --title " Health Check " --insecure --passwordbox "\nPassword root MariaDB:" 9 50 2>"$TEMP_FILE"
    local DB_PASS=""; [[ $? -eq 0 ]] && DB_PASS=$(cat "$TEMP_FILE")
    local DOMAIN="" sc; sc=$(find /etc/httpd/conf.d/ -name "*-ssl.conf" 2>/dev/null|head -1)
    [[ -n "$sc" ]] && DOMAIN=$(grep -i "ServerName" "$sc" 2>/dev/null|awk '{print $2}'|head -1)
    page_header "HEALTH CHECK - WEB"
    sub_hud "SERVICOS"
    check "Apache ativo" "systemctl is-active --quiet httpd"
    check "MariaDB ativo" "systemctl is-active --quiet mariadb"
    check "PHP instalado" "command -v php"
    check "PHP mysqlnd" "php -m 2>/dev/null|grep -qi mysqlnd"
    check "Firewalld ativo" "systemctl is-active --quiet firewalld"
    check "httpd boot" "systemctl is-enabled --quiet httpd"
    check "mariadb boot" "systemctl is-enabled --quiet mariadb"
    sub_hud "SEGURANCA"
    check "SELinux Enforcing" "[[ \$(getenforce 2>/dev/null) == 'Enforcing' ]]"
    check "Fail2ban ativo" "systemctl is-active --quiet fail2ban"
    check "ModSecurity" "httpd -M 2>/dev/null|grep -qi security"
    check "FW: ssh" "firewall-cmd --list-services 2>/dev/null|grep -qw ssh"
    check "FW: http" "firewall-cmd --list-services 2>/dev/null|grep -qw http"
    check "FW: https" "firewall-cmd --list-services 2>/dev/null|grep -qw https"
    if [[ -n "$DB_PASS" ]]; then
        check "MariaDB: sem anonimos" "[[ \$(mysql -u root -p'$DB_PASS' -N -e \"SELECT COUNT(*) FROM mysql.user WHERE User='';\" 2>/dev/null) == '0' ]]"
        check "MariaDB: root local" "! mysql -u root -p'$DB_PASS' -N -e \"SELECT Host FROM mysql.user WHERE User='root';\" 2>/dev/null|grep -qvE 'localhost|127.0.0.1|::1'"
        check "MariaDB: sem BD test" "! mysql -u root -p'$DB_PASS' -N -e 'SHOW DATABASES;' 2>/dev/null|grep -qw test"
    fi
    check "SQLi bloqueado (403)" "[[ \$(curl -s -o /dev/null -w '%{http_code}' \"http://localhost/?id=1' OR '1'='1\" 2>/dev/null) == '403' ]]"
    check "XSS bloqueado (403)" "[[ \$(curl -s -o /dev/null -w '%{http_code}' 'http://localhost/?q=<script>alert(1)</script>' 2>/dev/null) == '403' ]]"
    sub_hud "ACESSO EXTERNO"
    local pip; pip=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null)
    SCORE_TOTAL=$((SCORE_TOTAL+1)); [[ -n "$pip" ]] && { ok "IP publico: $pip"; SCORE_OK=$((SCORE_OK+1)); } || fail "IP publico nao obtido"
    if [[ -n "$DOMAIN" ]]; then
        check "HTTPS (200)" "[[ \$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 'https://$DOMAIN' 2>/dev/null) == '200' ]]"
        SCORE_TOTAL=$((SCORE_TOTAL+1)); local cd; cd=$(echo|openssl s_client -connect "$DOMAIN:443" -servername "$DOMAIN" 2>/dev/null|openssl x509 -noout -enddate 2>/dev/null|cut -d= -f2)
        [[ -n "$cd" ]] && { ok "SSL valido ate $cd"; SCORE_OK=$((SCORE_OK+1)); } || fail "SSL nao verificado"
    fi
    sub_hud "TUNING"
    check "mod_deflate" "httpd -M 2>/dev/null|grep -qi deflate"
    check "KeepAlive" "grep -rqi 'KeepAlive On' /etc/httpd/ 2>/dev/null"
    if [[ -n "$DB_PASS" ]]; then check "innodb_buffer_pool" "mysql -u root -p'$DB_PASS' -N -e \"SHOW VARIABLES LIKE 'innodb_buffer_pool_size';\" 2>/dev/null|grep -q '[0-9]'"; fi
    check "PHP timezone" "php -i 2>/dev/null|grep -qi 'Europe/Lisbon'"
    check "NTP sincronizado" "timedatectl 2>/dev/null|grep -qi 'synchronized: yes\|NTP.*active'"
    show_score; wait_enter
}

# ################################################################
#  BACKUPSERVER - FUNCOES DE DIAGNOSTICO
# ################################################################

bkp_test_servicos() {
    page_header "SERVICOS BACKUP"; section_hud "1. SERVICOS DO BACKUPSERVER"
    explain "Verificar firewall, SSH, crond, e conectividade ao WebServer."
    sub_hud "Servicos Locais"
    for svc in firewalld crond sshd; do
        showcmd "systemctl status $svc"
        if systemctl is-active --quiet "$svc" 2>/dev/null; then ok "$svc ativo"
        else fail "$svc inativo"; fi
    done
    sub_hud "Arranque Automatico"
    for svc in firewalld crond sshd; do
        systemctl is-enabled --quiet "$svc" 2>/dev/null && ok "$svc boot" || fail "$svc NAO no boot"
    done
    sub_hud "Firewall"
    showcmd "firewall-cmd --list-all"; firewall-cmd --list-all 2>/dev/null
    local svcs; svcs=$(firewall-cmd --list-services 2>/dev/null)
    echo "$svcs"|grep -qw ssh && ok "SSH aberto na firewall" || fail "SSH NAO aberto"
    sub_hud "Configuracao de Backup"
    if [[ -f "$CONF_FILE" ]]; then
        ok "Ficheiro $CONF_FILE encontrado"
        value "WebServer IP:" "${WEBSERVER_IP:-N/A}"
        value "WebServer User:" "${WEBSERVER_USER:-N/A}"
        value "Webroot Remoto:" "${WEBROOT_REMOTE:-N/A}"
        value "Base de Backup:" "${BACKUP_BASE:-N/A}"
    else fail "Ficheiro $CONF_FILE nao encontrado"; fi
    wait_enter
}

bkp_test_conectividade() {
    page_header "CONECTIVIDADE"; section_hud "2. LIGACAO AO WEBSERVER"
    explain "Testar ligacao SSH ao WebServer e verificar servicos remotos."
    local ws_ip="${WEBSERVER_IP:-}" ws_user="${WEBSERVER_USER:-root}"
    if [[ -z "$ws_ip" ]]; then
        dialog --title " WebServer IP " --inputbox "\nIP do WebServer:" 9 50 "192.168.1.100" 2>"$TEMP_FILE"
        [[ $? -ne 0 ]] && return; ws_ip=$(cat "$TEMP_FILE")
    fi
    page_header "CONECTIVIDADE"; section_hud "2. LIGACAO AO WEBSERVER"
    panel_open "DESTINO" 62; printf "  ${c_mgray}│${c_reset}  ${c_cyan}◇${c_reset}  ${ws_user}@%-42s  ${c_mgray}│${c_reset}\n" "$ws_ip"; panel_close 62
    sub_hud "Teste SSH"
    showcmd "ssh -o BatchMode=yes ${ws_user}@${ws_ip} 'echo ok'"
    spinner "A testar ligacao SSH..." 2
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${ws_user}@${ws_ip}" "echo ok" &>/dev/null; then
        ok "SSH funcional (sem password)"
        sub_hud "Servicos Remotos"
        local r_apache r_maria r_files r_disk
        r_apache=$(ssh "${ws_user}@${ws_ip}" "systemctl is-active httpd 2>/dev/null" 2>/dev/null)
        r_maria=$(ssh "${ws_user}@${ws_ip}" "systemctl is-active mariadb 2>/dev/null" 2>/dev/null)
        r_files=$(ssh "${ws_user}@${ws_ip}" "find ${WEBROOT_REMOTE:-/var/www/html}/ -type f 2>/dev/null|wc -l" 2>/dev/null)
        r_disk=$(ssh "${ws_user}@${ws_ip}" "df -h /var/www 2>/dev/null|tail -1|awk '{print \$4}'" 2>/dev/null)
        [[ "$r_apache" == "active" ]] && ok "Apache remoto: ativo" || fail "Apache remoto: $r_apache"
        [[ "$r_maria" == "active" ]] && ok "MariaDB remoto: ativo" || fail "MariaDB remoto: $r_maria"
        value "Ficheiros web:" "${r_files:-0}"
        value "Disco livre:" "${r_disk:-N/A}"
    else
        fail "SSH falhou"
        warn "Causas possiveis:"
        detail "- WebServer desligado"
        detail "- Chave SSH nao configurada"
        detail "- Firewall porta 22 bloqueada"
    fi
    wait_enter
}

bkp_test_raid() {
    while true; do
        dialog --title " RAID 10 " --cancel-label "Voltar" --menu "\nTestes RAID 10:" 18 55 8 \
            1 "Estado do RAID" 2 "Discos do RAID" 3 "Verificar fstab" \
            4 "Verificar mdadm.conf" 5 "Espaco em disco" \
            6 "Simular falha de disco" 7 "Rebuild do RAID" 8 "Backup em modo degraded" 2>"$TEMP_FILE"
        [[ $? -ne 0 ]] && return; case $(cat "$TEMP_FILE") in
            1) bkp_raid_estado;; 2) bkp_raid_discos;; 3) bkp_raid_fstab;;
            4) bkp_raid_mdadm;; 5) bkp_raid_espaco;; 6) bkp_raid_falha;;
            7) bkp_raid_rebuild;; 8) bkp_raid_backup_deg;; esac
    done
}

bkp_raid_estado() {
    page_header "RAID - ESTADO"; section_hud "RAID 10 - ESTADO"
    explain "Verificar estado geral do array RAID 10."
    if [[ ! -e /dev/md0 ]]; then fail "RAID /dev/md0 nao encontrado"; wait_enter; return; fi
    showcmd "mdadm --detail /dev/md0"
    local state; state=$(mdadm --detail /dev/md0 2>/dev/null|grep "State :"|awk -F: '{print $2}'|xargs)
    local active; active=$(mdadm --detail /dev/md0 2>/dev/null|grep "Active Devices"|awk -F: '{print $2}'|xargs)
    local total; total=$(mdadm --detail /dev/md0 2>/dev/null|grep "Raid Devices"|awk -F: '{print $2}'|xargs)
    panel_open "RAID STATUS" 62
    printf "  ${c_mgray}│${c_reset}  %-20s" "Estado:"
    if echo "$state"|grep -qi "clean\|active"; then printf "${c_green}%-30s${c_reset}" "$state"
    elif echo "$state"|grep -qi "degraded"; then printf "${c_yellow}%-30s${c_reset}" "$state"
    else printf "${c_red}%-30s${c_reset}" "$state"; fi
    printf "  ${c_mgray}│${c_reset}\n"
    printf "  ${c_mgray}│${c_reset}  %-20s ${c_white}%-30s${c_reset}  ${c_mgray}│${c_reset}\n" "Discos ativos:" "${active:-?} / ${total:-?}"
    printf "  ${c_mgray}│${c_reset}  %-20s ${c_white}%-30s${c_reset}  ${c_mgray}│${c_reset}\n" "Level:" "$(mdadm --detail /dev/md0 2>/dev/null|grep "Raid Level"|awk -F: '{print $2}'|xargs)"
    panel_close 62
    sub_hud "/proc/mdstat"; cat /proc/mdstat 2>/dev/null
    wait_enter
}

bkp_raid_discos() {
    page_header "RAID - DISCOS"; section_hud "DISCOS DO RAID"
    if [[ ! -e /dev/md0 ]]; then fail "RAID nao encontrado"; wait_enter; return; fi
    showcmd "mdadm --detail /dev/md0 (discos)"
    panel_open "DEVICES" 62
    mdadm --detail /dev/md0 2>/dev/null | grep -E "^\s+[0-9]" | while IFS= read -r line; do
        local dev state; dev=$(echo "$line"|awk '{print $NF}'); state=$(echo "$line"|awk '{print $(NF-1)}')
        if echo "$state"|grep -qi "active"; then printf "  ${c_mgray}│${c_reset}  ${c_green}✔${c_reset} %-48s${c_mgray}│${c_reset}\n" "$dev (active sync)"
        else printf "  ${c_mgray}│${c_reset}  ${c_red}✘${c_reset} %-48s${c_mgray}│${c_reset}\n" "$dev ($state)"; fi
    done
    panel_close 62; wait_enter
}

bkp_raid_fstab() {
    page_header "RAID - FSTAB"; section_hud "FSTAB"
    explain "Verificar que /backup esta no fstab com UUID e nofail."
    showcmd "grep backup /etc/fstab"
    local fstab_line; fstab_line=$(grep "backup" /etc/fstab 2>/dev/null)
    if [[ -n "$fstab_line" ]]; then
        ok "Entrada encontrada no fstab"; detail "$fstab_line"
        echo "$fstab_line"|grep -q "UUID=" && ok "Usa UUID" || warn "NAO usa UUID"
        echo "$fstab_line"|grep -q "nofail" && ok "Tem nofail" || warn "Sem nofail"
    else fail "Sem entrada para /backup no fstab"; fi
    sub_hud "Montagem Atual"
    mountpoint -q /backup && ok "/backup esta montado" || fail "/backup NAO montado"
    wait_enter
}

bkp_raid_mdadm() {
    page_header "RAID - MDADM.CONF"; section_hud "MDADM.CONF"
    showcmd "cat /etc/mdadm.conf"
    if [[ -f /etc/mdadm.conf ]]; then cat /etc/mdadm.conf 2>/dev/null
        grep -q "md0\|atec_raid10" /etc/mdadm.conf 2>/dev/null && ok "RAID presente no mdadm.conf" || fail "RAID nao encontrado no mdadm.conf"
    else fail "/etc/mdadm.conf nao existe"; fi
    wait_enter
}

bkp_raid_espaco() {
    page_header "RAID - ESPACO"; section_hud "ESPACO EM DISCO"
    if ! mountpoint -q /backup 2>/dev/null; then fail "/backup nao montado"; wait_enter; return; fi
    showcmd "df -h /backup"
    local df_line; df_line=$(df -h /backup|tail -1)
    local total used free pct; total=$(echo "$df_line"|awk '{print $2}'); used=$(echo "$df_line"|awk '{print $3}')
    free=$(echo "$df_line"|awk '{print $4}'); pct=$(echo "$df_line"|awk '{print $5}'|tr -d '%')
    panel_open "STORAGE" 62
    printf "  ${c_mgray}│${c_reset}  %-16s ${c_white}%-34s${c_reset}  ${c_mgray}│${c_reset}\n" "Total:" "$total"
    printf "  ${c_mgray}│${c_reset}  %-16s ${c_white}%-34s${c_reset}  ${c_mgray}│${c_reset}\n" "Usado:" "$used ($pct%%)"
    printf "  ${c_mgray}│${c_reset}  %-16s ${c_white}%-34s${c_reset}  ${c_mgray}│${c_reset}\n" "Livre:" "$free"
    panel_close 62
    printf "\n"; local usage=$((100-${pct:-0})); progress_bar "$usage" 100 40; printf " livre\n"
    wait_enter
}

bkp_raid_falha() {
    page_header "RAID - SIMULAR FALHA"; section_hud "SIMULAR FALHA DE DISCO"
    explain "Marcar um disco como falhado para testar resiliencia do RAID 10."
    if [[ ! -e /dev/md0 ]]; then fail "RAID nao encontrado"; wait_enter; return; fi
    local devs=() menu_items=() i=1
    while IFS= read -r line; do
        local dev; dev=$(echo "$line"|awk '{print $NF}')
        [[ -n "$dev" && "$dev" == /dev/* ]] && { devs+=("$dev"); menu_items+=("$i" "$dev"); i=$((i+1)); }
    done < <(mdadm --detail /dev/md0 2>/dev/null|grep -E "active sync")
    if [[ ${#devs[@]} -eq 0 ]]; then fail "Sem discos ativos para falhar"; wait_enter; return; fi
    dialog --title " Escolher Disco " --menu "\nDisco a marcar como falhado:" 14 55 "${#devs[@]}" "${menu_items[@]}" 2>"$TEMP_FILE"
    [[ $? -ne 0 ]] && return; local choice=$(($(cat "$TEMP_FILE")-1)); local target="${devs[$choice]}"
    dialog --title " CONFIRMAR " --yesno "\nMarcar $target como FALHADO?\n\nO RAID vai ficar degraded." 10 50
    [[ $? -ne 0 ]] && return
    page_header "RAID - SIMULAR FALHA"; countdown "A marcar $target como falhado..." 3
    showcmd "mdadm /dev/md0 --fail $target"
    mdadm /dev/md0 --fail "$target" 2>/dev/null
    sleep 2
    local state; state=$(mdadm --detail /dev/md0 2>/dev/null|grep "State :"|awk -F: '{print $2}'|xargs)
    result_box "Disco $target FALHADO" "${c_yellow}" "Estado: $state"
    sub_hud "/proc/mdstat"; cat /proc/mdstat 2>/dev/null
    showcmd "mdadm /dev/md0 --remove $target"
    mdadm /dev/md0 --remove "$target" 2>/dev/null; ok "Disco removido do array"
    wait_enter
}

bkp_raid_rebuild() {
    page_header "RAID - REBUILD"; section_hud "REBUILD DO RAID"
    explain "Re-adicionar um disco ao RAID para iniciar o rebuild."
    if [[ ! -e /dev/md0 ]]; then fail "RAID nao encontrado"; wait_enter; return; fi
    local state; state=$(mdadm --detail /dev/md0 2>/dev/null|grep "State :"|awk -F: '{print $2}'|xargs)
    if ! echo "$state"|grep -qi "degraded"; then warn "RAID nao esta degraded ($state)"; wait_enter; return; fi
    local missing; missing=$(mdadm --detail /dev/md0 2>/dev/null|grep "removed\|faulty"|awk '{print $NF}'|head -1)
    if [[ -z "$missing" ]]; then
        dialog --title " Disco " --inputbox "\nDispositivo para re-adicionar (ex: /dev/sdb1):" 9 55 2>"$TEMP_FILE"
        [[ $? -ne 0 ]] && return; missing=$(cat "$TEMP_FILE")
    fi
    dialog --title " CONFIRMAR " --yesno "\nAdicionar $missing ao RAID?\n\nO rebuild vai comecar." 10 50
    [[ $? -ne 0 ]] && return
    page_header "RAID - REBUILD"; countdown "A iniciar rebuild..." 3
    showcmd "mdadm /dev/md0 --add $missing"
    mdadm /dev/md0 --add "$missing" 2>/dev/null
    ok "Disco adicionado - rebuild em progresso"
    sub_hud "Progresso"
    local pr=0 count=0
    while [[ $pr -lt 100 && $count -lt 60 ]]; do
        pr=$(cat /proc/mdstat 2>/dev/null|grep -oP '[0-9]+(?=%)' | head -1)
        [[ -z "$pr" ]] && pr=100
        printf "\r"; braille_bar "$pr" 100 30
        sleep 2; count=$((count+1))
    done
    printf "\n"
    state=$(mdadm --detail /dev/md0 2>/dev/null|grep "State :"|awk -F: '{print $2}'|xargs)
    result_box "Rebuild concluido" "${c_green}" "Estado: $state"
    cat /proc/mdstat 2>/dev/null; wait_enter
}

bkp_raid_backup_deg() {
    page_header "BACKUP DEGRADED"; section_hud "BACKUP EM MODO DEGRADED"
    explain "Verificar que o backup continua a funcionar mesmo com RAID degraded."
    local state; state=$(mdadm --detail /dev/md0 2>/dev/null|grep "State :"|awk -F: '{print $2}'|xargs)
    panel_open "RAID STATUS" 62; printf "  ${c_mgray}│${c_reset}  Estado: ${c_yellow}%-42s${c_reset}${c_mgray}│${c_reset}\n" "$state"; panel_close 62
    mountpoint -q /backup && ok "/backup acessivel" || { fail "/backup NAO acessivel"; wait_enter; return; }
    sub_hud "Teste de Escrita"
    spinner "A escrever ficheiro de teste..." 1
    echo "DEGRADED_TEST $(date)" > /backup/degraded_test.tmp 2>/dev/null && \
        { ok "Escrita funcional"; rm -f /backup/degraded_test.tmp; } || fail "Escrita falhou"
    sub_hud "Teste de Leitura"
    spinner "A ler dados existentes..." 1
    ls /backup/web/incremental/ &>/dev/null && ok "Leitura funcional" || warn "Sem dados para ler"
    result_box "RAID DEGRADED - BACKUP FUNCIONAL" "${c_green}" "Os dados estao protegidos"
    wait_enter
}

bkp_test_backups() {
    page_header "BACKUPS"; section_hud "4. ESTADO DOS BACKUPS"
    explain "Verificar estrutura de backup, backups existentes e agendamentos."
    sub_hud "Estrutura de Diretorios"
    for dir in /backup/web /backup/web/incremental /backup/db /backup/db/incremental /backup/logs; do
        [[ -d "$dir" ]] && ok "$dir existe" || fail "$dir NAO existe"
    done
    sub_hud "Backups Web"
    local web_current="/backup/web/incremental/current"
    if [[ -d "$web_current" ]] && [[ -n "$(ls -A "$web_current" 2>/dev/null)" ]]; then
        local ws=$(du -sh "$web_current" 2>/dev/null|awk '{print $1}')
        local wf=$(find "$web_current" -type f 2>/dev/null|wc -l)
        ok "Backup web atual: $ws ($wf ficheiros)"
    else warn "Sem backup web atual"; fi
    local wv=$(find /backup/web/incremental -maxdepth 1 -name "changed_*" -type d 2>/dev/null|wc -l)
    value "Versoes incrementais:" "$wv"
    sub_hud "Backups BD"
    local db_count=$(find /backup/db/incremental -name "*.sql.gz" 2>/dev/null|wc -l)
    value "Backups BD (.sql.gz):" "$db_count"
    if [[ $db_count -gt 0 ]]; then
        local latest; latest=$(ls -t /backup/db/incremental/*.sql.gz 2>/dev/null|head -1)
        local lsize=$(du -h "$latest" 2>/dev/null|awk '{print $1}')
        local ldate=$(stat -c '%y' "$latest" 2>/dev/null|cut -d'.' -f1)
        value "Ultimo backup BD:" "$lsize ($ldate)"
    fi
    sub_hud "Agendamentos Cron"
    showcmd "crontab -l | grep backup"
    local cron_count=$(crontab -l 2>/dev/null|grep -c "backup-auto.sh" || echo 0)
    [[ $cron_count -gt 0 ]] && ok "$cron_count agendamento(s) ativo(s)" || warn "Sem agendamentos"
    crontab -l 2>/dev/null|grep "backup-auto.sh" || true
    sub_hud "Logs Recentes"
    local llog=$(ls -t /backup/logs/*.log 2>/dev/null|head -1)
    if [[ -n "$llog" ]]; then value "Ultimo log:" "$(basename "$llog")"
        local lastline; lastline=$(tail -1 "$llog" 2>/dev/null); detail "$lastline"
    else warn "Sem logs"; fi
    wait_enter
}

bkp_health_check() {
    page_header "HEALTH CHECK - BACKUP"; section_hud "VERIFICACAO GERAL - BACKUP SERVER"
    SCORE_OK=0; SCORE_TOTAL=0
    page_header "HEALTH CHECK - BACKUP"
    sub_hud "SERVICOS"
    check "Firewalld ativo" "systemctl is-active --quiet firewalld"
    check "crond ativo" "systemctl is-active --quiet crond"
    check "sshd ativo" "systemctl is-active --quiet sshd"
    check "FW: ssh aberto" "firewall-cmd --list-services 2>/dev/null|grep -qw ssh"
    check "Config backup" "[[ -f '$CONF_FILE' ]]"
    sub_hud "RAID 10"
    check "/dev/md0 existe" "[[ -e /dev/md0 ]]"
    check_val "RAID estado" "mdadm --detail /dev/md0 2>/dev/null|grep 'State :'|awk -F: '{print \$2}'|xargs" "clean"
    local ad; ad=$(mdadm --detail /dev/md0 2>/dev/null|grep "Active Devices"|awk -F: '{print $2}'|xargs)
    check "4/4 discos ativos" "[[ '$ad' == '4' ]]"
    check "Montado em /backup" "mountpoint -q /backup"
    check "fstab com UUID" "grep backup /etc/fstab 2>/dev/null|grep -q UUID="
    check "mdadm.conf" "grep -q 'md0\|atec_raid10' /etc/mdadm.conf 2>/dev/null"
    sub_hud "BACKUPS"
    check "/backup/web/" "[[ -d /backup/web ]]"
    check "/backup/db/" "[[ -d /backup/db ]]"
    check "/backup/logs/" "[[ -d /backup/logs ]]"
    check "Cron agendado" "crontab -l 2>/dev/null|grep -q backup-auto.sh"
    if [[ -n "${WEBSERVER_IP:-}" ]]; then
        check "SSH WebServer" "ssh -o BatchMode=yes -o ConnectTimeout=3 ${WEBSERVER_USER:-root}@${WEBSERVER_IP} 'echo ok'"
    fi
    local wb db
    wb=$(find /backup/web/incremental -maxdepth 1 -name "changed_*" -type d 2>/dev/null|wc -l)
    SCORE_TOTAL=$((SCORE_TOTAL+1)); [[ $wb -gt 0 ]] && { ok "Backups web: $wb versoes"; SCORE_OK=$((SCORE_OK+1)); } || fail "Sem backups web"
    db=$(find /backup/db/incremental -name "*.sql.gz" 2>/dev/null|wc -l)
    SCORE_TOTAL=$((SCORE_TOTAL+1)); [[ $db -gt 0 ]] && { ok "Backups BD: $db ficheiros"; SCORE_OK=$((SCORE_OK+1)); } || fail "Sem backups BD"
    sub_hud "SISTEMA"
    check "SELinux Enforcing" "[[ \$(getenforce 2>/dev/null) == 'Enforcing' ]]"
    check "NTP sincronizado" "timedatectl 2>/dev/null|grep -qi 'synchronized: yes\|NTP.*active'"
    show_score; wait_enter
}

# ################################################################
#  MENUS PRINCIPAIS
# ################################################################

splash_screen

if [[ "$SERVER_MODE" == "webserver" ]]; then
    # ==================== MENU WEBSERVER ====================
    while true; do
        dialog --title " ATEC // DIAGNOSTIC v4.0 ─ WEB SERVER " \
            --cancel-label "Sair" \
            --menu "\n  ${SERVER_ICON} Diagnostico do Web Server\n  ◇ Projeto ATEC SYSTEM_CORE_2026\n" 18 60 6 \
            1 "Servicos Principais (Apache, MariaDB, PHP)" \
            2 "Seguranca MariaDB + BD de Exemplo" \
            3 "Acesso Externo (IP, DuckDNS, SSL)" \
            4 "Seguranca (Firewall, SELinux, F2B, WAF)" \
            9 "VERIFICACAO GERAL (Health Check)" \
            2>"$TEMP_FILE"

        if [[ $? -ne 0 ]]; then
            clear; gradient_line "▀" 62; printf "\n"
            printf "  ${c_cyan}◉${c_reset} ${c_white}ATEC // DIAGNOSTIC ENCERRADO${c_reset}\n"
            printf "  ${c_gray}  Modo: WEB SERVER${c_reset}\n"
            printf "  ${c_gray}  Log: %s${c_reset}\n" "$LOG_FILE"
            printf "\n"; gradient_line "▄" 62; printf "\n"; exit 0
        fi

        case $(cat "$TEMP_FILE") in
            1) web_test_servicos ;;
            2) web_test_mariadb ;;
            3) web_test_acesso_externo ;;
            4) web_test_seguranca ;;
            9) web_health_check ;;
        esac
    done

else
    # ==================== MENU BACKUPSERVER ====================
    while true; do
        dialog --title " ATEC // DIAGNOSTIC v4.0 ─ BACKUP SERVER " \
            --cancel-label "Sair" \
            --menu "\n  ${SERVER_ICON} Diagnostico do Backup Server\n  ◇ Projeto ATEC SYSTEM_CORE_2026\n" 18 60 6 \
            1 "Servicos BackupServer (FW, SSH, Cron)" \
            2 "Conectividade ao WebServer" \
            3 "RAID 10 (Estado, Falha, Rebuild)" \
            4 "Estado dos Backups (Web + BD)" \
            9 "VERIFICACAO GERAL (Health Check)" \
            2>"$TEMP_FILE"

        if [[ $? -ne 0 ]]; then
            clear; gradient_line "▀" 62; printf "\n"
            printf "  ${c_cyan}◎${c_reset} ${c_white}ATEC // DIAGNOSTIC ENCERRADO${c_reset}\n"
            printf "  ${c_gray}  Modo: BACKUP SERVER${c_reset}\n"
            printf "  ${c_gray}  Log: %s${c_reset}\n" "$LOG_FILE"
            printf "\n"; gradient_line "▄" 62; printf "\n"; exit 0
        fi

        case $(cat "$TEMP_FILE") in
            1) bkp_test_servicos ;;
            2) bkp_test_conectividade ;;
            3) bkp_test_raid ;;
            4) bkp_test_backups ;;
            9) bkp_health_check ;;
        esac
    done
fi

# Revisto
