#!/bin/bash
# Transcreve um áudio pela Groq, com a chave do audio.json, SEM pôr a chave na
# linha de comando.
#
# Por quê: argumento de programa aparece para qualquer um que liste os processos
# (ps) e pode parar em registro de execução. Aqui a chave vai para o curl pela
# entrada padrão (-K -), como o comum.sh já faz com o token do Telegram.
#
# Uso:  bash ferramentas/transcrever-groq.sh <caminho do áudio>
# A transcrição sai pura no stdout. Sai 0 só se a Groq devolveu a transcrição.
#
# Dois detalhes que NÃO podem mudar:
#   - o ";filename=audio.ogg": a Groq valida pela extensão e recusa .oga (o
#     Telegram entrega .oga) com HTTP 400. O arquivo vai igualzinho, muda só o nome.
#     Outros formatos (m4a, mp3, wav...) vão como audio.<extensão>.
#   - o User-Agent: sem ele o Cloudflare da Groq devolve 403 "error code: 1010".
set -u
AUDIO="${1:-}"
[ -n "$AUDIO" ] && [ -f "$AUDIO" ] || { echo "uso: $0 <caminho do áudio>" >&2; exit 2; }
case "$AUDIO" in *';'*|*','*|*'"'*) echo "renomeie o áudio: o caminho não pode ter ; , ou aspas" >&2; exit 2 ;; esac
EXT=$(printf '%s' "${AUDIO##*.}" | tr '[:upper:]' '[:lower:]')
case "$EXT" in
  oga|ogg|opus) NOME_ENVIO="audio.ogg" ;;
  m4a|mp3|mp4|mpeg|mpga|wav|webm|flac) NOME_ENVIO="audio.$EXT" ;;
  *) echo "formato de áudio que a Groq não aceita: .$EXT" >&2; exit 2 ;;
esac
PASTA="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${AUDIO_JSON:-$PASTA/audio.json}"

CHAVE=$(/usr/bin/python3 -I -c 'import json,sys
d=json.load(open(sys.argv[1], encoding="utf-8"))
print(d.get("groq_api_key","") if d.get("provider")=="groq" else "")' "$CONF" 2>/dev/null)
[ -n "$CHAVE" ] || { echo "sem chave da Groq no $CONF (ou provider diferente de groq)" >&2; exit 1; }
# Só o formato de chave da Groq entra na configuração do curl (nada de aspas ou quebra de linha).
[[ "$CHAVE" =~ ^gsk_[A-Za-z0-9_-]{20,}$ ]] || { echo "a chave no $CONF não tem o formato da Groq (gsk_...)" >&2; exit 1; }

SAIDA=$(mktemp -t transcricao) || exit 1
trap 'rm -f "$SAIDA"' EXIT
CODIGO=$(printf 'header = "Authorization: Bearer %s"\n' "$CHAVE" \
  | curl -sS -m 120 -K - -o "$SAIDA" -w '%{http_code}' \
      -H "User-Agent: escudeiro/1.0" \
      -F "model=whisper-large-v3-turbo" -F "language=pt" -F "response_format=text" \
      -F "file=@$AUDIO;filename=$NOME_ENVIO" \
      https://api.groq.com/openai/v1/audio/transcriptions)
unset CHAVE
if [ "$CODIGO" = "200" ]; then
  cat "$SAIDA"
  exit 0
fi
echo "a Groq não transcreveu (HTTP ${CODIGO:-sem resposta}): $(head -c 200 "$SAIDA" 2>/dev/null)" >&2
exit 1
