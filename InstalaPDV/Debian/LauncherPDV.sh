#!/bin/bash
#===============================================================================
# Script de instalação/configuração PDV - Zanthus - DEBIAN 13 (labwc/Wayland)
# Autor original: @jjmoratelli, Jurandir Moratelli
#
# Versão para a imagem "Instalador Zeus PDV - Debian 13" da Zanthus, chamada
# pelo MenuGraficoInst.sh. O LauncherPDV.sh da pasta de cima continua sendo o
# do Ubuntu 22 e não deve mudar por causa deste.
#
# A imagem da Zanthus já faz parte do que o script do Ubuntu fazia, e isso
# fica de fora aqui:
#   - sessão gráfica: labwc do usuário zanthus (não root, não X11);
#   - subida do PDV e do Chromium: /opt/zeuspdv/bin/zeuspdv-launcher.sh;
#   - hostname, rede, DNS, CLAZ.CFG e ECF9F.CFG: perfil-360 (Zeus Config);
#   - monitores e touch: zeuspdv-telas.sh (/etc/zeuspdv-telas.json);
#   - bloqueio de atalhos: rc.xml do labwc.
# Este script completa o que é da loja: CFGs da Zanthus, fuso e NTP,
# EasyCash, desligamento, CUPS e IMP-NFE, interface, áudios, sinaleiro,
# periféricos e o protetor de tela (refeito para Wayland, seção 23).
#===============================================================================
clear

# Root logo no início: o log e o alerta dependem disso. O menu já chama com
# sudo; rodado à mão como usuário comum, eleva aqui.
if [[ "$EUID" -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

# Log fora do /tmp: no Debian o /tmp é tmpfs e o reboot do fim apagaria tudo.
mkdir -p /var/log/zanthus
LOGFILE="/var/log/zanthus/instala_pdv_$(date +%Y%m%d_%H%M%S).log"
touch "$LOGFILE"

AVISO_DIR="/tmp/aviso"
AVISO_PID=""
AVISO_TOTAL=26                     # total de seções (usado na barra de progresso)
mkdir -p "$AVISO_DIR"; chmod 755 "$AVISO_DIR"
: > "$AVISO_DIR/status"; echo AVISO > "$AVISO_DIR/modo"; rm -f "$AVISO_DIR/escolha"

# ---------------------------------------------------------------------------
# Funções de log/UI
# ---------------------------------------------------------------------------
C_RESET="\e[0m"; C_GREEN="\e[32m"; C_YELLOW="\e[33m"; C_RED="\e[31m"; C_CYAN="\e[36m"; C_BOLD="\e[1m"

# log_step [N] "Descrição"
#   Com número: alimenta a barra de progresso da janela (N de $AVISO_TOTAL).
#   Sem número: a barra volta a pulsar, só o texto é atualizado.
log_step() {
  local n=""
  if [[ "$1" =~ ^[0-9]+$ ]]; then n="$1"; shift; fi
  echo -e "\n${C_CYAN}${C_BOLD}▶ $*${C_RESET}"
  printf '%s|%s|%s\n' "${n:-0}" "$AVISO_TOTAL" "$*" > "$AVISO_DIR/status" 2>/dev/null
}
log_ok()    { echo -e "  ${C_GREEN}✔${C_RESET} $1"; }
log_skip()  { echo -e "  ${C_YELLOW}↷${C_RESET} $1 ${C_YELLOW}(já aplicado, pulando)${C_RESET}"; }
log_fora()  { echo -e "  ${C_YELLOW}↷${C_RESET} $1"; }   # fora no Debian de propósito (não é "já aplicado")
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

pkg_instalado() { dpkg -s "$1" >/dev/null 2>&1; }

# A imagem Debian vem com as listas do apt vazias: o primeiro pacote que faltar
# dispara um apt-get update, e só esse.
APT_ATUALIZADO=""
instala_pacote() {
  local pkg="$1"
  if pkg_instalado "$pkg"; then
    log_skip "Pacote $pkg"
    return 0
  fi
  if [ -z "$APT_ATUALIZADO" ]; then
    run_silent "apt-get update" apt-get update -y && APT_ATUALIZADO=1
  fi
  run_silent "Instalando $pkg" env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$pkg"
}

#===============================================================================
# ALERTA VISUAL - código da janela GTK (pode pular esta função na leitura)
#
# Diferente do Ubuntu: no Wayland não existe janela posicionada por coordenada
# (POPUP + move), então cada monitor ganha uma janela comum em tela cheia
# (fullscreen_on_monitor). E ela roda como o dono da sessão, não como root.
# Sem o modo de escolha de tela: no Debian quem cuida dos monitores é o Zeus
# Config da Zanthus (ver seção 19).
#===============================================================================
aviso_interface() {
cat << 'PYEOF' > "$AVISO_DIR/aviso.py"
import os, gi
gi.require_version('Gtk','3.0')
from gi.repository import Gtk, Gdk, GLib
GLib.set_prgname('zanthus-aviso')
D='/tmp/aviso'
def rd(f,d=''):
    try: return open(os.path.join(D,f)).read().strip()
    except Exception: return d

class Aviso:
    def __init__(self):
        self.dpy=Gdk.Display.get_default()
        self.prov=Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(),self.prov,600)
        self.wins=[]; self.geoms=[]; self.frac=None
        self.build()
        GLib.timeout_add(60,self.anim)
        GLib.timeout_add(300,self.tick)

    def gl(self): return [self.dpy.get_monitor(i).get_geometry() for i in range(self.dpy.get_n_monitors())]

    def lbl(self,box,t,n):
        l=Gtk.Label(label=t); l.set_name(n)
        l.set_justify(Gtk.Justification.CENTER); l.set_line_wrap(True)
        box.add(l); return l

    def mk(self,i,g):
        win=Gtk.Window(); win.set_decorated(False)
        win.connect('delete-event',lambda *a: True)
        ov=Gtk.Overlay()
        a=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=max(8,int(g.height*0.024)))
        a.set_halign(Gtk.Align.CENTER); a.set_valign(Gtk.Align.CENTER)
        self.lbl(a,'SISTEMA PDV','tag%d'%i)
        self.lbl(a,'ATUALIZANDO O SISTEMA','tit%d'%i)
        pb=Gtk.ProgressBar(); pb.set_name('pb%d'%i)
        pb.set_size_request(int(g.width*0.55),-1); a.add(pb)
        cnt=self.lbl(a,'','cnt%d'%i)
        step=self.lbl(a,'Iniciando...','step%d'%i); step.set_max_width_chars(46)
        self.lbl(a,'NÃO DESLIGUE O COMPUTADOR','warn%d'%i)
        self.lbl(a,'O terminal reiniciará automaticamente ao final.','sub%d'%i)
        ov.add(a)
        c=Gtk.Label(label='Desenvolvido por @JJMoratelli'); c.set_name('cred%d'%i)
        c.set_halign(Gtk.Align.END); c.set_valign(Gtk.Align.END)
        c.set_margin_end(24); c.set_margin_bottom(18); ov.add_overlay(c)
        win.add(ov); win.show_all()
        win.fullscreen_on_monitor(Gdk.Screen.get_default(), i)
        gw=win.get_window()
        if gw: gw.set_cursor(Gdk.Cursor.new_for_display(self.dpy, Gdk.CursorType.BLANK_CURSOR))
        return {'win':win,'pb':pb,'step':step,'cnt':cnt}

    def build(self):
        for w in self.wins: w['win'].destroy()
        self.geoms=self.gl()
        self.wins=[self.mk(i,g) for i,g in enumerate(self.geoms)]
        self.style()

    def style(self):
        p=['window{background:#0b0f14}']
        for i,g in enumerate(self.geoms):
            s=max(0.42,min(1.7,g.height/1080.0))
            f=lambda v,mn=10:max(mn,int(v*s))
            p.append('#tag%d{color:#7a8a9a;font-size:%dpx;letter-spacing:%dpx}'%(i,f(17,10),f(8,3)))
            p.append('#tit%d{color:#e8eef5;font-size:%dpx;font-weight:bold}'%(i,f(64,22)))
            p.append('#cnt%d{color:#5c6b7a;font-size:%dpx;letter-spacing:%dpx}'%(i,f(15,9),f(3,1)))
            p.append('#step%d{color:#7ac4ff;font-size:%dpx}'%(i,f(24,12)))
            p.append('#warn%d{color:#ff4d4d;font-size:%dpx;font-weight:bold}'%(i,f(38,16)))
            p.append('#sub%d{color:#93a3b3;font-size:%dpx}'%(i,f(20,11)))
            p.append('#cred%d{color:#3d4b59;font-size:%dpx}'%(i,f(14,9)))
            p.append('#pb%d trough{background:#1b2530;border:0;min-height:%dpx}'%(i,f(12,5)))
            p.append('#pb%d progress{background:#0a84ff;border:0;min-height:%dpx}'%(i,f(12,5)))
        self.prov.load_from_data(''.join(p).encode())

    def anim(self):
        for w in self.wins:
            pb=w['pb']
            if self.frac is None: pb.pulse()
            else:
                c=pb.get_fraction(); d=self.frac-c
                pb.set_fraction(self.frac if abs(d)<0.003 else c+d*0.18)
        return True

    def tick(self):
        g=self.gl()
        if [(x.x,x.y,x.width,x.height) for x in g]!=[(y.x,y.y,y.width,y.height) for y in self.geoms]:
            self.build(); return True
        n,tot,txt=0,0,''
        raw=rd('status')
        if raw:
            p=raw.split('|',2)
            if len(p)==3:
                try: n,tot=int(p[0]),int(p[1])
                except ValueError: n,tot=0,0
                txt=p[2]
            else: txt=raw
        txt=txt or 'Preparando ambiente...'
        self.frac=(max(0.0,min(1.0,float(n)/tot)) if (n>0 and tot>0) else None)
        c=('ETAPA %d DE %d'%(n,tot)) if (n>0 and tot>0) else ''
        for w in self.wins:
            if w['step'].get_text()!=txt: w['step'].set_text(txt)
            if w['cnt'].get_text()!=c: w['cnt'].set_text(c)
        return True

Aviso(); Gtk.main()
PYEOF
}

# --- controle do alerta -----------------------------------------------------
# A sessão do labwc é do zanthus: o root não consegue abrir janela nela. O
# alerta sobe como o dono do socket wayland-N, com o ambiente dessa sessão.
# O nome "aviso.py" na linha de comando é a marca que a tela de carregamento
# do menu procura para sair de cena.
SESSAO_SOCK=""
for _s in /run/user/*/wayland-[0-9]; do
  [ -S "$_s" ] || continue
  if [ "$(stat -c %u "$_s")" -ge 1000 ]; then SESSAO_SOCK="$_s"; break; fi
done

aviso_abre() {
  [ -n "$SESSAO_SOCK" ] || return 1
  runuser -u "$(stat -c %U "$SESSAO_SOCK")" -- env \
    XDG_RUNTIME_DIR="${SESSAO_SOCK%/*}" WAYLAND_DISPLAY="${SESSAO_SOCK##*/}" \
    GDK_BACKEND=wayland DBUS_SESSION_BUS_ADDRESS="unix:path=${SESSAO_SOCK%/*}/bus" \
    python3 "$AVISO_DIR/aviso.py" >>"$LOGFILE" 2>&1 &
  AVISO_PID=$!
  sleep 1
}
aviso_fecha() { [ -n "$AVISO_PID" ] && kill "$AVISO_PID" 2>/dev/null; AVISO_PID=""; }
aviso_vivo()  { [ -n "$AVISO_PID" ] && kill -0 "$AVISO_PID" 2>/dev/null; }

trap 'aviso_fecha' EXIT

#===============================================================================
# 1. Encerramento seguro dos processos PDV
#===============================================================================
log_step 1 "Encerrando processos PDV com segurança"
# Nomes exatos: o "pkill chro" do Ubuntu derruba também o chronyd (relógio).
# Ordem do zeuspdv-launcher.sh ao reiniciar: launcher e vigias, núcleo, telas.
pkill -f '/opt/zeuspdv/bin/zeuspdv-launcher.sh'
pkill -f 'zeuspdv-vigia-java'
pkill -9 -f 'pdvJava2' ; pkill -9 -f 'lnx_' ; pkill -9 -f 'jpdvgui'
log_info "Aguardando encerramento do sistema PDV..."
sleep 10
pkill -f -- '--user-data-dir=/home/zanthus/.cache/zeuspdv/chrome-'
sleep 2
log_ok "Processos encerrados"

#===============================================================================
# 2. Validações iniciais (o root já foi garantido no topo)
#===============================================================================
log_step 2 "Validações iniciais"
log_ok "Script sendo executado como usuário root"

# Alerta visual para o operador, na sessão do labwc
if [ -z "$SESSAO_SOCK" ]; then
  log_fail "Sessão gráfica (wayland) não encontrada - seguindo sem alerta visual"
elif ! python3 -c "import gi" >/dev/null 2>&1; then
  log_fail "python3-gi ausente - seguindo sem alerta visual"
else
  aviso_interface
  aviso_abre && log_ok "Alerta visual em tela cheia iniciado"
fi

#===============================================================================
# 3. Leitura de variáveis em disco (Filial, Caixa, Tipo de Instalação, Balança)
#    (unificada - antes existia duplicada no passo1 e no passo2)
#===============================================================================
log_step 3 "Lendo configuração local"
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
# 3.2 CONFIGURAÇÕES FIXAS DO LAUNCHER.CONF
#    (vinham do antigo instala_screensaver.sh - passo2)
#===============================================================================
# URL de origem do vídeo do screensaver (usada pelo launcher/atualizaSC embutido).
# Nome completo: no Debian o "serv-web" curto só resolve com o search do
# resolv.conf, que o perfil-360 reescreve sem ele quando é reaplicado.
SCREENSAVER_URL_BASE="http://serv-web.machadao.corp/uploads/screensaver"   # + /<filial>/screensaver.mp4

# Onde o launcher.conf será gravado.
CONF_PATH="/Zanthus/Zeus/pdvJava/launcher.conf"

# Valores FIXOS gravados no launcher.conf (iguais para todos os caixas da loja).
# Só estes precisam ser ajustados quando a loja/rede muda - o restante
# (FILIAL/CAIXA/TIPO/BALANCA) é lido do disco automaticamente (seção 3 acima).
CONF_TELA_CLIENTE="false"
CONF_MIRAGE_IP="192.168.12.42"
CONF_BALANCE_IP="192.168.12.44"
CONF_DAEMONIZE="true"

#===============================================================================
# 4. Desativação de atalhos de teclado (keyd)
#===============================================================================
log_step 4 "Bloqueio de atalhos de teclado"
# Sem keyd no Debian: os atalhos ficam no rc.xml do labwc, gerado a cada boot
# pelo zeuspdv-launcher.sh, e o keyd brigaria com Ctrl+Alt+D e Ctrl+Alt+F
# que a Zanthus usa ali.
log_fora "Debian: atalhos controlados pelo labwc (Zanthus)"

#===============================================================================
# 5. Ajustes de rede: sysctl
#    /etc/hosts e nsswitch ficam como o perfil-360 deixou: o hosts já vem com a
#    linha do IP (sem 127.0.1.1) e o nsswitch com o mDNS dos nomes .local.
#===============================================================================
log_step 5 "Otimizando parâmetros de rede"

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
log_step 6 "Ajustando timeouts de conexão (CARG0000, RESTG0000, ZMWS0000)"
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
log_ok "CARG0000.CFG: timeout e endereço (mirage) ajustados"

printf "Vivo=22\nClaro=12000000\nOi=35000000\nTim=74000000\nBrasil Telecom=11\nCTBC-Celular=12201\nCTBC-Fixo=12299\nEmbratel=14000000\nSercomtel-Celular=12301\nSercomtel-Fixo=12399\nL Economica=97100\nNextel=75000000\n" > /Zanthus/Zeus/pdvJava/RECRGOP0.CFG
chmod 777 /Zanthus/Zeus/pdvJava/RECRGOP0.CFG
log_ok "Operadoras de recarga configuradas (RECRGOP0.CFG)"

#===============================================================================
# 7. journald - limitar uso de disco
#===============================================================================
log_step 7 "Limitando o uso de disco do journald"
# Sem Storage=none: o Debian não tem rsyslog, então o journal é o único log do
# terminal (e o monitor de periféricos da Zanthus lê dele). Só limita o tamanho.
JOURNALD_DROPIN="/etc/systemd/journald.conf.d/50-zanthus.conf"
if [ -f "$JOURNALD_DROPIN" ]; then
  log_skip "Limite do journald"
else
  mkdir -p "$(dirname "$JOURNALD_DROPIN")"
  printf "[Journal]\nSystemMaxUse=1G\nSystemMaxFileSize=128M\n" > "$JOURNALD_DROPIN"
  run_silent "Reiniciando journald" systemctl restart systemd-journald
fi

#===============================================================================
# 8. GRUB - parâmetros para máquinas legado
#    Confere pelos próprios parâmetros: a linha do Debian é "quiet reboot=efi",
#    sem o "splash" que a conferência do Ubuntu esperava (lá, aqui ela nunca
#    passaria e a máquina reiniciaria a cada execução).
#===============================================================================
log_step 8 "Verificando parâmetros do GRUB"
cutoff_year=2018
bios_year=$(dmidecode -t 0 | grep "Release Date" | awk -F: '{ print $2 }' | sed 's/^[ \t]*//;s/[ \t]*$//' | awk -F'/' '{ print $3 }')

if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=".*pci=nommconf' /etc/default/grub; then
  log_skip "Ajustes de GRUB já aplicados"
elif [[ "${bios_year:-9999}" -lt "$cutoff_year" ]]; then
  log_info "BIOS anterior a 2018 detectada - aplicando ajustes legados"
  sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 pci=nommconf pcie_aspm=off pci=noaer"/' /etc/default/grub
  run_silent "Atualizando GRUB" update-grub
  log_info "A máquina será reiniciada. Reinicie o script após o boot para continuar."
  sleep 5
  systemctl reboot
  exit 0
else
  log_ok "BIOS posterior a 2018 - sem ajustes legados necessários"
fi

#===============================================================================
# 9. DNS
#    Sem systemd-resolved no Debian: os servidores ficam no /etc/resolv.conf
#    que o perfil-360 grava. Aqui só entram o domínio da rede e o gateway como
#    terceiro servidor (o FallbackDNS do Ubuntu).
#===============================================================================
log_step 9 "Ajustando /etc/resolv.conf"
DEFAULT_GW=$(ip -4 route show default | awk '{print $3}' | head -n 1)
if grep -q '^search machadao.corp$' /etc/resolv.conf; then
  log_skip "Domínio machadao.corp no resolv.conf"
else
  sed -i '/^search /d' /etc/resolv.conf
  sed -i '1i search machadao.corp' /etc/resolv.conf
  log_ok "Domínio machadao.corp adicionado"
fi
if [ -n "$DEFAULT_GW" ] && ! grep -q "^nameserver ${DEFAULT_GW}$" /etc/resolv.conf \
    && [ "$(grep -c '^nameserver' /etc/resolv.conf)" -lt 3 ]; then
  echo "nameserver ${DEFAULT_GW}" >> /etc/resolv.conf
  log_ok "Gateway ${DEFAULT_GW} como DNS reserva"
else
  log_skip "DNS reserva no resolv.conf"
fi

#===============================================================================
# 10. Timeout Sefaz
#===============================================================================
log_step 10 "Ajustando timeout da Sefaz"
sudo printf "timeout=60\n" > /Zanthus/Zeus/pdvJava/ZMWS1201.CFG
log_ok "ZMWS1201.CFG ajustado (timeout Sefaz)"

#===============================================================================
# 11. CUPS - configuração global
#===============================================================================
# A imagem Debian não traz o CUPS, e a IMP-NFE (Kyocera de rede da loja) segue
# necessária (decidido em 07/11/2026): o pacote é instalado aqui.
log_step 11 "Ajustando CUPS"
instala_pacote cups
if ! command -v cupsctl >/dev/null 2>&1; then
  log_fail "CUPS não ficou instalado - impressora IMP-NFE não será configurada"
else
  sed 's/^BrowseLocalProtocols.*$/BrowseLocalProtocols\ none/' -i /etc/cups/cupsd.conf
  run_silent "Reiniciando serviço CUPS" bash -c "cupsctl Web=yes; systemctl restart cups"
  run_silent "Habilitando administração remota" cupsctl --remote-admin --remote-any
  printf "linux.impressora=IMP-NFE\nlinux.opcoes=3\n" > /Zanthus/Zeus/pdvJava/ZPDF00.CFG
  log_ok "CUPS configurado"
fi

#===============================================================================
# 12. Instalação de impressora (Via Variáveis Globais)
#===============================================================================
log_step 12 "Configurando impressora fiscal - Loja $NOME_LOJA"
if ! command -v lpadmin >/dev/null 2>&1; then
  log_fora "Sem CUPS: impressora IMP-NFE não cadastrada"
elif lpstat -p IMP-NFE >/dev/null 2>&1; then
  log_skip "Impressora IMP-NFE já cadastrada no CUPS"
else
  log_info "Baixando driver: $CONF_IMPRESSORA_PPD"
  safe_download "$CONF_IMPRESSORA_URL" "/usr/share/cups/model/$CONF_IMPRESSORA_PPD"
  run_silent "Cadastrando impressora IMP-NFE ($CONF_IMPRESSORA_IP)" lpadmin -p IMP-NFE -E -v socket://$CONF_IMPRESSORA_IP -i /usr/share/cups/model/$CONF_IMPRESSORA_PPD
fi

#===============================================================================
# 13. Fuso horário e NTP (Via Variáveis Globais)
#    O Debian usa chrony (não ntp): o servidor da rede entra como fonte
#    preferida num arquivo próprio em /etc/chrony/sources.d.
#    O relógio de hardware fica em hora local, igual ao Ubuntu (decidido em
#    07/11/2026); a imagem Debian vem com ele em UTC.
#===============================================================================
log_step 13 "Ajustando fuso horário e NTP"
CHRONY_FONTE="/etc/chrony/sources.d/zanthus.sources"
if [ -f "$CHRONY_FONTE" ]; then
  log_skip "Servidor NTP da rede no chrony"
else
  mkdir -p "$(dirname "$CHRONY_FONTE")"
  echo "server ntp.redejcm.com.br iburst prefer" > "$CHRONY_FONTE"
  run_silent "Recarregando fontes do chrony" chronyc reload sources
fi

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
log_step 14 "Configurando servidor EasyCash"
printf "ENDERECO=$CONF_EASYCASH_IP\nPORTA=23454\n" > /Zanthus/Zeus/pdvJava/ZPPERD01.CFG
printf "TIPO01=1\nOPCOESLOG=255\n" > /Zanthus/Zeus/pdvJava/ZPPERD00.CFG
log_ok "Arquivos EasyCash gravados (IP: $CONF_EASYCASH_IP)"

log_step 14 "Agendando desligamento automático (cron)"
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
log_step 15 "Copiando arquivos de interface para tipo: $tipoInstala"

# A interface da imagem Debian (InstaladorPDV-3.D13) é de outra geração que a
# do Ubuntu, onde estes arquivos foram customizados. Antes da primeira troca,
# guarda a original inteira para dar para voltar se algo não casar.
BACKUP_IFACE="/Zanthus/Zeus/backup_interface_original.tar.gz"
if [ -f "$BACKUP_IFACE" ]; then
  log_skip "Backup da interface original"
else
  run_silent "Guardando a interface original em $BACKUP_IFACE" \
    tar -czf "$BACKUP_IFACE" -C /Zanthus/Zeus --exclude='Interface/Interface.zip' Interface
fi

if [ "$tipoInstala" == "SelfCheckout" ]; then
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/telas_touch.js" "/Zanthus/Zeus/Interface/resources/js/telas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Self/animacao-codigo-pdv.svg" "/Zanthus/Zeus/Interface/resources/imagens/animacao-codigo-pdv.svg"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Self/animacao-pagamento-pdv.svg" "/Zanthus/Zeus/Interface/resources/imagens/animacao-pagamento-pdv.svg"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Self/teclas_touch.js" "/Zanthus/Zeus/Interface/resources/js/teclas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/TelaComanda.js" "/Zanthus/Zeus/Interface/app/view/tela/2/TelaComanda.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Self/config.js" "/Zanthus/Zeus/Interface/config/config.js"
fi

if [ "$tipoInstala" == "Lanchonete" ]; then
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/telas_touch.js" "/Zanthus/Zeus/Interface/resources/js/telas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Lanchonete/teclas_touch.js" "/Zanthus/Zeus/Interface/resources/js/teclas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/TelaComanda.js" "/Zanthus/Zeus/Interface/app/view/tela/2/TelaComanda.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/config.js" "/Zanthus/Zeus/Interface/config/config.js"
fi

if [ "$tipoInstala" == "PDVTouch" ]; then
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/telas_touch.js" "/Zanthus/Zeus/Interface/resources/js/telas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Touch/teclas_touch.js" "/Zanthus/Zeus/Interface/resources/js/teclas_touch.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/config.js" "/Zanthus/Zeus/Interface/config/config.js"
fi

if [ "$tipoInstala" == "PDVComum" ]; then
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/PDVComum/config.js" "/Zanthus/Zeus/Interface/config/config.js"
    safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/PDVComum/Controller.js" "/Zanthus/Zeus/Interface/app/controller/Controller.js"
fi

log_step 15 "Copiando arquivos gerais de interface"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/Zeus_V.gif" "/Zanthus/Zeus/Interface/resources/imagens/Zeus_V.gif"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/logo.png" "/Zanthus/Zeus/Interface/resources/imagens/logo.png"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/logo_self.png" "/Zanthus/Zeus/Interface/resources/imagens/logo_self.png"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/descanso1000.jpg" "/Zanthus/Zeus/Interface/resources/imagens/descanso1000.jpg"

rm -f /Zanthus/Zeus/Interface/resources/imagens/self/codigo.gif
rm -f /Zanthus/Zeus/Interface/resources/imagens/cancela_sel.png
rm -f /Zanthus/Zeus/Interface/resources/imagens/cancela.png
log_ok "Arquivos obsoletos removidos (codigo.gif, cancela*.png)"

safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/style100.css" "/Zanthus/Zeus/Interface/resources/css/style100.css"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/style1000.css" "/Zanthus/Zeus/Interface/resources/css/style1000.css"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/style2.css" "/Zanthus/Zeus/Interface/resources/css/style2.css"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/stylemonitor_cliente.css" "/Zanthus/Zeus/Interface/resources/css/stylemonitor_cliente.css"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Interfaces/Comum/Buttons.js" "/Zanthus/Zeus/Interface/app/api/dinamico/pdvMouse/Buttons.js"

chmod 777 -R /Zanthus/Zeus/Interface/
log_ok "Permissões aplicadas em /Zanthus/Zeus/Interface/"

#===============================================================================
# 16. Áudios do PDV
#===============================================================================
log_step 16 "Baixando arquivos de áudio"
if [ "$tipoInstala" == "SelfCheckout" ]; then
  base_url="https://github.com/JMoratelli/Zanthus/raw/refs/heads/main/InstalaPDV/Interfaces/Self/audio/"
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
# DESLIGADO NO DEBIAN POR ENQUANTO (decisão de 07/11/2026).
# Motivo: a imagem Debian não traz o 7z para extrair a libCliSiTef.7z, e o TEF
# ainda não foi validado neste sistema. A ideia é validar primeiro o resto da
# instalação e só então trazer o CliSiTef de volta (instalando o pacote 7zip
# antes da extração). O bloco original segue abaixo, comentado.
log_step 17 "Configurando CliSiTef"
log_fora "Debian: CliSiTef fora por enquanto, até validar o resto da instalação"
# if [ "$tipoInstala" == "SelfCheckout" ]; then
#     safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDVJava/Self/CliSiTef.ini" "/Zanthus/Zeus/pdvJava/CliSiTef.ini"
# else
#     safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDVJava/Comum/CliSiTef.ini" "/Zanthus/Zeus/pdvJava/CliSiTef.ini"
# fi
#
# chmod 777 -R /Zanthus/Zeus/pdvJava/CliSiTef.ini
# safe_wget "http://192.168.12.223/uploads/interfaceZanthus/libCliSiTef.7z" "/Zanthus/Zeus/pdvJava/libCliSiTef.7z"
# run_silent "Extraindo libCliSiTef" 7z x -o/Zanthus/Zeus/pdvJava/ -y /Zanthus/Zeus/pdvJava/libCliSiTef.7z

#===============================================================================
# 18. Rede Docker
#===============================================================================
log_step 18 "Ajustando rede Docker"
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
# 19. Monitores
#    No Debian quem cuida disso é a Zanthus: o Zeus Config grava resolução,
#    orientação e touch em /etc/zeuspdv-telas.json e a tela do operador em
#    /etc/zeuspdv-monitores.conf (OPERADOR_SAIDA/CLIENTE_SAIDA), e o
#    zeuspdv-telas.sh aplica no boot via wlr-randr. O xrandr do Ubuntu aqui só
#    enxergaria o Xwayland e não mudaria nada.
#===============================================================================
log_step 19 "Conferindo monitores"
if [ -f /etc/zeuspdv-monitores.conf ]; then
  log_fora "Monitores pelo Zeus Config: $(tr '\n' ' ' < /etc/zeuspdv-monitores.conf)"
else
  log_fail "Sem /etc/zeuspdv-monitores.conf: identifique os monitores no Zeus Config"
fi

#===============================================================================
# 20. Sinaleiro (torre x lâmpada única)
#===============================================================================
log_step 20 "Configurando sinaleiro"
# ATENÇÃO: bug pré-existente - a variável $ip nunca é definida neste script,
# então a comparação abaixo sempre cai no else (lâmpada única).
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
log_step 21 "Limpando arquivos legados"
amixer set Master 87 >>"$LOGFILE" 2>&1
rm -f /opt/webadmin/extra/rules/Balanca/toledoDCPSC-var.sh
rm -f /Zanthus/Zeus/Interface/resources/imagens/processando.gif
log_ok "Arquivos legados removidos"

#===============================================================================
# 22. Periféricos USB (balança, etc.)
#===============================================================================
log_step 22 "Instalando script de periféricos USB"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Utilitarios/PerifericosUSB.sh" "/home/zanthus/PerifericosUSB.sh"
chmod +x /home/zanthus/PerifericosUSB.sh
run_silent "Executando PerifericosUSB.sh" /home/zanthus/PerifericosUSB.sh

#===============================================================================
# 23. Protetor de tela (Wayland)
#    O xscreensaver do Ubuntu só funciona em X11. O equivalente aqui:
#    - zanthus-protetor: swayidle (ociosidade do labwc) abre o mesmo vídeo no
#      mpv em tela cheia; qualquer toque ou tecla fecha. Sobe por um serviço de
#      usuário global (/etc/systemd/user), junto com a sessão do zanthus, sem
#      mexer no autostart do labwc, que é da Zanthus;
#    - zanthus-atualiza-protetor: baixa o vídeo da filial a cada boot quando o
#      tamanho no servidor muda. No Ubuntu isso é o atualizaSC do PDVTouch.sh,
#      que no Debian não roda.
#    Mesma regra do Ubuntu: protetor só em PDV Comum, Touch e Lanchonete.
#    Fora também: ubuntu-restricted-extras (não existe no Debian) e o
#    "export DISPLAY=:0" no /etc/profile (vazaria para o login que sobe o labwc).
#===============================================================================
log_step 23 "Configurando protetor de tela"
PROTETOR_VIDEO="/home/zanthus/scsmachadao.mp4"
PROTETOR_TEMPO=600                 # s sem uso até o vídeo (o timeout do .xscreensaver)

if [[ "$tipoInstala" == "PDVComum" || "$tipoInstala" == "PDVTouch" || "$tipoInstala" == "Lanchonete" ]]; then
  instala_pacote swayidle
  instala_pacote mpv

  # --- atualização do vídeo (root, no boot) ---------------------------------
  {
    echo '#!/bin/bash'
    echo '# Gerado pelo Debian/LauncherPDV.sh. Baixa o vídeo do protetor da filial'
    echo '# quando o tamanho no servidor muda (o atualizaSC do Ubuntu).'
    echo "URL=\"${SCREENSAVER_URL_BASE}/${filial}/screensaver.mp4\""
    echo "DESTINO=\"${PROTETOR_VIDEO}\""
    cat << 'EOF'
remoto=$(curl -sIL -m 20 "$URL" | grep -ioP '^content-length:\s*\K[0-9]+' | tail -n1)
atual=$(stat -c%s "$DESTINO" 2>/dev/null || echo 0)
if [ -z "$remoto" ] || [ "$remoto" -eq 0 ]; then
  logger -t zanthus-protetor "sem tamanho remoto para $URL - mantendo o vídeo atual"
  exit 0
fi
[ "$remoto" -eq "$atual" ] && exit 0
tmp="${DESTINO}.baixando"
if curl -sfL -m 900 -o "$tmp" "$URL" && [ "$(stat -c%s "$tmp")" -eq "$remoto" ]; then
  chown zanthus:zanthus "$tmp" && mv -f "$tmp" "$DESTINO"
  logger -t zanthus-protetor "vídeo atualizado ($remoto bytes)"
else
  rm -f "$tmp"
  logger -t zanthus-protetor "falha ao baixar $URL"
fi
EOF
  } > /usr/local/bin/zanthus-atualiza-protetor
  chmod 755 /usr/local/bin/zanthus-atualiza-protetor

  cat > /etc/systemd/system/zanthus-atualiza-protetor.service << 'EOF'
[Unit]
Description=Zanthus - atualiza o video do protetor de tela da filial
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/zanthus-atualiza-protetor

[Install]
WantedBy=multi-user.target
EOF
  run_silent "Habilitando a atualização do vídeo no boot" systemctl enable zanthus-atualiza-protetor.service
  run_silent "Baixando o vídeo do protetor da filial ${filial}" /usr/local/bin/zanthus-atualiza-protetor

  # --- protetor na sessão do zanthus ---------------------------------------
  {
    echo '#!/bin/bash'
    echo '# Gerado pelo Debian/LauncherPDV.sh. Protetor de tela do PDV no labwc:'
    echo '# depois de TEMPO sem uso, o vídeo da filial em tela cheia; qualquer toque'
    echo '# ou tecla fecha. Sobe pelo serviço de usuário zanthus-protetor.'
    echo "TEMPO=${PROTETOR_TEMPO}"
    echo "VIDEO=\"${PROTETOR_VIDEO}\""
    cat << 'EOF'
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
# a sessão do usuário sobe antes do labwc: espera o socket aparecer
until [ -S "$XDG_RUNTIME_DIR/wayland-0" ]; do sleep 2; done
export WAYLAND_DISPLAY=wayland-0
# tela do operador, como o Zeus Config deixou
SAIDA=$(sed -n 's/^OPERADOR_SAIDA=//p' /etc/zeuspdv-monitores.conf 2>/dev/null)
MPV="mpv --fullscreen ${SAIDA:+--fs-screen-name=$SAIDA} --loop=inf --no-osc --no-osd-bar"
MPV="$MPV --keepaspect=no --really-quiet --no-input-default-bindings"
MPV="$MPV --wayland-app-id=zanthus-protetor"
# Sem isto o mpv pede ao labwc para não considerar o sistema ocioso enquanto
# toca, o swayidle entende como retomada e fecha o vídeo assim que ele abre.
MPV="$MPV --stop-screensaver=no"
# A retomada encerra pelo PID gravado na abertura: um pkill -f pelo nome do
# vídeo ou do título casaria também com a linha de comando deste swayidle.
PID="$XDG_RUNTIME_DIR/zanthus-protetor.pid"
exec swayidle \
  timeout "$TEMPO" "[ -s '$VIDEO' ] && { $MPV '$VIDEO' & echo \$! > '$PID'; }" \
  resume "[ -f '$PID' ] && kill \$(cat '$PID') 2>/dev/null; rm -f '$PID'"
EOF
  } > /usr/local/bin/zanthus-protetor
  chmod 755 /usr/local/bin/zanthus-protetor

  cat > /etc/systemd/user/zanthus-protetor.service << 'EOF'
[Unit]
Description=Zanthus - protetor de tela do PDV (swayidle + mpv)
ConditionUser=zanthus

[Service]
ExecStart=/usr/local/bin/zanthus-protetor
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
  run_silent "Habilitando o protetor na sessão do zanthus" systemctl --global enable zanthus-protetor.service
else
  systemctl --global disable zanthus-protetor.service >/dev/null 2>&1
  log_fora "Protetor de tela não se aplica a ${tipoInstala:-tipo desconhecido}"
fi

#===============================================================================
# 24 e 25. Launcher PDVTouch.sh e launcher.conf
#    DESLIGADOS NO DEBIAN POR ENQUANTO (decisão de 07/11/2026): o PDVTouch.sh
#    não é mexido até o resto da instalação estar validado. Hoje, no Debian,
#    quem sobe o PDV é o /opt/zeuspdv/bin/zeuspdv-launcher.sh da Zanthus, e o
#    PDVTouch.sh (versão da imagem) nem é chamado; o nosso binário foi feito
#    para a sessão X do root no Ubuntu. O launcher.conf só é lido por ele.
#    Os blocos originais seguem abaixo, comentados.
#===============================================================================
log_step 24 "Launcher PDVTouch.sh"
log_fora "Debian: PDVTouch.sh e launcher.conf fora até validar o resto"

# #===============================================================================
# # 24. Download do launcher (só se o tamanho mudou)
# #    (vinha do antigo instala_screensaver.sh - passo2, seção 4.1)
# #===============================================================================
# # O launcher já existe (versão antiga). Só rebaixa se o tamanho do arquivo
# # remoto for diferente do local - evita baixar ~17MB a cada execução.
# # OBS: o GitHub raw responde em HTTP/2, então o header vem MINÚSCULO
# # (content-length) - por isso o grep é case-insensitive (-i), diferente do
# # atualizaSC que fala com o serv-web.
# LAUNCHER_URL="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDVJava/Comum/PDVTouch.sh"
# LAUNCHER_PATH="/Zanthus/Zeus/pdvJava/PDVTouch.sh"
#
# log_step 24 "Verificando launcher (PDVTouch.sh)"
# tam_remoto=$(curl -sIL "$LAUNCHER_URL" | grep -ioP 'content-length:\s*\K[0-9]+' | tail -n1)
# tam_local=$(stat -c%s "$LAUNCHER_PATH" 2>/dev/null)
#
# # Garante valor numérico (remove não-dígitos; vazio -> 0)
# tam_remoto=${tam_remoto//[^0-9]/}; tam_remoto=${tam_remoto:-0}
# tam_local=${tam_local//[^0-9]/};   tam_local=${tam_local:-0}
#
# if [ "$tam_remoto" -eq 0 ]; then
#     log_fail "Não consegui obter o tamanho remoto do launcher - mantendo o atual"
# elif [ "$tam_local" -eq "$tam_remoto" ]; then
#     log_skip "Launcher já atualizado (${tam_local} bytes)"
# else
#     log_info "Tamanho difere (local: ${tam_local}B | remoto: ${tam_remoto}B) - baixando"
#     rm -f /Zanthus/Zeus/pdvJava/PDVTouch.sh
#     safe_download "$LAUNCHER_URL" "$LAUNCHER_PATH"
#     chmod +x "$LAUNCHER_PATH"
# fi
#
# #===============================================================================
# # 25. Geração do launcher.conf
# #    O launcher (binário Rust) lê este .conf e faz toda a orquestração no boot
# #    (chromium, periféricos, xscreensaver, atualizaSC, resolução via xrandr,
# #    gateway e caminhos - tudo automático). Aqui só gravamos os campos que
# #    variam por caixa; os fixos vêm das constantes CONF_* da seção 3.2.
# #    O .conf é gravado SEM comentários.
# #===============================================================================
# log_step 25 "Gerando launcher.conf para o tipo: ${tipoInstala:-Desconhecido}"
#
# # Normaliza a balança para o vocabulário do launcher (vazio -> Nenhuma)
# balancaConf="${tipoBalanca:-Nenhuma}"
#
# if [ -z "$tipoInstala" ]; then
#     log_fail "Tipo de instalação desconhecido (${tipoInstala:-vazio}) - launcher.conf não será gerado"
# else
#     mkdir -p "$(dirname "$CONF_PATH")"
#     cat << EOF > "$CONF_PATH"
# FILIAL=${filial}
# CAIXA=${caixa}
# TIPO=${tipoInstala}
# BALANCA=${balancaConf}
# TELA_CLIENTE=${CONF_TELA_CLIENTE}
# MIRAGE_IP=${CONF_MIRAGE_IP}
# BALANCE_IP=${CONF_BALANCE_IP}
# DAEMONIZE=${CONF_DAEMONIZE}
# EOF
#     chmod 644 "$CONF_PATH"
#     log_ok "launcher.conf gerado em $CONF_PATH"
#     log_info "Filial ${filial:-ND} | Caixa ${caixa:-ND} | ${tipoInstala} | Balança ${balancaConf}"
# fi

#===============================================================================
# 26. Finalização e reboot
#===============================================================================
log_step 26 "Concluindo"
echo -e "\n${C_GREEN}${C_BOLD}✔ Instalação/configuração concluída.${C_RESET}"
echo -e "Log completo em: ${C_CYAN}$LOGFILE${C_RESET}"
log_info "Script feito por @jjmoratelli, Jurandir Moratelli"
sleep 5
for i in {1..10}; do
  echo -e "  ${C_YELLOW}Contagem regressiva: $((10 - i))${C_RESET}"
  sleep 1
done
log_step 26 "Reiniciando o terminal..."
sleep 2
aviso_fecha
systemctl reboot
