# Diretrizes para trabalhar neste repositório

- Não mencionar Claude, Anthropic ou IA/assistente em nenhum lugar do código,
  comentários, mensagens de commit ou descrições de PR deste projeto.
- Não adicionar linhas de `Co-Authored-By: Claude ...` (ou equivalentes) nos
  commits.

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
