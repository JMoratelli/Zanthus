#!/bin/bash

# ==============================================================================
# DEFINIÇÃO DE CORES
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# ==============================================================================
# VALIDAÇÃO DE ROOT
# ==============================================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERRO: Execute como root (sudo bash ...)${NC}"
    exit 1
fi

# ==============================================================================
# DETECÇÃO SILENCIOSA DE AMBIENTE
# ==============================================================================

# 1. Configuração de Diretórios e Limpeza
CONF_DIR="/home/zanthus/tmp/Script"
if [ ! -d "$CONF_DIR" ]; then mkdir -p "$CONF_DIR"; fi
rm -f "$CONF_DIR"/*

# 2. Inicialização de Variáveis para Display
DISPLAY_FILIAL="--"
DISPLAY_HOST="--"
HOST_ALTERADO="--"
ID_FILIAL=""
NOME_ARQUIVO_FILIAL=""
LOJA=""
NUMERO_FINAL=""
SUFIXO_CAIXA=""

# 3. Detecta Gateway e Define Filial (SILENCIOSO)
gateway=$(ip route show | grep default | awk '{print $3}')

case $gateway in
    10.1.1.1)
        LOJA="01"
        DISPLAY_FILIAL="100"
        ID_FILIAL="1"
        NOME_ARQUIVO_FILIAL="filial1.conf"
        CNPJ="03790904000156"
        ;;
    192.168.11.253)
        LOJA="02"
        DISPLAY_FILIAL="200"
        ID_FILIAL="3"
        NOME_ARQUIVO_FILIAL="filial3.conf"
        CNPJ="03790904000318"
        ;;
    192.168.5.253)
        LOJA="03"
        DISPLAY_FILIAL="300"
        ID_FILIAL="9"
        NOME_ARQUIVO_FILIAL="filial9.conf"
        CNPJ="03790904000407"
        ;;
     192.168.7.253)
        LOJA="05"
        DISPLAY_FILIAL="5300"  
        ID_FILIAL="53"
        NOME_ARQUIVO_FILIAL="filial53.conf"
        CNPJ="13338712000248"
        ;;
     192.168.9.253)
        LOJA="06"
        DISPLAY_FILIAL="5200"
        ID_FILIAL="52"
        NOME_ARQUIVO_FILIAL="filial52.conf"
        CNPJ="03790904000580"
        ;;
     192.168.57.193|192.168.57.1|192.168.156.1|192.168.57.129)
        LOJA="07"
        DISPLAY_FILIAL="5700"
        ID_FILIAL="57"
        NOME_ARQUIVO_FILIAL="filial57.conf"
        CNPJ="13338712000400"
        ;;
     192.168.58.1)
        LOJA="08"
        DISPLAY_FILIAL="5800"
        ID_FILIAL="58"
        NOME_ARQUIVO_FILIAL="filial58.conf"
        CNPJ="13338712000590"
        ;;
    *)
        # Mantém padrão "--"
        ;;
esac

# Cria o arquivo da filial se foi identificado
if [ -n "$NOME_ARQUIVO_FILIAL" ]; then
    touch "$CONF_DIR/$NOME_ARQUIVO_FILIAL"
fi

# 4. Detecta Caixa via IP e Define Hostname (SILENCIOSO)
if [ -n "$ID_FILIAL" ]; then
    MEU_IP=$(hostname -I | awk '{print $1}')
    ULTIMO_OCTETO=$(echo "$MEU_IP" | awk -F. '{print $4}')
    
    if [ -n "$ULTIMO_OCTETO" ]; then
        # Pega apenas os dois últimos dígitos do octeto final
        SUFIXO_CAIXA=$((ULTIMO_OCTETO % 100))
        
        # Soma o DISPLAY_FILIAL com os dois últimos dígitos do IP
        NUMERO_FINAL=$((DISPLAY_FILIAL + SUFIXO_CAIXA))
        
        touch "$CONF_DIR/caixa${NUMERO_FINAL}.conf"

        # --- LÓGICA DE DEFINIÇÃO DE HOSTNAME ---
        NOVO_HOSTNAME="CAIXA${NUMERO_FINAL}-LJ${LOJA}"
        
        DISPLAY_HOST="$NOVO_HOSTNAME"
        HOSTNAME_ATUAL=$(hostname)

        if [ "$HOSTNAME_ATUAL" != "$NOVO_HOSTNAME" ]; then
            hostnamectl set-hostname "$NOVO_HOSTNAME"
            sed -i "/127.0.1.1/d" /etc/hosts
            echo -e "127.0.1.1\t$NOVO_HOSTNAME" >> /etc/hosts
            HOST_ALTERADO="SIM"
        else
            HOST_ALTERADO="NAO"
        fi
    fi
fi

# --- BALANÇA-----------------------------
qtd_balancas=$(ls -l /dev/serial/by-id/* 2>/dev/null | grep -c 'usb-TOLEDO_CDC_DEVICE_')

if [ "$qtd_balancas" -eq 1 ]; then
    touch "$CONF_DIR/tipoBalancaToledo.conf"
elif [ "$qtd_balancas" -ge 2 ]; then
    touch "$CONF_DIR/tipoBalancaToledoDual.conf"
else
    touch "$CONF_DIR/tipoBalancaNull.conf"
fi
# -----------------------------------------

# ==============================================================================
# FUNÇÕES DE INTERFACE E COMPARAÇÃO
# ==============================================================================
show_header() {
    clear
    
    # --- BLOCO DE COMPARAÇÃO DE ARQUIVOS (CLAZ e ECF9F) ---
    local CLAZ_FILE="/Zanthus/Zeus/pdvJava/CLAZ.CFG"
    local ECF_FILE="/Zanthus/Zeus/pdvJava/ECF9F.CFG"

    local STATUS_FILIAL="N/A"
    local STATUS_CNPJ="N/A"
    local STATUS_CAIXA="N/A"

    local COLOR_FILIAL=$YELLOW
    local COLOR_CNPJ=$YELLOW
    local COLOR_CAIXA=$YELLOW

    # Validação do arquivo CLAZ.CFG
    if [ -f "$CLAZ_FILE" ]; then
        local FILE_LOJA=$(grep -i '^LOJA=' "$CLAZ_FILE" | cut -d= -f2 | tr -d '\r[:space:]')
        local FILE_CNPJ=$(grep -i '^CNPJ=' "$CLAZ_FILE" | cut -d= -f2 | tr -d '\r[:space:]')

        # Comparação numérica da Filial
        if [ -n "$ID_FILIAL" ] && [ -n "$FILE_LOJA" ] && [ "$ID_FILIAL" -eq "$FILE_LOJA" ] 2>/dev/null; then
            STATUS_FILIAL="OK"
            COLOR_FILIAL=$GREEN
        else
            STATUS_FILIAL="DIVERGENTE"
            COLOR_FILIAL=$RED
        fi

        # Comparação do CNPJ
        if [ -n "$CNPJ" ] && [ "$CNPJ" = "$FILE_CNPJ" ]; then
            STATUS_CNPJ="OK"
            COLOR_CNPJ=$GREEN
        else
            STATUS_CNPJ="DIVERGENTE"
            COLOR_CNPJ=$RED
        fi
    fi

    # Validação do arquivo ECF9F.CFG
    if [ -f "$ECF_FILE" ]; then
        local FILE_CAIXA=$(grep -i '^NUMERACAIXA=' "$ECF_FILE" | cut -d= -f2 | tr -d '\r[:space:]')
        local EXPECTED_CAIXA=""

        # REGRA ATUALIZADA: Lojas 1, 2 e 3 comparam com NUMERO_FINAL. Demais lojas comparam com SUFIXO_CAIXA.
        if [ "$LOJA" = "01" ] || [ "$LOJA" = "02" ] || [ "$LOJA" = "03" ]; then
            EXPECTED_CAIXA="$NUMERO_FINAL"
        else
            EXPECTED_CAIXA="$SUFIXO_CAIXA"
        fi

        if [ -n "$EXPECTED_CAIXA" ] && [ -n "$FILE_CAIXA" ] && [ "$EXPECTED_CAIXA" -eq "$FILE_CAIXA" ] 2>/dev/null; then
            STATUS_CAIXA="OK"
            COLOR_CAIXA=$GREEN
        else
            STATUS_CAIXA="DIVERGENTE"
            COLOR_CAIXA=$RED
        fi
    fi

    # Formatação das variáveis para garantir tamanho de string fixo (10 caracteres)
    local PAD_FILIAL PAD_CNPJ PAD_CAIXA
    printf -v PAD_FILIAL "%-10.10s" "$STATUS_FILIAL"
    printf -v PAD_CNPJ "%-10.10s" "$STATUS_CNPJ"
    printf -v PAD_CAIXA "%-10.10s" "$STATUS_CAIXA"
    # -----------------------------------------------------------

    echo -e "${CYAN}############################################################${NC}"
    echo -e "${CYAN}#                                                          #${NC}"
    echo -e "${CYAN}#                                                          #${NC}"
    
    # MATEMÁTICA DAS LINHAS ESTÁTICAS (Total 60 caracteres)
    echo -e "${CYAN}#             ${WHITE}SCRIPT DE INSTALAÇÃO ZANTHUS PDV${CYAN}             #${NC}"
    echo -e "${CYAN}#              ${WHITE}DESENVOLVIDO POR @JJMORATELLI${CYAN}               #${NC}"
    
    echo -e "${CYAN}#                                                          #${NC}"
    
    # MATEMÁTICA DO ALINHAMENTO LINHA 1 (Total 60 caracteres)
    printf "${CYAN}#  ${WHITE}Filial: ${CYAN}%-5.5s   ${WHITE}Host: ${CYAN}%-15.15s%19s${CYAN}#${NC}\n" "${ID_FILIAL:---}" "$DISPLAY_HOST" ""
    
    # MATEMÁTICA DO ALINHAMENTO LINHA 2 (Total 60 caracteres)
    printf "${CYAN}#  ${WHITE}Host Alterado: ${CYAN}%-3.3s%38s${CYAN}#${NC}\n" "$HOST_ALTERADO" ""

    # MATEMÁTICA DO ALINHAMENTO CLAZ.CFG (Total 60 caracteres)
    printf "${CYAN}#  ${WHITE}Filial CFG: ${COLOR_FILIAL}%s${WHITE}  CNPJ CFG: ${COLOR_CNPJ}%s%12s${CYAN}#${NC}\n" "$PAD_FILIAL" "$PAD_CNPJ" ""

    # MATEMÁTICA DO ALINHAMENTO ECF9F.CFG (Total 60 caracteres)
    printf "${CYAN}#  ${WHITE}Caixa CFG:  ${COLOR_CAIXA}%s%34s${CYAN}#${NC}\n" "$PAD_CAIXA" ""

    echo -e "${CYAN}#                                                          #${NC}"
    echo -e "${CYAN}############################################################${NC}"
    echo ""
}

run_installer() {
    local url=$1
    local name=$2
    
    echo ""
    echo -e "${GREEN}--> Iniciando: $name...${NC}"
    
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${YELLOW}Instalando dependência: curl...${NC}"
        apt-get update && apt-get install curl -y >/dev/null 2>&1
    fi

    # Executa o script remoto
    bash <(curl -s "$url")
}

# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================
while true; do
    show_header
    echo -e "${YELLOW}Escolha o tipo de instalação:${NC}"
    echo ""
    echo -e "   ${WHITE}[1]${NC} - Instalação PDV Comum"
    echo -e "   ${WHITE}[2]${NC} - Instalação PDV SelfCheckout"
    echo -e "   ${WHITE}[3]${NC} - Instalação PDV Lanchonete"
    echo ""
    echo -e "   ${WHITE}[0]${NC} - Sair"
    echo ""
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    
    echo -ne "Digite o número da opção: "
    read -r opcao_menu < /dev/tty

    if [ -z "$opcao_menu" ]; then
        continue
    fi

    case $opcao_menu in
        1)
            # SUBMENU PARA PDV COMUM
            echo ""
            echo -e "${YELLOW}Selecione a Interface:${NC}"
            echo -e "   ${WHITE}[1]${NC} - Interface Comum (Padrão)"
            echo -e "   ${WHITE}[2]${NC} - Interface Touch"
            echo ""
            echo -ne "Opção: "
            read -r sub_opcao < /dev/tty
            
            case $sub_opcao in
                1)
                    touch "$CONF_DIR/tipoConfComum.conf"
                    NOME="Instalação PDV Comum - Interface Padrão"
                    ;;
                2)
                    touch "$CONF_DIR/tipoConfTouch.conf"
                    NOME="Instalação PDV Comum - Interface Touch"
                    ;;
                *)
                    echo -e "${RED}Opção inválida. Escolha 1 ou 2.${NC}"
                    touch "$CONF_DIR/tipoConfComum.conf"                 
                    sleep 2
                    continue
                    ;;
            esac
            
            URL="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PosInstallPDV.sh"
            ;;
        2)
            touch "$CONF_DIR/tipoConfSelf.conf"
            NOME="Instalação PDV SelfCheckout"
            URL="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PosInstallPDV.sh"
            ;;
        3)
            touch "$CONF_DIR/tipoConfLancho.conf"
            NOME="Instalação PDV Lanchonete"
            URL="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PosInstallPDV.sh"
            ;;
        0)
            echo -e "${GREEN}Saindo...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opção inválida. Escolha 1, 2, 3 ou 0.${NC}"
            sleep 2
            continue
            ;;
    esac

    # ==========================================================================
    # CONFIRMAÇÃO
    # ==========================================================================
    while true; do
        echo ""
        echo -e "${YELLOW}Selecionado: ${WHITE}$NOME${NC}"
        echo -ne "Confirma? (digite ${GREEN}sim${NC}, ${RED}nao${NC}): "
        
        read -r confirmacao < /dev/tty

        confirmacao=$(echo "$confirmacao" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

        case $confirmacao in
            sim)
                run_installer "$URL" "$NOME"
                echo -e "${GREEN}Finalizado.${NC}"
                
                echo -e "Pressione ENTER para voltar..."
                read -r dummy < /dev/tty
                break 
                ;;
            nao|não)
                rm -f "$CONF_DIR/tipoConfComum.conf" "$CONF_DIR/tipoConfTouch.conf" "$CONF_DIR/tipoConfSelf.conf" "$CONF_DIR/tipoConfLancho.conf" 2>/dev/null
                break
                ;;
            *)
                echo -e "${RED}Responda com 'sim' ou 'não'.${NC}"
                ;;
        esac
    done
done
