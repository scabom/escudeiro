#!/bin/bash
# Manda uma mensagem ao dono pelo bot do Telegram, sem precisar da janela viva.
# Serve para as tarefas agendadas (a "corrente de avulsos") e para os scripts.
#
# Uso:  bash ferramentas/avisar-telegram.sh "texto puro, sem markdown"
#       echo "texto" | bash ferramentas/avisar-telegram.sh -
# Sai 0 só se o Telegram aceitou a mensagem.
. "$(dirname "$0")/comum.sh"
TEXTO="$1"
[ "$TEXTO" = "-" ] && TEXTO=$(cat)
[ -n "$TEXTO" ] || { echo "uso: $0 \"mensagem\"" >&2; exit 2; }
avisar_telegram "$TEXTO"
