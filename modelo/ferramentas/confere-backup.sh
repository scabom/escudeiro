#!/bin/bash
# Confere o backup — a "segunda ronda".
#
# O backup.sh já confere a si mesmo (contagem no destino + aviso de falha). Isto é OUTRO
# par de olhos, que roda separado (uns 40 minutos depois) e não confia no que o backup disse de si:
#   1. O backup rodou hoje? (o canário local tem a data de hoje)
#   2. O que ele disse que subiu, subiu mesmo? (o canário lido DE VOLTA do destino é igual ao local)
# Se algo não bate, avisa no Telegram. Se está tudo certo, só anota no log (silêncio = ok).
#
# O canário é um arquivinho sem dado nenhum (data e hora do backup), gravado pelo backup.sh
# antes de subir, em <pasta do agente>/logs/backup-canario.txt.
#
# Uso:  bash ferramentas/confere-backup.sh
# Teste do aviso (não mexe em nada): CONFERE_TESTE_DESTINO="remote-que-nao-existe:x" bash ferramentas/confere-backup.sh

. "$(dirname "$0")/comum.sh"
RCLONE="${RCLONE:-$(command -v rclone || echo "$HOME/.local/bin/rclone")}"
TESTE=""
if [ -n "$CONFERE_TESTE_DESTINO" ]; then BACKUP_DESTINO="$CONFERE_TESTE_DESTINO"; TESTE="[TESTE] "; fi
[ -n "$BACKUP_DESTINO" ] || { echo "backup desligado: nada a conferir"; exit 0; }
CANARIO="$PASTA/logs/backup-canario.txt"
REMOTO_CANARIO="$BACKUP_DESTINO/atual/$(basename "$PASTA")/logs/backup-canario.txt"
BACKUP_LOG="$LOGS/backup.log"
LOG="$LOGS/confere-backup.log"
HOJE=$(date +%Y-%m-%d)
registrar() { registrar_em "$LOG" "${TESTE}$*"; }
CACERT_ARGS=()
[ -n "$RCLONE_CACERT" ] && [ -f "$RCLONE_CACERT" ] && CACERT_ARGS=(--ca-cert "$RCLONE_CACERT")

# Se o Mac estava desligado na hora, o launchd dispara o backup e esta conferência juntos quando
# ele liga. Então: backup começou hoje e ainda não terminou? Espera (até 45 min) em vez de acusar.
ESPERAS=45; [ -n "$TESTE" ] && ESPERAS=0
while [ "$ESPERAS" -gt 0 ]; do
  ESPERAS=$((ESPERAS - 1))
  INICIO=$(grep -c "^$HOJE .*=== backup iniciado ===" "$BACKUP_LOG" 2>/dev/null)
  FIM=$(grep -c "^$HOJE .*=== backup terminado ===" "$BACKUP_LOG" 2>/dev/null)
  [ "${INICIO:-0}" -gt 0 ] && [ "${FIM:-0}" -ge "${INICIO:-0}" ] && break
  sleep 60
done

PROBLEMAS=()
LOCAL=$(cat "$CANARIO" 2>/dev/null)
case "$LOCAL" in
  "$HOJE "*) ;;
  *) PROBLEMAS+=("o backup de hoje não rodou (o último foi: ${LOCAL:-nenhum registro})") ;;
esac

if [ ${#PROBLEMAS[@]} -eq 0 ]; then
  REMOTO=$("$RCLONE" cat "$REMOTO_CANARIO" "${CACERT_ARGS[@]}" 2>/dev/null)
  if [ -z "$REMOTO" ]; then
    PROBLEMAS+=("não consegui ler a marca do backup de volta no destino")
  elif [ "$REMOTO" != "$LOCAL" ]; then
    PROBLEMAS+=("o destino está com a marca de outro backup ($REMOTO), e não com a de hoje ($LOCAL)")
  fi
fi

if [ ${#PROBLEMAS[@]} -eq 0 ]; then
  registrar "OK: backup de hoje conferido no destino ($LOCAL)"
  exit 0
fi

registrar "PROBLEMA: ${PROBLEMAS[*]}"
MSG="${TESTE}🔎 Conferência do backup ($HOJE): algo não bateu.

$(printf '• %s\n' "${PROBLEMAS[@]}")

O que já estava no backup continua lá. Me chama que eu olho (logs em logs/ na pasta do agente)."
if ERRO=$(avisar_telegram "$MSG" 2>&1); then registrar "aviso entregue no telegram"
else registrar "AVISO NAO ENTREGUE: $ERRO"; fi
exit 0
