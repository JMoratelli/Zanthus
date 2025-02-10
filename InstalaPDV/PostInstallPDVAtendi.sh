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

#Acrescenta parâmetros para tratar de forma melhor os erros que possam ser causados por instabilidades da Sefaz (Recomendação da Zanthus adicionar essa linha em PDVs comuns).
sudo printf "timeout=60\n" > /Zanthus/Zeus/pdvJava/ZMWS1201.CFG
echo "Ajustando arquivo ZMWS1201.CFG"
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
echo "Copiando config.js"
curl -o "/Zanthus/Zeus/Interface/config/config.js" "https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/config.js"
echo "Copiando Buttons.js"
curl -o "/Zanthus/Zeus/Interface/app/api/dinamico/pdvMouse/Buttons.js" "https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/PDV/Interface/Buttons.js"
echo "Aplicando permissões na pasta de interface"
chmod 777 -R /Zanthus/Zeus/Interface/

# Nessa etapa irá copiar os arquivos de ClisiTef
echo "Copiando arquivos CliSiTef do repositório"
curl -o "/Zanthus/Zeus/pdvJava/CliSiTef.ini" "https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/PDV/CliSiTef.ini"
echo "Aplicando permissões no CliSiTef"
chmod 777 -R /Zanthus/Zeus/pdvJava/CliSiTef.ini

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

#Removidas linhas de duplicação de monitores.

# Configurações do CUPS para ajustes da impressão
echo "Alterando parâmetros CUPS"
sudo sed 's/^BrowseLocalProtocols.*$/BrowseLocalProtocols\ none/' -i /etc/cups/cupsd.conf
cupsctl WebInterface=yes; service cups stop; service cups start
cupsctl --remote-admin --remote-any
printf "linux.impressora=IMP-NFE\nlinux.opcoes=3\n" > /Zanthus/Zeus/pdvJava/ZPDF00.CFG

#Instalar impressora
echo "Instalador de Impressora CUPS"

# Função para validar o endereço IP
validar_ip() {
    local ip="$1"
    if [[ $ip =~ ^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
        return 0
    else
        return 1
    fi
}
# Função para limpar a tela
clear
# Solicitar o IP da impressora
while true; do
    read -p "Digite o IP da impressora de NFE do Atendimento ao cliente: " IP
    if validar_ip "$IP"; then
        break
    else
        echo "Endereço IP inválido. Tente novamente."
    fi
done

# Comando CUPS para adicionar a impressora
echo "Adicionando impressora..."
# Verifica se o IP digitado é o do balcão fiscal de Confresa
if [[ "$IP" == "192.168.57.126" ]]; then
    #Caso a impressora seja a de Confresa, o Script vai executar esse script, para fazer os ajustes nela e adicionar o driver manualmente
    curl -o /usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/InstalaPDV/Drivers/Kyocera_ECOSYS_MA5500ifx_.ppd; lpadmin -p IMP-NFE -E -v socket://192.168.57.125 -i /usr/share/cups/model/Kyocera_ECOSYS_MA5500ifx_.ppd
else
    #Configura impressora em redes padrão, sem VLAN
    lpadmin -p IMP-NFE -E -v ipp://$IP -m everywhere
fi

# Verificar se a impressão foi adicionada com sucesso
if [ $? -eq 0 ]; then
    echo "Impressora adicionada com sucesso!"
else
    echo "Ocorreu um erro ao adicionar a impressora."
fi

echo "Parâmetros CUPS ajustados com sucesso, será iniciado a instalação do ScreenSaver"
echo "Script desenvolvido por @jjmoratelli, Jurandir Moratelli ;)."
sleep 5
#ACRESCENTADO SCRIPT DE SCREENSAVER AO SCRIPT PRINCIPAL - Parâmetros únicos são aplicados à PDVs do atendimento.
# Executa atualização do sistema
sudo apt update -y

# Realiza instalação do xscreensaver
sudo apt install xscreensaver -y

# Realiza instalação do mpv
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
# Pergunta ao usuário a filial
echo "Não utilize esse script em caixa SelfCheckout!"
echo "Selecione a filial que deseja configurar o screensaver, escolha com cuidado, operação não é reversível."
echo "Caso tenha escolhido a alternativa errada, não adiantará reexecutar o script, atenção!"
echo "1. Centro Colider LJ01 - FL1"
echo "2. Bairro Colider LJ02 - FL3"
echo "3. Matupá LJ03 - FL9"
echo "4. Alta Floresta LJ05 - FL53"
echo "5. Primavera LJ06 - FL52"
echo "6. Confresa LJ07 - FL57"

#Cria um laço de repetição, que seguirá rodando até selecionar uma opção válida do menu.
while true; do
  read -p "Digite a sua opção: " opcao

  case $opcao in
    1)
      # Comandos para a opção 1
      echo "Você escolheu a Filial de Colíder, Loja Centro"
      filial=1
      break ;;
    2)
      # Comandos para a opção 2
      echo "Você escolheu a Filial de Colíder, Loja Bairro"
      filial=3
      break ;;
    3)
      # Comandos para a opção 3
      echo "Você escolheu a Filial de Matupá"
      filial=9
      break ;;
    4)
      echo "Você escolheu a Filial de Alta Floresta"
      filial=53
      break ;;
    5)
      echo "Você escolheu a Filial de Primavera do Leste"
      filial=52
      break ;;
    6)
      echo "Você escolheu a Filial de Confresa"
      filial=57
      break ;;
    *)
      echo "Opção inválida! Por favor, digite uma opção válida." ;;
  esac
done

# Grava os dados de inicialização do PDV
curl -s -o /home/zanthus/atualizaSC$filial.sh https://raw.githubusercontent.com/JMoratelli/Zanthus/refs/heads/main/ScreenSaver/atualizaSC$filial.sh
echo "Realizado download do script para filial $filial"

# Força a execução do script de atualização pela primeira vez
chmod +x /home/zanthus/atualizaSC$filial.sh && /home/zanthus/atualizaSC$filial.sh

#Comando que gravará no PDVTouch.sh
script_PDVTouch=$(cat << EOF
#! /bin/bash
sudo xhost +local:zanthus
sudo -u zanthus xscreensaver -no-splash &
chmod +x /home/zanthus/atualizaSC$filial.sh && /home/zanthus/atualizaSC$filial.sh
chmod -x /usr/local/bin/igraficaJava;
chmod -x /usr/local/bin/dualmonitor_control-PDVJava
nohup recreate-user-rabbitmq.sh &
/Zanthus/Zeus/pdvJava/pdvJava2 &
sleep 30
nohup chromium-browser --disable-pinch --disable-gpu --disk-cache-dir=/tmp/chromium-cache --user-data-dir=$(mktemp -d) --test-type --no-sandbox --no-context-menu --disable-translate file:////Zanthus/Zeus/Interface/index.html
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
