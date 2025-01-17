#!/bin/bash
#Funcao Provisioria para corrigir arquivos de carga
sed -i "s/endereco=serv-zt-aplic/endereco=192.168.13.250:80/g" /Zanthus/Zeus/pdvJava/RESTG0000.CFG
sed -i "s/endereco=serv-zt-aplic/endereco=192.168.13.250:80/g" /Zanthus/Zeus/pdvJava/CARG0000.CFG
# Função para limpar a tela
clear
#Função para ajustar parâmetro de log, evitando lotar o HD
sudo sed -i 's/#SystemMaxUse=/SystemMaxUse=1G/g; s/#RuntimeKeepFree=/SystemKeepFree=40%/g' /etc/systemd/journald.conf
echo "Ajustando parâmetros journald.conf, aguarde..."
sleep 5
sudo systemctl restart systemd-journald
echo "Reiniciando journald, aguarde..."
sleep 5
# Atualiza o Grub, para acelerar processo de boot.
read -p "Deseja atualizar o Grub? (Não recomendado para dispositivos antigos) [S/n]: " resposta
if [[ "$resposta" == "S" || "$resposta" == "s" ]]; then
  # Executa o comando sudo grub-install
  sudo grub-install
else
  # Mensagem caso o usuário não queira atualizar
  echo "Ok, grub não será atualizado."
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
    read -p "Digite o IP da impressora de NFE: " IP
    if validar_ip "$IP"; then
        break
    else
        echo "Endereço IP inválido. Tente novamente."
    fi
done

# Comando CUPS para adicionar a impressora
echo "Adicionando impressora..."
# Verifica se o IP digitado é o do balcão fiscal de Confresa
if [[ "$IP" == "192.168.57.125" ]]; then
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
#Contador
for i in {1..10}; do
  echo "Contagem regressiva: $((10 - i))"
  sleep 1
done

# Função que chama o script de configuração do ScreenSaver
curl -s -o /home/zanthus/InstalaSC.sh https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/ScreenSaver/InstalaSC.sh && chmod +x /home/zanthus/InstalaSC.sh && /home/zanthus/InstalaSC.sh
