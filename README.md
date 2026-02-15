# 🚀 Projeto Scripting & Backups - ATEC 2026

![ATEC Logo](https://github.com/user-attachments/assets/c7009993-50b2-4bdb-babf-bc21a35a6008)

## 📋 Índice

- [Sobre o Projeto](#sobre-o-projeto)
- [Características](#características)
- [Requisitos](#requisitos)
- [Instalação Rápida](#instalação-rápida)
- [Scripts Disponíveis](#scripts-disponíveis)
- [Documentação Detalhada](#documentação-detalhada)
- [Troubleshooting](#troubleshooting)
- [Licença](#licença)

---

## 📖 Sobre o Projeto

Sistema completo de **Backup Automático** e **Servidor Web** desenvolvido para o projeto de scripting da ATEC 2026. O projeto implementa:

- ✅ **Servidor Web** (Apache) com HTTPS (SSL/TLS)
- ✅ **Servidor de Backup** com RAID 10
- ✅ **Backups Incrementais** (ficheiros + bases de dados)
- ✅ **Segurança** (Fail2Ban + ModSecurity WAF)
- ✅ **Performance Tuning** (Apache + MySQL + Sistema)
- ✅ **Interface Gráfica** (dialog + versão retro-futurista)
- ✅ **Agendamento Automático** (cron)
- ✅ **Monitorização** e diagnóstico

---

## ✨ Características

### 🌐 WebServer

- **Apache HTTP Server** otimizado
- **HTTPS** com certificados SSL (Let's Encrypt)
- **DuckDNS** para IP dinâmico
- **ModSecurity** (Web Application Firewall)
- **Performance Tuning** automático

### 💾 BackupServer

- **RAID 10** para redundância
- **Backups incrementais** com rsync
- **Backup de bases de dados** (mysqldump)
- **Restauro automático**
- **Gestão de versões** (rotação de backups antigos)
- **Agendamento personalizável**

### 🔒 Segurança

- **Fail2Ban** - Proteção contra brute-force
- **ModSecurity** - Web Application Firewall
- **Firewall** (firewalld) configurado
- **SELinux** suportado
- **SSH** com autenticação por chave

### 🎨 Interface

- **Gestor Dialog** - Interface gráfica em texto
- **Gestor Retro** - Visual cyberpunk/neon
- **Scripts de Diagnóstico**
- **Gestão interativa** de Fail2Ban e ModSecurity

---

## 📦 Requisitos

### Hardware Mínimo

**WebServer:**
- 1 CPU core
- 1 GB RAM
- 20 GB disco

**BackupServer:**
- 2 CPU cores
- 2 GB RAM
- 4 discos para RAID 10 (mínimo 20GB cada)

### Software

- **SO:** Rocky Linux 9 / AlmaLinux 9 / RHEL 9
- **Rede:** IP fixo ou DuckDNS
- **Acesso:** root/sudo

---

## 🚀 Instalação Rápida

### 1️⃣ WebServer

```bash
# Download dos scripts
git clone https://github.com/seu-repo/projeto-backup-atec.git
cd projeto-backup-atec

# Executar instalação do WebServer
sudo bash Script_WebServer_Final.sh

# Configurar HTTPS (opcional mas recomendado)
bash Script_SSL.sh
```

### 2️⃣ BackupServer

```bash
# Executar instalação do BackupServer
sudo bash Script_BackupServer_INSTALACAO.sh

# Abrir gestor de backups
sudo bash /usr/local/sbin/backup-gestor.sh
```

### 3️⃣ Segurança e Otimizações (Opcional)

```bash
# Backup de bases de dados
sudo bash Script_BackupDB.sh

# Fail2Ban (proteção brute-force)
sudo bash Script_Fail2Ban.sh

# ModSecurity (WAF)
sudo bash Script_ModSecurity.sh

# Performance Tuning
sudo bash Script_Performance.sh
```

---

## 📜 Scripts Disponíveis

### 🌐 WebServer

| Script | Descrição |
|--------|-----------|
| `Script_WebServer_Final.sh` | Instalação completa do WebServer (Apache + PHP + MySQL) |
| `Script_SSL.sh` | Configuração HTTPS com Let's Encrypt via DuckDNS |

### 💾 BackupServer

| Script | Descrição |
|--------|-----------|
| `Script_BackupServer_INSTALACAO.sh` | Instalação completa (RAID + SSH + Backup) |
| `Script_BackupServer_GESTOR.sh` | Gestor gráfico (dialog) |
| `Script_BackupServer_GESTOR_RETRO.sh` | Gestor visual retro-futurista |
| `Script_BackupServer_GESTOR_v3.sh` | Gestor v3 com agendamentos |

### 🗄️ Bases de Dados

| Script | Descrição |
|--------|-----------|
| `Script_BackupDB.sh` | Configuração de backups MySQL/MariaDB |
| `/usr/local/sbin/backup-db.sh` | Script de backup automático (criado após instalação) |
| `/usr/local/sbin/restore-db.sh` | Script de restauro (criado após instalação) |

### 🔒 Segurança

| Script | Descrição |
|--------|-----------|
| `Script_Fail2Ban.sh` | Instalação e configuração do Fail2Ban |
| `Script_ModSecurity.sh` | Instalação e configuração do ModSecurity WAF |
| `/usr/local/sbin/fail2ban-manager.sh` | Gestor interativo Fail2Ban |
| `/usr/local/sbin/modsec-manager.sh` | Gestor interativo ModSecurity |

### ⚡ Performance

| Script | Descrição |
|--------|-----------|
| `Script_Performance.sh` | Otimização Apache + MySQL + Sistema |
| `/usr/local/sbin/benchmark.sh` | Teste de performance |
| `/usr/local/sbin/monitor.sh` | Monitorização em tempo real |

### 🔧 Diagnóstico

| Script | Descrição |
|--------|-----------|
| `Script_Diagnostico.sh` | Diagnóstico de problemas de backup |
| `diagnostico_backup.sh` | Diagnóstico completo de conexão |
| `diagnostico_aprofundado.sh` | Diagnóstico avançado (erro rsync) |
| `corrigir_backup.sh` | Correção automática de problemas |
| `corrigir_forcado.sh` | Correção forçada para erros persistentes |

---

## 📖 Documentação Detalhada

### 🌐 WebServer - Instalação

O `Script_WebServer_Final.sh` configura automaticamente:

1. **Rede**: IP fixo ou DHCP
2. **Apache**: Instalação e configuração básica
3. **PHP**: Versão mais recente
4. **MySQL/MariaDB**: Base de dados
5. **Firewall**: Portas 80/443/22 abertas
6. **SELinux**: Configurado corretamente
7. **Website**: Página de teste em `/var/www/html`

**Comandos pós-instalação:**

```bash
# Ver status Apache
sudo systemctl status httpd

# Ver logs Apache
sudo tail -f /var/log/httpd/error_log

# Testar configuração
sudo httpd -t

# Reiniciar Apache
sudo systemctl restart httpd
```

### 🔐 HTTPS com DuckDNS

O `Script_SSL.sh` configura HTTPS automaticamente:

1. Regista domínio no DuckDNS
2. Obtém certificado Let's Encrypt
3. Configura Apache para HTTPS
4. Redireciona HTTP→HTTPS automaticamente
5. Renova certificados automaticamente (cron)

**Comandos úteis:**

```bash
# Renovar certificado manualmente
~/.acme.sh/acme.sh --renew -d seu-dominio.duckdns.org

# Ver certificados instalados
~/.acme.sh/acme.sh --list

# Testar renovação
~/.acme.sh/acme.sh --renew -d seu-dominio.duckdns.org --force
```

### 💾 BackupServer - Estrutura

**Diretórios criados:**

```
/backup/
├── web/
│   └── incremental/
│       ├── current/              # Backup atual completo
│       ├── changed_YYYYMMDD/     # Versões incrementais
│       └── changed_YYYYMMDD/
├── db/
│   ├── YYYY-MM-DD/               # Backups de BD por data
│   └── logs/
└── logs/                         # Logs de backup
```

**RAID 10:**

- Combina **striping** (RAID 0) com **mirroring** (RAID 1)
- Requer **4 discos mínimo**
- Oferece redundância e performance
- Capacidade útil: 50% do total

**Comandos RAID:**

```bash
# Ver estado do RAID
sudo mdadm --detail /dev/md0

# Ver reconstrução (se houver)
cat /proc/mdstat

# Adicionar disco ao RAID (substituir falha)
sudo mdadm --add /dev/md0 /dev/sdX

# Parar RAID (cuidado!)
sudo mdadm --stop /dev/md0
```

### 📊 Gestor de Backups

**Opções disponíveis:**

1. **Ver Estado**: SSH, backups, RAID, disco
2. **Fazer Backup**: Manual imediato
3. **Listar Backups**: Versões disponíveis
4. **Ver Conteúdo**: Ficheiros no backup
5. **Restaurar**: Repor backup no WebServer
6. **Apagar Site**: Limpar WebServer
7. **Testar SSH**: Verificar conexão
8. **Ver Logs**: Histórico de backups
9. **Estado RAID**: Verificar discos
10. **Agendamentos**: Configurar backups automáticos

**Agendamentos disponíveis:**

- **Diário**: Todos os dias a uma hora específica
- **Semanal**: Num dia da semana
- **Periódico**: A cada X horas (1, 2, 3, 4, 6, 12h)
- **Mensal**: Dia específico do mês

### 🗄️ Backup de Bases de Dados

O `Script_BackupDB.sh` configura:

1. **mysqldump** com opções otimizadas
2. **Compressão** gzip
3. **Rotação** automática (30 dias)
4. **Agendamento** via cron
5. **Script de restauro**

**Comandos:**

```bash
# Backup manual
sudo bash /usr/local/sbin/backup-db.sh

# Restaurar backup
sudo bash /usr/local/sbin/restore-db.sh

# Ver backups disponíveis
ls -lh /backup/db/

# Testar backup (sem gravar)
mysqldump -h IP -u user -p --all-databases --dry-run
```

### 🛡️ Fail2Ban

Protege contra ataques de força bruta:

- **SSH**: 5 tentativas = ban 1h
- **Apache**: Auth, overflows, bots
- **HTTP DoS**: 300 requests/5min = ban
- **Personalizado**: SQL Injection, Path Traversal

**Comandos úteis:**

```bash
# Gestor interativo
sudo bash /usr/local/sbin/fail2ban-manager.sh

# Ver status
sudo fail2ban-client status

# Ver IPs banidos (SSH)
sudo fail2ban-client status sshd

# Desbanir IP
sudo fail2ban-client set sshd unbanip 192.168.1.100

# Banir IP manualmente
sudo fail2ban-client set sshd banip 192.168.1.100

# Ver logs
sudo journalctl -u fail2ban -f
```

### 🔥 ModSecurity (WAF)

Web Application Firewall que bloqueia:

- SQL Injection
- XSS (Cross-Site Scripting)
- Path Traversal
- RFI/LFI
- Shellshock
- E muitos outros...

**Níveis de proteção:**

1. **Detecção**: Apenas regista ataques
2. **Bloqueio**: Bloqueia ataques (recomendado)
3. **Paranoico**: Máxima proteção (pode gerar falsos positivos)

**Comandos:**

```bash
# Gestor interativo
sudo bash /usr/local/sbin/modsec-manager.sh

# Testar proteções
sudo bash /usr/local/sbin/modsec-test.sh

# Ver logs
sudo tail -f /var/log/modsecurity/modsec_audit.log

# Ativar modo detecção
sudo sed -i 's/SecRuleEngine .*/SecRuleEngine DetectionOnly/' /etc/httpd/conf.d/mod_security.conf
sudo systemctl restart httpd

# Ativar modo bloqueio
sudo sed -i 's/SecRuleEngine .*/SecRuleEngine On/' /etc/httpd/conf.d/mod_security.conf
sudo systemctl restart httpd
```

### ⚡ Performance Tuning

Otimiza automaticamente baseado nos recursos:

**Perfis:**

- **Low** (<1GB RAM): Configuração conservadora
- **Medium** (1-4GB RAM): Configuração balanceada
- **High** (>4GB RAM): Configuração agressiva

**Otimizações aplicadas:**

**Apache:**
- MPM Event/Worker
- KeepAlive otimizado
- Compressão (mod_deflate)
- Cache de ficheiros estáticos
- File descriptors aumentados

**MySQL:**
- InnoDB Buffer Pool ajustado
- Query Cache
- Conexões otimizadas
- Logs otimizados

**Sistema:**
- Kernel parameters (network, file descriptors)
- Swappiness reduzido
- Dirty pages ajustadas

**Comandos:**

```bash
# Benchmark
sudo bash /usr/local/sbin/benchmark.sh

# Monitor em tempo real
sudo bash /usr/local/sbin/monitor.sh

# Ver configuração Apache
httpd -S
httpd -M  # módulos carregados

# Ver variáveis MySQL
mysql -e "SHOW VARIABLES;"
mysql -e "SHOW STATUS;"
```

---

## 🔧 Troubleshooting

### Problema: Erro rsync código 12

**Sintoma:** Backup falha com "error in rsync protocol data stream (code 12)"

**Causas comuns:**
1. rsync não instalado no WebServer (80%)
2. Disco cheio (15%)
3. Permissões incorretas (5%)

**Solução:**

```bash
# No BackupServer, executar diagnóstico
sudo bash diagnostico_aprofundado.sh

# Ou correção automática
sudo bash corrigir_forcado.sh

# Instalação manual do rsync (no WebServer)
sudo dnf install -y rsync
```

### Problema: SSH não funciona sem senha

**Sintoma:** Pede password a cada backup

**Solução:**

```bash
# No BackupServer, reconfigurar chave SSH
sudo ssh-copy-id root@IP_DO_WEBSERVER

# Testar
ssh -o BatchMode=yes root@IP_DO_WEBSERVER "echo ok"
```

### Problema: Apache não inicia

**Sintoma:** `systemctl status httpd` mostra erro

**Soluções:**

```bash
# Ver erro exato
sudo journalctl -xe

# Testar configuração
sudo httpd -t

# Verificar portas em uso
sudo ss -tlnp | grep -E ':80|:443'

# Se porta 80 ocupada, matar processo
sudo kill $(sudo lsof -t -i:80)

# Reiniciar
sudo systemctl restart httpd
```

### Problema: Disco cheio no backup

**Solução:**

```bash
# Ver uso
df -h /backup

# Remover backups antigos (>30 dias)
sudo find /backup/web/incremental -name "changed_*" -mtime +30 -exec rm -rf {} \;

# Remover logs antigos (>90 dias)
sudo find /backup/logs -name "*.log" -mtime +90 -delete

# Ver o que ocupa mais espaço
sudo du -sh /backup/* | sort -h
```

### Problema: RAID degradado

**Sintoma:** `mdadm --detail /dev/md0` mostra disco em falha

**Solução:**

```bash
# Ver estado
cat /proc/mdstat

# Remover disco com falha
sudo mdadm --fail /dev/md0 /dev/sdX
sudo mdadm --remove /dev/md0 /dev/sdX

# Adicionar disco novo (mesmo tamanho!)
sudo mdadm --add /dev/md0 /dev/sdY

# Aguardar reconstrução (pode demorar horas)
watch -n 1 cat /proc/mdstat
```

### Problema: Fail2Ban não bloqueia

**Verificar:**

```bash
# Status geral
sudo fail2ban-client status

# Ver se jail está ativo
sudo fail2ban-client status sshd

# Ver logs
sudo journalctl -u fail2ban -f

# Reiniciar
sudo systemctl restart fail2ban
```

### Problema: ModSecurity bloqueando legítimos

**Solução:**

```bash
# Ativar modo detecção (não bloqueia)
sudo sed -i 's/SecRuleEngine .*/SecRuleEngine DetectionOnly/' /etc/httpd/conf.d/mod_security.conf
sudo systemctl restart httpd

# Ver o que foi bloqueado
sudo tail -100 /var/log/modsecurity/modsec_audit.log

# Adicionar exceção (exemplo)
echo 'SecRuleRemoveById 1001' >> /etc/httpd/modsecurity.d/whitelist.conf
sudo systemctl restart httpd
```

---

## 📁 Estrutura do Projeto

```
projeto-backup-atec/
├── README.md                              # Este ficheiro
├── Script_WebServer_Final.sh              # Instalação WebServer
├── Script_SSL.sh                          # Configuração HTTPS
├── Script_BackupServer_INSTALACAO.sh      # Instalação BackupServer
├── Script_BackupServer_GESTOR.sh          # Gestor dialog
├── Script_BackupServer_GESTOR_RETRO.sh    # Gestor retro
├── Script_BackupServer_GESTOR_v3.sh       # Gestor v3 com agendamentos
├── Script_BackupDB.sh                     # Backup bases de dados
├── Script_Fail2Ban.sh                     # Instalação Fail2Ban
├── Script_ModSecurity.sh                  # Instalação ModSecurity
├── Script_Performance.sh                  # Performance Tuning
├── Script_Diagnostico.sh                  # Diagnóstico problemas
├── diagnostico_backup.sh                  # Diagnóstico completo
├── diagnostico_aprofundado.sh             # Diagnóstico avançado
├── corrigir_backup.sh                     # Correção automática
├── corrigir_forcado.sh                    # Correção forçada
├── GUIA_RESOLUCAO_ERRO.txt               # Guia troubleshooting
├── ERRO_12_AVANCADO.txt                  # Guia erro rsync 12
├── NOVAS_FUNCIONALIDADES.txt             # Changelog
└── VISUAL_PREVIEW.txt                    # Preview visual retro
```

---

## 🎯 Checklist de Requisitos

### ✅ Requisitos Implementados

- [x] **RAID 10** - 4 discos configurados automaticamente
- [x] **IP Público/Rede** - Configuração automática + DuckDNS
- [x] **HTTPS (SSL)** - Let's Encrypt via DuckDNS
- [x] **Backup Ficheiros** - Rsync incremental
- [x] **Backup Base de Dados** - mysqldump automático
- [x] **Firewall** - firewalld configurado
- [x] **SELinux** - Suportado e configurado
- [x] **Fail2Ban** - Proteção brute-force
- [x] **ModSecurity** - Web Application Firewall
- [x] **Performance Tuning** - Apache + MySQL + Sistema
- [x] **Agendamento** - Cron com múltiplas opções
- [x] **Interface Gráfica** - Dialog + versão retro
- [x] **Diagnóstico** - Scripts completos de troubleshooting
- [x] **Documentação** - README completo

---

## 👥 Contribuir

Este é um projeto académico da ATEC 2026. Contribuições são bem-vindas!

**Como contribuir:**

1. Fork do repositório
2. Criar branch para feature (`git checkout -b feature/NovaFuncionalidade`)
3. Commit das alterações (`git commit -m 'Adiciona nova funcionalidade'`)
4. Push para branch (`git push origin feature/NovaFuncionalidade`)
5. Abrir Pull Request

---

## 📝 Licença

Este projeto é desenvolvido para fins educacionais na ATEC 2026.

---

## 📞 Suporte

**Problemas comuns:**
- Ver secção [Troubleshooting](#troubleshooting)
- Ler `GUIA_RESOLUCAO_ERRO.txt`
- Executar scripts de diagnóstico

**Logs importantes:**
- Apache: `/var/log/httpd/error_log`
- Backup: `/backup/logs/`
- MySQL: `/var/log/mariadb/mariadb.log`
- Fail2Ban: `journalctl -u fail2ban`
- ModSecurity: `/var/log/modsecurity/`

---

## 🙏 Agradecimentos

- **ATEC** - Academia de Formação
- **Rocky Linux / AlmaLinux** - Sistema operativo
- **Apache Foundation** - Servidor web
- **Let's Encrypt** - Certificados SSL gratuitos
- **OWASP** - ModSecurity Core Rule Set

---

<div align="center">

**Desenvolvido por estudantes ATEC 2026**

[![Made with Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f.svg)](https://www.gnu.org/software/bash/)
[![Rocky Linux](https://img.shields.io/badge/Rocky%20Linux-9-green.svg)](https://rockylinux.org/)
[![License](https://img.shields.io/badge/License-Educational-blue.svg)]()

</div>
