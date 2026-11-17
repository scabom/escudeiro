#!/bin/bash
# Peças comuns dos scripts do agente (Escudeiro). Use com:  . "$(dirname "$0")/comum.sh"
#
# Define:
#   PASTA   a pasta do agente (a que tem o CLAUDE.md / AGENTS.md)
#   LOGS    $PASTA/logs (fora do git), ou $ESCUDEIRO_LOGS quando instalado
#   ESTADO  $LOGS/estado (marcas das rotinas)
#   avisar_telegram "texto"   manda uma mensagem ao dono; devolve 0 só se o Telegram aceitou
#   registrar_em ARQ "texto"  uma linha com data e hora num log
#
# Lê o escudeiro.conf como DADO (CHAVE="valor"), nunca como código: o arquivo
# fica numa pasta onde o agente escreve, e um `source` nele executaria o que
# estivesse escrito lá, inclusive pelas rotinas do launchd, fora da cerca.
#
# Quando roda instalado pelo mac/launchd/instalar-launchd.sh, o plist define:
#   ESCUDEIRO_PASTA  a pasta do agente (dados: logs, lembretes)
#   ESCUDEIRO_CONF   a cópia da configuração feita na instalação, FORA da pasta
#                    do agente. Aí o escudeiro.conf da pasta do agente é ignorado.
#   ESCUDEIRO_LOGS   onde ficam os logs e as marcas das rotinas, também FORA da
#                    pasta do agente (~/Library/Logs/Escudeiro/<rótulo>).

PASTA="${ESCUDEIRO_PASTA:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LOGS="${ESCUDEIRO_LOGS:-${LOGS:-$PASTA/logs}}"
ESTADO="${ESTADO:-$LOGS/estado}"
mkdir -p "$LOGS" "$ESTADO" 2>/dev/null

# Só estas chaves são aceitas; o resto do arquivo é ignorado.
CHAVES_CONF="NOME_AGENTE NOME_DONO TELEGRAM_ENV TELEGRAM_CHAT_ID TELEGRAM_ACESSO BACKUP_DESTINO BACKUP_ORIGENS RCLONE RCLONE_CACERT CLAUDE_TOKEN_ARQUIVO CLAUDE_EFFORT ANTHROPIC_MODEL"

# ler_conf ARQUIVO: aceita CHAVE="valor", CHAVE='valor' ou CHAVE=valor. Só expande
# $HOME, ${HOME} e o ~ do começo. Nada de $(...), crase ou outra variável: viram texto.
ler_conf() {
  local linha chave valor resto
  [ -f "$1" ] || return 0
  while IFS= read -r linha || [ -n "$linha" ]; do
    linha="${linha%$'\r'}"
    [[ "$linha" =~ ^[[:space:]]*([A-Z_][A-Z0-9_]*)=(.*)$ ]] || continue
    chave="${BASH_REMATCH[1]}"; valor="${BASH_REMATCH[2]}"
    case " $CHAVES_CONF " in *" $chave "*) ;; *) continue ;; esac
    case "$valor" in
      \"*) resto="${valor#\"}"; valor="${resto%%\"*}" ;;
      \'*) resto="${valor#\'}"; valor="${resto%%\'*}" ;;
      *) valor="${valor%%[[:space:]]#*}"; valor="${valor%"${valor##*[![:space:]]}"}" ;;
    esac
    valor="${valor//\$\{HOME\}/$HOME}"; valor="${valor//\$HOME/$HOME}"
    case "$valor" in "~"|"~/"*) valor="$HOME${valor:1}" ;; esac
    printf -v "$chave" '%s' "$valor"
  done < "$1"
}

if [ -n "${ESCUDEIRO_CONF:-}" ]; then
  ler_conf "$ESCUDEIRO_CONF"
  # Rotina instalada: caminho de programa ou de token tem de ser absoluto (um relativo
  # seria resolvido a partir da pasta de trabalho, que não é onde ele foi conferido).
  for _k in RCLONE RCLONE_CACERT TELEGRAM_ENV TELEGRAM_ACESSO; do
    case "${!_k:-}" in ''|/*) ;; *) echo "configuração instalada inválida: $_k não é caminho absoluto; rode o instalador de novo" >&2; exit 2 ;; esac
  done
  unset _k
else
  ler_conf "$PASTA/escudeiro.conf"
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
    c=$(/usr/bin/python3 -I -c 'import json,sys
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
  # Token com formato estranho não entra na configuração do curl (poderia injetar opções).
  [[ "$token" =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] || { echo "token do Telegram com formato inválido em $TELEGRAM_ENV" >&2; return 1; }
  [ -n "$chat" ] || { echo "sem chat do dono (configure TELEGRAM_CHAT_ID no escudeiro.conf)" >&2; return 1; }
  [[ "$chat" =~ ^-?[0-9]+$ ]] || { echo "TELEGRAM_CHAT_ID inválido (só números)" >&2; return 1; }
  resposta=$(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\n' "$token" \
             | curl -s -m 20 -K - -d "chat_id=$chat" --data-urlencode "text=$1" 2>&1)
  case "$resposta" in
    *'"ok":true'*) return 0 ;;
    *) echo "Telegram recusou: $(printf '%s' "$resposta" | head -c 200)" >&2; return 1 ;;
  esac
}
