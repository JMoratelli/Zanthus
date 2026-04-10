#!/bin/bash
clear
# --- Variáveis de Caminho ---
caminhoMirage="/docker/mirage/docker-compose.yml"
caminhoManager="/docker/manager/docker-compose.yml"
dirMirage="/docker/mirage"
dirManager="/docker/manager"

# --- Variáveis para Armazenar Versões Atuais ---
versaoAtualMirage=""
versaoAtualManager=""

# --- Função de Leitura para Pipe ---
ler_entrada() {
    local prompt="$1"
    local var_name="$2"
    echo -n "$prompt "
    read -r "$var_name" < /dev/tty
}

# --- 1. Recebendo e Validando a Nova Versão ---
ler_entrada "Digite a nova versão do manager (ex: php_8_2.30_185-160_EV_1):" novaVersao

# --- SANITIZAÇÃO DE TEXTO ---
# Substitui traços especiais (en-dash/em-dash) por hífen normal
novaVersao="${novaVersao//–/-}"
novaVersao="${novaVersao//—/-}"
# Remove qualquer espaço em branco ou "carriage return" (lixo invisível de Windows/cópia)
novaVersao=$(echo "$novaVersao" | tr -d ' \t\r\n')

# Validação do Padrão
if [[ ! "$novaVersao" =~ ^php_8_2\.30_([0-9]{3})-(.+)$ ]]; then
    echo "Erro de validação: O valor inserido é inválido. Ele deve iniciar obrigatoriamente com 'php_8_2.30_', possuir 3 dígitos para o banco, um hífen e a versão do manager."
    exit 1
fi

versaoBanco="${BASH_REMATCH[1]}"
versaoManager="${BASH_REMATCH[2]}"

# --- 2. Confirmação do Banco de Dados ---
ler_entrada "Versão do banco exigida $versaoBanco deseja prosseguir? (sim/não):" confirmaBanco

if [[ "${confirmaBanco,,}" != "sim" ]]; then
    echo "Operação abortada pelo usuário."
    exit 1
fi

echo "A versão do Manager identificada para atualização é: $versaoManager"
echo "--------------------------------------------------------"

# --- 3. Busca e Validação das Versões Atuais ---
if [[ -f "$caminhoMirage" ]]; then
    versaoAtualMirage=$(grep -oP 'image:\s*zanthusinovacao1/managerweb:\K.*' "$caminhoMirage" | tr -d ' "')
fi

if [[ -f "$caminhoManager" ]]; then
    versaoAtualManager=$(grep -oP 'image:\s*zanthusinovacao1/managerweb:\K.*' "$caminhoManager" | tr -d ' "')
fi

if [[ -z "$versaoAtualMirage" && -z "$versaoAtualManager" ]]; then
    echo "Erro: Nenhuma instalação do managerweb encontrada nos arquivos docker-compose.yml."
    exit 1
fi

if [[ -n "$versaoAtualMirage" ]]; then
    echo "Mirage - versão atual é: $versaoAtualMirage e a versão atualizada é: $novaVersao"
    if [[ ! "$versaoAtualMirage" =~ ^php_8_2\.30_([0-9]{3})-(.+)$ ]]; then
         echo "[Aviso] A versão atual lida no Mirage não corresponde ao padrão esperado (php_8_2.30_...)."
    fi
fi

if [[ -n "$versaoAtualManager" ]]; then
    echo "Manager - versão atual é: $versaoAtualManager e a versão atualizada é: $novaVersao"
    if [[ ! "$versaoAtualManager" =~ ^php_8_2\.30_([0-9]{3})-(.+)$ ]]; then
         echo "[Aviso] A versão atual lida no Manager não corresponde ao padrão esperado (php_8_2.30_...)."
    fi
fi

echo "--------------------------------------------------------"

# --- 4. Confirmação da Atualização ---
ler_entrada "Confirma a atualização do manager nos arquivos existentes? (sim/não):" confirmaAtualizacao

if [[ "${confirmaAtualizacao,,}" != "sim" ]]; then
    echo "Operação abortada pelo usuário."
    exit 1
fi

# --- 5. Funções Auxiliares de Atualização e Reinício ---
atualizar_arquivo() {
    local arquivo=$1
    local versao=$2
    if [[ -f "$arquivo" ]]; then
        sed -i -E "s|(image:[[:space:]]*zanthusinovacao1/managerweb:).*|\1$versao|" "$arquivo"
        echo "Sucesso: Atualizado o arquivo $arquivo para a versão $versao"
    fi
}

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
         echo "Aviso: O caminho '$dir' não existe nesta máquina. Reinicialização do $nome ignorada."
    fi
}

# --- 6. Aplicando a Nova Versão ---
atualizar_arquivo "$caminhoMirage" "$novaVersao"
atualizar_arquivo "$caminhoManager" "$novaVersao"

reiniciar_docker "$dirMirage" "Mirage"
reiniciar_docker "$dirManager" "Manager"

echo "--------------------------------------------------------"

# --- 7. Confirmação Final / Rollback ---
while true; do
    ler_entrada "Processo finalizado, deseja confirmar atualização ou dar rollback? Digite sim para confirmar, ou rollback para dar rollback:" acaoFinal
    
    # Valida as opções estritas
    acaoFinal_lower="${acaoFinal,,}"
    if [[ "$acaoFinal_lower" == "sim" || "$acaoFinal_lower" == "rollback" ]]; then
        break
    else
        echo "Opção inválida. Digite apenas 'sim' ou 'rollback'."
    fi
done

if [[ "$acaoFinal_lower" == "sim" ]]; then
    echo "Atualização confirmada com sucesso!"
elif [[ "$acaoFinal_lower" == "rollback" ]]; then
    echo "Iniciando processo de Rollback..."
    
    # Aplica as versões antigas guardadas em memória
    if [[ -n "$versaoAtualMirage" && -f "$caminhoMirage" ]]; then
        atualizar_arquivo "$caminhoMirage" "$versaoAtualMirage"
    fi
    
    if [[ -n "$versaoAtualManager" && -f "$caminhoManager" ]]; then
        atualizar_arquivo "$caminhoManager" "$versaoAtualManager"
    fi
    
    # Reinicia com a versão antiga
    reiniciar_docker "$dirMirage" "Mirage (Rollback)"
    reiniciar_docker "$dirManager" "Manager (Rollback)"
    
    echo "Rollback concluído. O sistema retornou às versões anteriores."
fi
