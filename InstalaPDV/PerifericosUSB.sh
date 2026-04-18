#!/bin/bash

config_file="/Zanthus/Zeus/pdvJava/ZSINALIZ_LAURENTI_ARDUINO.CFG"
arquivo_conf_self="/home/zanthus/tmp/Script/tipoConfSelf.conf"

# ==========================================
# 1. AUTOMAÇÃO DA BALANÇA
# ==========================================
output_balanca=$(ls -l /dev/serial/by-id/* 2>/dev/null | grep 'usb-TOLEDO_CDC_DEVICE_')
Y=$(echo "$output_balanca" | grep -oP 'ttyACM\K\d')

mv -f /dev/ttyS4 /dev/ttyS104 2>/dev/null
ln -sf /dev/ttyACM$Y /dev/ttyS4 2>/dev/null

# ==========================================
# 2. AUTOMAÇÃO DO LEITOR USB (CONDICIONAL)
# ==========================================
if [ -f "$arquivo_conf_self" ]; then
    
    # Busca pela string do leitor Datalogic
    output_leitor=$(ls -l /dev/serial/by-id/* 2>/dev/null | grep 'usb-Datalogic')
    Z=$(echo "$output_leitor" | grep -oP 'ttyACM\K\d')
    
    if [ -n "$Z" ]; then
        mv -f /dev/ttyS0 /dev/ttyS100 2>/dev/null
        ln -sf /dev/ttyACM$Z /dev/ttyS0 2>/dev/null
    fi
fi

# ==========================================
# 3. AUTOMAÇÃO DO SINALEIRO
# ==========================================
portaSin=$(ls -l /dev/serial/by-id/* 2>/dev/null | grep "usb-1a86" | grep -o "[0-9]$")

if [ -n "$portaSin" ]; then
    sed -i "2s/.*/linux_device=\/dev\/ttyUSB$portaSin/" "$config_file" 2>/dev/null
fi

exit
