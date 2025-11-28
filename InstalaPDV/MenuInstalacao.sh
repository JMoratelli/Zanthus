#!/bin/bash

# ==============================================================================
# DEFINIÇÃO DE CORES E ESTILOS
# ==============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color (Reset)

# ==============================================================================
# VALIDAÇÃO DE ROOT (SUPERUSUÁRIO)
# ==============================================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}ERRO CRÍTICO:${NC}"
    echo -e "Este script precisa ser executado como ${WHITE}ROOT${NC}."
    echo -e "Por favor, execute novamente utilizando: ${YELLOW}sudo $0${NC}"
    exit 1
fi

# ==============================================================================
# FUNÇÕES VISUAIS
# ==============================================================================

show_header() {
    clear
    echo -e "${CYAN}############################################################${NC}"
    echo -e "${CYAN}#                                                          #${NC}"
    echo -e "${CYAN}#          ${WHITE}SCRIPT DE INSTALAÇÃO ZANTHUS PDV${CYAN}                #${NC}"
    echo -e "${CYAN}#          ${WHITE}  DESENVOLVIDO POR @JJMORATELLI ${CYAN}                #${NC}"
    echo -e "${CYAN}#                                                          #${NC}"
    echo -e "${CYAN}############################################################${NC}"
    echo ""
}

run_installer() {
    local url=$1
    local name=$2
    
    echo ""
    echo -e "${GREEN}--> Iniciando download e execução de: $name...${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    
    if command -v curl >/dev/null 2>&1; then
        bash <(curl -s "$url")
    else
        echo -e "${RED}Erro: 'curl' não está instalado. Instalando curl...${NC}"
        apt-get install curl -y >/dev/null 2>&1
        bash <(curl -s "$url")
    fi
}

# ==============================================================================
# LOOP PRINCIPAL DO MENU
# ==============================================================================

while true; do
    show_header
    echo -e "${YELLOW}Escolha o tipo de instalação desejada:${NC}"
    echo ""
    echo -e "   ${WHITE}[1]${NC} - Instalação PDV Comum"
    echo -e "   ${WHITE}[2]${NC} - Instalação PDV SelfCheckout"
    echo -e "   ${WHITE}[3]${NC} - Instalação PDV Lanchonete"
    echo ""
    echo -e "   ${WHITE}[0]${NC} - Sair"
    echo ""
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    read -p "Digite o número da opção: " opcao_menu

    case $opcao_menu in
        1)
            NOME_SCRIPT="Instalação PDV Comum"
            URL_SCRIPT="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PostInstallPDV.sh"
            ;;
        2)
            NOME_SCRIPT="Instalação PDV SelfCheckout"
            URL_SCRIPT="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PostInstallSELF.sh"
            ;;
        3)
            NOME_SCRIPT="Instalação PDV Lanchonete"
            URL_SCRIPT="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PostInstallPDVLancho.sh"
            ;;
        0)
            echo -e "${GREEN}Saindo... Até logo!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Opção inválida! Por favor, escolha entre 1, 2, 3 ou 0.${NC}"
            sleep 2
            continue
            ;;
    esac

    # ==========================================================================
    # LOOP DE CONFIRMAÇÃO (SIM / NÃO / CANCELAR)
    # ==========================================================================
    while true; do
        echo ""
        echo -e "${YELLOW}Você selecionou: ${WHITE}$NOME_SCRIPT${NC}"
        echo -e "Para prosseguir digite 'sim', para voltar 'não', ou 'cancelar' para cancelar."
        read -p "Confirma? (sim/nao/cancelar): " confirmacao

        # Converte para minúsculas
        confirmacao=$(echo "$confirmacao" | tr '[:upper:]' '[:lower:]')

        case $confirmacao in
            sim|s)
                # Executa instalação
                run_installer "$URL_SCRIPT" "$NOME_SCRIPT"
                
                echo ""
                echo -e "${GREEN}Processo finalizado.${NC}"
                read -p "Pressione ENTER para voltar ao menu principal..."
                break 
                ;;
            nao|não|n)
                echo -e "${BLUE}Retornando ao menu inicial...${NC}"
                sleep 1
                break 
                ;;
            cancelar)
                echo -e "${RED}Operação cancelada.${NC}"
                sleep 2
                break # Sai do loop de confirmação e volta ao menu principal
                ;;
            *)
                echo -e "${RED}Resposta inválida! Digite 'sim', 'não' ou 'cancelar'.${NC}"
                # Loop repete
                ;;
        esac
    done
done
