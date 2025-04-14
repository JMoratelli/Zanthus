#!/bin/bash
echo "Script para configurar o sistema como root."

# Função para verificar se a senha root está definida
check_root_password() {
  if ! getent shadow root | grep -q ':\*:' && ! getent shadow root | grep -q '!!:'; then
    return 0
  else
    return 1
  fi
}

# Verifica se o script NÃO está sendo executado como root
if [[ "$EUID" -ne 0 ]]; then
  echo "O script precisa ser executado com privilégios de root."

  # Verifica se a senha root está definida
  if check_root_password; then
    echo "A senha root parece estar definida. Tentando executar como root..."
    sudo "$0" "$@"
    exit $?
  else
    echo "A senha root não está definida. Você precisa definir uma senha root para continuar."
    sudo passwd root
    echo "Senha root definida. Reexecutando o script como root..."
    sudo "$0" "$@"
    exit $?
  fi
else
  echo "Você já está logado como root. Continuando com a execução do script."
fi

#Adiciona parâmetros arquivos RESTG do MercaFacil, ajustando o TimeOut de 30 para 5.
printf "timeout=5\n" > /Zanthus/Zeus/pdvJava/RESTG4650.CFG && printf "timeout=5\n" > /Zanthus/Zeus/pdvJava/RESTG4651.CFG
#Funcao Provisioria para corrigir arquivos de carga
sed -i "s/endereco=serv-zt-aplic/endereco=192.168.13.250:80/g" /Zanthus/Zeus/pdvJava/RESTG0000.CFG
sed -i "s/endereco=serv-zt-aplic/endereco=192.168.13.250:80/g" /Zanthus/Zeus/pdvJava/CARG0000.CFG
#Adiciona linha de operadoras de recarga ao script
printf "Vivo=22\nClaro=12000000\nOi=35000000\nTim=74000000\nBrasil Telecom=11\nCTBC-Celular=12201\nCTBC-Fixo=12299\nEmbratel=14000000\nSercomtel-Celular=12301\nSercomtel-Fixo=12399\nL Economica=97100\nNextel=75000000\n" > /Zanthus/Zeus/pdvJava/RECRGOP0.CFG
chmod 777 /Zanthus/Zeus/pdvJava/RECRGOP0.CFG
# Função para limpar a tela
clear
#Função para ajustar parâmetro de log, evitando lotar o HD
sudo sed -i 's/#Storage=auto/Storage=none/g' /etc/systemd/journald.conf
sudo sed -i 's/#SystemKeepFree=/SystemKeepFree=60G/g' /etc/systemd/journald.conf
sudo sed -i 's/#SystemMaxUse=/SystemMaxUse=1G/g' /etc/systemd/journald.conf
sudo sed -i 's/#SystemMaxFileSize=/SystemMaxFileSize=1G/g' /etc/systemd/journald.conf
echo "Ajustando parâmetros journald.conf"

# Verifica se o script já foi executado
if grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash \(pci=nommconf\|pcie_aspm=off\|pci=noaer\)' /etc/default/grub; then
  # Se a linha já existe, executa o grub-install diretamente
  echo "Script já executado, script seguirá de forma automática, aguarde..."
  sleep 5
  sudo grub-install
else
  #Se primeira execução, exibe pergunta ao usuário
  read -p "Atualizar o GRUB sem ajustar parâmetros? (Digite \"n\" para máquinas mais antigas)[S/n]: " resposta
  if [[ "$resposta" == "S" || "$resposta" == "s" ]]; then
    echo "Atualizando GRUB..."
    sudo grub-install
  else
    echo "Ok, ajustes legados iniciados. Atualizando GRUB... Esse processo pode demorar, aguarde..."
    sudo grub-install
    echo "Parâmetros de inicialização serão aplicados, aguarde..."
    sudo sed -i '/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash \(pci=nommconf\|pcie_aspm=off\|pci=noaer\)/! s/\(GRUB_CMDLINE_LINUX_DEFAULT="quiet splash\)/\1 pci=nommconf pcie_aspm=off pci=noaer/' /etc/default/grub
    echo "Aguarde, esse processo pode ser demorado. Ajustando parâmetros kernel para máquinas legado."
    sleep 5
    sudo update-grub
    echo "A máquina será reinicializada para finalizar."
    sleep 5
    reboot
  fi
fi

echo "Ajustando opções no arquivo /etc/resolv.conf"
# Configura servidor DNS e adiciona o parâmetro search para que resolva o DNS do AD.
sudo printf "nameserver 192.168.12.1\n#options edns0 trust-ad\nsearch redemachado.local" > /etc/resolv.conf
echo "Ajustado opções no arquivo /etc/resolv.conf"

#Acrescenta parâmetros para tratar de forma melhor os erros que possam ser causados por instabilidades da Sefaz (Recomendação da Zanthus adicionar essa linha em PDVs comuns).
sudo printf "timeout=60\n" > /Zanthus/Zeus/pdvJava/ZMWS1201.CFG
echo "Ajustando arquivo ZMWS1201.CFG"
# Função para limpar a tela
clear

# Configurações do CUPS para ajustes da impressão
echo "Alterando parâmetros CUPS"
sudo sed 's/^BrowseLocalProtocols.*$/BrowseLocalProtocols\ none/' -i /etc/cups/cupsd.conf
cupsctl WebInterface=yes; service cups stop; service cups start
cupsctl --remote-admin --remote-any
printf "linux.impressora=IMP-NFE\nlinux.opcoes=3\n" > /Zanthus/Zeus/pdvJava/ZPDF00.CFG

#Instalar impressora
echo "Instalador de Impressora CUPS"
echo "Adicionando impressora..."
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
     192.168.57.193|192.168.57.1|192.168.156.1|192.168.57.129)
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
    hora_domingo=18
    ;;
  52 | 53 | 57)
    hora_domingo=21
    ;;
  *)
    echo "Erro: Valor inválido para a variável 'filial'."
    exit 1
    ;;
esac

# Cria as linhas para o crontab
linha_semana="00 23 * * * /sbin/shutdown -h now"
linha_domingo="00 $hora_domingo * * SUN /sbin/shutdown -h now"

# Adiciona as linhas ao crontab
echo "Gravando linhas ao crontab, por favor aguarde"
(echo "$linha_semana"; echo "$linha_domingo") | crontab -
sleep 5
(echo "$linha_semana"; echo "$linha_domingo") | crontab -
echo "Sucesso!"
echo "Desligamento agendado:"
echo "* Durante a semana: 23 horas"
echo "* Aos domingos: $hora_domingo horas"
echo "Confira as informações acima, contate suporte Jurandir caso haja incoerências. O processo continuará, não o interrompa caso esteja correto."
sleep 6
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

#Lista quantidade de telas conectadas em numeral
monCon=$(xrandr | grep " connected" | wc -l)
#Extrai nome da entrada 1
saida1=$(xrandr | grep " connected" | cut -d' ' -f1 | head -n 1)
#Extrai nome da entrada 2
saida2=$(xrandr | grep " connected" | cut -d' ' -f1 | head -n 2 | tail -n 1)

#Lista quantidade de telas conectadas para o usuário.
echo "$monCon monitor(es) conectados"
sleep 5
#Define a resolução no momento de execução.
echo "Definindo a resolução instantânea para a(s) tela(s) conectada(s)"
xrandr --output $saida1  --mode 1024x768
xrandr --output $saida2  --mode 1024x768

#Grava os dados de forma permanente no arquivo xrandr
echo "Gerando arquivo xrandr"

#Script xrandr.set
script_content=$(cat << EOF
#!/bin/bash
#Arquivo Gerado por script de inicialização
#@jjmoratelli
xrandr > /tmp/displays
xinput list --id-only > /tmp/xdevices-id
xinput list --name-only > /tmp/xdevices-name
DEFAULT=$(xrandr|grep -v eDP|awk 'BEGIN {} /^.*connected/{printf("%s;", $1)} END {}' | cut -d ";" -f 1 )
xrandr --output "$saida1" --mode 1024x768
xrandr --output "$saida2" --mode 1024x768
EOF
)

# Grava o conteúdo do script no arquivo
echo "$script_content" > /usr/local/bin/xrandr.set
# Torna o script executável
chmod +x /usr/local/bin/xrandr.set
sleep 5
#Duplicar monitores (script Zanthus)
echo [Inicio] $(date) 2>&1>> /tmp/set-duplicate-monitor.log

tela1=$(xrandr | grep ' connected' | awk '{print $1}' | head -n 1)
tela2=$(xrandr | grep ' connected' | awk '{print $1}' | tail -n 1)

linha="xrandr --output $tela1 --same-as $tela2"

if [ -e /usr/local/bin/xrandr.set ]; then
  echo >> /usr/local/bin/xrandr.set
fi

echo "$linha" | sudo tee -a /usr/local/bin/xrandr.set 2>&1>> /tmp/set-duplicate-monitor.log

echo [Fim] $(date) 2>&1>> /tmp/set-duplicate-monitor.log
echo [Reinicie sua maquina] 2>&1>> /tmp/set-duplicate-monitor.log

echo "Parâmetros ajustados com sucesso, será iniciado a instalação do ScreenSaver"
echo "Script desenvolvido por @jjmoratelli, Jurandir Moratelli ;)."
echo "Instalação ScreenSaver será iniciada. Aguarde..."
sleep 5

# Função que chama o script de configuração do ScreenSaver
curl -s -o /home/zanthus/InstalaSC.sh https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/ScreenSaver/InstalaSC.sh && chmod +x /home/zanthus/InstalaSC.sh && /home/zanthus/InstalaSC.sh
