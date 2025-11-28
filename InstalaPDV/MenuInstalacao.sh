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
# FUNÇÕES
# ==============================================================================
show_header() {
    clear
    echo -e "${CYAN}############################################################${NC}"
    echo -e "${CYAN}#                                                          #${NC}"
    echo -e "${CYAN}#                                                          #${NC}"
    echo -e "${CYAN}#          ${WHITE}SCRIPT DE INSTALAÇÃO ZANTHUS PDV${CYAN}                #${NC}"
    echo -e "${CYAN}#          ${WHITE}  DESENVOLVIDO POR @JJMORATELLI ${CYAN}                #${NC}"
    echo -e "${CYAN}#                                                          #${NC}"
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
    
    # CORREÇÃO AQUI: Adicionado < /dev/tty para ler do teclado, não do pipe
    echo -ne "Digite o número da opção: "
    read -r opcao_menu < /dev/tty

    if [ -z "$opcao_menu" ]; then
        continue
    fi

    case $opcao_menu in
        1)
            NOME="Instalação PDV Comum"
            URL="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PostInstallPDV.sh"
            ;;
        2)
            NOME="Instalação PDV SelfCheckout"
            URL="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PostInstallSELF.sh"
            ;;
        3)
            NOME="Instalação PDV Lanchonete"
            URL="https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/PostInstallPDVLancho.sh"
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
        
        # CORREÇÃO AQUI TAMBÉM: < /dev/tty
        read -r confirmacao < /dev/tty

        confirmacao=$(echo "$confirmacao" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

        case $confirmacao in
            sim)
                run_installer "$URL" "$NOME"
                echo -e "${GREEN}Finalizado.${NC}"
                
                # Pausa para leitura (também lendo do tty)
                echo -e "Pressione ENTER para voltar..."
                read -r dummy < /dev/tty
                break 
                ;;
            nao|não)
                break
                ;;
            *)
                echo -e "${RED}Responda com 'sim', 'não' ou 'cancelar'.${NC}"
                ;;
        esac
    done
done
