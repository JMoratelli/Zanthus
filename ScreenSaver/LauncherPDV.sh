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
CONF_DAEMONIZE="true"

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

#===============================================================================
# 4.1 Download do launcher (só se o tamanho mudou)
#===============================================================================
# O launcher já existe (versão antiga). Só rebaixa se o tamanho do arquivo
# remoto for diferente do local - evita baixar ~17MB a cada execução.
# OBS: o GitHub raw responde em HTTP/2, então o header vem MINÚSCULO
# (content-length) - por isso o grep é case-insensitive (-i), diferente do
# atualizaSC que fala com o serv-web.
LAUNCHER_URL="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/PDVTouch.sh"
LAUNCHER_PATH="/Zanthus/Zeus/pdvJava/PDVTouch.sh"

log_step "Verificando launcher (PDVTouch.sh)"
tam_remoto=$(curl -sIL "$LAUNCHER_URL" | grep -ioP 'content-length:\s*\K[0-9]+' | tail -n1)
tam_local=$(stat -c%s "$LAUNCHER_PATH" 2>/dev/null)

# Garante valor numérico (remove não-dígitos; vazio -> 0)
tam_remoto=${tam_remoto//[^0-9]/}; tam_remoto=${tam_remoto:-0}
tam_local=${tam_local//[^0-9]/};   tam_local=${tam_local:-0}

if [ "$tam_remoto" -eq 0 ]; then
    log_fail "Não consegui obter o tamanho remoto do launcher - mantendo o atual"
elif [ "$tam_local" -eq "$tam_remoto" ]; then
    log_skip "Launcher já atualizado (${tam_local} bytes)"
else
    log_info "Tamanho difere (local: ${tam_local}B | remoto: ${tam_remoto}B) - baixando"
    rm -f /Zanthus/Zeus/pdvJava/PDVTouch.sh
    safe_download "$LAUNCHER_URL" "$LAUNCHER_PATH"
    chmod +x "$LAUNCHER_PATH"
fi
#===============================================================================
# 5. Geração do launcher.conf
#    O launcher (binário Go) lê este .conf e faz toda a orquestração no boot
#    (chromium, xinput, periféricos, xscreensaver, atualizaSC, resolução via
#    xrandr, gateway e caminhos - tudo automático). Aqui só gravamos os campos
#    que variam por caixa; os fixos vêm das constantes CONF_* do topo.
#    O .conf é gravado SEM comentários.
#===============================================================================
log_step "Gerando launcher.conf para o tipo: ${tipoInstala:-Desconhecido}"

# Normaliza a balança para o vocabulário do launcher (vazio -> Nenhuma)
balancaConf="${tipoBalanca:-Nenhuma}"

if [ -z "$tipoInstala" ]; then
    log_fail "Tipo de instalação desconhecido (${tipoInstala:-vazio}) - launcher.conf não será gerado"
else
    mkdir -p "$(dirname "$CONF_PATH")"
    cat << EOF > "$CONF_PATH"
FILIAL=${filial}
CAIXA=${caixa}
TIPO=${tipoInstala}
BALANCA=${balancaConf}
TELA_CLIENTE=${CONF_TELA_CLIENTE}
MIRAGE_IP=${CONF_MIRAGE_IP}
BALANCE_IP=${CONF_BALANCE_IP}
DAEMONIZE=${CONF_DAEMONIZE}
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
