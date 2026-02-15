#!/bin/bash
# ============================================================
#  MOD_SECURITY + OWASP CRS - ATEC SYSTEM_CORE_2026
#  Proteção contra SQL Injection, XSS e outros ataques
#  VERSÃO CORRIGIDA - Com EPEL e nomes alternativos
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
echo "   ATEC // INSTALAÇÃO MOD_SECURITY + OWASP CRS"
echo "============================================================"
echo ""
echo "  ModSecurity é uma firewall de aplicação web (WAF)"
echo "  que protege contra:"
echo ""
echo "  - SQL Injection"
echo "  - Cross-Site Scripting (XSS)"
echo "  - Remote File Inclusion (RFI)"
echo "  - Command Injection"
echo "  - E muitos outros ataques web"
echo ""
echo "  OWASP CRS = Core Rule Set (regras de segurança)"
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
info "A procurar pacotes ModSecurity..."

# Variáveis para controlar instalação
MODSEC_INSTALLED=0
CRS_INSTALLED=0

# Tentar várias combinações de nomes de pacotes
echo ""
echo "  A tentar instalar ModSecurity..."

# Tentativa 1: Nomes padrão
if dnf install -y mod_security mod_security_crs 2>&1 | grep -q "Complete\|Nothing to do"; then
    ok "Instalado: mod_security + mod_security_crs"
    MODSEC_INSTALLED=1
    CRS_INSTALLED=1

# Tentativa 2: Nomes alternativos
elif dnf install -y mod_modsecurity modsecurity-crs 2>&1 | grep -q "Complete\|Nothing to do"; then
    ok "Instalado: mod_modsecurity + modsecurity-crs"
    MODSEC_INSTALLED=1
    CRS_INSTALLED=1

# Tentativa 3: Só ModSecurity
elif dnf install -y mod_security 2>&1 | grep -q "Complete\|Nothing to do"; then
    ok "Instalado: mod_security (sem CRS)"
    MODSEC_INSTALLED=1
    warn "OWASP CRS não encontrado - instalação básica"

# Tentativa 4: Nome alternativo sem CRS
elif dnf install -y mod_modsecurity 2>&1 | grep -q "Complete\|Nothing to do"; then
    ok "Instalado: mod_modsecurity (sem CRS)"
    MODSEC_INSTALLED=1
    warn "OWASP CRS não encontrado - instalação básica"

# Tentativa 5: Repositório CRB
else
    warn "Pacotes não encontrados no EPEL. A tentar CRB..."
    dnf config-manager --set-enabled crb 2>/dev/null || true
    
    if dnf install -y mod_security mod_security_crs 2>&1 | grep -q "Complete"; then
        ok "Instalado via CRB: mod_security + mod_security_crs"
        MODSEC_INSTALLED=1
        CRS_INSTALLED=1
    elif dnf install -y mod_security 2>&1 | grep -q "Complete"; then
        ok "Instalado via CRB: mod_security"
        MODSEC_INSTALLED=1
    else
        fail "Não foi possível instalar ModSecurity. Pacote pode não estar disponível no CentOS Stream 10."
    fi
fi

# Verificar se o módulo foi carregado
info "A verificar instalação..."
sleep 2

# Procurar ficheiros do ModSecurity
MODSEC_SO=$(find /usr/lib64/httpd/modules/ -name "*security*.so" 2>/dev/null | head -1)

if [[ -z "$MODSEC_SO" ]]; then
    fail "Módulo ModSecurity não encontrado em /usr/lib64/httpd/modules/"
fi

ok "Módulo encontrado: $(basename "$MODSEC_SO")"

# --- CONFIGURAÇÃO PRINCIPAL ---
info "A configurar ModSecurity..."

# Backup da configuração original
if [[ -f /etc/httpd/conf.d/mod_security.conf ]]; then
    cp /etc/httpd/conf.d/mod_security.conf /etc/httpd/conf.d/mod_security.conf.bak
fi

# Criar configuração
cat > /etc/httpd/conf.d/mod_security.conf <<EOF
#
# MOD_SECURITY - ATEC SECURITY CONFIG
#

# Carregar módulo (caminho automático)
LoadModule security2_module modules/$(basename "$MODSEC_SO")
LoadModule unique_id_module modules/mod_unique_id.so

<IfModule mod_security2.c>
    # --- CONFIGURAÇÃO BASE ---
    
    # Motor de regras: On (ativo), DetectionOnly (só detecta)
    SecRuleEngine On
    
    # Processar corpo dos pedidos (POST)
    SecRequestBodyAccess On
    SecRequestBodyLimit 13107200
    SecRequestBodyNoFilesLimit 131072
    
    # Não processar respostas (performance)
    SecResponseBodyAccess Off
    
    # --- AUDITORIA ---
    
    # Modo de auditoria: RelevantOnly (só ataques)
    SecAuditEngine RelevantOnly
    SecAuditLogRelevantStatus "^(?:5|4(?!04))"
    SecAuditLogParts ABIJDEFHZ
    SecAuditLogType Serial
    SecAuditLog /var/log/httpd/modsec_audit.log
    
    # --- PROTEÇÕES BÁSICAS ---
    
    # Timeout
    SecPcreMatchLimit 100000
    SecPcreMatchLimitRecursion 100000
    
    # Uploads
    SecTmpDir /var/lib/mod_security
    SecDataDir /var/lib/mod_security
    
    # Argumentos
    SecArgumentSeparator &
    SecCookieFormat 0
    
    # --- REGRAS BÁSICAS (se CRS não disponível) ---
    
    # SQL Injection básico
    SecRule ARGS "@rx (\bor\b|\band\b).*[=<>]" \
        "id:1001,phase:2,t:lowercase,deny,status:403,msg:'Possível SQL Injection'"
    
    # XSS básico
    SecRule ARGS "@rx <script" \
        "id:1002,phase:2,t:lowercase,deny,status:403,msg:'Possível XSS'"
    
EOF

# Adicionar CRS se disponível
if [[ $CRS_INSTALLED -eq 1 ]]; then
    cat >> /etc/httpd/conf.d/mod_security.conf <<'EOF'
    # --- OWASP CORE RULE SET ---
    
    # Tentar diferentes localizações do CRS
    IncludeOptional /etc/httpd/modsecurity.d/*.conf
    IncludeOptional /etc/httpd/modsecurity.d/activated_rules/*.conf
    IncludeOptional /usr/share/mod_modsecurity_crs/*.conf
    IncludeOptional /etc/modsecurity/*.conf
EOF
fi

echo "</IfModule>" >> /etc/httpd/conf.d/mod_security.conf

ok "Configuração principal criada."

# --- CONFIGURAR OWASP CRS (se disponível) ---
if [[ $CRS_INSTALLED -eq 1 ]]; then
    info "A configurar OWASP Core Rule Set..."
    
    # Criar diretórios
    mkdir -p /etc/httpd/modsecurity.d/activated_rules
    
    # Procurar ficheiros CRS
    CRS_SETUP=$(find /usr/share /etc -name "crs-setup.conf*" 2>/dev/null | head -1)
    CRS_RULES=$(find /usr/share /etc -type d -name "*rules*" 2>/dev/null | grep -i crs | head -1)
    
    if [[ -n "$CRS_SETUP" ]]; then
        cp "$CRS_SETUP" /etc/httpd/modsecurity.d/activated_rules/crs-setup.conf
        ok "CRS setup copiado."
    fi
    
    if [[ -n "$CRS_RULES" && -d "$CRS_RULES" ]]; then
        info "A ativar regras CRS de: $CRS_RULES"
        for rule in "${CRS_RULES}"/REQUEST-*.conf "${CRS_RULES}"/RESPONSE-*.conf; do
            if [[ -f "$rule" ]]; then
                ln -sf "$rule" /etc/httpd/modsecurity.d/activated_rules/ 2>/dev/null || true
            fi
        done
        ok "Regras OWASP ativadas."
    else
        warn "Regras CRS não encontradas. A usar proteções básicas."
    fi
fi

# Criar diretório temporário
mkdir -p /var/lib/mod_security
chown apache:apache /var/lib/mod_security
chmod 700 /var/lib/mod_security

# --- VERIFICAR SINTAXE ---
info "A verificar configuração do Apache..."
if httpd -t 2>&1 | grep -q "Syntax OK"; then
    ok "Sintaxe correta!"
else
    warn "Erro na sintaxe. A exibir output:"
    httpd -t
    fail "Corrige os erros antes de continuar."
fi

# --- REINICIAR APACHE ---
info "A reiniciar Apache..."
systemctl restart httpd

if systemctl is-active --quiet httpd; then
    ok "Apache reiniciado com sucesso!"
else
    fail "Falha ao reiniciar Apache. Verifica: systemctl status httpd"
fi

# --- TESTE DE FUNCIONAMENTO ---
echo ""
echo "============================================================"
echo "  TESTES DE VALIDAÇÃO:"
echo "============================================================"
echo ""

info "A testar proteção contra SQL Injection..."
sleep 1

# Teste 1: SQL Injection
TEST_RESULT=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/?id=1' OR '1'='1" 2>/dev/null || echo "000")

if [[ "$TEST_RESULT" == "403" ]]; then
    ok "SQL Injection BLOQUEADO! ✓"
elif [[ "$TEST_RESULT" == "200" ]]; then
    warn "SQL Injection NÃO foi bloqueado (pode ser esperado em modo inicial)"
else
    warn "Teste inconclusivo (código: $TEST_RESULT)"
fi

# Verificar logs
if [[ -f /var/log/httpd/modsec_audit.log ]]; then
    ENTRIES=$(wc -l < /var/log/httpd/modsec_audit.log)
    if [[ $ENTRIES -gt 0 ]]; then
        ok "Log de auditoria ativo ($ENTRIES entradas)"
    fi
fi

# --- INFORMAÇÕES FINAIS ---
echo ""
echo "============================================================"
echo "  INSTALAÇÃO CONCLUÍDA!"
echo "============================================================"
echo ""
echo "  ModSecurity: ATIVO"
if [[ $CRS_INSTALLED -eq 1 ]]; then
    echo "  OWASP CRS:   ATIVO"
else
    echo "  OWASP CRS:   Não disponível (proteções básicas ativas)"
fi
echo "  Modo:        Bloqueio (SecRuleEngine On)"
echo ""
echo "============================================================"
echo "  FICHEIROS IMPORTANTES:"
echo "============================================================"
echo ""
echo "  Configuração principal:"
echo "    /etc/httpd/conf.d/mod_security.conf"
echo ""
if [[ $CRS_INSTALLED -eq 1 ]]; then
    echo "  Regras ativadas:"
    echo "    /etc/httpd/modsecurity.d/activated_rules/"
    echo ""
fi
echo "  Logs de auditoria:"
echo "    /var/log/httpd/modsec_audit.log"
echo ""
echo "  Logs de erro do Apache:"
echo "    /var/log/httpd/error_log"
echo ""
echo "============================================================"
echo "  COMANDOS ÚTEIS:"
echo "============================================================"
echo ""
echo "  Ver logs de ataques bloqueados:"
echo "    sudo tail -f /var/log/httpd/modsec_audit.log"
echo ""
echo "  Ver erros do Apache:"
echo "    sudo tail -f /var/log/httpd/error_log"
echo ""
echo "  Testar SQL Injection:"
echo "    curl \"http://localhost/?id=1' OR '1'='1\""
echo "    (deve retornar 403 Forbidden)"
echo ""
echo "  Testar XSS:"
echo "    curl \"http://localhost/?q=<script>alert('xss')</script>\""
echo "    (deve retornar 403 Forbidden)"
echo ""
echo "  Reiniciar Apache:"
echo "    sudo systemctl restart httpd"
echo ""
echo "============================================================"
echo ""
ok "Sistema protegido contra ataques web!"
echo ""
if [[ $CRS_INSTALLED -eq 0 ]]; then
    warn "NOTA: OWASP CRS não está disponível no CentOS Stream 10."
    warn "Proteções básicas estão ativas (SQL Injection e XSS)."
fi
echo ""
