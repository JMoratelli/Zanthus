# Diretrizes para trabalhar neste repositório

- Não mencionar Claude, Anthropic ou IA/assistente em nenhum lugar do código,
  comentários, mensagens de commit ou descrições de PR deste projeto.
- Não adicionar linhas de `Co-Authored-By: Claude ...` (ou equivalentes) nos
  commits.
- **Nunca inserir credenciais neste repositório.** Sem senha, token, chave,
  hash ou string de conexão em código, comentário, arquivo de configuração,
  exemplo, mensagem de commit ou descrição de PR — nem como placeholder que
  pareça real. O repositório é público. Credencial de teste é credencial:
  vale a mesma regra. Quando um script precisar de segredo, ele lê de variável
  de ambiente, de cofre ou de arquivo fora da árvore do repositório, e o
  código traz só o nome de onde buscar.

## `InstalaPDV/PDVJava/Comum/PDVTouch.sh`

É o launcher gráfico do PDV, e este caminho é o **ponto de distribuição para a
frota de produção**: trocar o binário aqui chega nos caixas.

- **Só atualizar sob confirmação explícita, a cada vez.** Autorização de uma
  troca não vale para a seguinte.
- O nome `PDVTouch.sh` é **obrigatório e não pode mudar**. É um ELF nativo com
  nome de script de propósito: o watchdog faz `pgrep -f PDVTouch.sh` e precisa
  encontrar o processo do começo do boot até o PDV cair. Renomear quebra o
  watchdog em silêncio.
- O fonte **não mora aqui** — é o `JMoratelli/ZanthusLauncher`, privado. Compile
  lá com `make`, que constrói dentro de um container Ubuntu 22: o binário é
  dinâmico e herda a glibc de quem compilou, então compilar no host errado gera
  um executável que não sobe no caixa.
- Ao trocar, registre na mensagem de commit o sha256 que entra e o que sai. É o
  que permite rollback sem adivinhação.

## Hora dos terminais Windows

O relógio do PDV é responsabilidade do `w32tm`, que recebe servidor e intervalo
por diretiva de domínio. O script **não** configura fonte de tempo: o que vem de
diretiva tem precedência sobre configuração local, então mexer nisso aqui é
escrever o que nunca vale.

O que o script faz é garantir o fuso da filial (tabela `$configFiliais`; só a 57
é Brasília, as demais são Cuiabá), remover a tarefa legada `HoraCuiaba`, e
registrar a `RelogioPDV` — que roda **só na inicialização** e chama apenas
`w32tm /resync`.

- **Não acrescentar gatilho de evento na `RelogioPDV`.** A `HoraCuiaba` tinha um
  gatilho no evento "hora do sistema alterada" e ela própria alterava a hora: se
  realimentava. Medido em campo, 3032 execuções num único dia, uma a cada 11
  segundos, cada uma gravando o relógio a partir de uma resposta NTP sem
  validação nenhuma.
- **Não trocar o `sc privs` do `exec_pdv` por atribuição de direitos.** O
  `w_receb.exe` roda como LocalSystem e escreve no relógio via `SetLocalTime`.
  Atribuição de direitos (secpol/GPO) não alcança isso: o token do LocalSystem é
  montado pelo kernel. Em campo, o `SeSystemtimePrivilege` nem constava na
  atribuição da máquina e o `w_receb` mudava a hora assim mesmo.

### Verificação pendente

Falta a prova direta de que o `w_receb` **tenta** escrever no relógio e recebe
negativa. O que foi observado até agora é o efeito, não o ato: numa
sincronização forçada contra o servidor, o relógio não se moveu, e o PDV seguiu
funcionando. Para fechar, ligar auditoria de uso de privilégio com sucesso e
falha, forçar a sincronização e procurar o evento. Enquanto isso não for feito,
tratar o bloqueio como "funciona pelo resultado", não como confirmado.

Vale conferir também, depois de atualização grande do Zeus: se o instalador
recriar o serviço `exec_pdv`, a restrição de privilégio some sem avisar.
