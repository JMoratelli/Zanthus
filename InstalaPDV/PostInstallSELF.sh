#!/bin/bash
# Função para limpar a tela
clear
# Atualiza o Grub, para acelerar processo de boot.
sudo grub-install
echo "Ajustando opções no arquivo /etc/resolv.conf"
# Configura servidor DNS e adiciona o parâmetro search para que resolva o DNS do AD.
sudo printf "nameserver 192.168.12.1\n#options edns0 trust-ad\nsearch redemachado.local" > /etc/resolv.conf
echo "Ajustado opções no arquivo /etc/resolv.conf"
# Função para limpar a tela
clear
# Ajusta Fuso horário
echo "Escolha o fuso horário:"
echo "1. Cuiabá (America/Cuiaba)"
echo "2. São Paulo (America/Sao_Paulo)"

# Laço de repetição para selecionar o correto fuso horário
while true; do
    read -p "Digite 1 ou 2: " opcao
    case $opcao in
        1)
            timedatectl set-timezone America/Cuiaba; hwclock -w; sed -i 's/UTC/LOCAL/g' /etc/adjtime; hwclock -a
            hwclock --systohc
            hwclock --localtime
            echo "Aguarde..."
            sleep 5
            timedatectl set-timezone America/Cuiaba; hwclock -w; sed -i 's/UTC/LOCAL/g' /etc/adjtime; hwclock -w
            hwclock --systohc
            hwclock --localtime
            echo "Fuso horário definido para Cuiabá e ajustado relógio de hardware."
            break ;;
        2)
            timedatectl set-timezone America/Sao_Paulo; hwclock -w; sed -i 's/UTC/LOCAL/g' /etc/adjtime; hwclock -w
            echo "Aguarde..."
            sleep 5
            hwclock -w
            timedatectl set-timezone America/Sao_Paulo; hwclock -w; sed -i 's/UTC/LOCAL/g' /etc/adjtime; hwclock -w
            break ;;
        *)
            echo "Opção inválida. Por favor, digite 1 ou 2." ;;
    esac
done


# Função para validar a hora
validar_hora() {
  if [[ $1 =~ ^[0-9]{2}$ ]]; then
    if [[ $1 -ge 0 && $1 -le 23 ]]; then
      return 0
    fi
  fi
  echo "Hora inválida. Por favor, digite um número entre 00 e 23. Insira com atenção!"
  return 1
}
# Solicita as horas durante a semana ao usuário
while true; do
  read -p "Digite a hora para desligar o computador durante a semana (00-23): " hora_semana
  if validar_hora "$hora_semana"; then
    break
  fi
done

# Solicita as horas para desligar aos domingos ao usuário
while true; do
  read -p "Digite a hora para desligar o computador aos domingos (00-23): " hora_domingo
  if validar_hora "$hora_domingo"; then
    break
  fi
done

# Cria as linhas para o crontab
linha_semana="00 $hora_semana * * * /sbin/shutdown -h now"
linha_domingo="00 $hora_domingo * * SUN /sbin/shutdown -h now"

# Adiciona as linhas ao crontab
echo "Gravando linhas ao crontab, por favor aguarde"
(echo "$linha_semana"; echo "$linha_domingo") | crontab -
sleep 5
(echo "$linha_semana"; echo "$linha_domingo") | crontab -
echo "Sucesso!?"

echo "Desligamento agendado:"
echo "* Durante a semana: $hora_semana horas"
echo "* Aos domingos: $hora_domingo horas"

#Clone arquivos de áudio do PDV
base_url="https://github.com/JMoratelli/Zanthus/raw/refs/heads/main/InstalaPDV/Self/Interface/audio/"
# Diretório de destino
destino="/Zanthus/Zeus/Interface/resources/audio/"
# Loop para gerar as URLs e executar o wget
for i in {0..24}; do
  url="${base_url}${i}.mp3"
  wget -N -P "$destino" "$url"
done

# Cópia de arquivos de interface
echo "Iniciando copia de arquivos de interface a partir do git"
echo "Copiando Ícones"
wget https://github.com/JMoratelli/Zanthus/raw/refs/heads/main/InstalaPDV/InterfaceUnificada/icones.7z -O /Zanthus/Zeus/Interface/resources/icones/icones.7z && cd /Zanthus/Zeus/Interface/resources/icones/ && 7z x -y icones.7z "*"
echo "Copiando Zeus_V.gif"
curl -o "/Zanthus/Zeus/Interface/resources/imagens/Zeus_V.gif" "https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Zeus_V.gif"
echo "Copiando cancela_sel.png"
curl -o "/Zanthus/Zeus/Interface/resources/imagens/cancela_sel.png" "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/cancela_sel.png"
echo "Copiando cancela.png"
curl -o "/Zanthus/Zeus/Interface/resources/imagens/cancela.png" "https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/InterfaceUnificada/cancela.png"
echo "Copiando descanso1000.jpg"
curl -o "/Zanthus/Zeus/Interface/resources/imagens/descanso1000.jpg" "https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/descanso1000.jpg"
echo "Copiando codigo.gif"
curl -o "/Zanthus/Zeus/Interface/resources/imagens/self/codigo.gif" "https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/codigo.gif"
echo "Copiando telas_touch.js"
curl -o "/Zanthus/Zeus/Interface/resources/js/telas_touch.js" "https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/telas_touch.js"
echo "Copiando telas_touch.js"
curl -o "/Zanthus/Zeus/Interface/resources/js/teclas_touch.js" "https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/teclas_touch.js"
echo "Copiando config.js"
curl -o "/Zanthus/Zeus/Interface/config/config.js" "https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/Self/Interface/config.js"
echo "Aplicando permissões na pasta de interface"
chmod 777 -R /Zanthus/Zeus/Interface/

# Nessa etapa irá copiar os arquivos de ClisiTef
echo "Copiando arquivos CliSiTef do repositório"
curl -o "/Zanthus/Zeus/pdvJava/CliSiTef.ini" "https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/Self/CliSiTef.ini"
echo "Aplicando permissões no CliSiTef"
chmod 777 -R /Zanthus/Zeus/pdvJava/CliSiTef.ini

#Define o volume do PDV para 84%
echo "Ajustando volume Master"
amixer set Master 87

#Executa script docker para alterar rede docker para padrão 10.220.0.1
export DISPLAY=:0
#Define variável IP para padrão
user_ip="10.220.0.1"
echo "Escrevendo arquivo..."
#Altera configurações da rede Docker
config_data="{ \"bip\": \"$user_ip/16\", \"mtu\": 1500 }"
echo "$config_data" | sudo tee /etc/docker/daemon.json > /dev/null
echo "Reiniciando container docker..."
sudo systemctl restart docker 2>&1>> /tmp/switch-docker-network.log
echo "Container docker reiniciado."
echo "Rede alterada com sucesso para o endereço IP: $user_ip"
echo "Script docker finalizado"

curl -s -o /home/zanthus/BalancaUSB.sh https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/BalancaUSB.sh
chmod +x /home/zanthus/BalancaUSB.sh && /home/zanthus/BalancaUSB.sh

#Comando que gravará no PDVTouch.sh
script_PDVTouch=$(cat << EOF
#! /bin/bash
nohup /home/zanthus/BalancaUSB.sh &
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
echo "Linhas adicionadas ao arquivo /Zanthus/Zeus/pdvJava/PDVTouch.sh"
# Exibir o valor de Y (opcional)
echo "Balança conectada na porta: $Y"

#Configura sinaleiro do PDV
while true; do
  read -p "O sinaleiro é do tipo torre (PDV 33 ao 36 de Primavera)? (s/n): " resposta
  if [[ "$resposta" == "n" || "$resposta" == "N" ]]; then
    sudo printf "modelo=1\n" > /Zanthus/Zeus/pdvJava/ZSINALIZ_LAURENTI_ARDUINO.CFG
    echo "Sinaleiro tipo lâmpada única configurado."
    break
  elif [[ "$resposta" == "s" || "$resposta" == "S" ]]; then
   echo "Sinaleiro tipo torre configurado."
    break
  else
    echo "Resposta inválida. Por favor, digite 's' ou 'n'."
  fi
done

echo "Script desenvolvido por @jjmoratelli, Jurandir Moratelli. PDV será reiniciado após o fim do contador"
sleep 5
#Contador
for i in {1..10}; do
  echo "Contagem regressiva: $((10 - i))"
  sleep 1
done
echo "Adeus"
sudo reboot
