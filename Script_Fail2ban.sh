#!/bin/bash
# ============================================================
#  FAIL2BAN - ATEC SYSTEM_CORE_2026
#  Proteção contra ataques de força bruta
#  VERSÃO CORRIGIDA - Com instalação do EPEL
# ============================================================

set -euo pipefail

# --- CORES ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "\n${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $*"; }
fail() { echo -e "${RED}[ERRO]${NC} $*"; exit 1; }

# --- VERIFICAÇÃO DE ROOT ---
if [[ "$(id -u)" -ne 0 ]]; then
    fail "Este script tem de ser corrido como root (sudo)."
fi

clear
echo "============================================================"
echo "   ATEC // INSTALAÇÃO FAIL2BAN"
echo "============================================================"
echo ""
echo "  Fail2ban protege contra ataques de força bruta:"
echo "  - SSH (após 3 tentativas falhadas)"
echo "  - Apache (autenticação, bots maliciosos, ataques)"
echo "  - Bloqueio automático por 1 hora"
echo ""
echo "============================================================"
echo ""

# --- PASSO CRÍTICO: INSTALAR EPEL ---
info "A verificar repositório EPEL..."

if ! rpm -q epel-release &>/dev/null; then
    info "EPEL não instalado. A instalar..."
    dnf install -y epel-release
    ok "EPEL instalado!"
else
    ok "EPEL já instalado."
fi

# Atualizar lista de pacotes
info "A atualizar lista de repositórios..."
dnf makecache -q 2>/dev/null || true

# --- INSTALAÇÃO ---
info "A instalar Fail2ban..."

# Tentar instalar
if dnf install -y fail2ban fail2ban-firewalld 2>&1 | grep -q "Nothing to do\|Complete"; then
    ok "Pacotes instalados."
elif dnf install -y fail2ban 2>&1 | grep -q "Complete"; then
    ok "Fail2ban instalado (sem fail2ban-firewalld)."
else
    warn "Problema na instalação. A tentar repositório CRB..."
    dnf config-manager --set-enabled crb 2>/dev/null || true
    dnf install -y fail2ban fail2ban-firewalld || dnf install -y fail2ban
    ok "Fail2ban instalado via CRB."
fi

# Verificar instalação
if ! command -v fail2ban-client &>/dev/null; then
    fail "Fail2ban não foi instalado corretamente!"
fi

# --- CONFIGURAÇÃO ---
info "A configurar proteções..."

# Criar diretório se não existir
mkdir -p /etc/fail2ban

cat > /etc/fail2ban/jail.local <<'EOF'
#
# FAIL2BAN - ATEC SECURITY CONFIG
#

[DEFAULT]
# Tempo de banimento
bantime = 1h

# Janela de tempo para contar tentativas
findtime = 10m

# Número máximo de tentativas
maxretry = 3

# Email para notificações (opcional)
destemail = admin@atec.pt
sendername = Fail2Ban-ATEC

# Ação: banir + enviar email com logs
action = %(action_mwl)s

# Backend
backend = systemd

#
# PROTEÇÕES ATIVAS
#

# --- SSH (Proteção crítica) ---
[sshd]
enabled = true
port = 22
filter = sshd
logpath = /var/log/secure
maxretry = 3

# --- Apache: Autenticação falhada ---
[apache-auth]
enabled = true
port = http,https
filter = apache-auth
logpath = /var/log/httpd/*error_log
maxretry = 5

# --- Apache: Bad Bots ---
[apache-badbots]
enabled = true
port = http,https
filter = apache-badbots
logpath = /var/log/httpd/*access_log
maxretry = 2

# --- Apache: Scripts maliciosos ---
[apache-noscript]
enabled = true
port = http,https
filter = apache-noscript
logpath = /var/log/httpd/*error_log
maxretry = 6

# --- Apache: Buffer Overflow ---
[apache-overflows]
enabled = true
port = http,https
filter = apache-overflows
logpath = /var/log/httpd/*error_log
maxretry = 2

# --- Apache: Shellshock ---
[apache-shellshock]
enabled = true
port = http,https
filter = apache-shellshock
logpath = /var/log/httpd/*error_log
maxretry = 1
EOF

ok "Configuração criada em /etc/fail2ban/jail.local"

# --- ATIVAR SERVIÇO ---
info "A ativar Fail2ban..."
systemctl enable fail2ban >/dev/null 2>&1
systemctl start fail2ban

# Aguardar inicialização
sleep 3

# --- VERIFICAÇÃO ---
info "A verificar estado..."
if systemctl is-active --quiet fail2ban; then
    ok "Fail2ban está ATIVO!"
    echo ""
    echo "============================================================"
    echo "  STATUS DAS PROTEÇÕES:"
    echo "============================================================"
    fail2ban-client status 2>/dev/null | grep "Jail list" || echo "  A inicializar jails..."
    echo ""
    echo "  Detalhes de cada jail:"
    for jail in sshd apache-auth apache-badbots apache-noscript apache-overflows apache-shellshock; do
        if fail2ban-client status "$jail" &>/dev/null; then
            echo ""
            echo "  [$jail]"
            fail2ban-client status "$jail" | grep -E "Currently banned|Total banned" || echo "    OK - Ativo"
        fi
    done
else
    fail "Serviço não iniciou! Verifica: systemctl status fail2ban"
fi

echo ""
echo "============================================================"
echo "  COMANDOS ÚTEIS:"
echo "============================================================"
echo ""
echo "  Ver todas as proteções:"
echo "    sudo fail2ban-client status"
echo ""
echo "  Ver detalhes do SSH:"
echo "    sudo fail2ban-client status sshd"
echo ""
echo "  Ver IPs banidos:"
echo "    sudo fail2ban-client get sshd banip"
echo ""
echo "  Desbanir um IP:"
echo "    sudo fail2ban-client set sshd unbanip IP_AQUI"
echo ""
echo "  Ver logs:"
echo "    sudo tail -f /var/log/fail2ban.log"
echo ""
echo "============================================================"
echo ""
ok "Instalação concluída! Sistema protegido contra força bruta."
echo ""
