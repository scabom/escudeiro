#!/bin/bash
# Peças comuns dos scripts do agente (Escudeiro). Use com:  . "$(dirname "$0")/comum.sh"
#
# Define:
#   PASTA   a pasta do agente (a que tem o CLAUDE.md / AGENTS.md)
#   LOGS    $PASTA/logs (fora do git)
#   ESTADO  $PASTA/logs/estado (marcas das rotinas)
#   avisar_telegram "texto"   manda uma mensagem ao dono; devolve 0 só se o Telegram aceitou
#   registrar_em ARQ "texto"  uma linha com data e hora num log
#
# Lê o escudeiro.conf da pasta do agente, se existir.

PASTA="${PASTA:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOGS="${LOGS:-$PASTA/logs}"
ESTADO="${ESTADO:-$LOGS/estado}"
mkdir -p "$LOGS" "$ESTADO" 2>/dev/null

if [ -f "$PASTA/escudeiro.conf" ]; then
  # shellcheck disable=SC1091
  . "$PASTA/escudeiro.conf"
fi
NOME_AGENTE="${NOME_AGENTE:-Agente}"
case "$NOME_AGENTE" in *'{{'*) NOME_AGENTE="Agente" ;; esac
NOME_DONO="${NOME_DONO:-}"
case "$NOME_DONO" in *'{{'*) NOME_DONO="" ;; esac
TELEGRAM_ENV="${TELEGRAM_ENV:-$HOME/.claude/channels/telegram/.env}"

registrar_em() { echo "$(date '+%Y-%m-%d %H:%M:%S') $2" >> "$1"; }

_token_telegram() {
  grep '^TELEGRAM_BOT_TOKEN=' "$TELEGRAM_ENV" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'"'"' \r\n'
}

_chat_telegram() {
  if [ -n "$TELEGRAM_CHAT_ID" ]; then printf '%s' "$TELEGRAM_CHAT_ID"; return; fi
  local canal="$HOME/.claude/channels/telegram" c=""
  for arq in "$TELEGRAM_ACESSO" "$canal/access.json"; do
    [ -n "$arq" ] && [ -f "$arq" ] || continue
    c=$(/usr/bin/python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
l=d.get("allowFrom") or d.get("permitidos") or []
print(l[0] if l else "")' "$arq" 2>/dev/null | tr -dc '0-9-')
    [ -n "$c" ] && { printf '%s' "$c"; return; }
  done
  if [ -d "$canal/approved" ]; then
    for f in "$canal/approved"/*; do
      [ -f "$f" ] || continue
      c=$(tr -dc '0-9-' < "$f"); [ -n "$c" ] || c=$(basename "$f" | tr -dc '0-9-')
      [ -n "$c" ] && { printf '%s' "$c"; return; }
    done
  fi
}

# O token vai para o curl pela entrada padrão (-K -), nunca na linha de comando:
# argumento de programa aparece para qualquer um que liste os processos (ps).
# Confere a RESPOSTA, não só o código de saída: o curl sai com 0 mesmo quando o
# Telegram recusa a mensagem.
avisar_telegram() {
  local token chat resposta
  token=$(_token_telegram); chat=$(_chat_telegram)
  [ -n "$token" ] || { echo "sem token do Telegram em $TELEGRAM_ENV" >&2; return 1; }
  [ -n "$chat" ] || { echo "sem chat do dono (configure TELEGRAM_CHAT_ID no escudeiro.conf)" >&2; return 1; }
  resposta=$(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" \
             | curl -s -m 20 -K - -d "chat_id=$chat" --data-urlencode "text=$1" 2>&1)
  case "$resposta" in
    *'"ok":true'*) return 0 ;;
    *) echo "Telegram recusou: $(printf '%s' "$resposta" | head -c 200)" >&2; return 1 ;;
  esac
}
