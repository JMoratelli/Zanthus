#!/bin/bash
#Função para realizar atualização das interfaces
wget -q "https://github.com/JMoratelli/Zanthus/raw/refs/heads/main/InstalaPDV/InterfaceUnificada/Interface.7z" -O Interface.7z && 7z x -o/Zanthus/Zeus/Interface/ -y Interface.7z
#Funcao Provisioria para corrigir arquivos de carga
sed -i "s/endereco=serv-zt-aplic/endereco=192.168.13.250:80/g" /Zanthus/Zeus/pdvJava/RESTG0000.CFG
sed -i "s/endereco=serv-zt-aplic/endereco=192.168.13.250:80/g" /Zanthus/Zeus/pdvJava/CARG0000.CFG
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

#Lê e extrai o gateway da máquina
gateway=$(ip route show default | awk '{print $3}')

#Lê o Gateway e instala impressora de acordo com a loja
case $gateway in
    10.1.1.1)
        echo "Detectada impressora da Loja Centro"
	curl -o /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_M3655idn.ppd; lpadmin -p IMP-NFE -E -v socket://10.1.1.139 -i /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd
        filial=1
        ;;
    192.168.11.253)
        echo "Detectada impressora da Loja Bairro"
    	curl -o /usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_MA5500ifx_.ppd; lpadmin -p IMP-NFE -E -v socket://192.168.11.94 -i /usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd
        filial=3
        ;;
    192.168.5.253)
        echo "Detectada impressora de Matupá"
    	curl -o /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_M3655idn.ppd; lpadmin -p IMP-NFE -E -v socket://192.168.4.24 -i /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd
        filial=9
        ;;
     192.168.7.253)
        echo "Detectada impressora de Alta Floresta"  
    	curl -o /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_M3655idn.ppd; lpadmin -p IMP-NFE -E -v socket://192.168.6.14 -i /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd
        filial=53
        ;;
     192.168.9.253)
        echo "Detectada impressora de Primavera do Leste"
        curl -o /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_M3655idn.ppd; lpadmin -p IMP-NFE -E -v socket://192.168.8.27 -i /usr/share/cups/model/Kyocera_ECOSYS_M3655idn.ppd
        filial=52
        ;;
      192.168.57.193)
        echo "Detectada impressora de Confresa"
    	curl -o /usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_MA5500ifx_.ppd; lpadmin -p IMP-NFE -E -v socket://192.168.57.125 -i /usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd
        filial=57
        ;;
    *)
        echo "Valor de gateway não mapeado: $gateway"
        ;;
esac

echo "Ajustando fuso horário..."
# Ajusta Fuso horário
case $filial in
  1 | 3 | 9 | 52 | 53)
    timedatectl set-timezone America/Cuiaba
    hwclock -w
    sed -i 's/UTC/LOCAL/g' /etc/adjtime
    hwclock -w
    hwclock --systohc
    hwclock --localtime
    echo "Aguarde..."
    sleep 5
    timedatectl set-timezone America/Cuiaba
    hwclock -w
    sed -i 's/UTC/LOCAL/g' /etc/adjtime
    hwclock -w
    hwclock --systohc
    hwclock --localtime
    echo "Fuso horário definido para Cuiabá e ajustado relógio de hardware."
    ;;
  57)
    timedatectl set-timezone America/Sao_Paulo
    hwclock -w
    sed -i 's/UTC/LOCAL/g' /etc/adjtime
    hwclock -w
    echo "Aguarde..."
    sleep 5
    hwclock -w
    timedatectl set-timezone America/Sao_Paulo
    hwclock -w
    sed -i 's/UTC/LOCAL/g' /etc/adjtime
    hwclock -w
    echo "Fuso horário definido para São Paulo e ajustado relógio de hardware."
    ;;
  *)
    echo "Erro: Valor inválido para a variável 'filial'."
    exit 1
    ;;
esac

#Verifica filial para programar parâmetro ctron
case $filial in
  1 | 3 | 9)
    hora_domingo=14
    ;;
  52 | 53 | 57)
    hora_domingo=19
    ;;
  *)
    echo "Erro: Valor inválido para a variável 'filial'."
    exit 1
    ;;
esac

# Cria as linhas para o crontab
linha_semana="00 21 * * * /sbin/shutdown -h now"
linha_domingo="00 $hora_domingo * * SUN /sbin/shutdown -h now"

# Adiciona as linhas ao crontab
echo "Gravando linhas ao crontab, por favor aguarde"
(echo "$linha_semana"; echo "$linha_domingo") | crontab -
sleep 5
(echo "$linha_semana"; echo "$linha_domingo") | crontab -
echo "Sucesso!"
echo "Desligamento agendado:"
echo "* Durante a semana: 21 horas"
echo "* Aos domingos: $hora_domingo horas"
echo "Confira as informações acima, contate suporte Jurandir caso haja incoerências. O processo continuará, não o interrompa caso esteja correto."
sleep 6

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
#Obtém o endereço IP do host
ip=$(hostname -I | awk '{print $1}')

#Lista de IPs PDVs do tipo torre
ips_permitidos=("192.168.8.133" "192.168.8.134" "192.168.8.135" "192.168.8.136")

#Verifica se o IP do host é ou não do tipo torre
if [[ " ${ips_permitidos[@]} " =~ " ${ip} " ]]; then
  echo "Sinaleiro tipo torre configurado."
else
  sudo printf "modelo=1\n" > /Zanthus/Zeus/pdvJava/ZSINALIZ_LAURENTI_ARDUINO.CFG
  echo "Sinaleiro tipo lâmpada única configurado."
fi

echo "Script desenvolvido por @jjmoratelli, Jurandir Moratelli. PDV será reiniciado após o fim do contador"
sleep 5
#Contador
for i in {1..10}; do
  echo "Contagem regressiva: $((10 - i))"
  sleep 1
done
echo "Adeus"
sudo reboot
