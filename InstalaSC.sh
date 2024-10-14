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
echo "1. Loja 1 - Centro Colider"
echo "2. Loja 2 - Bairro Colider"
echo "3. Loja 3 - Matupá"
echo "4. Loja 5 - Alta Floresta"
echo "5. Loja 6 - Primavera"
echo "6. Loja 7 - Confresa"

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
        curl -s -o /home/zanthus/atualizaSC.sh https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/atualizaSC52.sh
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
