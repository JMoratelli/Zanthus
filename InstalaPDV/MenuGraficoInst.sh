#!/bin/bash
# ==============================================================================
# MenuGraficoInst.sh - Menu grafico de instalacao do PDV Zanthus
# Desenvolvido por @JJMoratelli
#
# Uso:  curl -sL https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/MenuGraficoInst.sh | bash
#       Funciona como root, como o usuario da sessao ou com `| sudo bash`.
#
# A janela roda no usuario dono da sessao grafica: root no Ubuntu 22, onde o
# tty1 entra como root numa sessao X, e zanthus no Debian 13, onde o labwc
# (Wayland) e do usuario e o root nao consegue abrir janela. So o que precisa
# de root passa pelo sudo.
#
# O corpo em Python fica embutido neste mesmo arquivo e e gravado em disco
# antes de rodar, porque a interface precisa se reinvocar (splash de
# transicao e acoes de root) e isso nao funciona com o script vindo de um pipe.
# ==============================================================================

set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# ------------------------------------------------------------ privilegio ----
# Root direto dispensa o sudo. Fora disso o sudo tem de responder; se ele
# pedir senha, ela e pedida aqui no terminal, antes de a tela abrir.
if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
    if ! sudo -n true 2>/dev/null; then
        echo -e "${YELLOW}O menu precisa de permissao de administrador (sudo).${NC}"
        sudo -v || {
            echo -e "${RED}ERRO: o usuario $(id -un) nao conseguiu usar o sudo.${NC}"
            exit 1; }
    fi
fi

# ---------------------------------------------------------------- sessao ----
# Descobre em qual tela abrir e de quem ela e:
#   Wayland (Debian/labwc): socket wayland-N em /run/user/<uid>;
#   X11 (Ubuntu/openbox):   DISPLAY, dono do socket em /tmp/.X11-unix.
# Sockets de usuario de sistema (o greeter do gdm, por exemplo) sao ignorados.
detectar_sessao() {
    SESSAO_UID=""; SESSAO_TIPO=""
    local s="" u _s _h

    if [ -n "${WAYLAND_DISPLAY:-}" ] && [ -S "${XDG_RUNTIME_DIR:-/nao}/${WAYLAND_DISPLAY}" ]; then
        s="${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}"
    else
        for _s in /run/user/*/wayland-[0-9]; do
            [ -S "$_s" ] || continue
            u=$(stat -c %u "$_s")
            if [ "$u" -eq 0 ] || [ "$u" -ge 1000 ]; then s="$_s"; break; fi
        done
    fi
    if [ -n "$s" ]; then
        SESSAO_TIPO="wayland"
        SESSAO_UID=$(stat -c %u "$s")
        export XDG_RUNTIME_DIR="${s%/*}"
        export WAYLAND_DISPLAY="${s##*/}"
        export GDK_BACKEND="wayland"
        return 0
    fi

    export DISPLAY="${DISPLAY:-:0}"
    s="/tmp/.X11-unix/X$(echo "${DISPLAY#*:}" | cut -d. -f1)"
    [ -S "$s" ] || return 1
    SESSAO_TIPO="x11"
    SESSAO_UID=$(stat -c %u "$s")
    if [ -z "${XAUTHORITY:-}" ]; then
        for _h in "$(getent passwd "$SESSAO_UID" | cut -d: -f6)" /root /home/zanthus; do
            if [ -f "${_h}/.Xauthority" ]; then
                export XAUTHORITY="${_h}/.Xauthority"
                break
            fi
        done
        # sem acesso para conferir (ex.: zanthus olhando o /root): aponta para
        # o do dono da sessao, que e quem vai abrir a janela
        [ -n "${XAUTHORITY:-}" ] || \
            export XAUTHORITY="$(getent passwd "$SESSAO_UID" | cut -d: -f6)/.Xauthority"
    fi
    return 0
}

if ! detectar_sessao; then
    echo -e "${RED}ERRO: nenhuma sessao grafica encontrada (nem Wayland, nem X em ${DISPLAY:-:0}).${NC}"
    exit 1
fi
USUARIO_SESSAO=$(id -nu "$SESSAO_UID")

if [ "$SESSAO_TIPO" = "x11" ] && [ "$(id -u)" -eq "$SESSAO_UID" ] \
        && ! timeout 5 xset q >/dev/null 2>&1; then
    echo -e "${YELLOW}Aviso: nao foi possivel falar com o servidor X em ${DISPLAY}.${NC}"
    echo -e "${YELLOW}Tentando liberar acesso local...${NC}"
    xhost +local: >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------- dependencias ----
FALTANDO=""
python3 -c "import gi" >/dev/null 2>&1 || FALTANDO="python3-gi"
python3 -c "import gi; gi.require_version('Gtk','3.0')" >/dev/null 2>&1 \
    || FALTANDO="$FALTANDO gir1.2-gtk-3.0"

if [ -n "$(echo "$FALTANDO" | tr -d ' ')" ]; then
    echo -e "${YELLOW}Instalando dependencias:${FALTANDO}${NC}"
    $SUDO apt-get update -qq >/dev/null 2>&1
    # shellcheck disable=SC2086
    $SUDO apt-get install -y $FALTANDO >/dev/null 2>&1 || {
        echo -e "${RED}ERRO: falha ao instalar${FALTANDO}${NC}"; exit 1; }
fi

# ------------------------------------------------- grava a interface em disco
DESTINO="/usr/local/lib/zanthus"
ALVO="${DESTINO}/menu_grafico_pdv.py"
$SUDO mkdir -p "$DESTINO"

$SUDO tee "$ALVO" >/dev/null <<'FIM_PY_ZANTHUS'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Instalador PDV Zanthus - Interface GTK3 (modo kiosk)
Desenvolvido por @JJMoratelli

Dependencias (Ubuntu 22.04 e Debian 13):
    sudo apt install python3-gi gir1.2-gtk-3.0

Execucao: pelo MenuGraficoInst.sh, a partir de um terminal (o instalador
assume a tela ao final). A janela roda no usuario dono da sessao grafica; o
que precisa de root e feito por este mesmo arquivo no modo --root, via sudo.
"""

import gi
gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, Gdk, GLib, Pango  # noqa: E402

import ipaddress
import os
import re
import glob
import socket
import subprocess
import sys
import time

# Nome fixo da janela (app_id no Wayland, WM_CLASS no X): e por ele que o
# labwc reconhece a janela, em vez do nome do arquivo.
GLib.set_prgname("zanthus-menu")

# ==============================================================================
# CONFIGURACAO
# ==============================================================================

CONF_DIR = "/home/zanthus/tmp/Script"
CLAZ_FILE = "/Zanthus/Zeus/pdvJava/CLAZ.CFG"
ECF_FILE = "/Zanthus/Zeus/pdvJava/ECF9F.CFG"
URL_BASE = "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/"
URL_LAUNCHER = URL_BASE + "LauncherPDV.sh"                 # Ubuntu 22
URL_LAUNCHER_DEBIAN = URL_BASE + "Debian/LauncherPDV.sh"   # Debian 13 (labwc)

# Caminho real deste arquivo. Fica None se o script for executado via stdin
# (`python3 - < arquivo` ou `curl | python3`), caso em que a splash e pulada.
CAMINHO_SCRIPT = os.path.abspath(__file__) if "__file__" in globals() else None

# Root no Ubuntu 22 (o tty1 entra como root); usuario comum no Debian 13.
EH_ROOT = os.geteuid() == 0

ESPERA_CONFIRMACAO = 3  # segundos de travamento no botao da confirmacao final
ESPERA_SAIR = 5         # segundos de travamento no botao de sair do instalador

# gateway -> (loja, display_filial, id_filial, cnpj)
FILIAIS = {
    "10.1.1.1":        ("01", 100,  1,  "03790904000156"),
    "192.168.11.253":  ("02", 200,  3,  "03790904000318"),
    "192.168.5.253":   ("03", 300,  9,  "03790904000407"),
    "192.168.7.253":   ("05", 5300, 53, "13338712000248"),
    "192.168.9.253":   ("06", 5200, 52, "03790904000580"),
    "192.168.57.193":  ("07", 5700, 57, "13338712000400"),
    "192.168.57.1":    ("07", 5700, 57, "13338712000400"),
    "192.168.156.1":   ("07", 5700, 57, "13338712000400"),
    "192.168.57.129":  ("07", 5700, 57, "13338712000400"),
    "192.168.58.1":    ("08", 5800, 58, "13338712000590"),
}

# (id, rotulo, cor, arquivo .conf, descricao)
PERFIS = [
    ("comum",  "PDV Comum",    "#1a5fb4", "tipoConfComum.conf",
     "Frente de caixa padrão, interface de teclado."),
    ("touch",  "PDV Touch",    "#3a6ea5", "tipoConfTouch.conf",
     "Frente de caixa padrão, interface sensível ao toque."),
    ("self",   "SelfCheckout", "#0a6f66", "tipoConfSelf.conf",
     "Autoatendimento com balança e monitor do cliente."),
    ("lancho", "Lanchonete",   "#a8480a", "tipoConfLancho.conf",
     "Terminal de pedidos da lanchonete."),
]

INK = "#16181a"
CINZA = "#c3cad0"
AZUL = "#1a5fb4"
VERMELHO = "#a51d2d"


# ==============================================================================
# ACOES DE ROOT
# A janela nao roda como root no Debian. O pouco que exige root e feito por
# este mesmo arquivo no modo --root, chamado por `sudo -n`, recebendo tudo por
# argumento: grava exatamente o que o tecnico confirmou na tela.
# ==============================================================================

NOME_CONF = re.compile(r"^[A-Za-z0-9_.-]+\.conf$")
NOME_HOST = re.compile(r"^[A-Za-z0-9-]{1,63}$")


def sudo_disponivel():
    """Root direto, ou sudo que responde sem pedir senha (se precisava de
    senha, o MenuGraficoInst.sh ja pediu no terminal)."""
    if EH_ROOT:
        return True
    try:
        return subprocess.call(["sudo", "-n", "true"],
                               stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL) == 0
    except OSError:
        return False


def executar_root(args):
    """Corpo do modo --root. Devolve o texto a imprimir na saida padrao."""
    acao = args[0] if args else ""
    if acao == "ler" and len(args) == 2 and args[1] in (CLAZ_FILE, ECF_FILE):
        with open(args[1], "r", errors="ignore") as fh:
            return fh.read()
    if acao == "hostname" and len(args) in (2, 3):
        Ambiente.gravar_hostname(*args[1:])
        return ""
    if acao == "conf" and len(args) >= 2:
        Ambiente.gravar_arquivos_conf(args[1:])
        return ""
    raise ValueError("acao de root invalida: %s" % " ".join(args))


def como_root(*args):
    """Executa uma acao do modo --root com privilegio de root. Em caso de
    falha sobe RuntimeError com a mensagem do outro lado."""
    args = [str(a) for a in args]
    if EH_ROOT:
        try:
            return executar_root(args)
        except Exception as erro:
            raise RuntimeError(str(erro))
    if not CAMINHO_SCRIPT:
        raise RuntimeError("script sem arquivo em disco: não dá para usar o sudo")
    r = subprocess.run(["sudo", "-n", sys.executable, CAMINHO_SCRIPT, "--root"] + args,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if r.returncode != 0:
        erros = [l for l in r.stdout.splitlines() if l.startswith("ERRO: ")]
        raise RuntimeError(erros[-1][6:] if erros else
                           (r.stderr.strip() or "sudo falhou (código %d)" % r.returncode))
    return r.stdout


# ==============================================================================
# DETECCAO DE AMBIENTE (sem efeitos colaterais)
# ==============================================================================

class Ambiente:
    def __init__(self):
        self.detectar()

    @staticmethod
    def _gateway():
        try:
            out = subprocess.check_output(["ip", "route", "show"], text=True)
        except Exception:
            return ""
        for linha in out.splitlines():
            campos = linha.split()
            if campos and campos[0] == "default" and "via" in campos:
                return campos[campos.index("via") + 1]
        return ""

    @staticmethod
    def _ip_local():
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("10.255.255.255", 1))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return ""

    @staticmethod
    def _ler_texto(caminho):
        """Conteudo do arquivo, ou None. No Debian o CLAZ.CFG e root:root
        0640: sem root, a leitura passa pelo sudo."""
        try:
            with open(caminho, "r", errors="ignore") as fh:
                return fh.read()
        except PermissionError:
            if EH_ROOT:
                return None
            try:
                return como_root("ler", caminho)
            except RuntimeError:
                return None
        except OSError:
            return None

    @classmethod
    def _ler_chave(cls, caminho, chave):
        texto = cls._ler_texto(caminho)
        if texto is None:
            return None
        for linha in texto.splitlines():
            if linha.strip().upper().startswith(chave.upper() + "="):
                return linha.split("=", 1)[1].strip()
        return None

    @staticmethod
    def _sistema():
        """ID do /etc/os-release: 'ubuntu', 'debian'..."""
        try:
            with open("/etc/os-release", "r") as fh:
                for linha in fh:
                    if linha.startswith("ID="):
                        return linha.split("=", 1)[1].strip().strip('"')
        except OSError:
            pass
        return ""

    @staticmethod
    def cnpj_fmt(v):
        d = re.sub(r"\D", "", v or "")
        if len(d) != 14:
            return v or "-"
        return "%s.%s.%s/%s-%s" % (d[:2], d[2:5], d[5:8], d[8:12], d[12:])

    def detectar(self):
        self.pode_elevar = sudo_disponivel()
        self.debian = self._sistema() == "debian"
        self.gateway = self._gateway()
        self.ip = self._ip_local()
        self.hostname_atual = socket.gethostname()

        dados = FILIAIS.get(self.gateway)
        if dados:
            self.loja, self.display_filial, self.id_filial, self.cnpj = dados
        else:
            self.loja = self.cnpj = ""
            self.display_filial = self.id_filial = None

        self.sufixo_caixa = None
        self.numero_final = None
        self.hostname_novo = ""
        if self.id_filial is not None and self.ip:
            try:
                octeto = int(self.ip.split(".")[3])
                self.sufixo_caixa = octeto % 100
                self.numero_final = self.display_filial + self.sufixo_caixa
                self.hostname_novo = "CAIXA%d-LJ%s" % (self.numero_final, self.loja)
            except (ValueError, IndexError):
                pass

        seriais = glob.glob("/dev/serial/by-id/*usb-TOLEDO_CDC_DEVICE_*")
        self.qtd_balancas = len(seriais)
        if self.qtd_balancas == 1:
            self.balanca_conf = "tipoBalancaToledo.conf"
            self.balanca_txt = "Toledo"
        elif self.qtd_balancas >= 2:
            self.balanca_conf = "tipoBalancaToledoDual.conf"
            self.balanca_txt = "Toledo dupla"
        else:
            self.balanca_conf = "tipoBalancaNull.conf"
            self.balanca_txt = "Nenhuma"

        self.validar_cfg()

    def validar_cfg(self):
        """Status por campo: 'ok' | 'divergente' | 'ausente'."""
        self.cfg_filial = self.cfg_cnpj = self.cfg_caixa = "ausente"
        self.claz_existe = os.path.isfile(CLAZ_FILE)
        self.ecf_existe = os.path.isfile(ECF_FILE)
        self.claz_filial = self.claz_cnpj = self.ecf_caixa = None

        if self.claz_existe:
            self.claz_filial = self._ler_chave(CLAZ_FILE, "LOJA")
            self.claz_cnpj = self._ler_chave(CLAZ_FILE, "CNPJ")
            try:
                self.cfg_filial = ("ok" if self.id_filial is not None
                                   and int(self.claz_filial) == self.id_filial
                                   else "divergente")
            except (TypeError, ValueError):
                self.cfg_filial = "divergente"
            self.cfg_cnpj = ("ok" if self.cnpj and self.claz_cnpj == self.cnpj
                             else "divergente")

        if self.ecf_existe:
            self.ecf_caixa = self._ler_chave(ECF_FILE, "NUMERACAIXA")
            try:
                self.cfg_caixa = ("ok" if self.caixa_esperado is not None
                                  and int(self.ecf_caixa) == self.caixa_esperado
                                  else "divergente")
            except (TypeError, ValueError):
                self.cfg_caixa = "divergente"

    @property
    def caixa_esperado(self):
        if self.loja in ("01", "02", "03"):
            return self.numero_final
        return self.sufixo_caixa

    @property
    def host_ok(self):
        return bool(self.hostname_novo) and self.hostname_atual == self.hostname_novo

    @property
    def claz_bloqueia(self):
        return "divergente" in (self.cfg_filial, self.cfg_cnpj)

    def aplicar_hostname(self):
        if self.debian and self.ip:
            como_root("hostname", self.hostname_novo, self.ip)
        else:
            como_root("hostname", self.hostname_novo)
        self.hostname_atual = self.hostname_novo

    @staticmethod
    def gravar_hostname(nome, ip=""):
        """Modo --root. Sem ip (Ubuntu): linha 127.0.1.1, que o LauncherPDV.sh
        troca depois pelo IP. Com ip (Debian): a linha do IP no formato que o
        perfil-360 grava, "<ip> <nome>.local <nome>", no lugar da antiga."""
        if not NOME_HOST.match(nome):
            raise ValueError("hostname inválido: %s" % nome)
        if ip:
            ipaddress.IPv4Address(ip)
        subprocess.check_call(["hostnamectl", "set-hostname", nome])
        try:
            with open("/etc/hosts", "r") as fh:
                linhas = [l for l in fh if "127.0.1.1" not in l
                          and not (ip and l.split()[:1] == [ip])]
        except OSError:
            linhas = []
        if ip:
            linhas.append("%s %s.local %s\n" % (ip, nome, nome))
        else:
            linhas.append("127.0.1.1\t%s\n" % nome)
        with open("/etc/hosts", "w") as fh:
            fh.writelines(linhas)

    def arquivos_conf(self, perfil_id):
        nomes = []
        if self.id_filial is not None:
            nomes.append("filial%d.conf" % self.id_filial)
        if self.numero_final is not None:
            nomes.append("caixa%d.conf" % self.numero_final)
        nomes.append(self.balanca_conf)
        nomes += [arq for pid, _n, _c, arq, _d in PERFIS if pid == perfil_id]
        return nomes

    def gravar_conf(self, perfil_id):
        como_root("conf", *self.arquivos_conf(perfil_id))

    @staticmethod
    def gravar_arquivos_conf(nomes):
        """Modo --root. Recria CONF_DIR so com os marcadores informados."""
        for nome in nomes:
            if not NOME_CONF.match(nome):
                raise ValueError("nome de arquivo inválido: %s" % nome)
        os.makedirs(CONF_DIR, exist_ok=True)
        for antigo in glob.glob(os.path.join(CONF_DIR, "*")):
            try:
                os.remove(antigo)
            except OSError:
                pass
        for nome in nomes:
            open(os.path.join(CONF_DIR, nome), "a").close()


# ==============================================================================
# ESTILO
# ==============================================================================

CSS = b"""
window, .fundo { background-color: #eef0f2; }

.eyebrow {
    color: #6b7580;
    font-family: "IBM Plex Mono", "DejaVu Sans Mono", monospace;
    font-size: 11px;
}
.titulo {
    color: #16181a;
    font-family: "IBM Plex Sans Condensed", "IBM Plex Sans", "Cantarell", sans-serif;
    font-size: 30px;
    font-weight: 600;
}
.assinatura {
    color: #8f9aa3;
    font-family: "IBM Plex Mono", "DejaVu Sans Mono", monospace;
    font-size: 11px;
}
.regua { min-height: 2px; }

.cartao {
    background-color: #ffffff;
    border: 1px solid #dfe3e6;
    border-radius: 4px;
}
.rotulo {
    color: #6b7580;
    font-family: "IBM Plex Mono", "DejaVu Sans Mono", monospace;
    font-size: 10px;
}
.valor { color: #16181a; font-size: 19px; font-weight: 600; }
.valor-mono {
    color: #16181a;
    font-family: "IBM Plex Mono", "DejaVu Sans Mono", monospace;
    font-size: 17px;
    font-weight: 600;
}
.valor-vazio { color: #b0b8bf; font-size: 19px; font-weight: 600; }
.secundario {
    color: #6b7580;
    font-family: "IBM Plex Mono", "DejaVu Sans Mono", monospace;
    font-size: 11px;
}

.chip {
    font-family: "IBM Plex Mono", "DejaVu Sans Mono", monospace;
    font-size: 10px;
    font-weight: 600;
    border-radius: 3px;
    padding: 3px 8px;
}
.chip-ok      { background-color: #dff2ec; color: #0a6f66; }
.chip-erro    { background-color: #fbe3e3; color: #a51d2d; }
.chip-neutro  { background-color: #e8ebed; color: #6b7580; }
.chip-atencao { background-color: #fdf0d5; color: #8a5a00; }

.perfil {
    background-image: none;
    background-color: #ffffff;
    border: 2px solid #dfe3e6;
    border-radius: 4px;
    padding: 0px;
}
.perfil:hover    { background-color: #f7f9fa; border-color: #aeb7be; }
.perfil:disabled { background-color: #f2f4f6; border-color: #e6e9ec; }
/* estado selecionado: borda ink cheia, mesmo peso de 2px (nao desloca nada) */
.perfil-sel, .perfil-sel:hover, .perfil-sel:checked {
    background-color: #ffffff;
    border-color: #16181a;
}
.perfil-nome { font-size: 16px; font-weight: 600; color: #16181a; }
.perfil-desc { font-size: 11px; color: #6b7580; }

.marca {
    font-family: "IBM Plex Mono", "DejaVu Sans Mono", monospace;
    font-size: 10px;
    font-weight: 600;
    border-radius: 3px;
    padding: 4px 9px;
}
.marca-off { background-color: #eef0f2; color: #9aa3ab; }
.marca-on  { background-color: #16181a; color: #ffffff; }

.trilho { border-radius: 2px; min-width: 5px; }

.acao {
    background-image: none;
    background-color: #16181a;
    color: #ffffff;
    border: none;
    border-radius: 4px;
    font-weight: 600;
    padding: 12px 26px;
}
.acao:hover { background-color: #2b3034; }
.acao:disabled { background-color: #c3cad0; color: #ffffff; }

.secundaria {
    background-image: none;
    background-color: #ffffff;
    color: #16181a;
    border: 1px solid #c3cad0;
    border-radius: 4px;
    padding: 9px 18px;
}
.secundaria:hover { background-color: #f2f4f6; }
.secundaria:disabled { color: #b0b8bf; border-color: #e0e4e7; }

.faixa-erro {
    background-color: #fbe3e3;
    border-left: 4px solid #a51d2d;
    border-radius: 3px;
}
.faixa-alerta {
    background-color: #fdf0d5;
    border-left: 4px solid #8a5a00;
    border-radius: 3px;
}
.faixa-titulo { font-size: 13px; font-weight: 600; color: #16181a; }
.faixa-txt { font-size: 12px; color: #4b545c; }

.dialogo {
    background-color: #ffffff;
    border: 1px solid #16181a;
    border-radius: 4px;
}
.dialogo-passo {
    color: #6b7580;
    font-family: "IBM Plex Mono", "DejaVu Sans Mono", monospace;
    font-size: 10px;
}
.dialogo-titulo {
    color: #16181a;
    font-family: "IBM Plex Sans Condensed", "IBM Plex Sans", sans-serif;
    font-size: 21px;
    font-weight: 600;
}
.dialogo-txt { color: #4b545c; font-size: 13px; }
.dialogo-mono {
    color: #16181a;
    font-family: "IBM Plex Mono", "DejaVu Sans Mono", monospace;
    font-size: 12px;
}
.dialogo-tabela {
    background-color: #f5f7f8;
    border: 1px solid #e6e9ec;
    border-radius: 3px;
}
"""


CSS_COMPACTO = b"""
.titulo      { font-size: 22px; }
.valor       { font-size: 16px; }
.valor-mono  { font-size: 14px; }
.valor-vazio { font-size: 16px; }
.secundario  { font-size: 10px; }
.perfil-nome { font-size: 14px; }
.perfil-desc { font-size: 10px; }
.acao        { padding: 9px 20px; }
.secundaria  { padding: 7px 14px; }
.dialogo-titulo { font-size: 18px; }
"""


def add_class(w, *nomes):
    ctx = w.get_style_context()
    for n in nomes:
        ctx.add_class(n)
    return w


def rotulo(texto, *classes, xalign=0.0):
    lb = Gtk.Label(xalign=xalign)
    lb.set_text(texto)
    return add_class(lb, *classes)


def chip(texto, tipo):
    cx = Gtk.Box()
    cx.set_halign(Gtk.Align.START)
    cx.pack_start(rotulo(texto, "chip", "chip-" + tipo), False, False, 0)
    return cx


def rgba(hexcor):
    h = hexcor.lstrip("#")
    return Gdk.RGBA(int(h[0:2], 16) / 255, int(h[2:4], 16) / 255,
                    int(h[4:6], 16) / 255, 1.0)


_PROVEDORES = {}


def pintar(w, hexcor):
    """Pinta o fundo via CssProvider proprio do widget.
    Substitui override_background_color(), depreciado desde o GTK 3.16."""
    prov = _PROVEDORES.get(hexcor)
    if prov is None:
        prov = Gtk.CssProvider()
        prov.load_from_data(("* { background-color: %s; }" % hexcor).encode())
        _PROVEDORES[hexcor] = prov
    w.get_style_context().add_provider(
        prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    return w


def regua(cor, altura=2):
    r = Gtk.Box()
    add_class(r, "regua")
    r.set_size_request(-1, altura)
    return pintar(r, cor)


CHIP_MAP = {"ok": ("CONFERE", "ok"),
            "divergente": ("DIVERGENTE", "erro"),
            "ausente": ("SEM ARQUIVO", "neutro")}


# ==============================================================================
# DIALOGO PADRAO (sem bordas, botoes do projeto, trava opcional por tempo)
# ==============================================================================

class Dialogo(Gtk.Dialog):
    def __init__(self, pai, passo, titulo, texto, linhas=None,
                 ok="Confirmar", cancelar="Cancelar", espera=0):
        super().__init__(transient_for=pai, modal=True, use_header_bar=False)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_position(Gtk.WindowPosition.CENTER_ON_PARENT)
        larg = 560
        try:
            d = Gdk.Display.get_default()
            mon = d.get_primary_monitor() or d.get_monitor(0)
            larg = min(560, mon.get_geometry().width - 60)
        except Exception:
            pass
        self.set_default_size(larg, -1)
        self._fonte = None
        self.connect("destroy", self._parar)

        area = self.get_content_area()
        area.set_spacing(0)

        moldura = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        add_class(moldura, "dialogo")
        moldura.pack_start(regua(INK, 3), False, False, 0)

        miolo = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        miolo.set_border_width(26)
        if passo:
            miolo.pack_start(rotulo(passo, "dialogo-passo"), False, False, 0)
        miolo.pack_start(rotulo(titulo, "dialogo-titulo"), False, False, 0)

        lb = rotulo(texto, "dialogo-txt")
        lb.set_line_wrap(True)
        lb.set_max_width_chars(62)
        miolo.pack_start(lb, False, False, 4)

        if linhas:
            tab = Gtk.Grid(column_spacing=18, row_spacing=5)
            tab.set_border_width(14)
            add_class(tab, "dialogo-tabela")
            for i, (k, v) in enumerate(linhas):
                tab.attach(rotulo(k.upper(), "rotulo"), 0, i, 1, 1)
                tab.attach(rotulo(str(v), "dialogo-mono"), 1, i, 1, 1)
            miolo.pack_start(tab, False, False, 6)

        botoes = Gtk.Box(spacing=10)
        botoes.set_halign(Gtk.Align.END)
        bc = None
        if cancelar:
            bc = Gtk.Button(label=cancelar)
            add_class(bc, "secundaria")
            bc.connect("clicked", lambda _b: self.response(Gtk.ResponseType.CANCEL))
            botoes.pack_start(bc, False, False, 0)

        self._ok_txt = ok
        self.bt_ok = Gtk.Button(label=ok)
        add_class(self.bt_ok, "acao")
        self.bt_ok.connect("clicked", lambda _b: self.response(Gtk.ResponseType.OK))
        botoes.pack_start(self.bt_ok, False, False, 0)
        miolo.pack_start(botoes, False, False, 10)

        moldura.pack_start(miolo, True, True, 0)
        area.pack_start(moldura, True, True, 0)
        self.show_all()

        if espera > 0:
            self._resta = espera
            self.bt_ok.set_sensitive(False)
            self.bt_ok.set_label("%s  (%d)" % (ok, self._resta))
            # largura fixa na do rotulo com a contagem: o texto muda, o botao
            # nao encolhe nem empurra o Cancelar
            self.bt_ok.set_size_request(self.bt_ok.get_preferred_width()[1], -1)
            if bc:
                bc.grab_focus()           # foco nasce na saida segura
            self._fonte = GLib.timeout_add_seconds(1, self._tique)

    def _tique(self):
        self._resta -= 1
        if self._resta <= 0:
            self.bt_ok.set_label(self._ok_txt)
            self.bt_ok.set_sensitive(True)
            self._fonte = None
            return False
        self.bt_ok.set_label("%s  (%d)" % (self._ok_txt, self._resta))
        return True

    def _parar(self, _w):
        if self._fonte:
            GLib.source_remove(self._fonte)
            self._fonte = None

    @staticmethod
    def confirmar(pai, passo, titulo, texto, linhas=None,
                  ok="Confirmar", espera=0):
        d = Dialogo(pai, passo, titulo, texto, linhas, ok=ok, espera=espera)
        r = d.run()
        d.destroy()
        return r == Gtk.ResponseType.OK

    @staticmethod
    def avisar(pai, titulo, texto, linhas=None, ok="Entendi"):
        d = Dialogo(pai, None, titulo, texto, linhas, ok=ok, cancelar=None)
        d.run()
        d.destroy()


# ==============================================================================
# SPLASH DE TRANSICAO
# Sobe como processo proprio antes do exec do instalador, para nao piscar a
# area de trabalho entre esta tela e a splash do LauncherPDV.sh.
# ==============================================================================

PID_SPLASH = "/tmp/pdv_splash_menu.pid"

# Trecho presente na linha de comando do alerta do LauncherPDV.sh: nos dois
# sistemas ele grava a janela em /tmp/aviso/aviso.py e roda o arquivo.
# A splash generica so sai do ar quando esse processo aparece.
MARCA_LAUNCHER = "/tmp/aviso/aviso.py"
TETO_ESPERA = 900          # s: rede de seguranca, caso a outra nunca suba

CSS_SPLASH = b"""
window { background-color: #0b0f14; }
#tag  { color: #7a8a9a; font-size: 16px; }
#tit  { color: #e8eef5; font-size: 56px; font-weight: bold; }
#sub  { color: #93a3b3; font-size: 20px; }
#cred { color: #3d4b59; font-size: 14px; }
progressbar trough   { min-height: 12px; background-color: #1b2530; border: 0; }
progressbar progress { min-height: 12px; background-color: #0a84ff; border: 0; }
"""


def _splash_label(texto, nome, espacamento=0):
    lb = Gtk.Label(label=texto)
    lb.set_name(nome)
    if espacamento:
        attrs = Pango.AttrList()
        try:
            attrs.insert(Pango.attr_letter_spacing_new(espacamento * Pango.SCALE))
            lb.set_attributes(attrs)
        except AttributeError:
            pass
    return lb


def _wayland():
    return "Wayland" in type(Gdk.Display.get_default()).__name__


def _splash_monitor(geo, indice):
    # X11: POPUP posicionado por coordenada, por cima de tudo. Wayland nao
    # posiciona janela por coordenada nem tem "sempre por cima": la cada
    # monitor ganha uma janela comum em tela cheia.
    if _wayland():
        janela = Gtk.Window()
        janela.set_decorated(False)
        janela.connect("delete-event", lambda *_a: True)
    else:
        janela = Gtk.Window(type=Gtk.WindowType.POPUP)
        janela.set_keep_above(True)

    over = Gtk.Overlay()
    caixa = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=26)
    caixa.set_halign(Gtk.Align.CENTER)
    caixa.set_valign(Gtk.Align.CENTER)

    caixa.add(_splash_label("SISTEMA PDV", "tag", 8))
    caixa.add(_splash_label("PREPARANDO INSTALAÇÃO", "tit"))

    barra = Gtk.ProgressBar()
    barra.set_size_request(min(700, geo.width - 80), -1)
    caixa.add(barra)

    caixa.add(_splash_label("Aguarde, o instalador está sendo carregado.", "sub"))
    over.add(caixa)

    cred = _splash_label("Desenvolvido por @JJMoratelli", "cred")
    cred.set_halign(Gtk.Align.END)
    cred.set_valign(Gtk.Align.END)
    cred.set_margin_end(24)
    cred.set_margin_bottom(18)
    over.add_overlay(cred)

    janela.add(over)
    if _wayland():
        janela.show_all()
        janela.fullscreen_on_monitor(Gdk.Screen.get_default(), indice)
    else:
        janela.set_size_request(geo.width, geo.height)
        janela.show_all()
        janela.move(geo.x, geo.y)
        janela.resize(geo.width, geo.height)
    try:
        janela.get_window().set_cursor(
            Gdk.Cursor(Gdk.CursorType.BLANK_CURSOR))
    except Exception:
        pass
    GLib.timeout_add(60, lambda: (barra.pulse(), True)[1])
    return janela


def _launcher_no_ar(marca, meu_pid):
    """Varre /proc atras da linha de comando da splash do LauncherPDV.sh."""
    for entrada in os.listdir("/proc"):
        if not entrada.isdigit() or int(entrada) == meu_pid:
            continue
        try:
            with open("/proc/%s/cmdline" % entrada, "rb") as fh:
                linha = fh.read().replace(b"\0", b" ").decode("utf-8", "ignore")
        except OSError:
            continue
        if marca in linha:
            return True
    return False


def rodar_splash(marca=MARCA_LAUNCHER, limite=TETO_ESPERA):
    """Cobre todos os monitores e so encerra quando a splash do
    LauncherPDV.sh entrar em cena (ou quando estourar o teto de espera)."""
    prov = Gtk.CssProvider()
    prov.load_from_data(CSS_SPLASH)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), prov, 600)

    display = Gdk.Display.get_default()
    for i in range(display.get_n_monitors()):
        _splash_monitor(display.get_monitor(i).get_geometry(), i)

    try:
        with open(PID_SPLASH, "w") as fh:
            fh.write(str(os.getpid()))
    except OSError:
        pass

    estado = {"saindo": False}
    meu_pid = os.getpid()

    def vigiar():
        if estado["saindo"]:
            return False
        if _launcher_no_ar(marca, meu_pid):
            # a outra splash ja subiu: pequena folga para ela desenhar
            # antes desta sair, senao o desktop pisca no meio.
            estado["saindo"] = True
            GLib.timeout_add(700, Gtk.main_quit)
            return False
        return True

    GLib.timeout_add(300, vigiar)
    GLib.timeout_add_seconds(limite, Gtk.main_quit)
    Gtk.main()
    try:
        os.remove(PID_SPLASH)
    except OSError:
        pass


# ==============================================================================
# JANELA PRINCIPAL
# ==============================================================================

class Janela(Gtk.Window):
    def __init__(self):
        super().__init__(title="Instalador PDV Zanthus")
        self.set_decorated(False)
        self.fullscreen()
        self.set_keep_above(True)
        self.connect("delete-event", lambda *_a: True)   # kiosk: sem saida
        self.connect("destroy", Gtk.main_quit)

        self.amb = Ambiente()
        self.perfil = None
        self.comando_final = None

        # --- adapta o layout ao tamanho real do monitor ---------------------
        self.tela_l, self.tela_a = self._geometria()
        self.compacto = self.tela_l < 1280 or self.tela_a < 800
        self.perfis_por_linha = 4 if self.tela_l >= 1180 else 2
        self.margem = 16 if self.compacto else 34
        self.larg_celula = 150 if self.compacto else 230

        prov = Gtk.CssProvider()
        prov.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), prov,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        if self.compacto:
            prov2 = Gtk.CssProvider()
            prov2.load_from_data(CSS_COMPACTO)
            Gtk.StyleContext.add_provider_for_screen(
                Gdk.Screen.get_default(), prov2,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1)

        # coluna unica: cabecalho e conteudo compartilham a mesma margem
        coluna = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        coluna.set_border_width(self.margem)
        add_class(coluna, "fundo")

        coluna.pack_start(self._cabecalho(), False, False, 0)

        self.faixa = Gtk.Box()
        coluna.pack_start(self.faixa, False, False, 0)

        coluna.pack_start(self._legenda("ESTAÇÃO"), False, False, 0)
        self.painel = Gtk.Box()
        coluna.pack_start(self.painel, False, False, 0)

        coluna.pack_start(self._legenda("PERFIL DE INSTALAÇÃO"), False, False, 0)
        coluna.pack_start(self._lista_perfis(), False, False, 0)

        coluna.pack_start(Gtk.Box(), True, True, 0)          # empurra o rodape
        coluna.pack_start(self._barra_acoes(), False, False, 0)

        # rolagem nos dois eixos: em telas pequenas nada fica inacessivel
        rolagem = Gtk.ScrolledWindow()
        rolagem.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        rolagem.add(coluna)
        add_class(rolagem, "fundo")
        self.add(rolagem)

        self.recarregar()

    @staticmethod
    def _geometria():
        try:
            display = Gdk.Display.get_default()
            mon = display.get_primary_monitor() or display.get_monitor(0)
            r = mon.get_geometry()
            return r.width, r.height
        except Exception:
            tela = Gdk.Screen.get_default()
            return tela.get_width(), tela.get_height()

    def _legenda(self, texto):
        cx = Gtk.Box()
        cx.set_margin_top(14 if self.compacto else 26)
        cx.set_margin_bottom(6)
        cx.pack_start(rotulo(texto, "rotulo"), False, False, 0)
        return cx

    # -- cabecalho ---------------------------------------------------------
    def _cabecalho(self):
        externo = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)

        barra = Gtk.Box(spacing=12)
        barra.set_margin_bottom(8 if self.compacto else 14)

        txt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        txt.set_valign(Gtk.Align.CENTER)
        txt.pack_start(rotulo("ZANTHUS  /  FRENTE DE CAIXA", "eyebrow"),
                       False, False, 0)
        txt.pack_start(rotulo("Instalação de PDV", "titulo"), False, False, 0)
        barra.pack_start(txt, True, True, 0)

        dir_ = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        dir_.set_valign(Gtk.Align.CENTER)
        dir_.set_halign(Gtk.Align.END)
        self.bt_reler = Gtk.Button(label="Reler ambiente")
        add_class(self.bt_reler, "secundaria")
        self.bt_reler.connect("clicked", lambda _b: self.recarregar())
        dir_.pack_start(self.bt_reler, False, False, 0)
        lb = rotulo("Desenvolvido por @JJMoratelli", "assinatura", xalign=1.0)
        dir_.pack_start(lb, False, False, 0)
        barra.pack_end(dir_, False, False, 0)

        externo.pack_start(barra, False, False, 0)
        externo.pack_start(regua(INK, 2), False, False, 0)
        return externo

    # -- painel unico da estacao (grade alinhada) ---------------------------
    def _montar_painel(self):
        for filho in self.painel.get_children():
            self.painel.remove(filho)

        a = self.amb
        cartao = Gtk.Box()
        add_class(cartao, "cartao")

        trilho = Gtk.Box()
        add_class(trilho, "trilho")
        pintar(trilho, VERMELHO if a.claz_bloqueia else
               (AZUL if a.id_filial is not None else CINZA))
        cartao.pack_start(trilho, False, False, 0)

        # Grade compartilhada: as 4 faixas (rotulo/valor/origem/estado) ficam
        # na mesma linha em todas as colunas, entao tudo alinha na horizontal.
        g = Gtk.Grid(column_spacing=0, row_spacing=6)
        g.set_border_width(14 if self.compacto else 20)
        g.set_column_homogeneous(False)

        bt_host = None
        if a.hostname_novo and not a.host_ok:
            bt_host = Gtk.Button(label="Corrigir")
            add_class(bt_host, "secundaria")
            bt_host.set_halign(Gtk.Align.START)
            bt_host.set_sensitive(a.pode_elevar)
            bt_host.connect("clicked", self.on_corrigir_hostname)

        linha1 = [
            ("FILIAL",
             "%d · Loja %s" % (a.id_filial, a.loja) if a.id_filial is not None else "",
             False,
             "CLAZ.CFG  %s" % (a.claz_filial or "sem arquivo"),
             CHIP_MAP[a.cfg_filial], None),
            ("CNPJ",
             Ambiente.cnpj_fmt(a.cnpj) if a.cnpj else "", True,
             "CLAZ.CFG  %s" % (Ambiente.cnpj_fmt(a.claz_cnpj)
                               if a.claz_cnpj else "sem arquivo"),
             CHIP_MAP[a.cfg_cnpj], None),
            ("CAIXA",
             a.numero_final if a.numero_final is not None else "", False,
             "ECF9F.CFG  %s  ·  esperado %s" % (
                 a.ecf_caixa or "sem arquivo",
                 a.caixa_esperado if a.caixa_esperado is not None else "-"),
             CHIP_MAP[a.cfg_caixa], None),
        ]
        linha2 = [
            ("HOSTNAME", a.hostname_atual, True,
             ("esperado  %s" % a.hostname_novo) if a.hostname_novo else "sem filial",
             ("CONFERE", "ok") if a.host_ok else
             (("DIVERGENTE", "atencao") if a.hostname_novo else None),
             bt_host),
            ("BALANÇA", a.balanca_txt, False,
             "Toledo CDC  ·  /dev/serial/by-id",
             ("%d PORTA%s" % (a.qtd_balancas, "S" if a.qtd_balancas != 1 else ""),
              "ok" if a.qtd_balancas else "neutro"), None),
            ("REDE", a.ip or "", True,
             "gateway  %s" % (a.gateway or "sem rota padrão"), None, None),
        ]

        def bloco(campos, base):
            for col, (tit, valor, mono, origem, chip_par, extra) in enumerate(campos):
                x = col * 2
                if col:
                    sep = Gtk.Separator(orientation=Gtk.Orientation.VERTICAL)
                    folga = 12 if self.compacto else 22
                    sep.set_margin_start(folga)
                    sep.set_margin_end(folga)
                    g.attach(sep, x - 1, base, 1, 4)

                cel = Gtk.Box()
                cel.set_size_request(self.larg_celula, -1)
                cel.set_hexpand(True)
                g.attach(cel, x, base, 1, 1)
                cel.pack_start(rotulo(tit, "rotulo"), False, False, 0)

                vazio = str(valor) in ("", "-", "None")
                g.attach(rotulo("não detectado" if vazio else str(valor),
                                "valor-vazio" if vazio else
                                ("valor-mono" if mono else "valor")),
                         x, base + 1, 1, 1)
                g.attach(rotulo(origem or " ", "secundario"), x, base + 2, 1, 1)

                estado = Gtk.Box(spacing=10)
                if chip_par:
                    estado.pack_start(chip(*chip_par), False, False, 0)
                if extra:
                    estado.pack_start(extra, False, False, 0)
                estado.set_size_request(-1, 30)
                g.attach(estado, x, base + 3, 1, 1)

        bloco(linha1, 0)
        divisor = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        folga = 10 if self.compacto else 18
        divisor.set_margin_top(folga)
        divisor.set_margin_bottom(folga)
        g.attach(divisor, 0, 4, 5, 1)
        bloco(linha2, 5)

        cartao.pack_start(g, True, True, 0)
        self.painel.pack_start(cartao, True, True, 0)
        self.painel.show_all()

    # -- faixa de bloqueio / alerta ----------------------------------------
    def _montar_faixa(self):
        for filho in self.faixa.get_children():
            self.faixa.remove(filho)

        a = self.amb
        if not a.pode_elevar:
            titulo = "Sem permissão de administrador"
            texto = ("O usuário %s não conseguiu usar o sudo sem senha. Rode o "
                     "menu pelo terminal: a senha é pedida lá, antes de a tela "
                     "abrir." % os.environ.get("USER", str(os.geteuid())))
            classe = "faixa-erro"
        elif a.claz_bloqueia:
            titulo = "CLAZ.CFG divergente — instalação bloqueada"
            texto = ("Os dados gravados em CLAZ.CFG não correspondem à filial "
                     "detectada na rede. É necessário refazer a instalação da "
                     "base Zanthus nesta máquina antes de instalar o PDV.")
            classe = "faixa-erro"
        elif a.id_filial is None:
            titulo = "Filial não identificada"
            texto = ("O gateway %s não consta na tabela de filiais. Verifique a "
                     "rede antes de prosseguir." % (a.gateway or "ausente"))
            classe = "faixa-erro"
        elif a.debian:
            titulo = "Instalação ainda não liberada no Debian"
            texto = ("O instalador do Debian (Debian/LauncherPDV.sh) está em "
                     "validação no terminal de teste. A conferência e a correção "
                     "do hostname funcionam; a instalação fica travada até lá.")
            classe = "faixa-erro"
        elif a.cfg_caixa == "divergente":
            titulo = "Número de caixa divergente no ECF9F.CFG"
            texto = ("O ECF9F.CFG aponta caixa %s, mas o esperado para este IP é %s. "
                     "A instalação pode seguir, mas confira ao concluir."
                     % (a.ecf_caixa, a.caixa_esperado))
            classe = "faixa-alerta"
        else:
            return

        cx = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
        cx.set_border_width(14)
        cx.set_margin_top(20)
        add_class(cx, classe)
        cx.pack_start(rotulo(titulo, "faixa-titulo"), False, False, 0)
        lb = rotulo(texto, "faixa-txt")
        lb.set_line_wrap(True)
        cx.pack_start(lb, False, False, 0)
        self.faixa.pack_start(cx, True, True, 0)
        self.faixa.show_all()

    # -- perfis -------------------------------------------------------------
    def _lista_perfis(self):
        """ToggleButton em vez de RadioButton: o grupo de radio obriga um item
        ativo desde o inicio, o que fazia o primeiro card nascer marcado e
        ignorar o primeiro clique."""
        g = Gtk.Grid(column_spacing=10, row_spacing=10, column_homogeneous=True)
        self.botoes_perfil = {}
        self._trocando = False

        for i, (pid, nome, cor, _arq, desc) in enumerate(PERFIS):
            bt = Gtk.ToggleButton()
            add_class(bt, "perfil")

            linha = Gtk.Box()
            trilho = Gtk.Box()
            add_class(trilho, "trilho")
            pintar(trilho, cor)
            trilho.set_size_request(5, -1)
            linha.pack_start(trilho, False, False, 0)

            txt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
            txt.set_border_width(11 if self.compacto else 16)
            txt.pack_start(rotulo(nome, "perfil-nome"), False, False, 0)
            d = rotulo(desc, "perfil-desc")
            d.set_line_wrap(True)
            d.set_line_wrap_mode(Pango.WrapMode.WORD)
            d.set_max_width_chars(26)
            d.set_size_request(-1, 30)
            d.set_valign(Gtk.Align.START)
            txt.pack_start(d, False, False, 0)
            linha.pack_start(txt, True, True, 0)

            marca = rotulo("SELECIONAR", "marca", "marca-off")
            caixa = Gtk.Box()
            caixa.set_valign(Gtk.Align.CENTER)
            caixa.set_margin_end(14)
            caixa.pack_start(marca, False, False, 0)
            linha.pack_end(caixa, False, False, 0)

            bt.add(linha)
            bt.set_active(False)
            bt.connect("toggled", self.on_perfil, pid)
            self.botoes_perfil[pid] = (bt, trilho, marca)
            g.attach(bt, i % self.perfis_por_linha,
                     i // self.perfis_por_linha, 1, 1)

        self.perfil = None
        return g

    def on_perfil(self, botao, pid):
        if self._trocando:
            return

        # clique no card ja selecionado nao desmarca: a escolha e obrigatoria
        if not botao.get_active():
            if self.perfil == pid:
                self._trocando = True
                botao.set_active(True)
                self._trocando = False
            return

        self._trocando = True
        self.perfil = pid
        for outro, (bt, trilho, marca) in self.botoes_perfil.items():
            sel = (outro == pid)
            if bt.get_active() != sel:
                bt.set_active(sel)
            ctx = bt.get_style_context()
            mctx = marca.get_style_context()
            if sel:
                ctx.add_class("perfil-sel")
                mctx.remove_class("marca-off")
                mctx.add_class("marca-on")
                marca.set_text("SELECIONADO")
                trilho.set_size_request(9, -1)
            else:
                ctx.remove_class("perfil-sel")
                mctx.remove_class("marca-on")
                mctx.add_class("marca-off")
                marca.set_text("SELECIONAR")
                trilho.set_size_request(5, -1)
        self._trocando = False
        self._atualizar_estado()

    # -- rodape -------------------------------------------------------------
    def _barra_acoes(self):
        cx = Gtk.Box(spacing=14)
        cx.set_margin_top(14 if self.compacto else 26)
        self.lb_status = rotulo("", "secundario")
        self.lb_status.set_valign(Gtk.Align.CENTER)
        cx.pack_start(self.lb_status, True, True, 0)

        self.bt_instalar = Gtk.Button(label="Iniciar instalação")
        add_class(self.bt_instalar, "acao")
        self.bt_instalar.connect("clicked", self.on_instalar)
        cx.pack_end(self.bt_instalar, False, False, 0)

        # Saida sempre disponivel: sem ela, filial nao identificada ou
        # CLAZ.CFG divergente prendiam o tecnico na tela cheia.
        bt_sair = Gtk.Button(label="Sair")
        add_class(bt_sair, "secundaria")
        bt_sair.set_valign(Gtk.Align.CENTER)
        bt_sair.connect("clicked", self.on_sair)
        cx.pack_end(bt_sair, False, False, 0)
        return cx

    def on_sair(self, _b):
        # Neutro, nao vermelho: sair nao destroi nada. O peso vem da
        # confirmacao travada, porque a instalacao nao volta sozinha.
        if Dialogo.confirmar(
                self, None, "Sair do instalador?",
                "A instalação do PDV não será iniciada e não começa de novo "
                "sozinha: para instalar este terminal depois, será preciso "
                "abrir o menu outra vez pelo terminal.",
                ok="Sair do instalador", espera=ESPERA_SAIR):
            self.destroy()

    # -- estado --------------------------------------------------------------
    def recarregar(self):
        self.amb.detectar()
        self._montar_faixa()
        self._montar_painel()
        self._atualizar_estado()

    def _atualizar_estado(self):
        a = self.amb
        if not a.pode_elevar:
            bloqueio = "Sem permissão de administrador (sudo)."
        elif a.claz_bloqueia:
            bloqueio = "CLAZ.CFG divergente. Refaça a instalação da base Zanthus."
        elif a.id_filial is None:
            bloqueio = "Filial não identificada pelo gateway."
        elif a.debian:
            bloqueio = "Instalação ainda não liberada no Debian."
        elif self.perfil is None:
            bloqueio = "Selecione um perfil para continuar."
        else:
            bloqueio = None

        liberado = (a.pode_elevar and not a.claz_bloqueia
                    and a.id_filial is not None)
        for bt, _trilho, _marca in self.botoes_perfil.values():
            bt.set_sensitive(liberado)

        self.bt_instalar.set_sensitive(bloqueio is None)
        if bloqueio:
            self.lb_status.set_text(bloqueio)
        else:
            nome = dict((p[0], p[1]) for p in PERFIS)[self.perfil]
            self.lb_status.set_text("Perfil selecionado: %s" % nome)

    def on_corrigir_hostname(self, _b):
        if not Dialogo.confirmar(
                self, None, "Corrigir hostname",
                "O nome da máquina será alterado e o /etc/hosts atualizado.",
                [("atual", self.amb.hostname_atual),
                 ("novo", self.amb.hostname_novo)],
                ok="Alterar"):
            return
        try:
            self.amb.aplicar_hostname()
        except Exception as erro:
            Dialogo.avisar(self, "Falha ao alterar hostname", str(erro))
        self.recarregar()

    # -- instalacao ----------------------------------------------------------
    def on_instalar(self, _b):
        a = self.amb
        if a.claz_bloqueia:
            Dialogo.avisar(
                self, "Instalação bloqueada",
                "O CLAZ.CFG desta máquina não corresponde à filial detectada. "
                "Refaça a instalação da base Zanthus antes de instalar o PDV.",
                [("filial detectada", a.id_filial),
                 ("filial no claz", a.claz_filial or "-"),
                 ("cnpj detectado", Ambiente.cnpj_fmt(a.cnpj)),
                 ("cnpj no claz", Ambiente.cnpj_fmt(a.claz_cnpj))])
            return

        nome = dict((p[0], p[1]) for p in PERFIS)[self.perfil]
        linhas = [("perfil", nome),
                  ("filial", "%s · Loja %s" % (a.id_filial, a.loja)),
                  ("caixa", a.numero_final),
                  ("hostname", a.hostname_atual),
                  ("balança", a.balanca_txt)]

        # 1a checagem — revisao dos dados
        if not Dialogo.confirmar(
                self, "CONFIRMAÇÃO 1 DE 2", "Confira os dados da estação",
                "Estes valores serão gravados em %s e usados pelo instalador. "
                "Se algo estiver errado, cancele e corrija antes." % CONF_DIR,
                linhas, ok="Está correto"):
            return

        # 2a checagem — travada por 3s
        avisos = []
        if not a.host_ok and a.hostname_novo:
            avisos.append("hostname ainda divergente")
        if a.cfg_caixa == "divergente":
            avisos.append("caixa divergente no ECF9F.CFG")
        texto = ("A instalação do %s começa agora e não pode ser interrompida "
                 "pela tela. O terminal assume a partir daqui." % nome)
        if avisos:
            texto += "  Pendências: " + ", ".join(avisos) + "."

        if not Dialogo.confirmar(
                self, "CONFIRMAÇÃO 2 DE 2", "Iniciar a instalação?", texto,
                ok="Instalar agora", espera=ESPERA_CONFIRMACAO):
            return

        try:
            a.gravar_conf(self.perfil)
        except Exception as erro:
            Dialogo.avisar(self, "Falha ao gravar configuração",
                           "Não foi possível escrever em %s." % CONF_DIR,
                           [("erro", erro)])
            return

        # 1) some com esta tela imediatamente
        self.hide()
        while Gtk.events_pending():
            Gtk.main_iteration()

        # 2) sobe a splash como processo independente (sobrevive ao exec)
        pid_splash = self.abrir_splash()

        # 3) entrega o controle ao terminal; a splash morre junto com o script.
        #    O LauncherPDV.sh precisa de root: fora do root, vai pelo sudo. O
        #    arquivo e temporario e proprio, porque um /tmp/LauncherPDV.sh de
        #    uma execucao anterior como root nao deixaria o curl sobrescrever.
        matar = ("kill %d 2>/dev/null" % pid_splash) if pid_splash else "true"
        self.comando_final = (
            "trap '%s' EXIT INT TERM; "
            "f=$(mktemp /tmp/LauncherPDV.XXXXXX) && "
            "curl -fsSL '%s' -o \"$f\" && %sbash \"$f\""
            % (matar, URL_LAUNCHER_DEBIAN if self.amb.debian else URL_LAUNCHER,
               "" if EH_ROOT else "sudo "))
        self.destroy()

    @staticmethod
    def abrir_splash():
        if not CAMINHO_SCRIPT:
            return None          # rodando via stdin: sem arquivo para respawnar
        try:
            proc = subprocess.Popen(
                [sys.executable, CAMINHO_SCRIPT, "--splash"],
                start_new_session=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return proc.pid
        except Exception:
            return None


def main():
    if "--root" in sys.argv:
        i = sys.argv.index("--root")
        try:
            sys.stdout.write(executar_root(sys.argv[i + 1:]))
        except Exception as erro:
            print("ERRO: %s" % erro)
            sys.exit(1)
        return

    if "--splash" in sys.argv:
        i = sys.argv.index("--splash")
        marca = sys.argv[i + 1] if len(sys.argv) > i + 1 else MARCA_LAUNCHER
        rodar_splash(marca)
        return

    janela = Janela()
    janela.show_all()
    Gtk.main()

    if janela.comando_final:
        time.sleep(0.6)          # deixa a splash mapear antes de trocar o processo
        os.execvp("/bin/bash", ["/bin/bash", "-c", janela.comando_final])
    sys.exit(0)


if __name__ == "__main__":
    main()
FIM_PY_ZANTHUS

$SUDO chmod 0755 "$ALVO"

# ------------------------------------------- abre no usuario dono da sessao
VARS=()
for _v in DISPLAY XAUTHORITY WAYLAND_DISPLAY XDG_RUNTIME_DIR GDK_BACKEND; do
    [ -n "${!_v:-}" ] && VARS+=("${_v}=${!_v}")
done
[ "$SESSAO_TIPO" = "wayland" ] \
    && VARS+=("DBUS_SESSION_BUS_ADDRESS=unix:path=${XDG_RUNTIME_DIR}/bus")

echo -e "${GREEN}Abrindo o menu grafico (sessao ${SESSAO_TIPO} de ${USUARIO_SESSAO})...${NC}"
if [ "$(id -u)" -eq "$SESSAO_UID" ]; then
    exec python3 "$ALVO"
elif [ "$(id -u)" -eq 0 ]; then
    exec runuser -u "$USUARIO_SESSAO" -- env "${VARS[@]}" python3 "$ALVO"
else
    exec sudo -u "$USUARIO_SESSAO" env "${VARS[@]}" python3 "$ALVO"
fi
