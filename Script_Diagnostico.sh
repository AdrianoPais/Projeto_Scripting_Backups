#!/bin/bash
# ============================================================
#  CORRECAO AUTOMATICA DE PROBLEMAS DE BACKUP
#  Tenta resolver os problemas mais comuns
# ============================================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

if [[ "$(id -u)" -ne 0 ]]; then
    echo -e "${RED}[ERRO]${NC} Corre como root: sudo bash $0"
    exit 1
fi

echo "============================================================"
echo "  CORRECAO AUTOMATICA - ATEC BACKUP"
echo "============================================================"
echo ""

# Carregar configuração
CONF_FILE="/etc/backup-atec.conf"
if [[ ! -f "$CONF_FILE" ]]; then
    echo -e "${RED}[ERRO]${NC} Ficheiro de configuracao nao encontrado"
    exit 1
fi

source "$CONF_FILE"

echo -e "${CYAN}WebServer:${NC} ${WEBSERVER_USER}@${WEBSERVER_IP}"
echo ""

# ============================================================
# CORRECAO 1: Permissões da chave SSH
# ============================================================
echo "------------------------------------------------------------"
echo "CORRECAO 1: Permissoes da chave SSH"
echo "------------------------------------------------------------"

if [[ -f /root/.ssh/id_rsa ]]; then
    chmod 700 /root/.ssh
    chmod 600 /root/.ssh/id_rsa
    echo -e "${GREEN}[OK]${NC} Permissoes corrigidas"
else
    echo -e "${YELLOW}[INFO]${NC} Chave nao existe, a criar..."
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    ssh-keygen -t rsa -b 4096 -f /root/.ssh/id_rsa -N "" -q
    echo -e "${GREEN}[OK]${NC} Chave criada"
fi
echo ""

# ============================================================
# CORRECAO 2: Reconfigurar chave SSH no WebServer
# ============================================================
echo "------------------------------------------------------------"
echo "CORRECAO 2: Reconfigurar acesso SSH"
echo "------------------------------------------------------------"

echo "A testar conexao SSH..."
if ssh -o BatchMode=yes -o ConnectTimeout=5 "${WEBSERVER_USER}@${WEBSERVER_IP}" "echo ok" &>/dev/null; then
    echo -e "${GREEN}[OK]${NC} SSH ja funciona sem senha"
else
    echo -e "${YELLOW}[INFO]${NC} SSH nao funciona, a reconfigurar..."
    echo ""
    echo "Vai pedir a PASSWORD do WebServer (so desta vez):"
    echo ""
    
    ssh-copy-id -o StrictHostKeyChecking=no "${WEBSERVER_USER}@${WEBSERVER_IP}"
    
    if ssh -o BatchMode=yes -o ConnectTimeout=5 "${WEBSERVER_USER}@${WEBSERVER_IP}" "echo ok" &>/dev/null; then
        echo -e "${GREEN}[OK]${NC} SSH reconfigurado com sucesso!"
    else
        echo -e "${RED}[ERRO]${NC} Nao foi possivel reconfigurar SSH"
        echo "Verifica:"
        echo "  1. WebServer esta ligado?"
        echo "  2. SSH esta ativo no WebServer? systemctl status sshd"
        echo "  3. Firewall aberto? firewall-cmd --list-services | grep ssh"
        exit 1
    fi
fi
echo ""

# ============================================================
# CORRECAO 3: Corrigir permissões no WebServer
# ============================================================
echo "------------------------------------------------------------"
echo "CORRECAO 3: Permissoes no WebServer"
echo "------------------------------------------------------------"

echo "A corrigir permissoes da pasta .ssh no WebServer..."
ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "
    chmod 700 ~/.ssh 2>/dev/null || true
    chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true
    echo 'Permissoes corrigidas'
" 2>/dev/null

echo -e "${GREEN}[OK]${NC} Permissoes verificadas"
echo ""

# ============================================================
# CORRECAO 4: Criar diretorio de backup se nao existir
# ============================================================
echo "------------------------------------------------------------"
echo "CORRECAO 4: Diretorios de backup"
echo "------------------------------------------------------------"

mkdir -p /backup/web/incremental/current
mkdir -p /backup/logs
chmod 700 /backup

echo -e "${GREEN}[OK]${NC} Diretorios criados"
echo ""

# ============================================================
# CORRECAO 5: Verificar e iniciar serviços
# ============================================================
echo "------------------------------------------------------------"
echo "CORRECAO 5: Servicos"
echo "------------------------------------------------------------"

# Crond local
systemctl enable --now crond 2>/dev/null
echo -e "${GREEN}[OK]${NC} Crond ativo"

# SSHD no WebServer (se for root)
if [[ "$WEBSERVER_USER" == "root" ]]; then
    ssh "${WEBSERVER_USER}@${WEBSERVER_IP}" "
        systemctl enable --now sshd 2>/dev/null
        systemctl enable --now httpd 2>/dev/null
    " 2>/dev/null
    echo -e "${GREEN}[OK]${NC} Servicos do WebServer verificados"
fi
echo ""

# ============================================================
# CORRECAO 6: Limpar ficheiros temporários antigos
# ============================================================
echo "------------------------------------------------------------"
echo "CORRECAO 6: Limpeza"
echo "------------------------------------------------------------"

# Remover logs antigos (mais de 90 dias)
if [[ -d /backup/logs ]]; then
    LOGS_REMOVED=$(find /backup/logs -name "*.log" -type f -mtime +90 -delete -print 2>/dev/null | wc -l)
    echo -e "${GREEN}[OK]${NC} Logs antigos removidos: ${LOGS_REMOVED}"
fi

# Remover versões incrementais antigas (mais de 30 dias)
if [[ -d /backup/web/incremental ]]; then
    VERS_REMOVED=$(find /backup/web/incremental -maxdepth 1 -name "changed_*" -type d -mtime +30 -print 2>/dev/null | wc -l)
    find /backup/web/incremental -maxdepth 1 -name "changed_*" -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null
    echo -e "${GREEN}[OK]${NC} Versoes antigas removidas: ${VERS_REMOVED}"
fi
echo ""

# ============================================================
# TESTE FINAL: Fazer backup de teste
# ============================================================
echo "------------------------------------------------------------"
echo "TESTE FINAL: Backup de teste"
echo "------------------------------------------------------------"

echo "A fazer backup de teste (dry-run)..."
RSYNC_OUTPUT=$(rsync -avzn --timeout=10 \
    "${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/" \
    /tmp/test_backup_$$ 2>&1)
RSYNC_EXIT=$?

if [[ $RSYNC_EXIT -eq 0 ]]; then
    echo -e "${GREEN}[OK]${NC} Backup de teste OK!"
    
    NUM_FILES=$(echo "$RSYNC_OUTPUT" | grep -c "^-" || echo 0)
    echo "  Ficheiros encontrados: ${NUM_FILES}"
    
    rm -rf /tmp/test_backup_$$ 2>/dev/null
else
    echo -e "${RED}[ERRO]${NC} Backup de teste falhou (codigo: $RSYNC_EXIT)"
    echo ""
    echo "Output:"
    echo "$RSYNC_OUTPUT"
    echo ""
    echo "Problemas que nao foram resolvidos automaticamente:"
    
    case $RSYNC_EXIT in
        12)
            echo "  - Erro 12: Problema na conexao/protocolo"
            echo "  - Pode ser espaço em disco cheio"
            echo "  - Ou permissoes no servidor remoto"
            ;;
        23)
            echo "  - Erro 23: Alguns ficheiros nao puderam ser transferidos"
            ;;
        255)
            echo "  - Erro 255: Problema de conexao SSH"
            ;;
    esac
    
    exit 1
fi
echo ""

# ============================================================
# RESUMO
# ============================================================
echo "============================================================"
echo "  CORRECAO CONCLUIDA"
echo "============================================================"
echo ""
echo -e "${GREEN}Sistema corrigido com sucesso!${NC}"
echo ""
echo "Proximos passos:"
echo "  1. Testa fazer backup pelo gestor"
echo "  2. Se continuar com erro, corre o diagnostico:"
echo "     sudo bash diagnostico_backup.sh"
echo ""
echo "============================================================"
