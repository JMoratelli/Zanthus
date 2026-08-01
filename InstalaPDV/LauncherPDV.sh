#!/bin/bash
#===============================================================================
# Script de instalação/configuração PDV - Zanthus
# Autor original: @jjmoratelli, Jurandir Moratelli
#
# VERSÃO MESCLADA (passo1 + passo2 em um único script):
# ALERTA VISUAL (GTK):
#===============================================================================
clear
LOGFILE="/tmp/instala_pdv_$(date +%Y%m%d_%H%M%S).log"
touch "$LOGFILE"

AVISO_DIR="/tmp/aviso"
AVISO_PID=""
AVISO_TOTAL=26                     # total de seções (usado na barra de progresso)
mkdir -p "$AVISO_DIR"
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

#===============================================================================
# ALERTA VISUAL - código da janela GTK (pode pular esta função na leitura)
#===============================================================================
aviso_interface() {
cat << 'PYEOF' > "$AVISO_DIR/aviso.py"
import os, gi
gi.require_version('Gtk','3.0')
from gi.repository import Gtk, Gdk, GLib
D='/tmp/aviso'
def rd(f,d=''):
    try: return open(os.path.join(D,f)).read().strip()
    except Exception: return d

class Aviso:
    def __init__(self):
        self.dpy=Gdk.Display.get_default()
        self.prov=Gtk.CssProvider()
        Gtk.StyleContext.add_provider_for_screen(Gdk.Screen.get_default(),self.prov,600)
        self.wins=[]; self.geoms=[]; self.modo=None; self.frac=None
        self.build()
        GLib.timeout_add(60,self.anim)
        GLib.timeout_add(300,self.tick)

    def gl(self): return [self.dpy.get_monitor(i).get_geometry() for i in range(self.dpy.get_n_monitors())]

    def outs(self):
        # (x,y) -> (nome_da_saida, ordinal)  - ordinal = ordem do xrandr
        m={}
        for ln in rd('saidas').splitlines():
            p=ln.split()
            if len(p)>=6: m[(int(p[1]),int(p[2]))]=(p[0],int(p[5]))
            elif len(p)>=3: m[(int(p[1]),int(p[2]))]=(p[0],0)
        return m

    def lbl(self,box,t,n):
        l=Gtk.Label(label=t); l.set_name(n)
        l.set_justify(Gtk.Justification.CENTER); l.set_line_wrap(True)
        box.add(l); return l

    def mk(self,i,g):
        win=Gtk.Window(type=Gtk.WindowType.POPUP); ov=Gtk.Overlay()
        root=Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        root.set_halign(Gtk.Align.CENTER); root.set_valign(Gtk.Align.CENTER)
        sp=max(8,int(g.height*0.024))

        # --- painel de andamento ---
        a=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=sp); a.set_halign(Gtk.Align.CENTER)
        self.lbl(a,'SISTEMA PDV','tag%d'%i)
        self.lbl(a,'ATUALIZANDO O SISTEMA','tit%d'%i)
        pb=Gtk.ProgressBar(); pb.set_name('pb%d'%i)
        pb.set_size_request(int(g.width*0.55),-1); a.add(pb)
        cnt=self.lbl(a,'','cnt%d'%i)
        step=self.lbl(a,'Iniciando...','step%d'%i); step.set_max_width_chars(46)
        self.lbl(a,'NÃO DESLIGUE O COMPUTADOR','warn%d'%i)
        self.lbl(a,'O terminal reiniciará automaticamente ao final.','sub%d'%i)

        # --- painel de escolha de tela ---
        e=Gtk.Box(orientation=Gtk.Orientation.VERTICAL,spacing=sp); e.set_halign(Gtk.Align.CENTER)
        self.lbl(e,'CONFIGURAÇÃO DE MONITORES','tag%d'%i)
        tit=self.lbl(e,'SOU A TELA %d'%(i+1),'tit%d'%i)
        info=self.lbl(e,'','sub%d'%i)
        self.lbl(e,'Esta é a tela do OPERADOR?','step%d'%i)
        b1=Gtk.Button(label='SIM, USAR ESTA TELA'); b1.set_name('b%d'%i)
        b1.connect('clicked',self.pick,i); e.add(b1)
        b2=Gtk.Button(label='DUPLICAR AS TELAS'); b2.set_name('b%d'%i)
        b2.connect('clicked',lambda *_: self.write('DUPLICAR')); e.add(b2)
        self.lbl(e,'A outra tela será a do cliente.','sub%d'%i)

        root.add(a); root.add(e); ov.add(root)
        c=Gtk.Label(label='Desenvolvido por @JJMoratelli'); c.set_name('cred%d'%i)
        c.set_halign(Gtk.Align.END); c.set_valign(Gtk.Align.END)
        c.set_margin_end(24); c.set_margin_bottom(18); ov.add_overlay(c)
        win.add(ov); win.show_all(); e.hide()
        win.move(g.x,g.y); win.resize(g.width,g.height)
        return {'win':win,'pb':pb,'step':step,'cnt':cnt,'a':a,'e':e,'info':info,'tit':tit,'i':i}

    def build(self):
        for w in self.wins: w['win'].destroy()
        self.geoms=self.gl()
        self.wins=[self.mk(i,g) for i,g in enumerate(self.geoms)]
        self.style(); self.modo=None
        for w in self.wins:
            gw=w['win'].get_window()
            if gw: gw.set_cursor(Gdk.Cursor(Gdk.CursorType.BLANK_CURSOR))

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
            p.append('#b%d{background-image:none;background-color:#12324f;color:#e8eef5;border:2px solid #2b6cb0;border-radius:%dpx;font-size:%dpx;font-weight:bold;padding:%dpx %dpx}'%(i,f(12,6),f(26,13),f(18,8),f(40,16)))
            p.append('#b%d:hover{background-color:#1a4a72}'%i)
            p.append('#b%d:active{background-color:#0a84ff}'%i)
        self.prov.load_from_data(''.join(p).encode())

    def anim(self):
        for w in self.wins:
            pb=w['pb']
            if self.frac is None: pb.pulse()
            else:
                c=pb.get_fraction(); d=self.frac-c
                pb.set_fraction(self.frac if abs(d)<0.003 else c+d*0.18)
        return True

    def pick(self,_b,i):
        g=self.geoms[i]
        self.write(self.outs().get((g.x,g.y),('',0))[0] or 'TELA%d'%(i+1))

    def write(self,v):
        try: open(os.path.join(D,'escolha'),'w').write(v+'\n')
        except Exception: pass

    def tick(self):
        g=self.gl()
        if len(g)!=len(self.geoms):
            self.build(); return True
        if any((x.x,x.y,x.width,x.height)!=(y.x,y.y,y.width,y.height) for x,y in zip(g,self.geoms)):
            self.geoms=g
            for w in self.wins:
                gg=g[w['i']]
                w['win'].move(gg.x,gg.y); w['win'].resize(gg.width,gg.height)
                w['pb'].set_size_request(int(gg.width*0.55),-1)
            self.style()

        modo=rd('modo','AVISO') or 'AVISO'
        if modo!=self.modo:
            self.modo=modo; esc=(modo=='ESCOLHA'); om=self.outs()
            for w in self.wins:
                gg=self.geoms[w['i']]
                if esc:
                    nm,ordn=om.get((gg.x,gg.y),('?',0))
                    w['tit'].set_text('SOU A TELA %d'%(ordn or (w['i']+1)))
                    w['info'].set_text('%s   %dx%d'%(nm,gg.width,gg.height))
                    w['a'].hide(); w['e'].show_all()
                else:
                    w['e'].hide(); w['a'].show_all()
                gw=w['win'].get_window()
                if gw: gw.set_cursor(None if esc else Gdk.Cursor(Gdk.CursorType.BLANK_CURSOR))

        if self.modo!='ESCOLHA':
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

os.makedirs(D,exist_ok=True); Aviso(); Gtk.main()
PYEOF
}

# --- controle do alerta -----------------------------------------------------
aviso_abre()  { DISPLAY=:0 python3 "$AVISO_DIR/aviso.py" >>"$LOGFILE" 2>&1 & AVISO_PID=$!; sleep 1; }
aviso_fecha() { [ -n "$AVISO_PID" ] && kill "$AVISO_PID" 2>/dev/null; AVISO_PID=""; }
aviso_vivo()  { [ -n "$AVISO_PID" ] && kill -0 "$AVISO_PID" 2>/dev/null; }

# Pergunta a tela do operador em DOIS canais ao mesmo tempo:
#   - na própria janela GTK (toque na tela desejada);
#   - no terminal (útil via SSH - localmente a janela cobre o console).
# Quem responder primeiro vence; o outro canal é encerrado.
# SEM timeout: só sai quando alguém responder.
# Requer as variáveis globais 'saidas' e 'modo_maximo' (seção 19).
# Ecoa o nome da saída (ex.: HDMI-1) ou a palavra DUPLICAR.
aviso_escolha_tela() {
  local total=$(( ${#saidas[@]} + 1 )) i rpid xmpids=() p
  rm -f "$AVISO_DIR/escolha"

  # Geometria + ordinal de cada saída, na MESMA ordem usada pelo menu abaixo
  xrandr --listactivemonitors | tail -n +2 | \
    awk '{g=$3; sub(/\/[0-9]+/,"",g); sub(/\/[0-9]+/,"",g); split(g,a,/[x+]/); print $NF, a[3], a[4], a[1], a[2], NR}' \
    > "$AVISO_DIR/saidas"

  if aviso_vivo; then
    echo ESCOLHA > "$AVISO_DIR/modo"
  else
    # Sem interface: identifica as telas com xmessage (sem timeout)
    while read -r _n _x _y _w _h _o; do
      xmessage -geometry "300x100+${_x}+${_y}" " SOU A TELA ${_o} " &
      xmpids+=($!)
    done < "$AVISO_DIR/saidas"
  fi

  # Menu vai para stderr: o stdout desta função é o RESULTADO da escolha
  {
    echo ""
    echo "=========================================================="
    echo " Toque na TELA DO OPERADOR ou responda aqui pelo terminal."
    echo " A outra tela é a que o CLIENTE verá."
    echo "=========================================================="
    i=1
    for p in "${saidas[@]}"; do
      echo "  $i - $p - Resolução Máxima: ${modo_maximo[$p]}"
      i=$((i+1))
    done
    echo "  $total - Duplicar telas"
  } >&2

  # Leitor do terminal em paralelo
  (
    op=""
    while read -rp "Opção (1-$total): " op < /dev/tty; do
      [ -s "$AVISO_DIR/escolha" ] && break
      if [[ "$op" =~ ^[0-9]+$ ]] && [ "$op" -ge 1 ] && [ "$op" -le "$total" ]; then
        if [ "$op" -eq "$total" ]; then
          echo DUPLICAR > "$AVISO_DIR/escolha"
        else
          echo "${saidas[$((op-1))]}" > "$AVISO_DIR/escolha"
        fi
        break
      fi
      echo "  Opção inválida." >&2
    done
  ) &
  rpid=$!

  # Espera qualquer um dos dois canais
  while [ ! -s "$AVISO_DIR/escolha" ]; do
    aviso_vivo || kill -0 "$rpid" 2>/dev/null || break
    sleep 1
  done

  kill "$rpid" 2>/dev/null; wait "$rpid" 2>/dev/null
  for p in "${xmpids[@]}"; do kill "$p" 2>/dev/null; done
  echo AVISO > "$AVISO_DIR/modo"
  head -n1 "$AVISO_DIR/escolha" 2>/dev/null
}

trap 'aviso_fecha' EXIT

#===============================================================================
# 1. Encerramento seguro dos processos PDV
#===============================================================================
log_step 1 "Encerrando processos PDV com segurança"
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
log_step 2 "Validações iniciais"
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
if DISPLAY=:0 python3 -c "import gi" >/dev/null 2>&1; then
  aviso_interface
  aviso_abre
  log_ok "Alerta visual em tela cheia iniciado"
else
  log_fail "python3-gi ausente - seguindo sem alerta visual"
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
SCREENSAVER_URL_BASE="http://serv-web/uploads/screensaver"   # + /<filial>/screensaver.mp4

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
log_step 4 "Configurando bloqueio de atalhos de teclado (keyd)"
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
log_step 5 "Ajustando /etc/hosts com o IP local do terminal"
sudo sed -i "s/^127\.0\.1\.1/$(ip -4 -brief addr show | awk '$1 != "lo" {print $3}' | cut -d/ -f1 | head -n 1)/" /etc/hosts
log_ok "/etc/hosts ajustado"

log_step 5 "Otimizando resolução de nomes e parâmetros de rede"
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
sed -i '/^endereco=/c endereco=192.168.12.42' /Zanthus/Zeus/pdvJava/CARG0000.CFG
printf "endereco=192.168.12.42\n" > /Zanthus/Zeus/pdvJava/RESTG0200.CFG
log_ok "CARG0000.CFG: timeout e endereço (mirage) ajustados"

printf "Vivo=22\nClaro=12000000\nOi=35000000\nTim=74000000\nBrasil Telecom=11\nCTBC-Celular=12201\nCTBC-Fixo=12299\nEmbratel=14000000\nSercomtel-Celular=12301\nSercomtel-Fixo=12399\nL Economica=97100\nNextel=75000000\n" > /Zanthus/Zeus/pdvJava/RECRGOP0.CFG
chmod 777 /Zanthus/Zeus/pdvJava/RECRGOP0.CFG
log_ok "Operadoras de recarga configuradas (RECRGOP0.CFG)"

#===============================================================================
# 7. journald - limitar uso de disco
#===============================================================================
log_step 7 "Ajustando parâmetros de journald.conf"
if grep -q '^Storage=none' /etc/systemd/journald.conf; then
  log_skip "journald.conf já ajustado"
else
  sudo sed -i 's/#Storage=auto/Storage=none/g; s/#SystemKeepFree=/SystemKeepFree=60G/g; s/#SystemMaxUse=/SystemMaxUse=1G/g; s/#SystemMaxFileSize=/SystemMaxFileSize=1G/g' /etc/systemd/journald.conf
  log_ok "journald.conf ajustado"
fi

#===============================================================================
# 8. GRUB - parâmetros para máquinas legado
#===============================================================================
log_step 8 "Verificando parâmetros do GRUB"
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
log_step 9 "Ajustando /etc/systemd/resolved.conf"
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
log_step 10 "Ajustando timeout da Sefaz"
sudo printf "timeout=60\n" > /Zanthus/Zeus/pdvJava/ZMWS1201.CFG
log_ok "ZMWS1201.CFG ajustado (timeout Sefaz)"

#===============================================================================
# 11. CUPS - configuração global
#===============================================================================
log_step 11 "Ajustando CUPS"
sudo sed 's/^BrowseLocalProtocols.*$/BrowseLocalProtocols\ none/' -i /etc/cups/cupsd.conf
run_silent "Reiniciando serviço CUPS" bash -c "cupsctl Web=yes; service cups stop; service cups start"
run_silent "Habilitando administração remota" cupsctl --remote-admin --remote-any
printf "linux.impressora=IMP-NFE\nlinux.opcoes=3\n" > /Zanthus/Zeus/pdvJava/ZPDF00.CFG
log_ok "CUPS configurado"

#===============================================================================
# 12. Instalação de impressora (Via Variáveis Globais)
#===============================================================================
log_step 12 "Configurando impressora fiscal - Loja $NOME_LOJA"
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
log_step 13 "Ajustando fuso horário e NTP"
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

log_step 15 "Copiando arquivos gerais de interface"
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
log_step 16 "Baixando arquivos de áudio"
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
log_step 17 "Configurando CliSiTef"
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
log_step 18 "Ajustando rede Docker"
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
  log_step 19 "Configurando monitores"

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
    # Pergunta na INTERFACE e no TERMINAL ao mesmo tempo (quem responder
    # primeiro vence). Sem timeout. Ver aviso_escolha_tela() no topo.
    resp=$(aviso_escolha_tela)

    if [ "$resp" == "DUPLICAR" ]; then
      duplicado=true
      operador="${saidas[0]}"
      xrandr --output "${saidas[0]}" --same-as "${saidas[1]}"
      log_ok "Telas duplicadas: ${saidas[0]} = ${saidas[1]}"
    elif [ -n "$resp" ]; then
      duplicado=false
      operador="$resp"
      log_ok "Tela do operador definida pelo técnico: $operador"
    else
      duplicado=false
      operador="${saidas[0]}"
      log_fail "Nenhuma resposta recebida - assumindo ${saidas[0]} como tela do operador"
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
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PerifericosUSB.sh" "/home/zanthus/PerifericosUSB.sh"
chmod +x /home/zanthus/PerifericosUSB.sh
run_silent "Executando PerifericosUSB.sh" /home/zanthus/PerifericosUSB.sh

#===============================================================================
# 23. ScreenSaver - pacotes e configuração
#    (vinha do antigo instala_screensaver.sh - passo2, seções 1 e 2)
#    OBS: a geração do atualizaSC<filial>.sh (antiga seção 4 do passo2) foi
#    removida daqui - essa lógica hoje está embutida no Machadão Launcher
#    Zanthus (Rust).
#===============================================================================
log_step 23 "Atualizando lista de pacotes"
run_silent "apt-get update" sudo apt-get update -y

log_step 23 "Instalando dependências (xscreensaver, restricted-extras, mpv)"
for pkg in xscreensaver ubuntu-restricted-extras mpv; do
  if pkg_instalado "$pkg"; then
    log_skip "Pacote $pkg"
  else
    run_silent "Instalando $pkg" sudo apt install -y -qq "$pkg"
  fi
done

log_step 23 "Aplicando configurações do xscreensaver"
safe_download "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/ScreenSaver/.xscreensaver" "/home/zanthus/.xscreensaver"

if ! grep -Fxq "export DISPLAY=:0" /etc/profile; then
  sudo echo "export DISPLAY=:0" >> /etc/profile
  log_ok "Linha 'export DISPLAY=:0' adicionada ao /etc/profile"
else
  log_skip "Linha 'export DISPLAY=:0' em /etc/profile"
fi

#===============================================================================
# 24. Download do launcher (só se o tamanho mudou)
#    (vinha do antigo instala_screensaver.sh - passo2, seção 4.1)
#===============================================================================
# O launcher já existe (versão antiga). Só rebaixa se o tamanho do arquivo
# remoto for diferente do local - evita baixar ~17MB a cada execução.
# OBS: o GitHub raw responde em HTTP/2, então o header vem MINÚSCULO
# (content-length) - por isso o grep é case-insensitive (-i), diferente do
# atualizaSC que fala com o serv-web.
LAUNCHER_URL="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PDV/PDVTouch.sh"
LAUNCHER_PATH="/Zanthus/Zeus/pdvJava/PDVTouch.sh"

log_step 24 "Verificando launcher (PDVTouch.sh)"
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
# 25. Geração do launcher.conf
#    O launcher (binário Rust) lê este .conf e faz toda a orquestração no boot
#    (chromium, periféricos, xscreensaver, atualizaSC, resolução via xrandr,
#    gateway e caminhos - tudo automático). Aqui só gravamos os campos que
#    variam por caixa; os fixos vêm das constantes CONF_* da seção 3.2.
#    O .conf é gravado SEM comentários.
#===============================================================================
log_step 25 "Gerando launcher.conf para o tipo: ${tipoInstala:-Desconhecido}"

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
sudo reboot
