#!/bin/bash

# Executa atualização do sistema
sudo apt update -y

# Realiza instalação do xscreensaver
sudo apt install xscreensaver -y


# Realiza instalação do mpv
sudo apt install mpv -y

# Faz download do arquivo de configuração do xscreensaver
curl -s -o /home/zanthus/.xscreensaver https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/.xscreensaver

# Grava a variável em /etc/profile para que usuário Zanthus possa executar o screensaver
sudo echo "export DISPLAY=:0" >> /etc/profile

# Pergunta ao usuário a filial
echo "ATENÇÃO! NUNCA EXECUTE O SCRIPT DUAS VEZES SEGUIDAS"
echo "Menu Principal selecione com cuidado a filial que deseja configurar o screensaver:"
echo "1. Centro Colider LJ01 - FL1"
echo "2. Bairro Colider LJ02 - FL3"
echo "3. Matupá LJ03 - FL9"
echo "4. Alta Floresta LJ05 - FL53"
echo "5. Primavera LJ06 - FL52"
echo "6. Confresa LJ07 - FL57"
read -p "Digite a sua opção: " opcao
case $opcao in
    1)
        # Comandos para a opção 1
        echo "Você escolheu a opção 1"
        ;;
    2)
        # Comandos para a opção 2
        echo "Você escolheu a opção 2"
        ;;
    3)
        # Comandos para a opção 3
        echo "Você escolheu a opção 3"
        ;;
    4)
        echo "Você escolheu a opção 4"
        ;;
    5)
        # Grava os dados de inicialização do PDV Filial 52
        curl -s -o /home/zanthus/atualizaSC52.sh https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/atualizaSC52.sh
	# Força a execução do script de atualização pela primeira vez
	chmod +x /home/zanthus/atualizaSC52.sh && /home/zanthus/atualizaSC52.sh
	# Adiciona o script de atualização do screensaver à inicialização do sistema
	sudo sed -i '1asudo xhost +local:zanthus\nsudo -u zanthus xscreensaver -no-splash &\nchmod +x /home/zanthus/atualizaSC52.sh && /home/zanthus/atualizaSC52.sh' /Zanthus/Zeus/pdvJava/PDVTouch.sh
        ;;
    6)
        # Comandos para a opção 6
        echo "Você escolheu a opção 6"
        ;;
    *)
        echo "Opção inválida!"
        ;;
esac
