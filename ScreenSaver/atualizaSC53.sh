#!/bin/bash

# Definindo as URLs dos arquivos
url_origem="http://serv-web/uploads/screensaver/53/screensaver.mp4"
arquivo_destino="/home/zanthus/scsmachadao.mp4"

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
    wget -q "$url_origem" -O "$arquivo_destino"
    echo "Download realizado com sucesso!"
else
    echo "Os arquivos possuem o mesmo tamanho. Download não realizado."
fi
