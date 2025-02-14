 #!/bin/bash

#Executa atualização do sistema
sudo apt update -y

#Realiza instalação do xscreensaver
sudo apt install xscreensaver -y

#Realiza instalação do mpv
sudo apt install mpv -y

# Faz download do arquivo de configuração do xscreensaver
curl -s -o /home/zanthus/.xscreensaver https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/ScreenSaver/.xscreensaver

# Verifica se a linha já existe no arquivo
if ! grep -Fxq "export DISPLAY=:0" /etc/profile; then
  # Se não existir, adiciona a linha
  sudo echo "export DISPLAY=:0" >> /etc/profile
  echo "Linha adicionada ao arquivo /etc/profile"
else
  echo "Linha já existe no arquivo /etc/profile"
fi
# Função para limpar a tela
clear
#Extrai o Gateway para definir a filial
gateway=$(ip route show default | awk '{print $3}')

#Lê o retorno da variável gateway
case $gateway in
    1)
        # Comandos para a opção 1
        echo "Você escolheu a Filial de Colíder, Loja Centro"
        gateway=10.1.1.1
        ;;
    2)
        # Comandos para a opção 2
        echo "Você escolheu a Filial de Colíder, Loja Bairro"
        gateway=192.168.11.253
        ;;
    3)
        # Comandos para a opção 3
        echo "Você escolheu a Filial de Matupá"
        gateway=192.168.5.253
        ;;
    4)
        # Comandos para a opção 4
        echo "Você escolheu a Filial de Alta Floresta"
        gateway=192.168.7.253
        ;;
    5)
        # Comandos para a opção 5
        echo "Você escolheu a Filial de Primavera do Leste"
        gateway=192.168.9.253
        ;;
    6)
        # Comandos para a opção 6
        echo "Você escolheu a Filial de Confresa"
        gateway=192.168.57.193
        ;;
    *)
        echo "Opção inválida! Por favor, digite uma opção válida." ;;
esac

#Traduz o gateway em filial
case $gateway in
    10.1.1.1)
        filial=1
        ;;
    192.168.11.253)
        filial=3
        ;;
    192.168.5.253)
        filial=9
        ;;
     192.168.7.253)
        filial=53
        ;;
     192.168.9.253)
        filial=52
        ;;
      192.168.57.193)
        filial=57
        ;;
    *)
        echo "Valor de gateway não mapeado: $gateway"
        ;;
esac
# Grava os dados de inicialização do PDV
curl -s -o /home/zanthus/atualizaSC$filial.sh https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/ScreenSaver/atualizaSC$filial.sh
echo "Realizado download do script para filial $filial"
# Faz download do atualizador de interface
curl -s -o /home/zanthus/AtualizaInterface.sh https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/AtualizaInterface.sh
# Força a execução do script de atualização pela primeira vez
chmod +x /home/zanthus/atualizaSC$filial.sh && /home/zanthus/atualizaSC$filial.sh
chmod +x /home/zanthus/AtualizaInterface.sh
#Comando que gravará no PDVTouch.sh
script_PDVTouch=$(cat << EOF
#! /bin/bash
sudo xhost +local:zanthus
sudo -u zanthus xscreensaver -no-splash &
chmod +x /home/zanthus/atualizaSC$filial.sh && /home/zanthus/atualizaSC$filial.sh
chmod +x /home/zanthus/AtualizaInterface.sh && /home/zanthus/AtualizaInterface.sh
chmod -x /usr/local/bin/igraficaJava;
chmod -x /usr/local/bin/dualmonitor_control-PDVJava
nohup recreate-user-rabbitmq.sh &
/Zanthus/Zeus/pdvJava/pdvJava2 &
sleep 30
nohup chromium-browser --disable-pinch --disable-gpu --disk-cache-dir=/tmp/chromium-cache --user-data-dir=$(mktemp -d) --test-type --no-sandbox --kiosk --no-context-menu --disable-translate file:////Zanthus/Zeus/Interface/index.html
EOF
)
# Grava o conteúdo do script no arquivo
echo "$script_PDVTouch" > /Zanthus/Zeus/pdvJava/PDVTouch.sh

chmod +x /Zanthus/Zeus/pdvJava/PDVTouch.sh

echo "Script finalizado, aguarde o fim do contador para que o PDV reinicie"
echo "Script feito por @jjmoratelli, Jurandir Moratelli."
sleep 5
#Contador
for i in {1..10}; do
  echo "Contagem regressiva: $((10 - i))"
  sleep 1
done

# Reinicia o PDV para aplicar configurações
echo "Reiniciando"
sudo reboot
