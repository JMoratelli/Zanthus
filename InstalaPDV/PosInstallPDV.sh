#!/bin/bash
#===============================================================================
# Script de instalação/configuração PDV - Zanthus
# Autor original: @jjmoratelli, Jurandir Moratelli
# Refatorado: logging limpo, downloads seguros (com retry), idempotência
# e centralização de configurações por filial.
#===============================================================================
clear
LOGFILE="/tmp/instala_pdv_$(date +%Y%m%d_%H%M%S).log"
touch "$LOGFILE"

# ---------------------------------------------------------------------------
# Funções de log/UI
# ---------------------------------------------------------------------------
C_RESET="\e[0m"; C_GREEN="\e[32m"; C_YELLOW="\e[33m"; C_RED="\e[31m"; C_CYAN="\e[36m"; C_BOLD="\e[1m"

log_step()  { echo -e "\n${C_CYAN}${C_BOLD}▶ $1${C_RESET}"; }
log_ok()    { echo -e "  ${C_GREEN}✔${C_RESET} $1"; }
log_skip()  { echo -e "  ${C_YELLOW}↷${C_RESET} $1 ${C_YELLOW}(já aplicado, pulando)${C_RESET}"; }
log_fail()  { echo -e "  ${C_RED}✘${C_RESET} $1"; }
log_info()  { echo -e "  ${C_CYAN}➜${C_RESET} $1"; }

# Executa um comando silenciando a saída (vai só para o log), mostrando OK/FAIL
run_silent() {
  local desc="$1"; shift
  {
    echo "### $desc ###"
    "$@"
  } >>"$LOGFILE" 2>&1
  if [ $? -eq 0 ]; then
    log_ok "$desc"
    return 0
  else
    log_fail "$desc (ver detalhes em $LOGFILE)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Download seguro
# ---------------------------------------------------------------------------
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

safe_wget() {
  local url="$1" dest="$2" tentativas="${3:-3}" tentativa=1
  mkdir -p "$(dirname "$dest")" 2>/dev/null
  while [ "$tentativa" -le "$tentativas" ]; do
    wget -q -O "$dest" "$url" >>"$LOGFILE" 2>&1
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

#===============================================================================
# 1. Encerramento seguro dos processos PDV
#===============================================================================
log_step "Encerrando processos PDV com segurança"
pkill -9 pdvJava2 ; pkill -9 jav ; pkill -9 lnx
log_info "Aguardando encerramento do sistema PDV..."
sleep 10
pkill -9 chro
sleep 5
pkill -9 chro
log_ok "Processos encerrados"

#===============================================================================
# 2. Validação de execução como root
#===============================================================================
log_step "Validações iniciais"
if [[ "$EUID" -ne 0 ]]; then
  log_fail "Este script precisa ser executado como root. Tentando reexecutar via su..."
  su root -c "$0 $@"
  if [[ "$?" -ne 0 ]]; then
    log_fail "Falha ao fazer login como root. Verifique suas permissões e senha."
    exit 1
  fi
  exit $?
fi
log_ok "Script sendo executado como usuário root"

# Alerta visual para o operador
export DISPLAY=:0
zenity --progress --title="AVISO DO SISTEMA" --text="<span foreground='red' size='44pt'><b>    ATUALIZANDO PDV\n    AGUARDE REINÍCIO\n        NÃO DESLIGUE\n       O COMPUTADOR</b></span>" --pulsate --no-cancel --width=800 --height=300 &

#===============================================================================
# 3. Leitura de variáveis em disco (Filial, Caixa, Tipo de Instalação)
#===============================================================================
log_step "Lendo configuração local"
D="/home/zanthus/tmp/Script"
filial=$(basename "$D"/filial*.conf .conf 2>/dev/null | tr -dc '0-9')
caixa=$(basename "$D"/caixa*.conf .conf 2>/dev/null | tr -dc '0-9')

[ -f "$D/tipoConfComum.conf" ]  && tipoInstala="PDVComum"
[ -f "$D/tipoConfTouch.conf" ]  && tipoInstala="PDVTouch"
[ -f "$D/tipoConfSelf.conf" ]   && tipoInstala="SelfCheckout"
[ -f "$D/tipoConfLancho.conf" ] && tipoInstala="Lanchonete"

log_info "Filial: ${filial:-ND} | Caixa: ${caixa:-ND} | Tipo: ${tipoInstala:-Desconhecido}"

#===============================================================================
# 3.1 SETOR DE CONFIGURAÇÕES (Central de Variáveis por Filial)
#===============================================================================
# Variáveis Globais de Configuração
CONF_FUSO_HORARIO="America/Cuiaba"     # Valor Padrão
CONF_HORA_DOMINGO=21                   # Valor Padrão
CONF_EASYCASH_IP=""
CONF_IMPRESSORA_IP=""
CONF_IMPRESSORA_PPD=""
CONF_IMPRESSORA_URL=""
NOME_LOJA=""

carregar_config_filial() {
  local id_filial="$1"
  local base_ppd_url="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers"

  case $id_filial in
    1)
      NOME_LOJA="Centro"
      CONF_EASYCASH_IP="192.168.50.130"
      CONF_IMPRESSORA_IP="10.1.1.139"
      CONF_IMPRESSORA_PPD="Kyocera_ECOSYS_M3655idn.ppd"
      CONF_HORA_DOMINGO=18
      ;;
    3)
      NOME_LOJA="Bairro"
      CONF_EASYCASH_IP="192.168.50.2"
      CONF_IMPRESSORA_IP="192.168.11.94"
      CONF_IMPRESSORA_PPD="Kyocera_ECOSYS_MA5500ifx_.ppd"
      CONF_HORA_DOMINGO=18
      ;;
    9)
      NOME_LOJA="Matupá"
      CONF_EASYCASH_IP="192.168.51.194"
      CONF_IMPRESSORA_IP="192.168.4.24"
      CONF_IMPRESSORA_PPD="Kyocera_ECOSYS_M3655idn.ppd"
      CONF_HORA_DOMINGO=18
      ;;
    52)
      NOME_LOJA="Primavera do Leste"
      CONF_EASYCASH_IP="192.168.51.130"
      CONF_IMPRESSORA_IP="192.168.8.27"
      CONF_IMPRESSORA_PPD="Kyocera_ECOSYS_M3655idn.ppd"
      ;;
    53)
      NOME_LOJA="Alta Floresta"
      CONF_EASYCASH_IP="192.168.51.2"
      CONF_IMPRESSORA_IP="192.168.6.14"
      CONF_IMPRESSORA_PPD="Kyocera_ECOSYS_M3655idn.ppd"
      ;;
    57)
      NOME_LOJA="Confresa"
      CONF_EASYCASH_IP="192.168.51.66"
      CONF_IMPRESSORA_IP="192.168.57.125"
      CONF_IMPRESSORA_PPD="Kyocera_ECOSYS_MA5500ifx_.ppd"
      CONF_FUSO_HORARIO="America/Sao_Paulo" # Sobrescreve o padrão
      ;;
    58)
      NOME_LOJA="Lucas do Rio Verde"
      CONF_EASYCASH_IP="192.168.53.2"
      CONF_IMPRESSORA_IP="192.168.58.160"
      CONF_IMPRESSORA_PPD="Kyocera_ECOSYS_MA5500ifx_.ppd"
      ;;
    *)
      log_fail "Valor de filial não mapeado nas configurações - contate o responsável pelo script (Jurandir): $id_filial"
      exit 1
      ;;
  esac

  # Monta a URL completa do PPD com base na escolha
  CONF_IMPRESSORA_URL="${base_ppd_url}/${CONF_IMPRESSORA_PPD}"
  log_ok "Configurações da loja $NOME_LOJA carregadas com sucesso!"
}

# Inicializa as variáveis com a filial lida
carregar_config_filial "$filial"

#===============================================================================
# 4. Desativação de atalhos de teclado (keyd)
#===============================================================================
log_step "Configurando bloqueio de atalhos de teclado (keyd)"
if command -v keyd >/dev/null 2>&1; then
  log_skip "keyd já instalado"
else
  run_silent "Clonando repositório keyd" git clone https://github.com/rvaiya/keyd
  ( cd keyd && run_silent "Compilando e instalando keyd" bash -c "make && sudo make install" )
  run_silent "Habilitando e iniciando serviço keyd" bash -c "sudo systemctl enable keyd && sudo systemctl start keyd"
  rm -rf keyd
fi
sudo printf "[ids]\n*\n\n[main]\n\n[control]\ntab = noop\nw = noop\nt = noop\nh = noop\nb = noop\no = noop\ns = noop\nd = noop\nn = noop\nc = noop\nv = noop\nx = noop\n\n[alt]\nf4 = noop\nf = noop\n\n[control+shift]\nw = noop\nf4 = noop\n\n[meta]\nf4 = noop\n" > /etc/keyd/default.conf
sudo keyd reload
log_ok "Configuração de atalhos aplicada"

#===============================================================================
# 5. Ajustes de rede: /etc/hosts, nsswitch, sysctl
#===============================================================================
log_step "Ajustando /etc/hosts com o IP local do terminal"
sudo sed -i "s/^127\.0\.1\.1/$(ip -4 -brief addr show | awk '$1 != "lo" {print $3}' | cut -d/ -f1 | head -n 1)/" /etc/hosts
log_ok "/etc/hosts ajustado"

log_step "Otimizando resolução de nomes e parâmetros de rede"
sudo sed -i 's/^hosts:          files.*/hosts:          files dns/' /etc/nsswitch.conf

sudo bash -c "cat << 'EOF' > /etc/sysctl.d/99-sysctl.conf
#Desabilitar IPV6 no Sistema
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

#Otimização de Buffer TCP (Kernel TCP Tuning)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

#Ativa o TCP Window Scaling
net.ipv4.tcp_window_scaling = 1

#MTU/MSS Probing (Mitigação para VPN/SD-WAN e TLS Fragmentado)
net.ipv4.tcp_mtu_probing = 1
EOF"
run_silent "Aplicando parâmetros sysctl" sudo sysctl --system

#===============================================================================
# 6. Ajustes de parâmetros de carga / timeout
#===============================================================================
log_step "Ajustando timeouts de conexão (CARG0000, RESTG0000, ZMWS0000)"
for ARQ in CARG0000 RESTG0000 ZMWS0000; do
  if ! grep -q '^conexao_timeout=10$' /Zanthus/Zeus/pdvJava/${ARQ}.CFG; then
    sed -i '/^opcoes=/a conexao_timeout=10' /Zanthus/Zeus/pdvJava/${ARQ}.CFG
    log_ok "conexao_timeout adicionado em ${ARQ}.CFG"
  else
    log_skip "conexao_timeout já definido em ${ARQ}.CFG"
  fi
done

printf "timeout=5\n" > /Zanthus/Zeus/pdvJava/RESTG4650.CFG
printf "timeout=5\n" > /Zanthus/Zeus/pdvJava/RESTG4651.CFG
log_ok "Timeout do MercaFacil ajustado (RESTG4650/4651)"

sed -i 's/^timeout=30$/timeout=60/' /Zanthus/Zeus/pdvJava/CARG0000.CFG
sed -i '/^endereco=/c endereco=192.168.12.42' /Zanthus/Zeus/pdvJava/CARG0000.CFG
log_ok "CARG0000.CFG: timeout e endereço (mirage) ajustados"

printf "Vivo=22\nClaro=12000000\nOi=35000000\nTim=74000000\nBrasil Telecom=11\nCTBC-Celular=12201\nCTBC-Fixo=12299\nEmbratel=14000000\nSercomtel-Celular=12301\nSercomtel-Fixo=12399\nL Economica=97100\nNextel=75000000\n" > /Zanthus/Zeus/pdvJava/RECRGOP0.CFG
chmod 777 /Zanthus/Zeus/pdvJava/RECRGOP0.CFG
log_ok "Operadoras de recarga configuradas (RECRGOP0.CFG)"

#===============================================================================
# 7. journald - limitar uso de disco
#===============================================================================
log_step "Ajustando parâmetros de journald.conf"
if grep -q '^Storage=none' /etc/systemd/journald.conf; then
  log_skip "journald.conf já ajustado"
else
  sudo sed -i 's/#Storage=auto/Storage=none/g; s/#SystemKeepFree=/SystemKeepFree=60G/g; s/#SystemMaxUse=/SystemMaxUse=1G/g; s/#SystemMaxFileSize=/SystemMaxFileSize=1G/g' /etc/systemd/journald.conf
  log_ok "journald.conf ajustado"
fi

#===============================================================================
# 8. GRUB - parâmetros para máquinas legado
#===============================================================================
log_step "Verificando parâmetros do GRUB"
cutoff_year=2018
bios_year=$(dmidecode -t 0 | grep "Release Date" | awk -F: '{ print $2 }' | sed 's/^[ \t]*//;s/[ \t]*$//' | awk -F'/' '{ print $3 }')

if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash \(pci=nommconf\|pcie_aspm=off\|pci=noaer\)' /etc/default/grub; then
  log_skip "Ajustes de GRUB já aplicados"
elif [[ "$bios_year" -lt "$cutoff_year" ]]; then
  log_info "BIOS anterior a 2018 detectada - aplicando ajustes legados"
  run_silent "Reinstalando GRUB" sudo grub-install
  sudo sed -i '/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash \(pci=nommconf\|pcie_aspm=off\|pci=noaer\)/! s/\(GRUB_CMDLINE_LINUX_DEFAULT="quiet splash\)/\1 pci=nommconf pcie_aspm=off pci=noaer/' /etc/default/grub
  run_silent "Atualizando GRUB" sudo update-grub
  log_info "A máquina será reiniciada. Reinicie o script após o boot para continuar."
  sleep 5
  reboot
else
  log_ok "BIOS posterior a 2018 - sem ajustes legados necessários"
fi

#===============================================================================
# 9. DNS (systemd-resolved)
#===============================================================================
log_step "Ajustando /etc/systemd/resolved.conf"
# Captura o gateway padrão IPv4 da máquina (pega a primeira linha caso haja mais de um)
DEFAULT_GW=$(ip -4 route show default | awk '{print $3}' | head -n 1)
# Monta o conteúdo usando a variável $DEFAULT_GW no lugar do IP fixo
RESOLVED_CONTENT="[Resolve]\nDNS=192.168.12.5 192.168.2.10\nFallbackDNS=${DEFAULT_GW}\nDomains=machadao.corp\n"
if [ -f /etc/systemd/resolved.conf ] && [ "$(cat /etc/systemd/resolved.conf)" == "$(printf "$RESOLVED_CONTENT")" ]; then
  log_skip "resolved.conf já ajustado"
else
  printf "$RESOLVED_CONTENT" | sudo tee /etc/systemd/resolved.conf >>"$LOGFILE"
  log_ok "resolved.conf ajustado (FallbackDNS=${DEFAULT_GW})"
fi
#===============================================================================
# 10. Timeout Sefaz
#===============================================================================
sudo printf "timeout=60\n" > /Zanthus/Zeus/pdvJava/ZMWS1201.CFG
log_ok "ZMWS1201.CFG ajustado (timeout Sefaz)"

#===============================================================================
# 11. CUPS - configuração global
#===============================================================================
log_step "Ajustando CUPS"
sudo sed 's/^BrowseLocalProtocols.*$/BrowseLocalProtocols\ none/' -i /etc/cups/cupsd.conf
run_silent "Reiniciando serviço CUPS" bash -c "cupsctl Web=yes; service cups stop; service cups start"
run_silent "Habilitando administração remota" cupsctl --remote-admin --remote-any
printf "linux.impressora=IMP-NFE\nlinux.opcoes=3\n" > /Zanthus/Zeus/pdvJava/ZPDF00.CFG
log_ok "CUPS configurado"

#===============================================================================
# 12. Instalação de impressora (Via Variáveis Globais)
#===============================================================================
log_step "Configurando impressora fiscal - Loja $NOME_LOJA"
if lpstat -p IMP-NFE >/dev/null 2>&1; then
  log_skip "Impressora IMP-NFE já cadastrada no CUPS"
else
  log_info "Baixando driver: $CONF_IMPRESSORA_PPD"
  safe_download "$CONF_IMPRESSORA_URL" "/usr/share/cups/model/$CONF_IMPRESSORA_PPD"
  run_silent "Cadastrando impressora IMP-NFE ($CONF_IMPRESSORA_IP)" lpadmin -p IMP-NFE -E -v socket://$CONF_IMPRESSORA_IP -i /usr/share/cups/model/$CONF_IMPRESSORA_PPD
fi

#===============================================================================
# 13. Fuso horário (Via Variáveis Globais)
#===============================================================================
log_step "Ajustando fuso horário e NTP"
sed -i 's/^server 0\.br\.pool\.ntp\.org iburst/server ntp.redejcm.com.br iburst prefer/' /etc/ntp.conf
run_silent "Reiniciando serviço NTP" systemctl restart ntp

fuso_atual=$(timedatectl show --property=Timezone --value 2>/dev/null)
if [ "$fuso_atual" == "$CONF_FUSO_HORARIO" ]; then
  log_skip "Fuso horário já definido para $CONF_FUSO_HORARIO"
else
  timedatectl set-timezone "$CONF_FUSO_HORARIO"
  log_ok "Fuso horário definido para $CONF_FUSO_HORARIO"
fi

# Sincronização de hardware clock (Roda sempre para evitar perda de sincronia da BIOS)
hwclock -w
sed -i 's/UTC/LOCAL/g' /etc/adjtime
hwclock --systohc
hwclock --localtime
hwclock -w
log_ok "Relógio de hardware ajustado e sincronizado com o sistema"

#===============================================================================
# 14. Agendamento de desligamento e EasyCash (Via Variáveis Globais)
#===============================================================================
log_step "Configurando servidor EasyCash"
printf "ENDERECO=$CONF_EASYCASH_IP\nPORTA=23454\n" > /Zanthus/Zeus/pdvJava/ZPPERD01.CFG
printf "TIPO01=1\nOPCOESLOG=255\n" > /Zanthus/Zeus/pdvJava/ZPPERD00.CFG
log_ok "Arquivos EasyCash gravados (IP: $CONF_EASYCASH_IP)"

log_step "Agendando desligamento automático (cron)"
linha_semana="00 23 * * * /sbin/shutdown -h now"
linha_domingo="00 $CONF_HORA_DOMINGO * * SUN /sbin/shutdown -h now"

cron_atual=$(crontab -l 2>/dev/null)
if echo "$cron_atual" | grep -qF "$linha_semana" && echo "$cron_atual" | grep -qF "$linha_domingo"; then
  log_skip "Agendamento de desligamento já configurado"
else
  (echo "$linha_semana"; echo "$linha_domingo") | crontab -
  log_ok "Desligamento agendado: semana às 23h | domingo às ${CONF_HORA_DOMINGO}h"
fi

#===============================================================================
# 15. Cópia de arquivos de interface
#===============================================================================
log_step "Copiando arquivos de interface para tipo: $tipoInstala"

if [ "$tipoInstala" == "SelfCheckout" ]; then
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/telas_touch.js" "/Zanthus/Zeus/Interface/resources/js/telas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/animacao-codigo-pdv.svg" "/Zanthus/Zeus/Interface/resources/imagens/animacao-codigo-pdv.svg"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/animacao-pagamento-pdv.svg" "/Zanthus/Zeus/Interface/resources/imagens/animacao-pagamento-pdv.svg"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/teclas_touch.js" "/Zanthus/Zeus/Interface/resources/js/teclas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Lanchonete/TelaComanda.js" "/Zanthus/Zeus/Interface/app/view/tela/2/TelaComanda.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/config.js" "/Zanthus/Zeus/Interface/config/config.js"
fi

if [ "$tipoInstala" == "Lanchonete" ]; then
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/telas_touch.js" "/Zanthus/Zeus/Interface/resources/js/telas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Lanchonete/teclas_touch.js" "/Zanthus/Zeus/Interface/resources/js/teclas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Lanchonete/TelaComanda.js" "/Zanthus/Zeus/Interface/app/view/tela/2/TelaComanda.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Lanchonete/config.js" "/Zanthus/Zeus/Interface/config/config.js"
fi

if [ "$tipoInstala" == "PDVTouch" ]; then
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/telas_touch.js" "/Zanthus/Zeus/Interface/resources/js/telas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/teclas_touch.js" "/Zanthus/Zeus/Interface/resources/js/teclas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Lanchonete/config.js" "/Zanthus/Zeus/Interface/config/config.js"
fi

if [ "$tipoInstala" == "PDVComum" ]; then
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/config.js" "/Zanthus/Zeus/Interface/config/config.js"
fi

log_step "Copiando arquivos gerais de interface"
safe_wget "https://github.com/JMoratelli/Zanthus/raw/refs/heads/main/InstalaPDV/InterfaceUnificada/icones.7z" "/Zanthus/Zeus/Interface/resources/icones/icones.7z"
run_silent "Extraindo ícones" bash -c "cd /Zanthus/Zeus/Interface/resources/icones/ && 7z x -y icones.7z '*'"

safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Zeus_V.gif" "/Zanthus/Zeus/Interface/resources/imagens/Zeus_V.gif"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/logo.png" "/Zanthus/Zeus/Interface/resources/imagens/logo.png"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/logo_self.png" "/Zanthus/Zeus/Interface/resources/imagens/logo_self.png"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/descanso1000.jpg" "/Zanthus/Zeus/Interface/resources/imagens/descanso1000.jpg"

rm -f /Zanthus/Zeus/Interface/resources/imagens/self/codigo.gif
rm -f /Zanthus/Zeus/Interface/resources/imagens/cancela_sel.png
rm -f /Zanthus/Zeus/Interface/resources/imagens/cancela.png
log_ok "Arquivos obsoletos removidos (codigo.gif, cancela*.png)"

safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/style100.css" "/Zanthus/Zeus/Interface/resources/css/style100.css"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/style1000.css" "/Zanthus/Zeus/Interface/resources/css/style1000.css"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/style2.css" "/Zanthus/Zeus/Interface/resources/css/style2.css"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/stylemonitor_cliente.css" "/Zanthus/Zeus/Interface/resources/css/stylemonitor_cliente.css"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Buttons.js" "/Zanthus/Zeus/Interface/app/api/dinamico/pdvMouse/Buttons.js"

chmod 777 -R /Zanthus/Zeus/Interface/
log_ok "Permissões aplicadas em /Zanthus/Zeus/Interface/"

#===============================================================================
# 16. Áudios do PDV
#===============================================================================
log_step "Baixando arquivos de áudio"
if [ "$tipoInstala" == "SelfCheckout" ]; then
  base_url="https://github.com/JMoratelli/Zanthus/raw/refs/heads/main/InstalaPDV/Self/Interface/audio/"
  destino="/Zanthus/Zeus/Interface/resources/audio/"
  audio_ok=0; audio_falha=0
  for i in {0..24}; do
    if wget -q -N -P "$destino" "${base_url}${i}.mp3" >>"$LOGFILE" 2>&1 && [ -s "${destino}${i}.mp3" ]; then
      audio_ok=$((audio_ok + 1))
    else
      audio_falha=$((audio_falha + 1))
    fi
  done
  log_ok "$audio_ok baixados, $audio_falha falharam"
else
  log_skip "Terminal não self, pulando download de arquivos"
fi

#===============================================================================
# 17. CliSiTef
#===============================================================================
log_step "Configurando CliSiTef"
if [ "$tipoInstala" == "SelfCheckout" ]; then
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/CliSiTef.ini" "/Zanthus/Zeus/pdvJava/CliSiTef.ini"
else
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/CliSiTef.ini" "/Zanthus/Zeus/pdvJava/CliSiTef.ini"
fi

chmod 777 -R /Zanthus/Zeus/pdvJava/CliSiTef.ini
safe_wget "http://192.168.12.223/uploads/interfaceZanthus/libCliSiTef.7z" "/Zanthus/Zeus/pdvJava/libCliSiTef.7z"
run_silent "Extraindo libCliSiTef" 7z x -o/Zanthus/Zeus/pdvJava/ -y /Zanthus/Zeus/pdvJava/libCliSiTef.7z

#===============================================================================
# 18. Rede Docker
#===============================================================================
log_step "Ajustando rede Docker"
export DISPLAY=:0
user_ip="10.220.0.1"
config_data="{ \"bip\": \"$user_ip/16\", \"mtu\": 1500 }"

if [ -f /etc/docker/daemon.json ] && grep -q "$user_ip" /etc/docker/daemon.json 2>/dev/null; then
  log_skip "Rede Docker já configurada"
else
  echo "$config_data" | sudo tee /etc/docker/daemon.json > /dev/null
  run_silent "Reiniciando Docker" sudo systemctl restart docker
  log_ok "Rede Docker alterada para $user_ip"
fi

#===============================================================================
# 19. Configuração de monitores (PDVs com dois monitores)
#===============================================================================
if [[ "$tipoInstala" == "PDVComum" || "$tipoInstala" == "PDVTouch" || "$tipoInstala" == "Lanchonete" ]]; then
  log_step "Configurando monitores"

  get_best_mode() {
    local saida="$1"
    xrandr | awk -v out="$saida" '
      $1==out {found=1; next}
      /^[A-Za-z]/ && found {exit}
      found && /^[[:space:]]+[0-9]+x[0-9]+/ {print $1}
    ' | awk -F'x' '{
      diff = (($1-1024)^2 + ($2-768)^2)
      if (best=="" || diff<bestdiff) {best=$0; bestdiff=diff}
    } END {print best}'
  }

  get_max_mode() {
    local saida="$1"
    xrandr | awk -v out="$saida" '
      $1==out {found=1; next}
      /^[A-Za-z]/ && found {exit}
      found && /^[[:space:]]+[0-9]+x[0-9]+/ {print $1}
    ' | awk -F'x' '{
      area = $1*$2
      if (best=="" || area>bestarea) {best=$0; bestarea=area}
    } END {print best}'
  }

  monCon=$(xrandr | grep " connected" | wc -l)
  mapfile -t saidas < <(xrandr | grep " connected" | cut -d' ' -f1)
  log_info "$monCon monitor(es) conectados: ${saidas[*]}"

  declare -A modo_escolhido
  declare -A modo_maximo
  for saida in "${saidas[@]}"; do
    modo=$(get_best_mode "$saida")
    if [ -z "$modo" ]; then
      log_info "Nenhum modo encontrado para $saida, pulando"
      continue
    fi
    modo_escolhido["$saida"]="$modo"
    modo_maximo["$saida"]=$(get_max_mode "$saida")
  done

  cmd_xrandr=(xrandr)
  anterior=""
  for saida in "${saidas[@]}"; do
    [ -z "${modo_escolhido[$saida]}" ] && continue
    cmd_xrandr+=(--output "$saida" --mode "${modo_escolhido[$saida]}")
    if [ -z "$anterior" ]; then
      cmd_xrandr+=(--pos 0x0)
    else
      cmd_xrandr+=(--right-of "$anterior")
    fi
    anterior="$saida"
  done
  "${cmd_xrandr[@]}"
  log_ok "Resolução aplicada"

  operador=""
  if [ "$monCon" -ge 2 ]; then
    monitores_geom=$(xrandr --listactivemonitors | tail -n +2)
    i=1
    for saida in "${saidas[@]}"; do
      geom=$(echo "$monitores_geom" | grep -w "$saida" | awk '{print $3}')
      coord=$(echo "$geom" | grep -o '+.*')
      xmessage -geometry "300x100$coord" -timeout 20 " SOU A TELA $i " &
      i=$((i+1))
    done

    echo ""
    echo "=========================================================="
    echo " A tela definida como PRINCIPAL será a tela do OPERADOR."
    echo " A outra tela é a tela que o CLIENTE verá."
    echo "=========================================================="
    echo "Selecione a tela principal:"
    i=1
    for saida in "${saidas[@]}"; do
      echo "$i - $saida - Resolução Máxima: ${modo_maximo[$saida]}"
      i=$((i+1))
    done
    opcao_duplicar=$((${#saidas[@]}+1))
    echo "$opcao_duplicar - Duplicar telas"

    escolha=""
    max_opcao_total=$(( ${#saidas[@]} + 1 ))
    while true; do
      read -rp "Opção (1-$max_opcao_total): " escolha < /dev/tty
      if [[ "$escolha" =~ ^[0-9]+$ ]] && [ "$escolha" -ge 1 ] && [ "$escolha" -le "$max_opcao_total" ]; then
        break
      fi
      echo "Opção inválida."
    done

    if [ "$escolha" -eq "$opcao_duplicar" ]; then
      duplicado=true
      operador="${saidas[0]}"
      xrandr --output "${saidas[0]}" --same-as "${saidas[1]}"
      log_ok "Telas duplicadas: ${saidas[0]} = ${saidas[1]}"
    else
      duplicado=false
      operador="${saidas[$((escolha-1))]}"
    fi
  else
    duplicado=false
    operador="${saidas[0]}"
  fi

  if [ "$duplicado" != "true" ]; then
    xrandr --output "$operador" --primary
    log_ok "Tela do operador definida: $operador"
  fi

  {
    echo '#!/bin/bash'
    echo '#Arquivo Gerado por script de inicialização'
    echo '#@jjmoratelli'
    echo 'xrandr > /tmp/displays'
    echo 'xinput list --id-only > /tmp/xdevices-id'
    echo 'xinput list --name-only > /tmp/xdevices-name'
    if [ "$duplicado" = "true" ]; then
      for saida in "${saidas[@]}"; do
        [ -z "${modo_escolhido[$saida]}" ] && continue
        echo "xrandr --output $saida --mode ${modo_escolhido[$saida]}"
      done
      echo "xrandr --output ${saidas[0]} --same-as ${saidas[1]}"
    else
      anterior=""
      for saida in "${saidas[@]}"; do
        [ -z "${modo_escolhido[$saida]}" ] && continue
        if [ -z "$anterior" ]; then
          echo "xrandr --output $saida --mode ${modo_escolhido[$saida]} --pos 0x0"
        else
          echo "xrandr --output $saida --mode ${modo_escolhido[$saida]} --right-of $anterior"
        fi
        anterior="$saida"
      done
      echo "xrandr --output $operador --primary"
    fi
  } > /usr/local/bin/xrandr.set
  chmod +x /usr/local/bin/xrandr.set

  log_ok "Monitores configurados"
fi

#===============================================================================
# 20. Sinaleiro (torre x lâmpada única)
#===============================================================================
log_step "Configurando sinaleiro"
ips_permitidos=("192.168.8.133" "192.168.8.134" "192.168.8.135" "192.168.8.136")
if [[ " ${ips_permitidos[@]} " =~ " ${ip} " ]]; then
  printf "modelo=0\n#Reserva\n" > /Zanthus/Zeus/pdvJava/ZSINALIZ_LAURENTI_ARDUINO.CFG
  log_ok "Sinaleiro tipo torre configurado"
else
  printf "modelo=1\n#Reserva\n" > /Zanthus/Zeus/pdvJava/ZSINALIZ_LAURENTI_ARDUINO.CFG
  log_ok "Sinaleiro tipo lâmpada única configurado"
fi

#===============================================================================
# 21. Volume e limpeza de arquivos legados
#===============================================================================
log_step "Limpando arquivos legados"
amixer set Master 87 >>"$LOGFILE" 2>&1
rm -f /opt/webadmin/extra/rules/Balanca/toledoDCPSC-var.sh
rm -f /Zanthus/Zeus/Interface/resources/imagens/processando.gif
log_ok "Arquivos legados removidos"

#===============================================================================
# 22. Periféricos USB (balança, etc.)
#===============================================================================
log_step "Instalando script de periféricos USB"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PerifericosUSB.sh" "/home/zanthus/PerifericosUSB.sh"
chmod +x /home/zanthus/PerifericosUSB.sh
run_silent "Executando PerifericosUSB.sh" /home/zanthus/PerifericosUSB.sh

#===============================================================================
# 23. ScreenSaver
#===============================================================================
log_step "Iniciando Instalação Passo 2/2"
echo -e "\n${C_GREEN}${C_BOLD}✔ Instalação/configuração concluída.${C_RESET}"
echo -e "Log completo em: ${C_CYAN}$LOGFILE${C_RESET}"
sleep 5
curl -s https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/ScreenSaver/InstalaSC.sh | bash
