#!/bin/bash
# ============================================================
#  DIAGNOSTICO APROFUNDADO - ERRO 12 DO RSYNC
#  Para quando SSH funciona mas rsync falha
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "============================================================"
echo "  DIAGNOSTICO APROFUNDADO - ERRO RSYNC 12"
echo "============================================================"
echo ""

# Carregar configuração
CONF_FILE="/etc/backup-atec.conf"
if [[ ! -f "$CONF_FILE" ]]; then
    echo -e "${RED}[ERRO]${NC} Ficheiro de configuracao nao encontrado"
    exit 1
fi

source "$CONF_FILE"

echo -e "${CYAN}WebServer:${NC} ${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}"
echo ""

# ============================================================
# TESTE CRITICO 1: Espaço em disco (DETALHADO)
# ============================================================
echo "============================================================"
echo "TESTE 1: ESPACO EM DISCO (detalhado)"
echo "============================================================"
echo ""

echo -e "${CYAN}[LOCAL] BackupServer:${NC}"
echo "------------------------------------------------------------"
df -h | grep -E "Filesystem|backup|/$"
echo ""

# Detalhes do /backup
if [[ -d /backup ]]; then
    BACKUP_USAGE=$(df /backup 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//')
    BACKUP_FREE=$(df -h /backup 2>/dev/null | tail -1 | awk '{print $4}')
    
    echo -e "Diretorio /backup:"
    echo -e "  Uso: ${BACKUP_USAGE}%"
    echo -e "  Livre: ${BACKUP_FREE}"
    
    if [[ $BACKUP_USAGE -gt 95 ]]; then
        echo -e "${RED}  [CRITICO]${NC} Disco quase cheio! (${BACKUP_USAGE}%)"
        echo -e "  ${YELLOW}Solucao:${NC} Apaga backups antigos!"
        echo ""
        echo "  Comando para limpar:"
        echo "    find /backup/web/incremental -name 'changed_*' -mtime +7 -exec rm -rf {} \;"
        echo ""
    elif [[ $BACKUP_USAGE -gt 85 ]]; then
        echo -e "${YELLOW}  [AVISO]${NC} Disco a encher (${BACKUP_USAGE}%)"
    else
        echo -e "${GREEN}  [OK]${NC} Espaco suficiente"
    fi
else
    echo -e "${RED}[ERRO]${NC} /backup nao existe!"
    echo "  Cria com: mkdir -p /backup"
    exit 1
fi

echo ""
echo -e "${CYAN}[REMOTO] WebServer:${NC}"
echo "------------------------------------------------------------"

# Disco do WebServer
REMOTE_DISK_INFO=$(ssh -o BatchMode=yes "${WEBSERVER_USER}@${WEBSERVER_IP}" \
    "df -h | grep -E 'Filesystem|var|/$'" 2>/dev/null)

if [[ -n "$REMOTE_DISK_INFO" ]]; then
    echo "$REMOTE_DISK_INFO"
    echo ""
    
    # Analisar uso
    REMOTE_ROOT_USAGE=$(ssh -o BatchMode=yes "${WEBSERVER_USER}@${WEBSERVER_IP}" \
        "df / | tail -1 | awk '{print \$5}' | sed 's/%//'" 2>/dev/null)
    
    if [[ -n "$REMOTE_ROOT_USAGE" ]] && [[ $REMOTE_ROOT_USAGE -gt 95 ]]; then
        echo -e "${RED}[CRITICO]${NC} Disco do WebServer quase cheio! (${REMOTE_ROOT_USAGE}%)"
        echo -e "${YELLOW}>>> ESTE E PROVAVELMENTE O PROBLEMA! <<<${NC}"
        echo ""
        echo "Solucao no WebServer:"
        echo "  1. Ver o que ocupa espaco:"
        echo "     du -sh /var/* | sort -h"
        echo ""
        echo "  2. Limpar logs:"
        echo "     journalctl --vacuum-size=100M"
        echo "     rm -f /var/log/*.log.* /var/log/*.gz"
        echo ""
        echo "  3. Limpar cache:"
        echo "     dnf clean all"
        echo ""
        exit 1
    elif [[ -n "$REMOTE_ROOT_USAGE" ]] && [[ $REMOTE_ROOT_USAGE -gt 85 ]]; then
        echo -e "${YELLOW}[AVISO]${NC} Disco do WebServer a encher (${REMOTE_ROOT_USAGE}%)"
    else
        echo -e "${GREEN}[OK]${NC} Espaco suficiente no WebServer"
    fi
else
    echo -e "${RED}[ERRO]${NC} Nao foi possivel verificar disco remoto"
fi

echo ""

# ============================================================
# TESTE CRITICO 2: rsync instalado no WebServer
# ============================================================
echo "============================================================"
echo "TESTE 2: RSYNC NO WEBSERVER"
echo "============================================================"
echo ""

RSYNC_PATH=$(ssh -o BatchMode=yes "${WEBSERVER_USER}@${WEBSERVER_IP}" \
    "which rsync 2>/dev/null" 2>/dev/null)

if [[ -n "$RSYNC_PATH" ]]; then
    echo -e "${GREEN}[OK]${NC} rsync instalado: $RSYNC_PATH"
    
    # Versão
    RSYNC_VERSION=$(ssh -o BatchMode=yes "${WEBSERVER_USER}@${WEBSERVER_IP}" \
        "rsync --version 2>/dev/null | head -1" 2>/dev/null)
    echo "  Versao: $RSYNC_VERSION"
else
    echo -e "${RED}[ERRO]${NC} rsync NAO esta instalado no WebServer!"
    echo -e "${YELLOW}>>> ESTE E O PROBLEMA! <<<${NC}"
    echo ""
    echo "Solucao no WebServer:"
    echo "  dnf install -y rsync"
    echo ""
    exit 1
fi

echo ""

# ============================================================
# TESTE CRITICO 3: Permissões no diretório remoto
# ============================================================
echo "============================================================"
echo "TESTE 3: PERMISSOES NO WEBSERVER"
echo "============================================================"
echo ""

# Verificar se diretório existe
DIR_EXISTS=$(ssh -o BatchMode=yes "${WEBSERVER_USER}@${WEBSERVER_IP}" \
    "if [[ -d '${WEBROOT_REMOTE}' ]]; then echo 'YES'; else echo 'NO'; fi" 2>/dev/null)

if [[ "$DIR_EXISTS" == "NO" ]]; then
    echo -e "${RED}[ERRO]${NC} Diretorio NAO existe: ${WEBROOT_REMOTE}"
    echo ""
    echo "Solucao no WebServer:"
    echo "  mkdir -p ${WEBROOT_REMOTE}"
    echo "  chown -R ${WEBSERVER_USER}:${WEBSERVER_USER} ${WEBROOT_REMOTE}"
    echo ""
    exit 1
fi

echo -e "${GREEN}[OK]${NC} Diretorio existe: ${WEBROOT_REMOTE}"

# Verificar permissões
PERMS_INFO=$(ssh -o BatchMode=yes "${WEBSERVER_USER}@${WEBSERVER_IP}" \
    "ls -ld ${WEBROOT_REMOTE}" 2>/dev/null)

if [[ -n "$PERMS_INFO" ]]; then
    echo "  Permissoes: $PERMS_INFO"
    
    # Verificar se é legível
    CAN_READ=$(ssh -o BatchMode=yes "${WEBSERVER_USER}@${WEBSERVER_IP}" \
        "if [[ -r '${WEBROOT_REMOTE}' ]]; then echo 'YES'; else echo 'NO'; fi" 2>/dev/null)
    
    if [[ "$CAN_READ" == "NO" ]]; then
        echo -e "${RED}[ERRO]${NC} Sem permissao de leitura!"
        echo ""
        echo "Solucao no WebServer:"
        echo "  chmod 755 ${WEBROOT_REMOTE}"
        echo "  chown -R ${WEBSERVER_USER}:${WEBSERVER_USER} ${WEBROOT_REMOTE}"
        exit 1
    fi
else
    echo -e "${YELLOW}[AVISO]${NC} Nao foi possivel verificar permissoes"
fi

# Verificar se consegue listar ficheiros
NUM_FILES=$(ssh -o BatchMode=yes "${WEBSERVER_USER}@${WEBSERVER_IP}" \
    "ls -1 ${WEBROOT_REMOTE}/ 2>/dev/null | wc -l" 2>/dev/null)

if [[ -n "$NUM_FILES" ]]; then
    echo "  Ficheiros encontrados: $NUM_FILES"
    
    if [[ $NUM_FILES -eq 0 ]]; then
        echo -e "${YELLOW}[AVISO]${NC} Diretorio vazio"
    fi
else
    echo -e "${RED}[ERRO]${NC} Nao consegue listar ficheiros!"
fi

echo ""

# ============================================================
# TESTE CRITICO 4: SELinux
# ============================================================
echo "============================================================"
echo "TESTE 4: SELINUX NO WEBSERVER"
echo "============================================================"
echo ""

SELINUX_STATUS=$(ssh -o BatchMode=yes "${WEBSERVER_USER}@${WEBSERVER_IP}" \
    "getenforce 2>/dev/null" 2>/dev/null)

if [[ -n "$SELINUX_STATUS" ]]; then
    echo "  SELinux: $SELINUX_STATUS"
    
    if [[ "$SELINUX_STATUS" == "Enforcing" ]]; then
        echo -e "${YELLOW}[INFO]${NC} SELinux esta ativo (pode causar problemas)"
        echo ""
        echo "  Se o problema persistir, tenta:"
        echo "  1. Corrigir contextos:"
        echo "     restorecon -Rv ${WEBROOT_REMOTE}"
        echo ""
        echo "  2. OU desativar temporariamente:"
        echo "     setenforce 0"
        echo ""
    else
        echo -e "${GREEN}[OK]${NC} SELinux nao esta a bloquear"
    fi
else
    echo -e "${GREEN}[OK]${NC} SELinux nao instalado ou desativo"
fi

echo ""

# ============================================================
# TESTE CRITICO 5: Teste de escrita no destino local
# ============================================================
echo "============================================================"
echo "TESTE 5: PERMISSOES LOCAIS DE ESCRITA"
echo "============================================================"
echo ""

TEST_DIR="/backup/web/incremental/current"
mkdir -p "$TEST_DIR" 2>/dev/null

if touch "${TEST_DIR}/test_write_$$" 2>/dev/null; then
    echo -e "${GREEN}[OK]${NC} Pode escrever em ${TEST_DIR}"
    rm -f "${TEST_DIR}/test_write_$$"
else
    echo -e "${RED}[ERRO]${NC} NAO pode escrever em ${TEST_DIR}"
    echo ""
    echo "Solucao:"
    echo "  chmod 755 /backup"
    echo "  chmod -R 755 /backup/web"
    exit 1
fi

echo ""

# ============================================================
# TESTE CRITICO 6: Teste rsync VERBOSE
# ============================================================
echo "============================================================"
echo "TESTE 6: RSYNC VERBOSE (ver erro exato)"
echo "============================================================"
echo ""

echo "A executar rsync com output detalhado..."
echo "------------------------------------------------------------"

RSYNC_VERBOSE=$(rsync -avvvz --timeout=10 --dry-run \
    "${WEBSERVER_USER}@${WEBSERVER_IP}:${WEBROOT_REMOTE}/" \
    /tmp/test_backup_verbose_$$ 2>&1)
RSYNC_EXIT=$?

echo "$RSYNC_VERBOSE"
echo "------------------------------------------------------------"
echo ""

if [[ $RSYNC_EXIT -ne 0 ]]; then
    echo -e "${RED}[ERRO]${NC} Rsync falhou com codigo: $RSYNC_EXIT"
    echo ""
    
    # Analisar output para pistas
    if echo "$RSYNC_VERBOSE" | grep -qi "no space"; then
        echo -e "${YELLOW}>>> PROBLEMA: SEM ESPACO EM DISCO <<<${NC}"
        echo ""
        echo "Verifica:"
        echo "  df -h /backup"
        echo "  ssh ${WEBSERVER_USER}@${WEBSERVER_IP} \"df -h\""
        
    elif echo "$RSYNC_VERBOSE" | grep -qi "permission denied"; then
        echo -e "${YELLOW}>>> PROBLEMA: PERMISSOES <<<${NC}"
        echo ""
        echo "Verifica permissoes no WebServer:"
        echo "  ls -la ${WEBROOT_REMOTE}"
        
    elif echo "$RSYNC_VERBOSE" | grep -qi "connection reset\|broken pipe"; then
        echo -e "${YELLOW}>>> PROBLEMA: CONEXAO INSTAVEL <<<${NC}"
        echo ""
        echo "Tenta:"
        echo "  1. Verifica rede: ping -c 10 ${WEBSERVER_IP}"
        echo "  2. Reinicia SSH: systemctl restart sshd"
        
    elif echo "$RSYNC_VERBOSE" | grep -qi "timeout"; then
        echo -e "${YELLOW}>>> PROBLEMA: TIMEOUT <<<${NC}"
        echo ""
        echo "Servidor remoto muito lento ou travado"
        
    else
        echo "Nao foi possivel identificar o problema especifico"
        echo ""
        echo "Copia o output acima e analisa"
    fi
    
else
    echo -e "${GREEN}[OK]${NC} Rsync funcionou!"
fi

rm -rf /tmp/test_backup_verbose_$$ 2>/dev/null

echo ""

# ============================================================
# TESTE CRITICO 7: Logs do sistema remoto
# ============================================================
echo "============================================================"
echo "TESTE 7: LOGS DO WEBSERVER (ultimas linhas)"
echo "============================================================"
echo ""

echo "Logs de SSH no WebServer:"
echo "------------------------------------------------------------"
ssh -o BatchMode=yes "${WEBSERVER_USER}@${WEBSERVER_IP}" \
    "tail -20 /var/log/secure 2>/dev/null || tail -20 /var/log/auth.log 2>/dev/null" 2>/dev/null
echo "------------------------------------------------------------"
echo ""

# ============================================================
# RESUMO E RECOMENDACOES
# ============================================================
echo "============================================================"
echo "  RESUMO E PROXIMOS PASSOS"
echo "============================================================"
echo ""

if [[ $RSYNC_EXIT -eq 0 ]]; then
    echo -e "${GREEN}Todos os testes passaram!${NC}"
    echo ""
    echo "O problema pode ser intermitente ou ja foi resolvido."
    echo "Tenta fazer backup novamente pelo gestor."
else
    echo -e "${RED}Problema identificado!${NC}"
    echo ""
    echo "Revê os testes acima e segue as solucoes sugeridas."
    echo ""
    echo "Mais comum:"
    echo "  1. Disco cheio (95%+)"
    echo "  2. rsync nao instalado no WebServer"
    echo "  3. Permissoes incorretas"
fi

echo ""
echo "============================================================"
