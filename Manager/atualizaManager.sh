#!/bin/bash

# --- Variáveis de Caminho ---
caminhoMirage="/docker/mirage/docker-compose.yml"
caminhoManager="/docker/manager/docker-compose.yml"
dirMirage="/docker/mirage"
dirManager="/docker/manager"

# --- Função de Leitura para Pipe ---
# Permite solicitar inputs de texto mesmo se o script for chamado via "curl ... | bash"
ler_entrada() {
    local prompt="$1"
    local var_name="$2"
    echo -n "$prompt "
    read -r "$var_name" < /dev/tty
}

# --- 1. Recebendo e Validando a Nova Versão ---
ler_entrada "Digite a nova versão do manager (ex: ORA_8_1.26_184-159-a):" novaVersao

# Validação: Começa com ORA_8_1.26_, seguido de 3 dígitos, um hífen e o resto (manager)
if [[ ! "$novaVersao" =~ ^ORA_8_1\.26_([0-9]{3})-(.+)$ ]]; then
    echo "Erro de validação: O valor inserido é inválido. Ele deve iniciar obrigatoriamente com 'ORA_8_1.26_', possuir 3 dígitos para o banco, um hífen e a versão do manager."
    exit 1
fi

versaoBanco="${BASH_REMATCH[1]}"
versaoManager="${BASH_REMATCH[2]}"

# --- 2. Confirmação do Banco de Dados ---
ler_entrada "Versão do banco exigida $versaoBanco deseja prosseguir? (sim/não):" confirmaBanco

# Converte a resposta para minúscula e valida
if [[ "${confirmaBanco,,}" != "sim" ]]; then
    echo "Operação abortada pelo usuário."
    exit 1
fi

echo "A versão do Manager identificada para atualização é: $versaoManager"
echo "--------------------------------------------------------"

# --- 3. Busca e Validação das Versões Atuais ---
novaVersaoMirage=""
novaVersaoManager=""

# Busca no Mirage
if [[ -f "$caminhoMirage" ]]; then
    # O comando grep com \K extrai apenas o que está DEPOIS do "managerweb:"
    novaVersaoMirage=$(grep -oP 'image:\s*zanthusinovacao1/managerweb:\K.*' "$caminhoMirage" | tr -d ' "')
fi

# Busca no Manager
if [[ -f "$caminhoManager" ]]; then
    novaVersaoManager=$(grep -oP 'image:\s*zanthusinovacao1/managerweb:\K.*' "$caminhoManager" | tr -d ' "')
fi

# Verifica se nenhum foi encontrado
if [[ -z "$novaVersaoMirage" && -z "$novaVersaoManager" ]]; then
    echo "Erro: Nenhuma instalação do managerweb encontrada nos arquivos docker-compose.yml."
    exit 1
fi

# Exibe Mirage se existir e valida o padrão inicial da versão que estava lá
if [[ -n "$novaVersaoMirage" ]]; then
    echo "Mirage - versão atual é: $novaVersaoMirage e a versão atualizada é: $novaVersao"
    if [[ ! "$novaVersaoMirage" =~ ^ORA_8_1\.26_([0-9]{3})-(.+)$ ]]; then
         echo "[Aviso] A versão atual lida no Mirage não corresponde ao padrão esperado (ORA_8_1.26_...)."
    fi
fi

# Exibe Manager se existir e valida o padrão inicial da versão que estava lá
if [[ -n "$novaVersaoManager" ]]; then
    echo "Manager - versão atual é: $novaVersaoManager e a versão atualizada é: $novaVersao"
    if [[ ! "$novaVersaoManager" =~ ^ORA_8_1\.26_([0-9]{3})-(.+)$ ]]; then
         echo "[Aviso] A versão atual lida no Manager não corresponde ao padrão esperado (ORA_8_1.26_...)."
    fi
fi

echo "--------------------------------------------------------"

# --- 4. Confirmação da Atualização ---
ler_entrada "Confirma a atualização do manager nos arquivos existentes? (sim/não):" confirmaAtualizacao

if [[ "${confirmaAtualizacao,,}" != "sim" ]]; then
    echo "Operação abortada pelo usuário."
    exit 1
fi

# --- 5. Atualizando os Arquivos (Substituindo APENAS após os dois pontos) ---
atualizar_arquivo() {
    local arquivo=$1
    if [[ -f "$arquivo" ]]; then
        # O 'sed' agrupa tudo até os dois pontos como \1, mantendo intacto, e injeta a $novaVersao logo após
        sed -i -E "s|(image:[[:space:]]*zanthusinovacao1/managerweb:).*|\1$novaVersao|" "$arquivo"
        echo "Sucesso: Atualizado o arquivo $arquivo"
    fi
}

atualizar_arquivo "$caminhoMirage"
atualizar_arquivo "$caminhoManager"

echo "--------------------------------------------------------"

# --- 6. Executando os Comandos do Docker ---
reiniciar_docker() {
    local dir=$1
    local nome=$2
    if [[ -d "$dir" ]]; then
        echo "Acessando o diretório do $nome ($dir)..."
        cd "$dir" || { echo "Falha ao acessar $dir"; exit 1; }
        
        echo "Parando os serviços do $nome..."
        docker-compose down
        
        echo "Iniciando os serviços do $nome..."
        docker-compose up -d
    else
        echo "Aviso mais amigável: Opa, parece que o caminho '$dir' não existe nesta máquina. Vou pular a reinicialização do $nome!"
    fi
}

reiniciar_docker "$dirMirage" "Mirage"
reiniciar_docker "$dirManager" "Manager"

echo "--------------------------------------------------------"
echo "Processo finalizado com sucesso! Todas as etapas permitidas foram executadas."
