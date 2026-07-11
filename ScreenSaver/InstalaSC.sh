#!/bin/bash
#===============================================================================
# Script de instalação/configuração do ScreenSaver + geração do PDVTouch.sh
# Autor original: @jjmoratelli, Jurandir Moratelli
# Refatorado: logging limpo, downloads seguros, geração unificada do
# PDVTouch.sh (uma única escrita, com config no topo) e geração inline do
# atualizaSC<filial>.sh (sem depender de download externo).
# O CERNE (pacotes instalados, comandos do PDVTouch.sh, lógica de balança,
# reboot final) NÃO foi alterado - apenas a forma de montar/relatar mudou.
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
# Única coisa que realmente varia entre filiais: a URL de origem do vídeo do
# screensaver (o restante do atualizaSC<filial>.sh e do PDVTouch.sh é fixo).
SCREENSAVER_URL_BASE="http://serv-web/uploads/screensaver"   # + /<filial>/screensaver.mp4

# Flags do chromium: uma única variável, igual para os 4 tipos de PDV. O
# --touch-events=enabled não atrapalha PDVs só-mouse (só habilita o
# navegador a tratar eventos de toque, não desliga o mouse), então ficou
# fixo para todos. Não inclui --user-data-dir aqui porque o PDVTouch.sh
# agora define um diretório fixo por janela (caixa/cliente) - ver Base_Fim.
CHROMIUM_FLAGS='--touch-events=enabled --disable-pinch --disable-gpu --disk-cache-dir=/tmp/chromium-cache --test-type --no-sandbox --kiosk --no-context-menu --disable-translate'

log_step "Instalação do ScreenSaver / PDVTouch"
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
# 4. Geração do atualizaSC<filial>.sh (antes era baixado do GitHub)
#    Usa a mesma lógica enviada para a filial 1, parametrizada pela variável
#    $filial já lida acima (a URL de origem segue o padrão .../screensaver/<filial>/...)
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
# 5. Geração do PDVTouch.sh
#    PDVTouchBase   = trecho fixo, igual para os 4 tipos de instalação.
#    PDVTouchVar_*  = pedaços que mudam de acordo com o tipo (e a balança).
#    No final, tudo é gravado de uma vez, em sequência, com um único
#    "cat << EOF > arquivo" - sem usar echo para montar o arquivo.
#===============================================================================
log_step "Montando PDVTouch.sh para o tipo: ${tipoInstala:-Desconhecido}"

# -------------------------------------------------------------------------
# 5.1 Flags por tipo de instalação - definem qual PDVTouchVar_* entra no arquivo
# -------------------------------------------------------------------------
#   INCLUI_XINPUT_DISABLE : desliga o touch da mesa ILITEK          (só PDVTouch)
#   PERIFERICOS_USB       : true/false - roda o nohup PerifericosUSB.sh no boot
#   INCLUI_XSCREENSAVER   : liga o xscreensaver do usuário zanthus  (todos, exceto SelfCheckout)
#   INCLUI_ATUALIZASC     : chama o atualizaSC<filial>.sh no boot   (todos, exceto SelfCheckout)
INCLUI_XINPUT_DISABLE=false
PERIFERICOS_USB=false
INCLUI_XSCREENSAVER=false
INCLUI_ATUALIZASC=false

case "$tipoInstala" in
    SelfCheckout)
        PERIFERICOS_USB=true
        ;;
    PDVTouch)
        INCLUI_XINPUT_DISABLE=true
        PERIFERICOS_USB=false   # ajustado abaixo conforme $tipoBalanca
        INCLUI_XSCREENSAVER=true
        INCLUI_ATUALIZASC=true
        ;;
    PDVComum)
        INCLUI_XSCREENSAVER=true
        INCLUI_ATUALIZASC=true
        ;;
    Lanchonete)
        PERIFERICOS_USB=true
        INCLUI_XSCREENSAVER=true
        INCLUI_ATUALIZASC=true
        ;;
    *)
        log_fail "Tipo de instalação desconhecido (${tipoInstala:-vazio}) - PDVTouch.sh não será gerado"
        ;;
esac

# Balança: só se aplica ao PDVTouch (equivalente ao sed que rodava depois da
# gravação no script original - aqui já decidimos antes de gravar o arquivo)
if [ "$tipoInstala" == "PDVTouch" ]; then
    if [ "$tipoBalanca" == "Toledo" ]; then
        PERIFERICOS_USB=true
    elif [ "$tipoBalanca" == "ToledoDual" ]; then
        PERIFERICOS_USB=false
        log_info "Balança ToledoDual: modelo não suportado, PerifericosUSB.sh permanece desativado"
    fi
fi

# -------------------------------------------------------------------------
# 5.2 PDVTouchVar_* - trechos que mudam de acordo com o tipo (ficam vazios
#     quando não se aplicam ao tipo atual; linhas em branco são limpas no final)
# -------------------------------------------------------------------------
PDVTouchVar_Xinput=""
if $INCLUI_XINPUT_DISABLE; then
    PDVTouchVar_Xinput=$(cat << 'EOF'
xinput list --id-only "ILITEK ILITEK-TP" | xargs -I{} xinput disable {}
EOF
)
fi

PDVTouchVar_Perifericos=""
$PERIFERICOS_USB && PDVTouchVar_Perifericos="nohup /home/zanthus/PerifericosUSB.sh &"

PDVTouchVar_Xscreensaver=""
if $INCLUI_XSCREENSAVER; then
    PDVTouchVar_Xscreensaver=$(cat << 'EOF'
sudo xhost +local:zanthus
sudo -u zanthus xscreensaver -no-splash &
EOF
)
fi

PDVTouchVar_AtualizaSC=""
if $INCLUI_ATUALIZASC; then
    PDVTouchVar_AtualizaSC=$(cat << EOF
chmod +x /home/zanthus/atualizaSC${filial}.sh && /home/zanthus/atualizaSC${filial}.sh
EOF
)
fi

# -------------------------------------------------------------------------
# 5.3 PDVTouchBase - trecho fixo, igual nos 4 tipos (definido por último,
#     depois de resolvidas todas as variantes acima). A linha do chromium
#     entrou aqui porque deixou de variar por tipo (flags únicas para todos).
# -------------------------------------------------------------------------
PDVTouchBase_Inicio=$(cat << 'EOF'
#! /bin/bash
/usr/bin/setxkbmap -layout br -variant abnt2 > /tmp/setxkbmap.log 2>&1
# Executa a atualização da interface
chmod +x /home/zanthus/AtualizaInterface.sh && /home/zanthus/AtualizaInterface.sh
EOF
)

PDVTouchBase_Fim=$(cat << EOF
set -e
set -u

# ==========================================
# CONFIGURAÇÕES
# ==========================================
# Mude para "true" se este caixa tiver o segundo monitor (tela do cliente)
HABILITAR_TELA_CLIENTE="false"
PDV_PATH="/Zanthus/Zeus/pdvJava"
INTERFACE_PATH="/Zanthus/Zeus/Interface"

# ==========================================
# LIMPEZA E PREPARAÇÃO DO AMBIENTE
# ==========================================
killall chromium-browser lnx_receb.xz64 2>/dev/null || true
sleep 2
killall -9 chromium-browser lnx_receb.xz64 2>/dev/null || true
rm -f "\$PDV_PATH/ZEUSPDV_EXEC.UNICO"
chmod -x /usr/local/bin/igraficaJava 2>/dev/null || true
chmod +x /usr/local/bin/dualmonitor_control-PDVJava

# LIMPEZA DE PERFIS TEMPORÁRIOS
# Apagar as pastas temporárias garante que o Chromium nunca exiba
# aquele balão chato de "Restaurar páginas?" após um desligamento forçado.
rm -rf /tmp/pdv_caixa /tmp/pdv_cliente

# ==========================================
# INICIALIZAÇÃO DO PDV
# ==========================================
nohup "\$PDV_PATH/pdvJava2" >/dev/null 2>&1 &
while ! pgrep -f "lnx_receb.xz64" >/dev/null; do
    sleep 1
done

# ==========================================
# ABERTURA E POSICIONAMENTO DIRETO DAS TELAS
# ==========================================
# A Interface principal sempre abre (Monitor 1)
setsid chromium-browser ${CHROMIUM_FLAGS} --user-data-dir="/tmp/pdv_caixa" --window-position=0,0 --app="file://\$INTERFACE_PATH/index.html" >/dev/null 2>&1 &

# A Interface do cliente só abre se a variável lá em cima estiver "true"
if [ "\$HABILITAR_TELA_CLIENTE" = "true" ]; then
    setsid chromium-browser ${CHROMIUM_FLAGS} --user-data-dir="/tmp/pdv_cliente" --window-position=1024,0 --app="file://\$INTERFACE_PATH/cliente.html" >/dev/null 2>&1 &
fi

# ==========================================
# MANTER O SCRIPT VIVO AMARRADO AO PDV
# ==========================================
tail --pid=\$(pgrep -f "lnx_receb.xz64" | head -n 1) -f /dev/null

EOF
)

# -------------------------------------------------------------------------
# 5.4 Grava tudo de uma vez, na sequência correta, no PDVTouch.sh
# -------------------------------------------------------------------------
if [ -n "$tipoInstala" ]; then
    cat << EOF > /Zanthus/Zeus/pdvJava/PDVTouch.sh
${PDVTouchBase_Inicio}
${PDVTouchVar_Xinput}
${PDVTouchVar_Perifericos}
${PDVTouchVar_Xscreensaver}
${PDVTouchVar_AtualizaSC}
${PDVTouchBase_Fim}
EOF
    # Remove linhas em branco deixadas pelos trechos que não se aplicam a este tipo
    sed -i '/^[[:space:]]*$/d' /Zanthus/Zeus/pdvJava/PDVTouch.sh
    chmod +x /Zanthus/Zeus/pdvJava/PDVTouch.sh
    log_ok "PDVTouch.sh gerado para ${tipoInstala} (PerifericosUSB: ${PERIFERICOS_USB})"
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
