#!/bin/bash
# ============================================================
#  WEB SERVER (DMZ) - ATEC SYSTEM_CORE_2026
#  Configuração Interativa + Design Cyberpunk
# ============================================================

set -euo pipefail

# --- 0. VERIFICAÇÃO DE ROOT (Deve ser a primeira coisa) ---
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
    
    # Pedir Hostname
    read -p "Definir Hostname (Enter para 'webserver-atec'): " HOSTNAME_INPUT
    HOSTNAME_NEW="${HOSTNAME_INPUT:-webserver-atec}"
    
    # Listar interfaces
    echo -e "\n[INFO] Interfaces detetadas:"
    nmcli device status | grep -v "DEVICE"
    echo ""

    read -p "Nome da interface a configurar (ex: ens33): " IFACE
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
    
    # Tenta configurar a ligação existente ou cria uma nova se falhar
    nmcli con mod "Wired connection 1" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore 2>/dev/null || \
    nmcli con mod "$IFACE" ipv4.method manual ipv4.addresses "$IP_ADDR" ipv4.gateway "$GATEWAY" ipv4.dns "$DNS1" ipv6.method ignore
    
    # Reiniciar interface
    nmcli con down "$IFACE" 2>/dev/null || true
    nmcli con up "$IFACE" 2>/dev/null || nmcli con up "Wired connection 1"
    
    echo "[OK] Rede configurada."
}

# --- 1. EXECUTAR CONFIGURAÇÃO DE REDE ---
configurar_rede_interativa

# --- 2. CONFIGURAÇÃO DUCKDNS ---
echo -e "\n[INFO] A configurar DuckDNS para acesso externo..."

# Dados do utilizador
read -p "Introduza o seu Token do DuckDNS: " DUCK_TOKEN
DUCK_DOMAIN="webserver-atec"

# Criar o script de atualização
cat > /usr/local/sbin/duckdns_update.sh <<EOF
#!/bin/bash
echo url="https://www.duckdns.org/update?domains=${DUCK_DOMAIN}&token=${DUCK_TOKEN}&ip=" | curl -k -K -
EOF

chmod +x /usr/local/sbin/duckdns_update.sh

# Adicionar ao crontab para atualizar a cada 5 minutos
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/sbin/duckdns_update.sh >/dev/null 2>&1") | crontab -

echo "[OK] DuckDNS configurado. O domínio ${DUCK_DOMAIN}.duckdns.org será atualizado automaticamente."

# --- 3. INSTALAÇÃO DE SERVIÇOS (LAMP) ---
echo -e "\n[INFO] A instalar Apache, PHP e MariaDB..."
dnf -y update
dnf -y install httpd php php-mysqlnd mariadb-server firewalld rsync

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
    <title>ATEC // SYSTEM_CORE_2026</title>
    <link href="https://fonts.googleapis.com/css2?family=Orbitron:wght@400;700;900&family=VT323&display=swap" rel="stylesheet">
    <style>
        /* VARIÁVEIS DE CORES NEON */
        :root {
            --neon-pink: #ff2a6d;
            --neon-blue: #05d9e8;
            --neon-purple: #d100d1;
            --grid-bg: #01012b;
            --text-main: #e0e0e0;
        }

        /* RESET E BASE */
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            background-color: var(--grid-bg);
            color: var(--text-main);
            font-family: 'VT323', monospace;
            overflow-x: hidden;
            font-size: 1.2rem;
            line-height: 1.6;
        }

        /* EFEITO DE SCANLINE (CRT) */
        .scanlines {
            position: fixed;
            top: 0;
            left: 0;
            width: 100%;
            height: 100%;
            background: linear-gradient(
                to bottom,
                rgba(255, 255, 255, 0),
                rgba(255, 255, 255, 0) 50%,
                rgba(0, 0, 0, 0.2) 50%,
                rgba(0, 0, 0, 0.2)
            );
            background-size: 100% 4px;
            pointer-events: none;
            z-index: 1000;
            animation: scanline 0.2s linear infinite;
        }

        /* ANIMAÇÃO DO FUNDO EM GRELHA 3D */
        .grid-floor {
            position: fixed;
            bottom: 0;
            left: 0;
            width: 100%;
            height: 50vh;
            background: 
                linear-gradient(transparent 0%, var(--grid-bg) 100%),
                linear-gradient(90deg, rgba(5, 217, 232, 0.3) 1px, transparent 1px),
                linear-gradient(0deg, rgba(255, 42, 109, 0.3) 1px, transparent 1px);
            background-size: 100% 100%, 40px 40px, 40px 40px;
            transform: perspective(500px) rotateX(60deg) translateY(100px) scale(2);
            z-index: -1;
            animation: moveGrid 5s linear infinite;
        }

        /* HEADER */
        header {
            text-align: center;
            padding: 3rem 1rem;
            border-bottom: 2px solid var(--neon-pink);
            box-shadow: 0 0 20px var(--neon-pink);
        }

        h1 {
            font-family: 'Orbitron', sans-serif;
            font-size: 4rem;
            text-transform: uppercase;
            color: #fff;
            text-shadow: 
                0 0 5px #fff,
                0 0 10px #fff,
                0 0 20px var(--neon-blue),
                0 0 40px var(--neon-blue),
                0 0 80px var(--neon-blue);
            letter-spacing: 5px;
            margin-bottom: 0.5rem;
        }

        .subtitle {
            color: var(--neon-pink);
            font-size: 1.5rem;
            letter-spacing: 3px;
            text-transform: uppercase;
        }

        /* CONTEÚDO PRINCIPAL */
        main {
            max-width: 1000px;
            margin: 4rem auto;
            padding: 0 2rem;
            z-index: 10;
            position: relative;
        }

        .terminal-box {
            border: 1px solid var(--neon-blue);
            background: rgba(5, 217, 232, 0.05);
            padding: 2rem;
            margin-bottom: 3rem;
            box-shadow: 0 0 15px rgba(5, 217, 232, 0.2);
        }

        h2 {
            font-family: 'Orbitron', sans-serif;
            color: var(--neon-blue);
            border-bottom: 1px dashed var(--neon-blue);
            padding-bottom: 0.5rem;
            margin-bottom: 1.5rem;
        }

        /* GRELHA DE CURSOS */
        .courses-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
            gap: 2rem;
        }

        .card {
            border: 2px solid var(--neon-purple);
            padding: 1.5rem;
            background: rgba(13, 2, 33, 0.8);
            transition: all 0.3s ease;
            position: relative;
            overflow: hidden;
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 0 25px var(--neon-purple);
            background: rgba(209, 0, 209, 0.1);
        }

        .card h3 {
            color: var(--neon-pink);
            font-family: 'Orbitron', sans-serif;
            margin-bottom: 1rem;
        }

        .btn {
            display: inline-block;
            margin-top: 1rem;
            padding: 0.5rem 1.5rem;
            background: transparent;
            color: var(--neon-blue);
            border: 2px solid var(--neon-blue);
            text-decoration: none;
            font-weight: bold;
            text-transform: uppercase;
            letter-spacing: 2px;
            transition: 0.3s;
            cursor: pointer;
        }

        .btn:hover {
            background: var(--neon-blue);
            color: var(--grid-bg);
            box-shadow: 0 0 20px var(--neon-blue);
        }

        /* RODAPÉ */
        footer {
            text-align: center;
            padding: 2rem;
            color: var(--neon-purple);
            font-size: 1rem;
            margin-top: 4rem;
            border-top: 1px solid var(--neon-purple);
        }

        /* ANIMAÇÕES */
        @keyframes moveGrid {
            0% { background-position: 0 0, 0 0, 0 0; }
            100% { background-position: 0 100%, 0 40px, 0 40px; }
        }

        @keyframes scanline {
            0% { background-position: 0 0; }
            100% { background-position: 0 100%; }
        }

        /* PISCAR CURSOR */
        .blink {
            animation: blinker 1s linear infinite;
        }
        @keyframes blinker {
            50% { opacity: 0; }
        }
    </style>
</head>
<body>

    <div class="scanlines"></div>
    <div class="grid-floor"></div>

    <header>
        <h1>ATEC</h1>
        <div class="subtitle">ACADEMIA_DE_FORMAÇÃO // 2026</div>
    </header>

    <main>
        <section class="terminal-box">
            <p>> A INICIAR SISTEMA...</p>
            <p>> CARREGAR MÓDULOS DE CONHECIMENTO... [OK]</p>
            <p>> LIGAR AOS SERVIDORES DE PALMELA E MATOSINHOS... [OK]</p>
            <br>
            <p>BEM-VINDO, UTILIZADOR. O FUTURO DA TUA CARREIRA COMEÇA AQUI. PREPARA-TE PARA O UPLOAD DE COMPETÊNCIAS TÉCNICAS.<span class="blink">_</span></p>
        </section>

        <h2>// ÁREAS_DE_DADOS</h2>
        <div class="courses-grid">
            <div class="card">
                <h3>CIBERSEGURANÇA</h3>
                <p>Protege a rede neural. Aprende defesa cibernética, hacking ético e segurança de infraestruturas críticas.</p>
                <a href="#" class="btn">ACEDER ></a>
            </div>

            <div class="card">
                <h3>PROGRAMAÇÃO</h3>
                <p>Escreve o código do amanhã. Java, Python, C# e desenvolvimento Web Full-Stack para arquitetos digitais.</p>
                <a href="#" class="btn">ACEDER ></a>
            </div>

            <div class="card">
                <h3>MECATRÓNICA</h3>
                <p>Fusão de hardware e inteligência. Automação industrial, robótica e manutenção de sistemas complexos.</p>
                <a href="#" class="btn">ACEDER ></a>
            </div>
            
             <div class="card">
                <h3>REDES 5G</h3>
                <p>Conetividade de alta velocidade. Instalação e gestão de redes de nova geração.</p>
                <a href="#" class="btn">ACEDER ></a>
            </div>
        </div>
    </main>

    <footer>
        <p>COPYRIGHT © 2026 ATEC // TODOS OS SISTEMAS OPERACIONAIS</p>
        <p>PALMELA | MATOSINHOS | CASCAIS</p>
    </footer>

</body>
</html>
HTML

# Definir permissões e contexto SELinux
chown -R apache:apache "${WEBROOT}"
restorecon -Rv "${WEBROOT}"

# --- 6. ATIVAR SERVIÇOS E HARDENING (MARIADB) ---
echo "[INFO] A iniciar serviços e aplicar hardening total do MariaDB..."
systemctl enable --now httpd
systemctl enable --now mariadb

# CORREÇÃO: Sintaxe correta do 'read'
echo ""
echo "!!! ATENÇÃO: A próxima password será definida como ROOT da base de dados !!!"
read -s -p "Introduz a password para o root do MariaDB: " DB_ROOT_PASSWORD
echo ""

# Execução do Hardening Completo
mysql -u root <<SQL
-- 1. Definir password do root
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';

-- 2. Remover utilizadores anónimos
DELETE FROM mysql.user WHERE User='';

-- 3. Desativar login remoto do root
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- 4. Remover base de dados de teste
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- 5. Recarregar privilégios
FLUSH PRIVILEGES;
SQL

# CORREÇÃO: 'ok' substituído por 'echo'
echo "[OK] MariaDB configurado de acordo com os requisitos de segurança."

# --- 7. RESUMO FINAL ---
IP_FINAL=$(hostname -I | awk '{print $1}')
echo ""
echo "============================================================"
echo "   INSTALAÇÃO CONCLUÍDA - ATEC SYSTEM CORE"
echo "============================================================"
echo " > Website Online: http://${IP_FINAL}"
echo " > Hostname:       $(hostname)"
echo ""
echo " Certifique-se de configurar o Port Forwarding (Porta 80)"
echo " no router para o IP ${IP_FINAL}."
echo "============================================================"
