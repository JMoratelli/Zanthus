#!/bin/bash
#Caminho de manipulação arquivos sinaleiros
config_file="/Zanthus/Zeus/pdvJava/ZSINALIZ_LAURENTI_ARDUINO.CFG"

#Obtém os valores de ACMx para o link simbólico
output=$(ls -l /dev/serial/by-id/* | grep 'usb-TOLEDO_CDC_DEVICE_')

#Obtém valor númerico da porta do sinaleiro
portaSin=$(ls -l /dev/serial/by-id/* | grep "usb-1a86_USB_Serial-if00-port0" | grep -o "[0-9]$")

#Extrai a porta da balança e grava em "Y"
Y=$(echo "$output" | grep -oP 'ttyACM\K\d')

#Manipula portas e grava variáveis de forma fixa no sistema.
mv -vf /dev/ttyS4 /dev/ttyS104
ln -s /dev/ttyACM$Y /dev/ttyS4

# Substitui a linha de configuração do sinaleiro, de forma dinâmica, caso seja alterado, irá reconfigurar.
sed -i "2s/.*/linux_device=\/dev\/ttyUSB$portaSin/" "$config_file"
exit
