#!/bin/bash
echo "Ajustando opções no arquivo /etc/resolv.conf"
# Configura servidor DNS e adiciona o parâmetro search para que resolva o DNS do AD.
sudo printf "nameserver 192.168.12.1\n#options edns0 trust-ad\nsearch redemachado.local" > /etc/resolv.conf
echo "Ajustado opções no arquivo /etc/resolv.conf"

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
echo "Etapa de clone de Interface e Clisitef, clone de um PDV do mesmo tipo"
echo "Nunca aponte de um Self para um PDV ou de um PDV para um Self"
echo "Aponte para um PDV do mesmo tipo que já foi configurado, cuidado! Nunca para esse PDV que está configurando."
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
echo "Digite a senha do usuário root (consulte manual)"
rsync -avz -I -e "ssh -o StrictHostKeyChecking=no -p 22" root@$IP_CAIXA:/Zanthus/Zeus/Interface/ /Zanthus/Zeus/Interface/
sleep 5
# Nessa etapa irá copiar os arquivos de ClisiTef do PDV que apontou
echo "Digite a senha do usuário novamente para copiar os arquivos ClisiTef"
rsync -avz -I -e "ssh -o StrictHostKeyChecking=no -p 22" root@$IP_CAIXA:/Zanthus/Zeus/pdvJava/CliSiTef.ini /Zanthus/Zeus/pdvJava/

# Configurações do CUPS para ajustes da impressão
echo "Alterando parâmetros CUPS"
sudo sed 's/^BrowseLocalProtocols.*$/BrowseLocalProtocols\ none/' -i /etc/cups/cupsd.conf
cupsctl WebInterface=yes; service cups stop; service cups start
cupsctl --remote-admin --remote-any
printf "linux.impressora=IMP-NFE\nlinux.opcoes=3\n" > /Zanthus/Zeus/pdvJava/ZPDF00.CFG
echo "Parâmetros CUPS ajustados com sucesso, será iniciado a instalação do ScreenSaver"
echo "Script feito por @jjmoratelli, Jurandir Moratelli."
sleep 5
#Contador
for i in {1..10}; do
  echo "Contagem regressiva: $((10 - i))"
  sleep 1
done

# Função que chama o script de configuração do ScreenSaver
curl -s -o /home/zanthus/InstalaSC.sh https://raw.githubusercontent.com/M4ch4d0C0l1d4r/Zanthus/refs/heads/main/ScreenSaver/InstalaSC.sh && chmod +x /home/zanthus/InstalaSC.sh && /home/zanthus/InstalaSC.sh

