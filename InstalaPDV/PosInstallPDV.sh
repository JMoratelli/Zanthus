#!/bin/bash
#===============================================================================
# Script de instalação/configuração PDV - Zanthus
# Autor original: @jjmoratelli, Jurandir Moratelli
# Refatorado: logging limpo, downloads seguros (com retry) e idempotência.
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
# Download seguro com retries e validação de arquivo vazio/corrompido
# safe_download <url> <destino> [tentativas]
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
# 4. Desativação de atalhos de teclado (keyd) - self checkout não é afetado
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
if grep -q '^conexao_timeout=10$' /Zanthus/Zeus/pdvJava/CARG0000.CFG; then
  log_skip "conexao_timeout já definido em CARG0000.CFG"
else
  sed -i '/^opcoes=/a conexao_timeout=10' /Zanthus/Zeus/pdvJava/CARG0000.CFG
  log_ok "conexao_timeout adicionado em CARG0000.CFG"
fi
if grep -q '^conexao_timeout=10$' /Zanthus/Zeus/pdvJava/RESTG0000.CFG; then
  log_skip "conexao_timeout já definido em RESTG0000.CFG"
else
  sed -i '/^opcoes=/a conexao_timeout=10' /Zanthus/Zeus/pdvJava/RESTG0000.CFG
  log_ok "conexao_timeout adicionado em RESTG0000.CFG"
fi
if grep -q '^conexao_timeout=10$' /Zanthus/Zeus/pdvJava/ZMWS0000.CFG; then
  log_skip "conexao_timeout já definido em ZMWS0000.CFG"
else
  sed -i '/^opcoes=/a conexao_timeout=10' /Zanthus/Zeus/pdvJava/ZMWS0000.CFG
  log_ok "conexao_timeout adicionado em ZMWS0000.CFG"
fi

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
# 7. journald - limitar uso de disco com logs
#===============================================================================
log_step "Ajustando parâmetros de journald.conf"
if grep -q '^Storage=none' /etc/systemd/journald.conf; then
  log_skip "journald.conf já ajustado"
else
  sudo sed -i 's/#Storage=auto/Storage=none/g' /etc/systemd/journald.conf
  sudo sed -i 's/#SystemKeepFree=/SystemKeepFree=60G/g' /etc/systemd/journald.conf
  sudo sed -i 's/#SystemMaxUse=/SystemMaxUse=1G/g' /etc/systemd/journald.conf
  sudo sed -i 's/#SystemMaxFileSize=/SystemMaxFileSize=1G/g' /etc/systemd/journald.conf
  log_ok "journald.conf ajustado"
fi

#===============================================================================
# 8. GRUB - parâmetros para máquinas legado (BIOS anterior a 2018)
#===============================================================================
log_step "Verificando parâmetros do GRUB"
cutoff_year=2018
bios_year=$(dmidecode -t 0 | grep "Release Date" | awk -F: '{ print $2 }' | sed 's/^[ \t]*//;s/[ \t]*$//' | awk -F'/' '{ print $3 }')

if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash \(pci=nommconf\|pcie_aspm=off\|pci=noaer\)' /etc/default/grub; then
  log_skip "Ajustes de GRUB já aplicados"
else
  if [[ "$bios_year" -lt "$cutoff_year" ]]; then
    log_info "BIOS anterior a 2018 detectada - aplicando ajustes legados"
    run_silent "Reinstalando GRUB" sudo grub-install
    sudo sed -i '/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash \(pci=nommconf\|pcie_aspm=off\|pci=noaer\)/! s/\(GRUB_CMDLINE_LINUX_DEFAULT="quiet splash\)/\1 pci=nommconf pcie_aspm=off pci=noaer/' /etc/default/grub
    sleep 5
    run_silent "Atualizando GRUB" sudo update-grub
    log_info "A máquina será reiniciada. Reinicie o script após o boot para continuar."
    sleep 5
    reboot
  else
    log_ok "BIOS posterior a 2018 - sem ajustes legados necessários"
    sleep 5
  fi
fi

#===============================================================================
# 9. DNS (systemd-resolved)
#===============================================================================
log_step "Ajustando /etc/systemd/resolved.conf"
RESOLVED_CONTENT="[Resolve]\nDNS=192.168.12.5 192.168.2.10\nFallbackDNS=192.168.12.99\nDomains=machadao.corp\n"
if [ -f /etc/systemd/resolved.conf ] && [ "$(cat /etc/systemd/resolved.conf)" == "$(printf "$RESOLVED_CONTENT")" ]; then
  log_skip "resolved.conf já ajustado"
else
  printf "$RESOLVED_CONTENT" | sudo tee /etc/systemd/resolved.conf >>"$LOGFILE"
  log_ok "resolved.conf ajustado"
fi

#===============================================================================
# 10. Timeout Sefaz (recomendação Zanthus)
#===============================================================================
sudo printf "timeout=60\n" > /Zanthus/Zeus/pdvJava/ZMWS1201.CFG
log_ok "ZMWS1201.CFG ajustado (timeout Sefaz)"

#===============================================================================
# 11. CUPS - configuração de impressão
#===============================================================================
log_step "Ajustando CUPS"
sudo sed 's/^BrowseLocalProtocols.*$/BrowseLocalProtocols\ none/' -i /etc/cups/cupsd.conf
run_silent "Reiniciando serviço CUPS" bash -c "cupsctl Web=yes; service cups stop; service cups start"
run_silent "Habilitando administração remota do CUPS" cupsctl --remote-admin --remote-any
printf "linux.impressora=IMP-NFE\nlinux.opcoes=3\n" > /Zanthus/Zeus/pdvJava/ZPDF00.CFG
log_ok "CUPS configurado"

#===============================================================================
# 12. Instalação de impressora (por filial)
#===============================================================================
log_step "Configurando impressora fiscal"
if lpstat -p IMP-NFE >/dev/null 2>&1; then
  log_skip "Impressora IMP-NFE já cadastrada no CUPS"
else
  case $filial in
      1)
          log_info "Detectada impressora da Loja Centro"
          safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_M3655idn.ppd" "/usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd"
          run_silent "Cadastrando impressora IMP-NFE" lpadmin -p IMP-NFE -E -v socket://10.1.1.139 -i /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd
          ;;
      3)
          log_info "Detectada impressora da Loja Bairro"
          safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_MA5500ifx_.ppd" "/usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd"
          run_silent "Cadastrando impressora IMP-NFE" lpadmin -p IMP-NFE -E -v socket://192.168.11.94 -i /usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd
          ;;
      9)
          log_info "Detectada impressora de Matupá"
          safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_M3655idn.ppd" "/usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd"
          run_silent "Cadastrando impressora IMP-NFE" lpadmin -p IMP-NFE -E -v socket://192.168.4.24 -i /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd
          ;;
       53)
          log_info "Detectada impressora de Alta Floresta"
          safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_M3655idn.ppd" "/usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd"
          run_silent "Cadastrando impressora IMP-NFE" lpadmin -p IMP-NFE -E -v socket://192.168.6.14 -i /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd
          ;;
       52)
          log_info "Detectada impressora de Primavera do Leste"
          safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_M3655idn.ppd" "/usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd"
          run_silent "Cadastrando impressora IMP-NFE" lpadmin -p IMP-NFE -E -v socket://192.168.8.27 -i /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd
          ;;
       57)
          log_info "Detectada impressora de Confresa"
          safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_MA5500ifx_.ppd" "/usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd"
          run_silent "Cadastrando impressora IMP-NFE" lpadmin -p IMP-NFE -E -v socket://192.168.57.125 -i /usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd
          ;;
       58)
          log_info "Detectada impressora de Lucas do Rio Verde"
          safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_MA5500ifx_.ppd" "/usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd"
          run_silent "Cadastrando impressora IMP-NFE" lpadmin -p IMP-NFE -E -v socket://192.168.58.160 -i /usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd
          ;;
      *)
          log_fail "Valor de filial não mapeado - contate o responsável pelo script (Jurandir): $filial"
          exit
          ;;
  esac
fi

# 13. Fuso horário
log_step "Ajustando fuso horário e NTP"
sed -i 's/^server 0\.br\.pool\.ntp\.org iburst/server ntp.redejcm.com.br iburst prefer/' /etc/ntp.conf
run_silent "Reiniciando serviço NTP" systemctl restart ntp

case $filial in
  1 | 3 | 9 | 52 | 53 | 58)
    fuso_alvo="America/Cuiaba"
    ;;
  57)
    fuso_alvo="America/Sao_Paulo"
    ;;
  *)
    log_fail "Valor inválido para a variável 'filial'."
    exit 1
    ;;
esac

fuso_atual=$(timedatectl show --property=Timezone --value 2>/dev/null)
if [ "$fuso_atual" == "$fuso_alvo" ]; then
  log_skip "Fuso horário já definido para $fuso_alvo"
else
  timedatectl set-timezone "$fuso_alvo"
  hwclock -w
  sed -i 's/UTC/LOCAL/g' /etc/adjtime
  hwclock --systohc
  hwclock --localtime
  hwclock -w
  log_ok "Fuso horário definido para $fuso_alvo e relógio de hardware ajustado"
fi

#===============================================================================
# 14. Agendamento de desligamento (cron)
#===============================================================================
case $filial in
  1 | 3 | 9)
    hora_domingo=18
    ;;
  52 | 53 | 57 | 58)
    hora_domingo=21
    ;;
  *)
    log_fail "Valor inválido para a variável 'filial'."
    exit 1
    ;;
esac

log_step "Configurando servidor EasyCash"
case $filial in
  1)  log_info "Servidor EasyCash configurado para Loja 1"; ipEasyCash=192.168.50.130 ;;
  3)  log_info "Servidor EasyCash configurado para Loja 2"; ipEasyCash=192.168.50.2 ;;
  9)  log_info "Servidor EasyCash configurado para Loja 3"; ipEasyCash=192.168.51.194 ;;
  52) log_info "Servidor EasyCash configurado para Loja 6 - Primavera do Leste"; ipEasyCash=192.168.51.130 ;;
  53) log_info "Servidor EasyCash configurado para Loja 5 - Alta Floresta"; ipEasyCash=192.168.51.2 ;;
  57) log_info "Servidor EasyCash configurado para Loja 7 - Confresa"; ipEasyCash=192.168.51.66 ;;
  58) log_info "Servidor EasyCash configurado para Loja 8 - Lucas do Rio Verde"; ipEasyCash=192.168.53.2 ;;
  *)  log_fail "Não existe parâmetro de servidor EasyCash para essa loja." ;;
esac

printf "ENDERECO=$ipEasyCash\nPORTA=23454\n" > /Zanthus/Zeus/pdvJava/ZPPERD01.CFG
printf "TIPO01=1\nOPCOESLOG=255\n" > /Zanthus/Zeus/pdvJava/ZPPERD00.CFG
log_ok "Arquivos EasyCash gravados"

log_step "Agendando desligamento automático (cron)"
linha_semana="00 23 * * * /sbin/shutdown -h now"
linha_domingo="00 $hora_domingo * * SUN /sbin/shutdown -h now"

cron_atual=$(crontab -l 2>/dev/null)
if echo "$cron_atual" | grep -qF "$linha_semana" && echo "$cron_atual" | grep -qF "$linha_domingo"; then
  log_skip "Agendamento de desligamento já configurado"
else
  (echo "$linha_semana"; echo "$linha_domingo") | crontab -
  log_ok "Desligamento agendado: semana às 23h | domingo às ${hora_domingo}h"
fi

#===============================================================================
# 15. Cópia de arquivos de interface (conforme tipo de instalação)
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
log_step "Baixando arquivos de áudio (0-24)"
base_url="https://github.com/JMoratelli/Zanthus/raw/refs/heads/main/InstalaPDV/Self/Interface/audio/"
destino="/Zanthus/Zeus/Interface/resources/audio/"
audio_ok=0; audio_falha=0
for i in {0..24}; do
  url="${base_url}${i}.mp3"
  if wget -q -N -P "$destino" "$url" >>"$LOGFILE" 2>&1 && [ -s "${destino}${i}.mp3" ]; then
    audio_ok=$((audio_ok + 1))
  else
    audio_falha=$((audio_falha + 1))
  fi
done
log_ok "Áudios: $audio_ok baixados/atualizados, $audio_falha falharam"

#===============================================================================
# 17. CliSiTef
#===============================================================================
log_step "Configurando CliSiTef"
if [ "$tipoInstala" == "SelfCheckout" ]; then
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Self/CliSiTef.ini" "/Zanthus/Zeus/pdvJava/CliSiTef.ini"
fi

if [[ "$tipoInstala" == "PDVComum" || "$tipoInstala" == "PDVTouch" || "$tipoInstala" == "Lanchonete" ]]; then
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
  log_skip "Rede Docker já configurada para $user_ip"
else
  echo "$config_data" | sudo tee /etc/docker/daemon.json > /dev/null
  run_silent "Reiniciando serviço Docker" sudo systemctl restart docker
  log_ok "Rede Docker alterada com sucesso para o endereço IP: $user_ip"
fi

#===============================================================================
# 19. Duplicação de telas (PDVs com dois monitores)
#===============================================================================
if [[ "$tipoInstala" == "PDVComum" || "$tipoInstala" == "PDVTouch" || "$tipoInstala" == "Lanchonete" ]]; then
  log_step "Configurando duplicação de monitores"
  monCon=$(xrandr | grep " connected" | wc -l)
  saida1=$(xrandr | grep " connected" | cut -d' ' -f1 | head -n 1)
  saida2=$(xrandr | grep " connected" | cut -d' ' -f1 | head -n 2 | tail -n 1)

  log_info "$monCon monitor(es) conectados"
  sleep 5

  xrandr --output $saida1  --mode 1024x768
  xrandr --output $saida2  --mode 1024x768

  script_content=$(cat << EOF
#!/bin/bash
#Arquivo Gerado por script de inicialização
#@jjmoratelli
xrandr > /tmp/displays
xinput list --id-only > /tmp/xdevices-id
xinput list --name-only > /tmp/xdevices-name
DEFAULT=$(xrandr|grep -v eDP|awk 'BEGIN {} /^.*connected/{printf("%s;", $1)} END {}' | cut -d ";" -f 1 )
xrandr --output "$saida1" --mode 1024x768
xrandr --output "$saida2" --mode 1024x768
EOF
)

  echo "$script_content" > /usr/local/bin/xrandr.set
  chmod +x /usr/local/bin/xrandr.set
  sleep 5

  tela1=$(xrandr | grep ' connected' | awk '{print $1}' | head -n 1)
  tela2=$(xrandr | grep ' connected' | awk '{print $1}' | tail -n 1)
  linha="xrandr --output $tela1 --same-as $tela2"

  if [ -e /usr/local/bin/xrandr.set ]; then
    echo >> /usr/local/bin/xrandr.set
  fi
  echo "$linha" | sudo tee -a /usr/local/bin/xrandr.set >>"$LOGFILE" 2>&1

  log_ok "Duplicação de monitores configurada ($tela1 = $tela2)"
fi

#===============================================================================
# 20. Sinaleiro (torre x lâmpada única)
#===============================================================================
log_step "Configurando tipo de sinaleiro"
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
log_step "Ajustando volume e limpando arquivos legados"
amixer set Master 87 >>"$LOGFILE" 2>&1
log_ok "Volume Master ajustado para 87%"

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
echo -e "Script desenvolvido por @jjmoratelli, Jurandir Moratelli ;)"
sleep 10
curl -s https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/ScreenSaver/InstalaSC.sh | bash
