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
# FUNÇÕES VISUAIS
# ==============================================================================

# Função para limpar a tela e mostrar o cabeçalho
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

# Função para executar o script remoto
run_installer() {
    local url=$1
    local name=$2
    
    echo ""
    echo -e "${GREEN}--> Iniciando download e execução de: $name...${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    
    # Verifica se tem curl instalado
    if command -v curl >/dev/null 2>&1; then
        bash <(curl -s "$url")
    else
        echo -e "${RED}Erro: 'curl' não está instalado. Por favor instale para continuar.${NC}"
        read -p "Pressione ENTER para voltar."
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

    # Definição das variáveis com base na escolha
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
            continue # Volta para o início do loop principal
            ;;
    esac

    # ==========================================================================
    # LOOP DE CONFIRMAÇÃO (SIM/NÃO)
    # ==========================================================================
    while true; do
        echo ""
        echo -e "${YELLOW}Você selecionou: ${WHITE}$NOME_SCRIPT${NC}"
        read -p "Você tem certeza que gostaria de iniciar a instalação? (sim/nao): " confirmacao

        # Converte a entrada para minúsculas para facilitar a comparação
        confirmacao=$(echo "$confirmacao" | tr '[:upper:]' '[:lower:]')

        case $confirmacao in
            sim|s)
                # Executa o instalador e sai do loop de confirmação
                run_installer "$URL_SCRIPT" "$NOME_SCRIPT"
                
                # Após a instalação, pergunta se quer sair ou voltar ao menu
                echo ""
                echo -e "${GREEN}Processo finalizado.${NC}"
                read -p "Pressione ENTER para voltar ao menu principal..."
                break # Sai do loop de confirmação, volta para o menu principal
                ;;
            nao|não|n)
                echo -e "${BLUE}Operação cancelada. Retornando ao menu principal...${NC}"
                sleep 1
                break # Sai do loop de confirmação, volta para o menu principal
                ;;
            *)
                echo -e "${RED}Resposta inválida! Digite apenas 'sim' ou 'não'.${NC}"
                # O loop continua aqui, repetindo a pergunta
                ;;
        esac
    done
done
