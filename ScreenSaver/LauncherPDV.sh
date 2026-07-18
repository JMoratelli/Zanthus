#!/bin/bash
#===============================================================================
# Script de instalação/configuração do ScreenSaver + geração do launcher.conf
# Autor original: @jjmoratelli, Jurandir Moratelli
#
# MUDANÇA DESTA VERSÃO:
#   - O instalador NÃO monta mais o PDVTouch.sh. Quem orquestra o boot do PDV
#     agora é o "Machadão Launcher Zanthus" (binário Go), que lê o launcher.conf.
#   - Este script apenas ALIMENTA o launcher.conf com os dados que variam por
#     caixa/filial (FILIAL, CAIXA, TIPO, BALANCA). O restante são valores fixos,
#     definidos na seção CONFIGURAÇÕES abaixo.
#   - O launcher.conf é gravado em /Zanthus/Zeus/pdvJava/launcher.conf.
#
# O CERNE (pacotes instalados, geração do atualizaSC<filial>.sh, reboot final)
# NÃO foi alterado.
#===============================================================================

LOGFILE="/tmp/instala_screensaver_$(date +%Y%m%d_%H%M%S).log"
touch "$LOGFILE"

# ---------------------------------------------------------------------------
# Funções de log/UI (mesmo padrão do instala_pdv.sh)
# ---------------------------------------------------------------------------
C_RESET="\e[0m"; C_GREEN="\e[32m"; C_YELLOW="\e[33m"; C_RED="\e[31m"; C_CYAN="\e[36m"; C_BOLD="\e[1m"

log_step()  { echo -e "\n${C_CYAN}${C_BOLD}▶ $1${C_RESET}"; }
log_ok()    { echo -e "  ${C_GREEN}✔${C_RESET} $1"; }
log_skip()  { echo -e "  ${C_YELLOW}↷${C_RESET} $1 ${C_YELLOW}(já aplicado, pulando)${C_RESET}"; }
log_fail()  { echo -e "  ${C_RED}✘${C_RESET} $1"; }
log_info()  { echo -e "  ${C_CYAN}➜${C_RESET} $1"; }

run_silent() {
  local desc="$1"; shift
  { echo "### $desc ###"; "$@"; } >>"$LOGFILE" 2>&1
  if [ $? -eq 0 ]; then log_ok "$desc"; return 0; else log_fail "$desc (ver $LOGFILE)"; return 1; fi
}

safe_download() {
  local url="$1" dest="$2" tentativas="${3:-3}" tentativa=1
  mkdir -p "$(dirname "$dest")" 2>/dev/null
  while [ "$tentativa" -le "$tentativas" ]; do
    curl -sSfL -o "$dest" "$url" >>"$LOGFILE" 2>&1
    if [ -s "$dest" ]; then
      log_ok "Baixado: $(basename "$dest") ($tentativa/$tentativas)"
      return 0
    fi
    log_fail "Falha ao baixar $(basename "$dest") (tentativa $tentativa/$tentativas)"
    rm -f "$dest"
    tentativa=$((tentativa + 1))
    sleep 2
  done
  log_fail "Não foi possível baixar $(basename "$dest") após $tentativas tentativas - seguindo assim mesmo"
  return 1
}

pkg_instalado() { dpkg -s "$1" >/dev/null 2>&1; }

#===============================================================================
# CONFIGURAÇÕES
#===============================================================================
# URL de origem do vídeo do screensaver (usada pelo atualizaSC<filial>.sh).
SCREENSAVER_URL_BASE="http://serv-web/uploads/screensaver"   # + /<filial>/screensaver.mp4

# Onde o launcher.conf será gravado.
CONF_PATH="/Zanthus/Zeus/pdvJava/launcher.conf"

# ---------------------------------------------------------------------------
# Valores FIXOS gravados no launcher.conf (iguais para todos os caixas da loja).
# Só estes precisam ser ajustados quando a loja/rede muda - o restante
# (FILIAL/CAIXA/TIPO/BALANCA) é lido do disco automaticamente mais abaixo.
# ---------------------------------------------------------------------------
CONF_TELA_CLIENTE="false"
CONF_MIRAGE_IP="192.168.12.42"
CONF_BALANCE_IP="192.168.12.44"
CONF_GATEWAY_IP=""                     # vazio = launcher detecta o gateway
CONF_JANELA="kiosk"                    # kiosk (tela cheia, padrão) | janela
CONF_JANELA_POS="0,0"
CONF_JANELA_TAM="1024,768"
CONF_JANELA_POS_CLIENTE="1024,0"
CONF_JANELA_TAM_CLIENTE="1024,768"
CONF_DAEMONIZE="false"

log_step "Instalação do ScreenSaver / launcher.conf"
log_info "Não encerre o processo enquanto ele estiver rodando"

#===============================================================================
# 1. Atualização do sistema e pacotes
#===============================================================================
log_step "Atualizando lista de pacotes"
run_silent "apt-get update" sudo apt-get update -y

log_step "Instalando dependências (xscreensaver, restricted-extras, mpv)"
for pkg in xscreensaver ubuntu-restricted-extras mpv; do
  if pkg_instalado "$pkg"; then
    log_skip "Pacote $pkg"
  else
    run_silent "Instalando $pkg" sudo apt install -y -qq "$pkg"
  fi
done

#===============================================================================
# 2. Configuração do xscreensaver e DISPLAY
#===============================================================================
log_step "Aplicando configurações do xscreensaver"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/ScreenSaver/.xscreensaver" "/home/zanthus/.xscreensaver"

if ! grep -Fxq "export DISPLAY=:0" /etc/profile; then
  sudo echo "export DISPLAY=:0" >> /etc/profile
  log_ok "Linha 'export DISPLAY=:0' adicionada ao /etc/profile"
else
  log_skip "Linha 'export DISPLAY=:0' em /etc/profile"
fi

#===============================================================================
# 3. Leitura de variáveis em disco (Filial, Caixa, Tipo, Balança)
#===============================================================================
log_step "Lendo configuração local"
D="/home/zanthus/tmp/Script"
filial=$(basename "$D"/filial*.conf .conf 2>/dev/null | tr -dc '0-9')
caixa=$(basename "$D"/caixa*.conf .conf 2>/dev/null | tr -dc '0-9')

[ -f "$D/tipoConfComum.conf" ]  && tipoInstala="PDVComum"
[ -f "$D/tipoConfTouch.conf" ]  && tipoInstala="PDVTouch"
[ -f "$D/tipoConfSelf.conf" ]   && tipoInstala="SelfCheckout"
[ -f "$D/tipoConfLancho.conf" ] && tipoInstala="Lanchonete"

[ -f "$D/tipoBalancaToledo.conf" ]     && tipoBalanca="Toledo"
[ -f "$D/tipoBalancaToledoDual.conf" ] && tipoBalanca="ToledoDual"

log_info "Filial: ${filial:-ND} | Caixa: ${caixa:-ND} | Tipo: ${tipoInstala:-Desconhecido} | Balança: ${tipoBalanca:-Nenhuma}"

#===============================================================================
# 4. Geração do atualizaSC<filial>.sh (inalterado)
#===============================================================================
log_step "Gerando script atualizaSC${filial}.sh"

ATUALIZASC_PATH="/home/zanthus/atualizaSC${filial}.sh"

cat << EOF > "$ATUALIZASC_PATH"
#!/bin/bash
# Gerado automaticamente para a filial ${filial}
url_origem="${SCREENSAVER_URL_BASE}/${filial}/screensaver.mp4"
arquivo_destino="/home/zanthus/scsmachadao.mp4"

obter_tamanho() {
    local arquivo="\$1"
    local tamanho=\$(stat -c%s "\$arquivo" 2>/dev/null)
    if [ \$? -eq 0 ]; then
        echo "\$tamanho"
    else
        echo "0"
    fi
}

tamanho_origem=\$(curl -s -I "\$url_origem" | grep -oP 'Content-Length: \K\d+')
tamanho_destino=\$(obter_tamanho "\$arquivo_destino")

tamanho_origem_num=\$(echo "\$tamanho_origem" | grep -Eo '[0-9]+')
tamanho_destino_num=\$(echo "\$tamanho_destino" | grep -Eo '[0-9]+')

if [ "\$tamanho_origem_num" != "\$tamanho_destino_num" ]; then
    wget -q "\$url_origem" -O "\$arquivo_destino"
    echo "Download realizado com sucesso!"
else
    echo "Os arquivos possuem o mesmo tamanho. Download não realizado."
fi

sudo journalctl --vacuum-size=200M
EOF

chmod +x "$ATUALIZASC_PATH"
log_ok "atualizaSC${filial}.sh gerado em $ATUALIZASC_PATH"

log_info "Executando atualizaSC${filial}.sh pela primeira vez"
run_silent "atualizaSC${filial}.sh" "$ATUALIZASC_PATH"

log_step "Preparando AtualizaInterface.sh"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/AtualizaInterface.sh" "/home/zanthus/AtualizaInterface.sh"
chmod +x /home/zanthus/AtualizaInterface.sh

#===============================================================================
# 5. Geração do launcher.conf
#    Antes este bloco montava o PDVTouch.sh (com variantes por tipo/balança).
#    Agora o launcher (binário Go) lê o launcher.conf e faz toda a orquestração
#    (chromium, xinput, periféricos, xscreensaver, atualizaSC). Aqui só gravamos
#    os campos que variam por caixa; os fixos vêm das constantes CONF_* do topo.
#===============================================================================
log_step "Gerando launcher.conf para o tipo: ${tipoInstala:-Desconhecido}"

# Normaliza a balança para o vocabulário do launcher (vazio -> Nenhuma)
balancaConf="${tipoBalanca:-Nenhuma}"
geradoEm="$(date '+%Y-%m-%d %H:%M:%S')"

if [ -z "$tipoInstala" ]; then
    log_fail "Tipo de instalação desconhecido (${tipoInstala:-vazio}) - launcher.conf não será gerado"
else
    mkdir -p "$(dirname "$CONF_PATH")"
    cat << EOF > "$CONF_PATH"
# launcher.conf — Machadão Launcher Zanthus (${tipoInstala})
#
# Gerado automaticamente pelo instalador em ${geradoEm}.
# NÃO editar à mão: rode o instalador de novo para regenerar.
#
# COMO ADICIONAR UMA FLAG NOVA:
#   escreva CHAVE=VALOR aqui e leia no código com
#   cfg.Str("CHAVE") / cfg.Bool("CHAVE") / cfg.Int("CHAVE", default).
FILIAL=${filial}
CAIXA=${caixa}
TIPO=${tipoInstala}          # PDVComum | PDVTouch | SelfCheckout | Lanchonete
BALANCA=${balancaConf}        # Toledo | ToledoDual | Nenhuma  (só afeta PDVTouch)
TELA_CLIENTE=${CONF_TELA_CLIENTE}
# --- Rede / connection manager (bolinhas verde/vermelho no cabeçalho) ---
MIRAGE_IP=${CONF_MIRAGE_IP}
BALANCE_IP=${CONF_BALANCE_IP}
GATEWAY_IP=${CONF_GATEWAY_IP}            # vazio = detecta o gateway automaticamente
# --- Janela do chromium do PDV ---
JANELA=${CONF_JANELA}               # kiosk (tela cheia, padrão) | janela
JANELA_POS=${CONF_JANELA_POS}
JANELA_TAM=${CONF_JANELA_TAM}
JANELA_POS_CLIENTE=${CONF_JANELA_POS_CLIENTE}
JANELA_TAM_CLIENTE=${CONF_JANELA_TAM_CLIENTE}
# --- Esconder o terminal que abre o launcher ---
# true = relança destacado e encerra a instância do terminal. Só resolve se o
# terminal fechar ao fim do comando (xterm -e, .desktop Terminal=true).
DAEMONIZE=${CONF_DAEMONIZE}
# --- Caminhos (default; descomente só se mudar) ---
# PDV_PATH=/Zanthus/Zeus/pdvJava
# INTERFACE_PATH=/Zanthus/Zeus/Interface
# HOME_ZANTHUS=/home/zanthus
EOF
    chmod 644 "$CONF_PATH"
    log_ok "launcher.conf gerado em $CONF_PATH"
    log_info "Filial ${filial:-ND} | Caixa ${caixa:-ND} | ${tipoInstala} | Balança ${balancaConf}"
fi

#===============================================================================
# 6. Finalização e reboot
#===============================================================================
log_step "Concluindo"
log_ok "Script finalizado - aguardando contagem regressiva para reiniciar"
log_info "Script feito por @jjmoratelli, Jurandir Moratelli"
sleep 5
for i in {1..10}; do
  echo -e "  ${C_YELLOW}Contagem regressiva: $((10 - i))${C_RESET}"
  sleep 1
done

log_step "Reiniciando"
sudo reboot
