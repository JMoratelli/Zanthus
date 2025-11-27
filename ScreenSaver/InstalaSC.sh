 #!/bin/bash
clear
echo "Iniciando instalação do scripts de screensaver, não encerre o processo =)"
echo "Atualizando o sistema... Aguarde, pode demorar."
#Executa atualização do sistema
sudo apt-get update -y > /dev/null 2>&1
echo "Instalando pacote xscreensaver..."
#Realiza instalação do xscreensaver
sudo apt install xscreensaver -y -qq
echo "Instalando pacote MPV..."
#Realiza instalação do mpv
sudo apt install mpv -y -qq
echo "Pacotes instalados, realizando configurações..."
# Faz download do arquivo de configuração do xscreensaver
curl -s -o /home/zanthus/.xscreensaver https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/ScreenSaver/.xscreensaver

# Verifica se a linha já existe no arquivo
if ! grep -Fxq "export DISPLAY=:0" /etc/profile; then
  # Se não existir, adiciona a linha
  sudo echo "export DISPLAY=:0" >> /etc/profile
  echo "Linha adicionada ao arquivo /etc/profile"
else
  echo "Linha já existe no arquivo /etc/profile, já configurando."
fi

#Extrai o Gateway para definir a filial
gateway=$(ip route show default | awk '{print $3}')

#Traduz o gateway em filial
case $gateway in
    10.1.1.1)
        filial=1
        echo "Detectada a filial $filial"
        ;;
    192.168.11.253)
        filial=3
        echo "Detectada a filial $filial"
        ;;
    192.168.5.253)
        filial=9
        echo "Detectada a filial $filial"
        ;;
     192.168.7.253)
        filial=53
        echo "Detectada a filial $filial"
        ;;
     192.168.9.253)
        filial=52
        echo "Detectada a filial $filial"
        ;;
      192.168.57.193|192.168.57.1|192.168.156.1|192.168.57.129)
        filial=57
        echo "Detectada a filial $filial"
        ;;
    *)
        clear
        echo "Valor de gateway não mapeado: $gateway. Encerrando, contate o Jurandir para correções."
        exit 0
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
/usr/bin/setxkbmap -layout br -variant abnt2 > /tmp/setxkbmap.log 2>&1
if ! mountpoint -q /media/root/GERSAT3/; then
    mount /media/root/GERSAT3/
fi
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
rm -- "$0"
sudo reboot
