#!/bin/bash

#Definir variáveis
PORTA="9090"
CAMINHO_URL="/moduloPHPPDV/info.php"
STRING_VALIDACAO="Data do servidor"

#Diretórios de configuração
DIR_REMOTO="/Zanthus/Zeus/pdvJava/GERAL/SINCRO/WEB/moduloPHPPDV/"
DIR_LOCAL="/Zanthus/Zeus/pdvJava/GERAL/SINCRO/WEB/moduloPHPPDV/"
USUARIO_SSH="zanthus"

#Captura IP Local
IP_LOCAL=$(hostname -I | awk '{print $1}')

echo "--- Iniciando Verificação ---"
echo "IP Local detectado: $IP_LOCAL"

# Função para testar se o módulo está operacional
verificar_modulo() {
    local ip_alvo=$1
    local url="http://${ip_alvo}:${PORTA}${CAMINHO_URL}"    
    local resposta=$(curl -s --connect-timeout 3 "$url")
    # Verifica se a resposta começa com "Data do servidor"
    if [[ "$resposta" == "$STRING_VALIDACAO"* ]]; then
        return 0 # Sucesso (0 = true no bash)
    else
        return 1 # Falha
    fi
}

#Checa se precisa fazer ajustes no terminal
echo "Testando: http://${IP_LOCAL}:${PORTA}${CAMINHO_URL} ..."

if verificar_modulo "$IP_LOCAL"; then
    echo "Ok, terminal com módulo PHPPDV operacional."
    exit 0
else
    echo "Falha: O módulo local não retornou a validação esperada."
    echo "Iniciando processo de recuperação..."
fi

#Solicita IP do terminal que está funcionando
echo ""
echo "Digite o IP de um terminal que esteja funcionando corretamente:"
read -r IP_ORIGEM < /dev/tty

# Validação simples se o usuário digitou algo
if [ -z "$IP_ORIGEM" ]; then
    echo "Erro: Nenhum IP foi digitado."
    exit 1
fi

#Valida se o ip selecionado está com o módulo funcionando
echo "Verificando se o IP $IP_ORIGEM possui o módulo operacional..."

if verificar_modulo "$IP_ORIGEM"; then
    echo "IP de origem validado. O módulo está OK lá."
else
    echo "Erro: O terminal de origem ($IP_ORIGEM) também não está respondendo corretamente."
    echo "Operação abortada para evitar cópia de arquivos corrompidos."
    exit 1
fi

#Executa cópia dos arquivos via RSync
echo ""
echo "Iniciando sincronização (Rsync)..."
echo "Origem: $IP_ORIGEM | Destino: Local"
rsync -avz --delete "${USUARIO_SSH}@${IP_ORIGEM}:${DIR_REMOTO}" "${DIR_LOCAL}"

# Verifica se o rsync rodou com sucesso (código de saída 0)
if [ $? -ne 0 ]; then
    echo "Falha durante a execução do rsync."
    exit 1
fi

echo "Sincronização concluída."

#Valida se o módulo retornou à operação.
echo ""
echo "Realizando validação final no terminal local..."

if verificar_modulo "$IP_LOCAL"; then
    echo "Ok, terminal com módulo PHPPDV operacional."
else
    echo "Aviso: Os arquivos foram copiados, mas o módulo ainda não respondeu como esperado."
    echo "Verifique se o serviço precisa ser reiniciado."
fi
