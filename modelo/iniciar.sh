#!/bin/bash
# Acorda o agente (Claude Code) com o canal do Telegram anexado.
# Rode com:  screen -dmS agente "<pasta do agente>/iniciar.sh"
# (e para espiar: screen -r agente; para sair sem desligar: Ctrl+A e depois D)
#
# Lições que estão aqui dentro, todas de quedas silenciosas reais:

PASTA="$(cd "$(dirname "$0")" && pwd)"

# 1. Um Claude Code carrega variáveis CLAUDE_* que dizem QUEM ELE É. Quem herda
#    essas variáveis (subindo de dentro de outra sessão) nasce achando que é um
#    pedaço de outra sessão: sem gravar conversa e sem ler o próprio canal.
for _v in $(env | sed -n 's/^\(CLAUDE[A-Z_]*\)=.*/\1/p'); do unset "$_v"; done
unset _v

# 2. Cada máquina põe o claude num lugar (npm global, ~/.local, Homebrew). Sem o
#    caminho certo, o script morre com "claude: command not found", CALADO.
export PATH="$HOME/.bun/bin:$HOME/.local/npm/bin:$HOME/.local/node/bin:$HOME/.local/bin:$HOME/.claude/local:/opt/homebrew/bin:/usr/local/bin:$PATH"

. "$PASTA/ferramentas/comum.sh"

# 3. E se AINDA assim não achar, isto grita em vez de morrer em silêncio. O aviso
#    vai pelo Telegram, que é onde o dono realmente olha.
if ! command -v claude >/dev/null 2>&1; then
  avisar_telegram "⚠️ Não consegui subir: o comando 'claude' não está no PATH desta máquina. Me ajuda a conferir a instalação?" >/dev/null 2>&1
  registrar_em "$LOGS/iniciar.log" "FATAL: claude nao encontrado no PATH"
  exit 1
fi

# 4. Sem isto, subindo pelo launchd/screen, o terminal fica com LANG vazio e não
#    entende UTF-8: quem espiar a screen vê "conexÃ£o" no lugar de "conexão".
export LANG="${LANG:-pt_BR.UTF-8}"
export LC_ALL="${LC_ALL:-pt_BR.UTF-8}"

cd "$PASTA" || exit 1

# 5. Com a extensão do Claude no Chrome instalada, o Claude Code pode abrir com
#    uma PERGUNTA na primeira tela e esperar uma tecla PARA SEMPRE. Ninguém
#    digita nada numa screen: o canal nunca sobe. Um agente que roda sozinho não
#    pode depender de tecla humana para terminar de subir.
export CLAUDE_CODE_ENABLE_CFC=false

# 6. Esforço e modelo escritos AQUI (e não só no ambiente de quem acordou o
#    agente): garantia que só existe enquanto ninguém reinicia de outro jeito não
#    é garantia. Configure em escudeiro.conf (CLAUDE_EFFORT).
[ -n "$CLAUDE_EFFORT" ] && export CLAUDE_EFFORT
[ -n "$ANTHROPIC_MODEL" ] && export ANTHROPIC_MODEL

# 7. Token de longa duração (opcional). O login comum vence e se renova sozinho;
#    com dois agentes renovando ao mesmo tempo, um pode derrubar o outro. O token
#    do `claude setup-token` não se renova: sem corrida. Ele mora FORA do git
#    (CLAUDE_TOKEN_ARQUIVO no escudeiro.conf, chmod 600) e é lido DEPOIS da
#    limpeza das variáveis CLAUDE_* lá em cima, senão seria apagado.
if [ -n "$CLAUDE_TOKEN_ARQUIVO" ]; then
  _tok=$(grep '^CLAUDE_CODE_OAUTH_TOKEN=' "${CLAUDE_TOKEN_ARQUIVO/#\~/$HOME}" 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' \r\n')
  [ -n "$_tok" ] && export CLAUDE_CODE_OAUTH_TOKEN="$_tok"
  unset _tok
fi

CANAL="plugin:telegram@claude-plugins-official"

# --continue retoma a conversa anterior. Na primeira vez não há o que retomar,
# então cai para uma sessão nova.
claude --continue --channels "$CANAL" || claude --channels "$CANAL"
