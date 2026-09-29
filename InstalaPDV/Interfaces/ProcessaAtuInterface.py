#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ProcessaAtuInterface - prepara o pacote de atualizacao da interface Zanthus.

Pega o .zip que a Zanthus mandou, descarta os arquivos que temos versao
propria, reaplica nossas customizacoes de codigo e gera o interface.7z.

    ./ProcessaAtuInterface.py [diretorio_base]

O diretorio base e onde o .zip da Zanthus foi colocado e onde o interface.7z
sai. Se nao for informado, usa o diretorio do proprio script.

Duas politicas convivem aqui, e a diferenca importa:

  REMOVER   arquivos dos quais mantemos versao propria e integral (imagens,
            CSS, config.js...). O 7z simplesmente nao os leva, entao o que
            ja esta no PDV permanece.

  PATCHES   arquivos que sao codigo da Zanthus com um enxerto nosso. Esses
            PRECISAM ser atualizados a cada release - senao perdemos as
            correcoes que a Zanthus faz neles. O enxerto e reaplicado por
            ancora textual, nao por numero de linha, e por isso sobrevive a
            reminificacao de cada versao.

Se um patch nao encaixar, o script aborta sem gerar pacote. E preferivel
nao entregar nada a entregar um interface.7z sem a customizacao.

Requer: 7z (p7zip) no PATH.
"""

import os
import re
import shutil
import subprocess
import sys
import zipfile


# ===========================================================================
# BLOCO 1 - CONFIGURACAO
# ===========================================================================

PADROES_ZIP = ("Interface_R-*.zip", "InterfaceUnificada_*.zip")

NOME_SAIDA = "interface.7z"
NOME_TEMP = "pasta_temporaria"

# Arquivos e pastas com versao propria: saem do pacote para nao sobrescrever
# o que ja esta instalado no PDV.
REMOVER = (
    "app/api/dinamico/pdvMouse/Buttons.js",
    "app/view/tela/2/TelaComanda.js",
    "config/config.js",
    "resources/audio",
    "resources/css/style2.css",
    "resources/css/style100.css",
    "resources/css/style1000.css",
    "resources/css/stylemonitor_cliente.css",
    "resources/icones",
    "resources/imagens/Zeus_V.gif",
    "resources/imagens/cancela.png",
    "resources/imagens/cancela_sel.png",
    "resources/imagens/descanso1000.jpg",
    "resources/imagens/logo.png",
    "resources/imagens/logo_self.png",
    "resources/imagens/processando.gif",
    "resources/imagens/self/codigo.gif",
    "resources/js/teclas_touch.js",
    "resources/js/telas_touch.js",
)


# ===========================================================================
# BLOCO 2 - CUSTOMIZACOES REAPLICADAS (PATCHES)
# ===========================================================================
#
# Cada patch enxerta 'corpo' imediatamente APOS a primeira e unica ocorrencia
# de 'ancora_apos' dentro de 'alvo'. A 'marca' identifica o patch ja aplicado
# e torna a operacao idempotente; mude a versao dela ao editar o corpo.
#
# Ao escolher uma ancora, prefira um trecho de codigo da Zanthus que seja
# semanticamente estavel entre releases e sintaticamente inconfundivel.

PATCH_SETAS_BOTOES = r"""/* VERSAO_JJM=v4 */ /* === [@JJMoratelli] setas laterais nos botoes + Esc no coletor sem teclamensageira ===   Esc: age SO onde o tratamento nativo (case 27) comprovadamente nao age -   dialogo com campo de digitacao, nenhum teclamensageira vivo e um unico   botao na toolbar. Havendo teclamensageira, o nativo cuida e este bloco   nao entra. Acionamento por fireHandler porque botao xtype "tecla" usa   handler inline, que fireEvent("click") nao executa. */
                        try {
                            if (__habilita_setas_opcoes && (a.keyCode == 37 || a.keyCode == 39 || a.keyCode == 13 || a.keyCode == 38 || a.keyCode == 40 || a.keyCode == 27)) {
                                var _dl = Ext.ComponentQuery.query("dialogo{isVisible(true)}");
                                if (!Ext.isEmpty(_dl)) {
                                    var _dg = _dl[_dl.length - 1],
                                        _tb = _dg.down("toolbar");
                                    if (_tb) {
                                        var _bt = _tb.query("component{isVisible(true)}").filter(function(c) {
                                            return c.xtype !== "tbfill" && c.xtype !== "tbspacer" && c.xtype !== "tbseparator" && !c.disabled
                                        });
                                        var _G = Pdv.api.sistema.Gerenciador;
                                        if (_G.dlgSeletor !== _dg.id) {
                                            _G.dlgSeletor = _dg.id;
                                            _G.colSeletor = null
                                        }
                                        var _pt = function() {
                                            _bt.forEach(function(b, i) {
                                                b.el.dom.classList.toggle("selecionado-seta-botao", i === _G.colSeletor)
                                            })
                                        };
                                        var _ac = function(b) {
                                            b.el.dom.classList.remove("selecionado-seta-botao");
                                            Ext.isFunction(b.fireHandler) ? b.fireHandler() : b.fireEvent("click", b)
                                        };
                                        if (a.keyCode == 27) {
                                            var _esc = (typeof __desativaTeclaEscDialogo == "undefined" || !__desativaTeclaEscDialogo) && _dg.campo !== undefined && Ext.ComponentQuery.query("teclamensageira").length === 0 && _bt.length == 1;
                                            if (_esc) {
                                                _G.colSeletor = null;
                                                _G.dlgSeletor = null;
                                                _ac(_bt[0]);
                                                return true
                                            }
                                        } else if (_bt.length > 1) {
                                            if (a.keyCode == 38 || a.keyCode == 40) {
                                                if (_G.colSeletor != null) {
                                                    _G.colSeletor = null;
                                                    _pt()
                                                }
                                            } else {
                                                var _ps = a.keyCode == 39 ? 1 : a.keyCode == 37 ? -1 : 0;
                                                if (_ps) {
                                                    _G.colSeletor = _G.colSeletor == null ? (_ps > 0 ? 0 : _bt.length - 1) : (_G.colSeletor + _ps + _bt.length) % _bt.length;
                                                    _pt();
                                                    return true
                                                }
                                                if (a.keyCode == 13 && _G.colSeletor != null && _bt[_G.colSeletor]) {
                                                    var _b = _bt[_G.colSeletor];
                                                    _G.colSeletor = null;
                                                    _G.dlgSeletor = null;
                                                    _ac(_b);
                                                    return true
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } catch (_e) {} /* === fim === */"""

PATCHES = (
    {
        "nome": "setas-botoes",
        "alvo": "app/controller/Controller.js",
        "ancora_apos": "__gatilho_teclas(a)==true)return true;",
        "marca": "VERSAO_JJM=v4",
        "desc": "setas laterais nos botoes do dialogo + Esc no coletor sem teclamensageira",
        "corpo": PATCH_SETAS_BOTOES,
        # Par visual: a classe .selecionado-seta-botao vive no nosso style100.css.
    },
)


# ===========================================================================
# BLOCO 3 - UTILIDADES
# ===========================================================================

class Erro(Exception):
    """Falha que aborta o processamento com mensagem limpa."""


def log(msg):
    print(msg, flush=True)


def localizar_zip(base):
    import fnmatch
    achados = sorted(
        nome for nome in os.listdir(base)
        if os.path.isfile(os.path.join(base, nome))
        and any(fnmatch.fnmatch(nome, p) for p in PADROES_ZIP)
    )
    if not achados:
        raise Erro("nenhum .zip da Zanthus encontrado em '%s' (padroes: %s)"
                   % (base, ", ".join(PADROES_ZIP)))
    if len(achados) > 1:
        raise Erro("mais de um .zip em '%s': %s - deixe so o que sera processado"
                   % (base, ", ".join(achados)))
    return os.path.join(base, achados[0])


def exigir_7z():
    for cmd in ("7z", "7za", "7zz"):
        if shutil.which(cmd):
            return cmd
    raise Erro("7z nao encontrado no PATH - instale o p7zip")


# ===========================================================================
# BLOCO 4 - ETAPAS
# ===========================================================================

def extrair(caminho_zip, destino):
    log("Descompactando %s..." % os.path.basename(caminho_zip))
    if os.path.exists(destino):
        shutil.rmtree(destino)
    os.makedirs(destino)
    with zipfile.ZipFile(caminho_zip) as z:
        z.extractall(destino)


def remover_substituidos(raiz):
    log("Removendo arquivos com versao propria...")
    ausentes = []
    for rel in REMOVER:
        caminho = os.path.join(raiz, rel)
        if os.path.isdir(caminho):
            shutil.rmtree(caminho)
        elif os.path.exists(caminho):
            os.remove(caminho)
        else:
            ausentes.append(rel)
    if ausentes:
        # Nao e fatal: a Zanthus pode ter deixado de enviar o arquivo. Mas vale
        # saber, porque tambem pode significar que ele mudou de lugar.
        log("  aviso: nao vieram no pacote desta vez: %s" % ", ".join(ausentes))


def aplicar_patch(patch, raiz):
    alvo = os.path.join(raiz, patch["alvo"])
    if not os.path.isfile(alvo):
        raise Erro("patch '%s': alvo '%s' nao existe no pacote"
                   % (patch["nome"], patch["alvo"]))

    with open(alvo, encoding="utf-8", errors="surrogateescape") as fh:
        texto = fh.read()

    if patch["marca"] in texto:
        log("  [ja aplicado] %s (marca %s presente)" % (patch["nome"], patch["marca"]))
        return

    ocorrencias = texto.count(patch["ancora_apos"])
    if ocorrencias != 1:
        raise Erro(
            "patch '%s': ancora encontrada %d vez(es) em '%s', esperado 1.\n"
            "A Zanthus mexeu nesse trecho - revise o patch contra a nova versao.\n"
            "Ancora: %s" % (patch["nome"], ocorrencias, patch["alvo"],
                            patch["ancora_apos"]))

    pos = texto.index(patch["ancora_apos"]) + len(patch["ancora_apos"])
    novo = texto[:pos] + patch["corpo"] + texto[pos:]

    with open(alvo, "w", encoding="utf-8", errors="surrogateescape") as fh:
        fh.write(novo)

    if shutil.which("node"):
        check = subprocess.run(["node", "--check", alvo], capture_output=True, text=True)
        if check.returncode != 0:
            with open(alvo, "w", encoding="utf-8", errors="surrogateescape") as fh:
                fh.write(texto)
            raise Erro("patch '%s': o resultado nao passou no 'node --check':\n%s"
                       % (patch["nome"], check.stderr.strip()))

    log("  [aplicado]    %s - %s" % (patch["nome"], patch["desc"]))


def aplicar_patches(raiz):
    log("Reaplicando customizacoes...")
    for patch in PATCHES:
        aplicar_patch(patch, raiz)


def empacotar(raiz, saida, cmd_7z):
    log("Gerando %s..." % os.path.basename(saida))
    if os.path.exists(saida):
        os.remove(saida)
    itens = sorted(os.listdir(raiz))
    if not itens:
        raise Erro("nada a empacotar - '%s' esta vazio" % raiz)
    resultado = subprocess.run([cmd_7z, "a", saida] + itens, cwd=raiz,
                               capture_output=True, text=True)
    if resultado.returncode != 0:
        raise Erro("7z falhou:\n%s" % (resultado.stderr.strip() or resultado.stdout.strip()))


# ===========================================================================
# BLOCO 5 - MAIN
# ===========================================================================

def processar(base):
    if not os.path.isdir(base):
        raise Erro("diretorio base '%s' nao encontrado" % base)

    cmd_7z = exigir_7z()
    caminho_zip = localizar_zip(base)
    temp = os.path.join(base, NOME_TEMP)
    saida = os.path.join(base, NOME_SAIDA)

    extrair(caminho_zip, temp)
    remover_substituidos(temp)
    aplicar_patches(temp)          # aborta antes de empacotar se algo nao encaixar
    empacotar(temp, saida, cmd_7z)

    shutil.rmtree(temp)
    os.remove(caminho_zip)

    tamanho = os.path.getsize(saida) / (1024.0 * 1024.0)
    log("")
    log("Pronto. '%s' processado; '%s' criado em '%s' (%.1f MB)."
        % (os.path.basename(caminho_zip), NOME_SAIDA, base, tamanho))
    log("Envie o arquivo para a pasta de atualizacao manualmente.")


def main():
    if len(sys.argv) > 2:
        sys.exit("uso: %s [diretorio_base]" % os.path.basename(sys.argv[0]))
    base = sys.argv[1] if len(sys.argv) == 2 else os.path.dirname(os.path.abspath(__file__))

    try:
        processar(os.path.abspath(base))
    except Erro as erro:
        print("\nErro: %s" % erro, file=sys.stderr)
        print("Nenhum pacote foi gerado. A pasta '%s' foi mantida para inspecao."
              % NOME_TEMP, file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print("\nInterrompido.", file=sys.stderr)
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
