#!/bin/bash

# Definindo as URLs dos arquivos
url_origem="http://serv-web/uploads/interfaceZanthus/interface.7z"
arquivo_destino="/Zanthus/Zeus/Interface/interface.7z"

# Função para obter o tamanho do arquivo em bytes
obter_tamanho() {
    local arquivo="$1"
    local tamanho=$(stat -c%s "$arquivo" 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$tamanho"
    else
        echo "0"
    fi
}

# Obtendo os tamanhos dos arquivos
tamanho_origem=$(curl -s -I "$url_origem" | grep -oP 'Content-Length: \K\d+')
tamanho_destino=$(obter_tamanho "$arquivo_destino")

# Convertendo os tamanhos para números
tamanho_origem_num=$(echo "$tamanho_origem" | grep -Eo '[0-9]+')
tamanho_destino_num=$(echo "$tamanho_destino" | grep -Eo '[0-9]+')

# Comparando os tamanhos
if [ "$tamanho_origem_num" != "$tamanho_destino_num" ]; then
    # Baixando o arquivo se os tamanhos forem diferentes
    cd /Zanthus/Zeus/Interface/
    wget -q "$url_origem" -O "$arquivo_destino" && 7z x -o/Zanthus/Zeus/Interface/ -y interface.7z
    echo "Atualizado com sucesso!"
else
    echo "Os arquivos possuem o mesmo tamanho. Download não realizado."
fi
echo "Aplicando permissões na pasta de interface"
chmod 777 -R /Zanthus/Zeus/Interface/
# Exibe o alerta com contagem regressiva
(
  zenity --warning --no-wrap --text "<span foreground='red'><b>PDV ATUALIZADO, AGUARDE REINÍCIO</b></span>" --width=300 --height=150 &
  PID=$!

  for i in {5..1}; do
    sleep 1
    zenity --warning --no-wrap --text "<span foreground='red'><b>PDV SERÁ REINICIADO EM $i SEGUNDOS</b></span>" --width=300 --height=150 --pid=$PID
  done

  sleep 1
  zenity --warning --text "<span foreground='red'><b>PDV REINICIANDO...</b></span>" --width=300 --height=150 --pid=$PID
  reboot
)

