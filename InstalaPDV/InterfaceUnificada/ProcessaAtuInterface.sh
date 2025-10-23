#!/bin/bash

#Atenção! Para a execução do script, deve existir a pasta "/home/zanthus/ProcessaZip" O arquivo de interface vindo da Zanthus deverá estar dentro dessa pasta, ele será apagado após realizar o processamento, não altere o código!
# Define o diretório base
diretorio_base="/home/zanthus/ProcessaZip"

# Verifica se o diretório base existe
if [ ! -d "$diretorio_base" ]; then
  echo "Erro: Diretório base '$diretorio_base' não encontrado."
  exit 1
fi

# Encontra o arquivo .zip (que começa com "Interface_R-" ou "InterfaceUnificada_")
arquivo_zip=$(find "$diretorio_base" -maxdepth 1 -name "Interface_R-*.zip" -o -name "InterfaceUnificada_*.zip" 2>/dev/null)

# Verifica se o arquivo .zip foi encontrado
if [ -z "$arquivo_zip" ]; then
  echo "Erro: Arquivo .zip não encontrado no diretório '$diretorio_base'."
  exit 1
fi

# Se o arquivo interface.7z existir, remove-o
if [ -f "$diretorio_base/interface.7z" ]; then
  rm -f "$diretorio_base/interface.7z"
fi

# Extrai o nome base do arquivo (sem a extensão .zip)
nome_base=$(basename "$arquivo_zip" .zip)

# Cria um diretório temporário para extrair o arquivo .zip
mkdir -p "$diretorio_base/pasta_temporaria"

# Descompacta o arquivo .zip para o diretório temporário
unzip "$arquivo_zip" -d "$diretorio_base/pasta_temporaria"

# Remove arquivos e diretórios específicos
rm -f "$diretorio_base/pasta_temporaria/app/api/dinamico/pdvMouse/Buttons.js"
rm -f "$diretorio_base/pasta_temporaria/resources/imagens/Zeus_V.gif"
rm -f "$diretorio_base/pasta_temporaria/resources/imagens/cancela_sel.png"
rm -f "$diretorio_base/pasta_temporaria/resources/imagens/cancela.png"
rm -f "$diretorio_base/pasta_temporaria/resources/imagens/descanso1000.jpg"
rm -f "$diretorio_base/pasta_temporaria/resources/imagens/self/codigo.gif"
rm -f "$diretorio_base/pasta_temporaria/resources/js/telas_touch.js"
rm -f "$diretorio_base/pasta_temporaria/resources/js/teclas_touch.js"
rm -f "$diretorio_base/pasta_temporaria/config/config.js"
rm -f "$diretorio_base/pasta_temporaria/app/view/tela/2/TelaComanda.js"

rm -rf "$diretorio_base/pasta_temporaria/resources/icones"
rm -rf "$diretorio_base/pasta_temporaria/resources/audio"

# Compacta a pasta modificada em um arquivo 7z
7z a "$diretorio_base/interface.7z" "$diretorio_base/pasta_temporaria"/*

# Remove o diretório temporário
rm -rf "$diretorio_base/pasta_temporaria"

# Remove o arquivo .zip original
rm -f "$arquivo_zip"

echo "Arquivo '$arquivo_zip' processado com sucesso. Arquivo 'interface.7z' criado em '$diretorio_base'."
