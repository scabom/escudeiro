#!/bin/bash
# Preenche os modelos de LaunchAgent desta pasta e (opcionalmente) liga no macOS.
#
# Uso:
#   bash mac/launchd/instalar-launchd.sh <pasta do agente> [rotinas...]   → só mostra o que faria
#   bash mac/launchd/instalar-launchd.sh <pasta do agente> --ligar [rotinas...]
#
# Rotinas: bom-dia backup confere-backup vigia-atrasos (padrão: todas).
# Horários (variáveis de ambiente, opcionais):
#   HORA_BOM_DIA=7 MINUTO_BOM_DIA=10 HORA_BACKUP=22 MINUTO_BACKUP=0 HORA_CONFERE=22 MINUTO_CONFERE=40
# Rótulo: ROTULO=com.escudeiro.<nome-da-pasta-em-minúsculas> (padrão).
#
# Para desligar uma rotina depois:
#   launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/<rótulo>.<rotina>.plist
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
PASTA="${1:-}"
[ -n "$PASTA" ] && [ -d "$PASTA" ] || { echo "uso: $0 <pasta do agente> [--ligar] [rotinas...]"; exit 1; }
PASTA="$(cd "$PASTA" && pwd)"
shift
LIGAR=0
[ "${1:-}" = "--ligar" ] && { LIGAR=1; shift; }
ROTINAS=("$@")
[ ${#ROTINAS[@]} -gt 0 ] || ROTINAS=(bom-dia backup confere-backup vigia-atrasos)

BASE=$(basename "$PASTA" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-')
ROTULO="${ROTULO:-com.escudeiro.$BASE}"
DESTINO="$HOME/Library/LaunchAgents"
mkdir -p "$PASTA/logs"

for r in "${ROTINAS[@]}"; do
  modelo="$AQUI/$r.plist.modelo"
  [ -f "$modelo" ] || { echo "❌ não existe modelo para '$r'"; continue; }
  saida="$DESTINO/$ROTULO.$r.plist"
  texto=$(sed -e "s|{{ROTULO}}|$ROTULO|g" -e "s|{{PASTA_AGENTE}}|$PASTA|g" -e "s|{{HOME}}|$HOME|g" \
              -e "s|{{HORA_BOM_DIA}}|${HORA_BOM_DIA:-7}|g" -e "s|{{MINUTO_BOM_DIA}}|${MINUTO_BOM_DIA:-10}|g" \
              -e "s|{{HORA_BACKUP}}|${HORA_BACKUP:-22}|g" -e "s|{{MINUTO_BACKUP}}|${MINUTO_BACKUP:-0}|g" \
              -e "s|{{HORA_CONFERE}}|${HORA_CONFERE:-22}|g" -e "s|{{MINUTO_CONFERE}}|${MINUTO_CONFERE:-40}|g" "$modelo")
  if [ "$LIGAR" = "0" ]; then
    echo "→ criaria $saida"
    continue
  fi
  printf '%s\n' "$texto" > "$saida"
  plutil -lint "$saida" >/dev/null || { echo "❌ plist inválido: $saida"; continue; }
  launchctl bootout "gui/$(id -u)" "$saida" 2>/dev/null
  if launchctl bootstrap "gui/$(id -u)" "$saida"; then echo "✅ ligado: $ROTULO.$r"
  else echo "❌ não consegui ligar $saida (veja: launchctl print gui/$(id -u)/$ROTULO.$r)"; fi
done
[ "$LIGAR" = "0" ] && echo "(só mostrei. Para criar e ligar de verdade, rode de novo com --ligar)"
exit 0
