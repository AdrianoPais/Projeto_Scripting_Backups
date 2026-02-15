#!/bin/bash
# ============================================================
#  WEB SERVER (DMZ) - ATEC SYSTEM_CORE_2026
#  Configuração Interativa + Design Cyberpunk
# ============================================================

set -euo pipefail

# --- 0. VERIFICAÇÃO DE ROOT ---
if [[ "$(id -u)" -ne 0 ]]; then
    echo "ERRO: Este script tem de ser corrido como root (sudo)."
    exit 1
fi

# --- FUNÇÃO DE CONFIGURAÇÃO DE REDE ---
configurar_rede_interativa() {
    clear
    echo "============================================================"
    echo "   ATEC // SYSTEM_CORE_2026 - CONFIGURAÇÃO DE REDE"
    echo "============================================================"
    
    read -p "Definir Hostname (Enter para 'webserver-atec'): " HOSTNAME_INPUT
    HOSTNAME_NEW="${HOSTNAME_INPUT:-webserver-atec}"
    
    echo -e "\n[INFO] Interfaces detetadas:"
    nmcli device status | grep -v "DEVICE"
    echo ""

    read -p "Nome da interface a configurar (ex: enp0s3): " IFACE
    read -p "Endereço IP (ex: 192.168.1.100/24): " IP_ADDR
    read -p "Gateway (IP do Router): " GATEWAY
    read -p "DNS Primário (ex: 1.1.1.1): " DNS1
    
    echo -e "\n------------------------------------------------------------"
    echo "Vou aplicar:"
    echo " > Hostname: $HOSTNAME_NEW"
    echo " > Interface: $IFACE"
    echo " > IP: $IP_ADDR"
    echo " > Gateway: $GATEWAY"
    echo " > DNS: $DNS1"
    echo "------------------------------------------------------------"
    
    read -p "Confirmar? (s/n): " confirmar
    if [[ "$confirmar" != "s" ]]; then
        echo "Cancelado pelo utilizador."
        exit 1
    fi

    echo -e "\n[INFO] A aplicar configurações de rede..."
    hostnamectl set-hostname "$HOSTNAME_NEW"
    
    nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore 2>/dev/null || \
    nmcli con mod "$IFACE" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore
    
    nmcli con down "$IFACE" 2>/dev/null || true
    nmcli con up "$IFACE" 2>/dev/null || nmcli con up "Wired connection 1"
    
    echo "[OK] Rede configurada."
}

# --- 1. EXECUTAR CONFIGURAÇÃO DE REDE ---
configurar_rede_interativa

# --- 2. CONFIGURAÇÃO DUCKDNS ---
echo -e "\n[INFO] A configurar DuckDNS para acesso externo..."
DUCK_TOKEN="4d97ee77-41b5-4f2d-a9e1-b305a7e9a61a"
DUCK_DOMAIN="webserver-atec"

cat > /usr/local/sbin/duckdns_update.sh <<EOF
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=${DUCK_DOMAIN}&token=${DUCK_TOKEN}&ip=" | curl -k -K -
EOF

chmod 700 /usr/local/sbin/duckdns_update.sh
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/sbin/duckdns_update.sh >/dev/null 2>&1") | crontab -
echo "[OK] DuckDNS configurado."

# --- 3. INSTALAÇÃO DE SERVIÇOS (LAMP + SEGURANÇA) ---
echo -e "\n[INFO] A instalar Apache, PHP, MariaDB e Ferramentas de Segurança..."
dnf -y install epel-release
dnf -y update
dnf -y install httpd php php-mysqlnd mariadb-server firewalld rsync \
    fail2ban fail2ban-firewalld mod_security mod_security_crs

# --- 4. CONFIGURAÇÃO FIREWALL (DMZ) ---
echo "[INFO] A configurar Firewall..."
systemctl enable --now firewalld
firewall-cmd --permanent --add-service={http,https,ssh}
firewall-cmd --reload

# --- 5. IMPLEMENTAÇÃO DO SITE CYBERPUNK ---
echo "[INFO] A criar interface ATEC SYSTEM_CORE..."
WEBROOT="/var/www/html"
mkdir -p "$WEBROOT"

cat > "${WEBROOT}/index.html" <<'HTML'
<!DOCTYPE html>
<html lang="pt-pt">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>ATEC // NEON_CORE_2026</title>
    <link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@400;900&family=Mr+Dafoe&family=VT323&display=swap" rel="stylesheet">
    <style>
        :root {
            --bg-color: #050011;
            --neon-pink: #ff0055;
            --neon-magenta: #d600ff;
            --neon-cyan: #00f2ff;
            --grid-line: rgba(255, 0, 85, 0.2);
            --card-bg: rgba(10, 10, 10, 0.8);
        }

        * { margin: 0; padding: 0; box-sizing: border-box; }

        body {
            background-color: var(--bg-color);
            color: #fff;
            font-family: 'VT323', monospace;
            overflow-x: hidden;
            font-size: 1.3rem;
        }

        /* --- FUNDO E GRELHA --- */
        .retro-landscape {
            position: fixed;
            top: 0; left: 0; width: 100%; height: 100%;
            z-index: -2;
            background: linear-gradient(to bottom, #020005 0%, #1a001a 100%);
        }

        .grid {
            position: fixed;
            bottom: -30%; left: -50%; width: 200%; height: 100%;
            background-image: 
                linear-gradient(0deg, transparent 24%, var(--grid-line) 25%, var(--grid-line) 26%, transparent 27%, transparent 74%, var(--grid-line) 75%, var(--grid-line) 76%, transparent 77%, transparent),
                linear-gradient(90deg, transparent 24%, var(--grid-line) 25%, var(--grid-line) 26%, transparent 27%, transparent 74%, var(--grid-line) 75%, var(--grid-line) 76%, transparent 77%, transparent);
            background-size: 50px 50px;
            transform: perspective(300px) rotateX(60deg);
            animation: moveGrid 4s linear infinite;
            z-index: -1;
            box-shadow: 0 0 50px var(--neon-pink);
        }

        .scanlines {
            position: fixed;
            top: 0; left: 0; width: 100%; height: 100%;
            background: linear-gradient(rgba(18, 16, 16, 0) 50%, rgba(0, 0, 0, 0.25) 50%);
            background-size: 100% 4px;
            pointer-events: none;
            z-index: 999;
            opacity: 0.4;
        }

        /* --- HEADER --- */
        header {
            min-height: 90vh;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            text-align: center;
            position: relative;
        }

        /* A TUA IMAGEM (LOGÓTIPO) */
        .cyber-logo {
            width: 180px;
            height: auto;
            filter: drop-shadow(0 0 25px var(--neon-cyan)) drop-shadow(0 0 10px var(--neon-magenta));
            animation: floatAndSpin 8s ease-in-out infinite;
            margin-bottom: 2rem;
        }

        h1 {
            font-family: 'Orbitron', sans-serif;
            font-size: clamp(4rem, 10vw, 8rem);
            font-weight: 900;
            color: #fff;
            text-transform: uppercase;
            letter-spacing: 5px;
            text-shadow: 4px 4px 0px var(--neon-pink), -2px -2px 0px var(--neon-cyan);
            animation: glitch 3s infinite;
            line-height: 1;
        }

        .subtitle {
            font-family: 'Mr Dafoe', cursive;
            font-size: 2.5rem;
            color: var(--neon-cyan);
            text-shadow: 0 0 15px var(--neon-cyan);
            transform: rotate(-5deg) translateY(-10px);
            margin-bottom: 3rem;
        }

        /* --- CONTEÚDO (SOBRE A ATEC) --- */
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 2rem;
            position: relative;
            z-index: 10;
        }

        .info-panel {
            border: 2px solid var(--neon-cyan);
            background: rgba(0, 10, 20, 0.8);
            padding: 2rem;
            margin-bottom: 4rem;
            box-shadow: 0 0 20px rgba(0, 242, 255, 0.2);
            position: relative;
        }

        .info-panel::before {
            content: "SYSTEM_INFO // READ_ONLY";
            position: absolute;
            top: -15px; left: 20px;
            background: var(--bg-color);
            padding: 0 10px;
            color: var(--neon-cyan);
            font-family: 'Orbitron', sans-serif;
            font-size: 0.9rem;
        }

        p.description {
            font-size: 1.4rem;
            line-height: 1.6;
            color: #eee;
            text-align: justify;
        }

        .highlight { color: var(--neon-pink); font-weight: bold; }

        /* --- CARTÕES DE CURSOS --- */
        .section-title {
            color: var(--neon-magenta);
            font-family: 'Orbitron', sans-serif;
            font-size: 2.5rem;
            border-bottom: 3px solid var(--neon-pink);
            display: inline-block;
            margin-bottom: 3rem;
            text-shadow: 0 0 10px var(--neon-magenta);
        }

        .cards-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
            gap: 2rem;
        }

        .cyber-card {
            background: var(--card-bg);
            border: 1px solid var(--neon-pink);
            padding: 2rem;
            transition: 0.3s;
            position: relative;
            overflow: hidden;
        }

        .cyber-card::after {
            content: "";
            position: absolute;
            top: 0; left: 0; width: 100%; height: 5px;
            background: var(--neon-cyan);
            box-shadow: 0 0 15px var(--neon-cyan);
        }

        .cyber-card:hover {
            transform: translateY(-10px);
            box-shadow: 0 0 30px var(--neon-pink);
            border-color: var(--neon-cyan);
        }

        .cyber-card h3 {
            font-family: 'Orbitron', sans-serif;
            color: var(--neon-cyan);
            font-size: 1.6rem;
            margin-bottom: 1rem;
        }

        .cyber-card ul {
            list-style: none;
            margin-top: 1rem;
        }

        .cyber-card li {
            margin-bottom: 0.5rem;
            padding-left: 1.5rem;
            position: relative;
        }

        .cyber-card li::before {
            content: ">";
            position: absolute;
            left: 0;
            color: var(--neon-pink);
        }

        /* --- LOCALIZAÇÕES --- */
        .locations {
            display: flex;
            justify-content: space-around;
            margin-top: 5rem;
            flex-wrap: wrap;
            gap: 2rem;
        }

        .node {
            text-align: center;
            border: 1px dashed var(--neon-magenta);
            padding: 1.5rem 3rem;
            border-radius: 50px;
            background: rgba(255, 0, 85, 0.05);
        }

        .node h4 {
            color: var(--neon-pink);
            font-size: 1.8rem;
            font-family: 'Orbitron', sans-serif;
        }

        /* --- FOOTER --- */
        footer {
            text-align: center;
            padding: 3rem;
            margin-top: 4rem;
            border-top: 1px solid #333;
            color: #666;
        }

        /* --- ANIMAÇÕES --- */
        @keyframes moveGrid {
            0% { transform: perspective(300px) rotateX(60deg) translateY(0); }
            100% { transform: perspective(300px) rotateX(60deg) translateY(50px); }
        }

        @keyframes floatAndSpin {
            0% { transform: translateY(0) rotate(0deg); }
            50% { transform: translateY(-15px) rotate(180deg); }
            100% { transform: translateY(0) rotate(360deg); }
        }

        @keyframes glitch {
            0% { text-shadow: 4px 4px 0 var(--neon-pink), -2px -2px 0 var(--neon-cyan); }
            2% { text-shadow: -4px 4px 0 var(--neon-pink), 2px -2px 0 var(--neon-cyan); }
            100% { text-shadow: 4px 4px 0 var(--neon-pink), -2px -2px 0 var(--neon-cyan); }
        }
    </style>
</head>
<body>

    <div class="scanlines"></div>
    <div class="retro-landscape">
        <div class="grid"></div>
    </div>

    <header>
        <img src="images-removebg-preview.ico" alt="ATEC CORE" class="cyber-logo">
        
        <h1>ATEC</h1>
        <div class="subtitle">Academia do Futuro</div>
    </header>

    <div class="container">
        
        <div class="info-panel">
            <p class="description">
                A <span class="highlight">ATEC</span> é o núcleo central de processamento de talento técnico. 
                Dedicada ao desenvolvimento de hardware humano, convertemos utilizadores comuns em 
                <span class="highlight">Especialistas de Sistema</span>.
                <br><br>
                Com infraestruturas de última geração, operamos na fronteira entre a teoria e a prática, 
                garantindo que o código da tua carreira está otimizado para o mercado global.
            </p>
        </div>

        <h2 class="section-title">>> MÓDULOS DE DADOS</h2>
        
        <div class="cards-grid">
            <div class="cyber-card">
                <h3>CIBERSEGURANÇA</h3>
                <p style="color: #aaa;">NÍVEL 5 // TESP</p>
                <ul>
                    <li>Ethical Hacking</li>
                    <li>Criptografia de Dados</li>
                    <li>Defesa de Redes</li>
                    <li>Análise Forense</li>
                </ul>
            </div>

            <div class="cyber-card">
                <h3>PROGRAMAÇÃO</h3>
                <p style="color: #aaa;">NÍVEL 5 // TESP</p>
                <ul>
                    <li>Java & Python</li>
                    <li>Web Development</li>
                    <li>Base de Dados SQL</li>
                    <li>Inteligência Artificial</li>
                </ul>
            </div>

            <div class="cyber-card">
                <h3>MECATRÓNICA</h3>
                <p style="color: #aaa;">NÍVEL 4 // APRENDIZAGEM</p>
                <ul>
                    <li>Robótica Industrial</li>
                    <li>Automação (PLC)</li>
                    <li>Eletrónica Digital</li>
                    <li>Manutenção 4.0</li>
                </ul>
            </div>

             <div class="cyber-card">
                <h3>REDES 5G</h3>
                <p style="color: #aaa;">ESPECIALIZAÇÃO</p>
                <ul>
                    <li>Infraestruturas Cloud</li>
                    <li>Virtualização</li>
                    <li>IoT (Internet of Things)</li>
                    <li>Routing & Switching</li>
                </ul>
            </div>
        </div>

        <div class="locations">
            <div class="node">
                <h4>PALMELA</h4>
                <p style="color: var(--neon-cyan)">SERVER_01 // HQ</p>
            </div>
            <div class="node">
                <h4>MATOSINHOS</h4>
                <p style="color: var(--neon-cyan)">SERVER_02 // NORTH</p>
            </div>
        </div>

    </div>

    <footer>
        <p>COPYRIGHT © 2026 ATEC // SISTEMA OPERATIVO SEGURO</p>
    </footer>

</body>
</html>
HTML

chown -R apache:apache "${WEBROOT}"
restorecon -Rv "${WEBROOT}"

# --- 6. INTEGRACAO: PERFORMANCE TUNING ---
echo "[INFO] A aplicar Performance Tuning (Apache/MySQL/System)..."

# Apache Performance
cat > /etc/httpd/conf.d/performance.conf <<PERFCONF
Timeout 60
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5
<IfModule mpm_event_module>
    StartServers             5
    MinSpareThreads          5
    MaxSpareThreads          10
    ThreadsPerChild          25
    MaxRequestWorkers        150
    MaxConnectionsPerChild   1000
</IfModule>
<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css application/javascript application/json
</IfModule>
PERFCONF

# Kernel Performance
cat >> /etc/sysctl.conf <<SYSCTLCONF
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096
fs.file-max = 65536
vm.swappiness = 10
SYSCTLCONF
sysctl -p &>/dev/null || true

# --- 7. INTEGRACAO: FAIL2BAN ---
echo "[INFO] A configurar Fail2Ban..."
cat > /etc/fail2ban/jail.local <<F2BCONF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = systemd
banaction = firewallcmd-ipset
[sshd]
enabled = true
[apache-auth]
enabled = true
[apache-badbots]
enabled = true
[apache-noscript]
enabled = true
F2BCONF

# --- 8. INTEGRACAO: MODSECURITY (WAF) ---
echo "[INFO] A configurar ModSecurity..."
cp /etc/httpd/conf.d/mod_security.conf /etc/httpd/conf.d/mod_security.conf.orig 2>/dev/null || true
sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/httpd/conf.d/mod_security.conf 2>/dev/null || true
# Copiar configuração CRS se existir
if [[ -f /usr/share/mod_modsecurity_crs/crs-setup.conf.example ]]; then
    cp /usr/share/mod_modsecurity_crs/crs-setup.conf.example /usr/share/mod_modsecurity_crs/crs-setup.conf
fi

# --- 9. ATIVAR SERVIÇOS E HARDENING (MARIADB) ---
echo "[INFO] A iniciar serviços e aplicar hardening total..."
systemctl enable --now httpd
systemctl enable --now mariadb
systemctl enable --now fail2ban

echo ""
echo "!!! ATENÇÃO: A próxima password será definida como ROOT da base de dados !!!"
read -s -p "Introduz a password para o root do MariaDB: " DB_ROOT_PASSWORD
echo ""

# Hardening MySQL e Tuning básico (Performance)
mysql -u root <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
SET GLOBAL max_connections = 150;
SET GLOBAL innodb_buffer_pool_size = 512 * 1024 * 1024;
SQL

# Criar configuração permanente do MySQL para Performance
cat > /etc/my.cnf.d/performance.cnf <<MYSQLCONF
[mysqld]
max_connections = 150
innodb_buffer_pool_size = 512M
innodb_flush_log_at_trx_commit = 2
innodb_file_per_table = 1
query_cache_type = 0
query_cache_size = 0
MYSQLCONF

systemctl restart mariadb
systemctl restart httpd

# --- 10. RESUMO FINAL ---
IP_FINAL=$(hostname -I | awk '{print $1}')
echo ""
echo "============================================================"
echo "   INSTALAÇÃO CONCLUÍDA - ATEC SYSTEM CORE"
echo "============================================================"
echo " > Website Online: http://${IP_FINAL}"
echo " > Hostname:       $(hostname)"
echo ""
echo "  MÓDULOS ATIVOS:"
echo "  [OK] Performance Tuning (Apache/Kernel/MySQL)"
echo "  [OK] Fail2Ban (Proteção Brute-force)"
echo "  [OK] ModSecurity (WAF)"
echo ""
echo "============================================================"
