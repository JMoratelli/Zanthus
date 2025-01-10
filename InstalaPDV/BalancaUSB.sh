#!/bin/bash
#Obtém os valores de ACMx para o link simbólico
output=$(ls -l /dev/serial/by-id/* | grep 'usb-TOLEDO_CDC_DEVICE_')

# Verificar se a linha foi encontrada
if [[ -z "$output" ]]; then
  echo "Dispositivo não encontrado."
  exit 1
fi

# Extrair o dígito Y usando expressões regulares
Y=$(echo "$output" | grep -oP 'ttyACM\K\d')

mv -vf /dev/ttyS4 /dev/ttyS104
ln -s /dev/ttyACM$Y /dev/ttyS4
exit
