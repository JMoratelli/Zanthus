#!/bin/bash

# --- Configurações ---
PORTA="9090"
CAMINHO_URL="/moduloPHPPDV/info.php"
# String que valida se está funcionando
STRING_VALIDACAO="Data do servidor"

# Caminhos do RSYNC (Origem remota e Destino local)
DIR_REMOTO="/Zanthus/Zeus/pdvJava/GERAL/SINCRO/WEB/moduloPHPPDV/"
DIR_LOCAL="/Zanthus/Zeus/pdvJava/GERAL/SINCRO/WEB/moduloPHPPDV/"
USUARIO_SSH="zanthus"

# --- Passo 1: Capturar IP Local ---
# hostname -I pega os IPs, awk '{print $1}' pega o primeiro (caso tenha mais de uma placa de rede)
IP_LOCAL=$(hostname -I | awk '{print $1}')

if [ -z "$IP_LOCAL" ]; then
    echo "Erro: Não foi possível detectar o IP local."
    exit 1
fi

echo "--- Iniciando Verificação ---"
echo "IP Local detectado: $IP_LOCAL"

# Função para testar se o módulo está operacional
verificar_modulo() {
    local ip_alvo=$1
    local url="http://${ip_alvo}:${PORTA}${CAMINHO_URL}"
    
    # curl -s: modo silencioso
    # --connect-timeout 3: espera no máximo 3 segundos
    local resposta=$(curl -s --connect-timeout 3 "$url")

    # Verifica se a resposta começa com "Data do servidor"
    if [[ "$resposta" == "$STRING_VALIDACAO"* ]]; then
        return 0 # Sucesso (0 = true no bash)
    else
        return 1 # Falha
    fi
}

# --- Passo 2: Checagem Local ---
echo "Testando: http://${IP_LOCAL}:${PORTA}${CAMINHO_URL} ..."

if verificar_modulo "$IP_LOCAL"; then
    echo "✅ Ok, terminal com módulo PHPPDV operacional."
    exit 0
else
    echo "❌ Falha: O módulo local não retornou a validação esperada."
    echo "Iniciando processo de recuperação..."
fi

# --- Passo 3: Solicitar IP de um terminal funcional ---
echo ""
echo "Digite o IP de um terminal que esteja funcionando corretamente:"
read -p "IP do Terminal Origem: " IP_ORIGEM

# Validação simples se o usuário digitou algo
if [ -z "$IP_ORIGEM" ]; then
    echo "Erro: Nenhum IP foi digitado."
    exit 1
fi

# --- Passo 4: Validar o IP de Origem ---
echo "Verificando se o IP $IP_ORIGEM possui o módulo operacional..."

if verificar_modulo "$IP_ORIGEM"; then
    echo "✅ IP de origem validado. O módulo está OK lá."
else
    echo "❌ Erro: O terminal de origem ($IP_ORIGEM) também não está respondendo corretamente."
    echo "Operação abortada para evitar cópia de arquivos corrompidos."
    exit 1
fi

# --- Passo 5: Executar o Rsync ---
echo ""
echo "Iniciando sincronização (Rsync)..."
echo "Origem: $IP_ORIGEM | Destino: Local"

# Comando rsync solicitado
rsync -avz --delete "${USUARIO_SSH}@${IP_ORIGEM}:${DIR_REMOTO}" "${DIR_LOCAL}"

# Verifica se o rsync rodou com sucesso (código de saída 0)
if [ $? -ne 0 ]; then
    echo "❌ Erro crítico: Falha durante a execução do rsync."
    exit 1
fi

echo "Sincronização concluída."

# --- Passo 6: Validação Final ---
echo ""
echo "Realizando validação final no terminal local..."

if verificar_modulo "$IP_LOCAL"; then
    echo "✅ Ok, terminal com módulo PHPPDV operacional."
else
    echo "⚠️ Aviso: Os arquivos foram copiados, mas o módulo ainda não respondeu como esperado."
    echo "Verifique se o serviço precisa ser reiniciado."
fi
