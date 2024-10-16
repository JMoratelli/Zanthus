#!/bin/bash
echo "Ajustando opções no arquivo /etc/resolv.conf"
# Configura servidor DNS e adiciona o parâmetro search para que resolva o DNS do AD.
sudo printf "nameserver 192.168.12.1\n#options edns0 trust-ad\nsearch redemachado.local" > /etc/resolv.conf
echo "Ajustado opções no arquivo /etc/resolv.conf"

# Ajusta Fuso horário
echo "Escolha o fuso horário:"
echo "1. Cuiabá (America/Cuiaba)"
echo "2. São Paulo (America/Sao_Paulo)"

read -p "Digite 1 ou 2: " opcao

case $opcao in
    1)
        timedatectl set-timezone America/Cuiaba
        hwclock -w
        sed -i 's/UTC/LOCAL/g' /etc/adjtime
        hwclock -w
        sed -i 's/UTC/LOCAL/g' /etc/adjtime
        hwclock -w
        echo "Fuso horário definido para Cuiabá e ajustado relógio de hardware."
        ;;
    2)
        timedatectl set-timezone America/Sao_Paulo
        hwclock -w
        sed -i 's/UTC/LOCAL/g' /etc/adjtime
        hwclock -w
        sed -i 's/UTC/LOCAL/g' /etc/adjtime
        hwclock -w
        echo "Fuso horário definido para São Paulo e ajustado relógio de hardware."
        ;;
    *)
        echo "Opção inválida. Por favor, digite 1 ou 2."
        ;;
esac

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
# Solicita as horas ao usuário
read -p "Digite a hora para desligar o computador durante a semana, com dois dígitos (00-23): " hora_semana
validar_hora "$hora_semana" || exit 1

read -p "Digite a hora para desligar o computador aos domingos, com dois dígitos (00-23): " hora_domingo
validar_hora "$hora_domingo" || exit 1

# Cria as linhas para o crontab
linha_semana="00 $hora_semana * * * /sbin/shutdown -h now"
linha_domingo="00 $hora_domingo * * SUN /sbin/shutdown -h now"

# Adiciona as linhas ao crontab
(echo "$linha_semana"; echo "$linha_domingo") | crontab -
sleep 5
(echo "$linha_semana"; echo "$linha_domingo") | crontab -

echo "Desligamento agendado:"
echo "* Durante a semana: $hora_semana horas"
echo "* Aos domingos: $hora_domingo horas"

# Cópia de arquivos de interface
echo "Etapa de clone de Interface e Clisitef, clone de um PDV do mesmo tipo"
echo "Nunca aponte de um Self para um PDV ou de um PDV para um Self"
echo "Aponte para um PDV do mesmo tipo que já foi configurado, cuidado!"
read -p "Digite o IP do caixa a ser clonado (ou pressione Enter caso tenha feito manualmente): " IP_CAIXA

# Validação básica do IP
if [[ $IP_CAIXA =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
  echo "IP válido: $IP_CAIXA"
else
  # IP inválido
  echo "IP inválido ou decidiu pular a etapa. "
  IP_CAIXA="batata"
fi
# Comando irá clonar os arquivos de interface do PDV que apontou
rsync -avz -I -e "ssh -p 22" root@$IP_CAIXA:/Zanthus/Zeus/Interface/ /Zanthus/Zeus/Interface/
sleep 5
# Nessa etapa irá copiar os arquivos de ClisiTef do PDV que apontou
rsync -avz -I -e "ssh -p 22" root@$IP_CAIXA:/Zanthus/Zeus/pdvJava/CliSiTef.ini /Zanthus/Zeus/pdvJava/

# Configurações do CUPS para ajustes da impressão
echo "Alterando parâmetros CUPS"
sudo sed 's/^BrowseLocalProtocols.*$/BrowseLocalProtocols\ none/' -i /etc/cups/cupsd.conf
cupsctl WebInterface=yes; service cups stop; service cups start
cupsctl --remote-admin --remote-any
printf "linux.impressora=IMP-NFE\nlinux.opcoes=3\n" > /Zanthus/Zeus/pdvJava/ZPDF00.CFG
echo "Parâmetros CUPS ajustados com sucesso, será iniciado a instalação do ScreenSaver"
sleep 5

# Função que chama o script de configuração do ScreenSaver
curl -s -o /home/zanthus/InstalaSC.sh https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/ScreenSaver/InstalaSC.sh && chmod +x /home/zanthus/InstalaSC.sh && /home/zanthus/InstalaSC.sh

