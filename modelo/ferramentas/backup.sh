#!/bin/bash
# Backup diário do essencial do agente (e de outras pastas que o dono escolher), com o rclone.
#
# Estratégia: espelho do estado ATUAL + histórico de versões.
#   <destino>/atual/<pasta>/          -> como as coisas estão agora
#   <destino>/versoes/DATA/<pasta>/   -> o que foi alterado ou apagado naquele dia
# Assim, apagar um arquivo aqui NÃO o apaga do backup: ele vai para o histórico.
#
# Configuração (escudeiro.conf, na pasta do agente):
#   BACKUP_DESTINO="<remote>:<pasta>"   ex.: "meu-drive:Backup-Agente" (crie o remote com "rclone config")
#   BACKUP_ORIGENS="$HOME/Documentos/projeto:$HOME/outra-pasta"   (opcional; a pasta do agente entra sempre)
#   RCLONE, RCLONE_CACERT                (opcionais)
#
# Dica de segurança para o remote do Google Drive: crie um client_id próprio e use o escopo
# "drive.file" (o rclone só enxerga o que ele mesmo criou), em vez do escopo "drive", que abre o
# Drive INTEIRO para quem tiver a chave.
#
# Uso:  bash ferramentas/backup.sh
# Teste do aviso de falha (não mexe no backup de verdade):
#   BACKUP_TESTE_DESTINO="remote-que-nao-existe:x" bash ferramentas/backup.sh

. "$(dirname "$0")/comum.sh"
RCLONE="${RCLONE:-$(command -v rclone || echo "$HOME/.local/bin/rclone")}"
TESTE=""
if [ -n "$BACKUP_TESTE_DESTINO" ]; then BACKUP_DESTINO="$BACKUP_TESTE_DESTINO"; TESTE="[TESTE] "; fi
HOJE=$(date +%Y-%m-%d)
LOG="$LOGS/backup.log"
CANARIO="$PASTA/logs/backup-canario.txt"
registrar() { registrar_em "$LOG" "${TESTE}$*"; }

# ⚠️ AVISO DE FALHA. Backup que falha calado é o pior tipo: a gente só descobre no
# dia em que precisa dele. Qualquer falha vira mensagem no Telegram.
avisar() {
  if ERRO=$(avisar_telegram "$1" 2>&1); then registrar "aviso de falha entregue no telegram"
  else registrar "AVISO NAO ENTREGUE: $ERRO"; fi
}

if [ -z "$BACKUP_DESTINO" ]; then
  echo "backup desligado: configure BACKUP_DESTINO no escudeiro.conf"
  exit 0
fi
if [ ! -x "$RCLONE" ]; then
  registrar "=== backup iniciado ==="
  registrar "FALHOU: rclone nao encontrado ($RCLONE)"
  avisar "${TESTE}⚠️ Aviso do backup ($HOJE): não achei o rclone nesta máquina, então nada foi copiado. Me chama que eu olho."
  registrar "=== backup terminado ==="
  exit 1
fi

CACERT_ARGS=()
# Se a verificação de certificado do macOS falhar para o rclone (erro "tls: failed to verify
# certificate"), um pacote de certificados próprio contorna:
#   curl -sSL -o ~/.config/rclone/cacert.pem https://curl.se/ca/cacert.pem
[ -n "$RCLONE_CACERT" ] && [ -f "$RCLONE_CACERT" ] && CACERT_ARGS=(--ca-cert "$RCLONE_CACERT")

# Segredos NUNCA sobem: chaves e .env são regeneráveis, não vale o risco de
# deixá-los na nuvem. Pesados e reinstaláveis também ficam de fora.
#
# ⚠️ ARMADILHA DO PADRÃO: `**/node_modules/**` NÃO exclui `node_modules/` quando
# ela está na RAIZ da origem, porque o `**/` exige pelo menos uma pasta antes.
# A forma certa é sem o `**/` na frente: `node_modules/**` casa na raiz E
# aninhado. E confira medindo o que subiu, não confiando no que foi escrito.
#
# ⚠️ OS BRUTOS NUNCA SOBEM: quando o agente converte um documento com dado
# pessoal, ele guarda o bruto como `NAO-LER-*` (só para conferir o filtro) e o
# `*.limpo.*`. O bruto não protege nada (é cópia do original) e só expõe.
EXCLUSOES=(
  --exclude "audio.json"
  --exclude "*.env"
  --exclude ".env*"
  --exclude "ponte.env*"
  --exclude "escudeiro.conf"
  --exclude ".DS_Store"
  --exclude "node_modules/**"
  --exclude "__pycache__/**"
  --exclude ".git/**"
  --exclude "NAO-LER-*"
)

registrar "=== backup iniciado ==="
# Canário: marca sem dado nenhum, lida DE VOLTA do destino pelo confere-backup.sh.
[ -z "$TESTE" ] && echo "$HOJE $(date +%H:%M:%S)" > "$CANARIO"

FALHAS=()
PRIMEIRO_ERRO=""
IFS=':' read -r -a EXTRAS <<< "${BACKUP_ORIGENS:-}"
for ORIGEM in "$PASTA" "${EXTRAS[@]}"; do
  [ -n "$ORIGEM" ] || continue
  ORIGEM="${ORIGEM/#\~/$HOME}"
  NOME=$(basename "$ORIGEM")
  [ -d "$ORIGEM" ] || { registrar "pulando $NOME (nao existe)"; continue; }

  SAIDA=$("$RCLONE" sync "$ORIGEM" "$BACKUP_DESTINO/atual/$NOME" \
      --backup-dir "$BACKUP_DESTINO/versoes/$HOJE/$NOME" \
      "${EXCLUSOES[@]}" "${CACERT_ARGS[@]}" \
      --stats-one-line --stats 0 --log-level NOTICE 2>&1)
  CODIGO=$?
  if [ $CODIGO -eq 0 ]; then
    registrar "OK: $NOME"
  else
    registrar "FALHOU: $NOME (codigo $CODIGO) — $(echo "$SAIDA" | tail -3 | tr '\n' ' ' | cut -c1-300)"
    FALHAS+=("$NOME")
    [ -z "$PRIMEIRO_ERRO" ] && PRIMEIRO_ERRO=$(echo "$SAIDA" | grep -m1 -i -E 'error|failed|couldn' | cut -c1-300)
  fi
done

# Confere que o backup realmente tem conteúdo do outro lado. Sem contagem é falha
# também: não dá para afirmar que o backup existe se não conseguimos olhar para ele.
ARQUIVOS=$("$RCLONE" size "$BACKUP_DESTINO/atual" "${CACERT_ARGS[@]}" --json 2>/dev/null | sed -n 's/.*"count":\([0-9]*\).*/\1/p')
registrar "total no backup: ${ARQUIVOS:-?} arquivos"

if [ ${#FALHAS[@]} -gt 0 ] || [ -z "$ARQUIVOS" ]; then
  MSG="${TESTE}⚠️ Aviso do backup ($HOJE): deu FALHA."
  [ ${#FALHAS[@]} -gt 0 ] && MSG="$MSG

Não foram copiadas: ${FALHAS[*]}"
  [ -z "$ARQUIVOS" ] && MSG="$MSG

Não consegui contar os arquivos no destino do backup."
  [ -n "$PRIMEIRO_ERRO" ] && MSG="$MSG

Erro: $PRIMEIRO_ERRO"
  MSG="$MSG

O que já estava no backup continua lá. Detalhes em logs/backup.log. Me chama que eu olho."
  avisar "$MSG"
fi

registrar "=== backup terminado ==="
[ ${#FALHAS[@]} -eq 0 ] && [ -n "$ARQUIVOS" ]
