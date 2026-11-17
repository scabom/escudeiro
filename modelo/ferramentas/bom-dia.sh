#!/bin/bash
# BOM-DIA — o "estado da casa", todo dia de manhã, pelo Telegram.
#
# A ideia: o dono COMEÇA o dia sabendo, em vez de supondo. Um agente que pode
# ter caído durante a noite sem ninguém saber é um agente em que não dá para
# confiar; este recado existe para acabar com essa dúvida.
#
# É de propósito um despertador próprio (LaunchAgent, veja mac/launchd/ no
# pacote), e não uma tarefa do agente: se o agente estiver fora do ar, este
# recado chega do mesmo jeito, e conta que ele está fora.
#
# O que ele diz:
#   1. o backup da noite rodou E deu certo? (se o backup estiver configurado)
#   2. alguma rotina vigiada atrasou? (vigia-atrasos.py)
#   3. o agente está de pé agora? o Mac está na bateria?
#   4. os lembretes com data (lembretes.txt), em três blocos curtos
#   5. lembretes avulsos (lembretes-avulsos.txt, opcional): um por mensagem
#
# Teste sem enviar:  SEM_ENVIO=1 bash bom-dia.sh
#
# Código de saída (o rotina-vigiada.sh conta como falha tudo o que não for 0):
#   0  tudo entregue (ou SEM_ENVIO=1)
#   1  alguma parte do bom-dia ou algum lembrete avulso NÃO foi entregue

. "$(dirname "$0")/comum.sh"
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$LOGS/bom-dia.log"
LOG_BK="$LOGS/backup.log"
registrar() { registrar_em "$LOG" "$*"; }

HOJE=$(date '+%Y-%m-%d')
ONTEM=$(date -v-1d '+%Y-%m-%d' 2>/dev/null || date -d yesterday '+%Y-%m-%d' 2>/dev/null)
PROBLEMAS=""

# ---------- 1. o backup rodou E DEU CERTO? ----------
# Lição: "terminou" e "deu certo" não são a mesma pergunta. O backup escreve
# "backup terminado" SEMPRE, inclusive quando todas as cópias falham. Olhar só
# essa linha produz um "Backup: feito" falso, justo no recado que existe para o
# dono não ter de adivinhar. Por isso conta também as linhas FALHOU do dia.
if [ -n "$BACKUP_DESTINO" ]; then
  BK=$(grep "backup terminado" "$LOG_BK" 2>/dev/null | grep -v TESTE | tail -1 | awk '{print $1" "$2}')
  BK_DIA=$(echo "$BK" | awk '{print $1}')
  BK_FALHAS=$(awk -v d="$BK_DIA" '$1==d && /FALHOU/ && !/TESTE/' "$LOG_BK" 2>/dev/null | wc -l | tr -dc '0-9')
  if [ "$BK_DIA" = "$HOJE" ] || [ "$BK_DIA" = "$ONTEM" ]; then
    if [ "${BK_FALHAS:-0}" -gt 0 ]; then
      LINHA_BK="Backup: FALHOU em ${BK_FALHAS} parte(s) na última tentativa ($(echo "$BK_DIA" | cut -c9,10)/$(echo "$BK_DIA" | cut -c6,7)). Seus arquivos NÃO subiram."
    else
      LINHA_BK="Backup: feito ($(echo "$BK" | awk '{print $2}' | cut -c1-5) de $(echo "$BK_DIA" | cut -c9,10)/$(echo "$BK_DIA" | cut -c6,7))"
    fi
  else
    LINHA_BK="Backup: NÃO RODOU, o último foi em ${BK_DIA:-nunca}. Precisa de olho."
  fi
else
  LINHA_BK="Backup: ainda não configurado (BACKUP_DESTINO no escudeiro.conf)."
fi

# ---------- 2. rotinas atrasadas ----------
ATRASOS=$(/usr/bin/python3 -I "$DIR/vigia-atrasos.py" --bom-dia 2>/dev/null || true)
[ -n "$ATRASOS" ] && PROBLEMAS="${PROBLEMAS}${ATRASOS}; "
# E quem vigia o vigia: se ele está instalado mas não confere há mais de 2 h, conta.
VIGIA_LOG="$LOGS/rotinas/vigia-atrasos.log"
if [ -f "$VIGIA_LOG" ]; then
  ULT_VIGIA=$(grep "conferi;" "$VIGIA_LOG" 2>/dev/null | tail -1 | cut -c1-19)
  if [ -z "$ULT_VIGIA" ] || [ $(( $(date +%s) - $(date -j -f '%Y-%m-%d %H:%M:%S' "$ULT_VIGIA" +%s 2>/dev/null || echo 0) )) -gt 7200 ]; then
    PROBLEMAS="${PROBLEMAS}o vigia de rotinas atrasadas não confere desde ${ULT_VIGIA:-nunca}; "
  fi
fi

# ---------- 3. como está a casa agora ----------
# O agente está de pé? Claude Code com o canal do Telegram, ou a ponte do Codex.
if ! pgrep -f "channels plugin:telegram" >/dev/null 2>&1 && ! pgrep -f "ponte.mjs" >/dev/null 2>&1; then
  PROBLEMAS="${PROBLEMAS}${NOME_AGENTE} não está rodando (nem o Claude com o Telegram, nem a ponte do Codex); "
fi
pmset -g batt 2>/dev/null | head -1 | grep -q "Battery Power" && PROBLEMAS="${PROBLEMAS}o Mac está na bateria; "

# ---------- 4. lembretes com data ----------
# Peça isolada: se o script de lembretes falhar, o bom-dia sai do mesmo jeito.
LEMBRETES=$(bash "$DIR/lembretes.sh" 2>/dev/null || true)
# BOM-DIA ENXUTO: lista corrida comprida ninguém lê de manhã. Três blocos curtos:
#   📌 HOJE · 📅 ESTA SEMANA (até 7 dias) · ⏳ Esperando você (os ATRASADO viram
#   UMA linha com o número; a lista completa vai quando o dono pedir).
# Cada item fica só com a 1ª frase, no máximo 90 caracteres.
BLOCO_LEMBRETES=$(printf '%s' "$LEMBRETES" | /usr/bin/python3 -I -c '
import re, sys
hoje, semana, esperando = [], [], []
def curto(t):
    t = t.strip()
    m = re.search(r"(?<!\bDr)(?<!\bDra)(?<!\bProf)(?<!\bSr)(?<!\bSra)\. ", t)
    if m and m.start() <= 90: t = t[:m.start()]
    return t if len(t) <= 90 else t[:87] + "..."
for l in sys.stdin.read().splitlines():
    if " — " not in l: continue
    tipo, texto = l.split(" — ", 1)
    if tipo.startswith("ATRASADO"):
        esperando.append(curto(texto))
    elif tipo.startswith("Em "):
        m = re.match(r"Em (\d+) dias? \((\d\d/\d\d)\)", tipo)
        if m and int(m.group(1)) <= 7: semana.append((int(m.group(1)), m.group(2) + " " + curto(texto)))
    else:
        hoje.append(curto(texto))
out = []
if hoje: out += ["", "📌 HOJE"] + ["• " + t for t in hoje]
if semana: out += ["", "📅 ESTA SEMANA"] + ["• " + t for _, t in sorted(semana)]
if esperando: out += ["", "⏳ Esperando você (%d): me pede \"me lista os atrasados\" que eu mando tudo" % len(esperando)]
print("\n".join(out))
' 2>/dev/null || printf '\nLembretes:\n%s' "$LEMBRETES")

# ---------- 5. lembretes AVULSOS (opcional) ----------
# Mesmo formato do lembretes.txt, mas cada um que vencer sai numa MENSAGEM
# PRÓPRIA, curta, depois do bom-dia (para o que não pode se perder no meio).
AVULSOS=""
[ -f "$PASTA/lembretes-avulsos.txt" ] && \
  AVULSOS=$(LEMBRETES_ARQUIVO="$PASTA/lembretes-avulsos.txt" bash "$DIR/lembretes.sh" 2>/dev/null || true)

# ---------- monta a mensagem ----------
# "Tudo em ordem" só pode ser dito quando está TUDO em ordem mesmo. Falsa
# tranquilidade é exatamente o que este recado existe para acabar.
SAUDACAO="Bom dia${NOME_DONO:+, $NOME_DONO}! ☀️ Estado da casa em $(date '+%d/%m'):"
TUDO_BEM=sim
case "$LINHA_BK" in *"NÃO RODOU"*|*"FALHOU"*) TUDO_BEM=nao ;; esac
[ -z "$PROBLEMAS" ] || TUDO_BEM=nao
if [ -n "$PROBLEMAS" ]; then
  FECHO="ATENÇÃO agora: ${PROBLEMAS%%; }.
Me chama que eu olho isso."
elif [ "$TUDO_BEM" = "nao" ]; then
  FECHO="Não está tudo redondo, como você vê acima. Me chama quando puder que eu cuido disso hoje."
else
  FECHO="Tudo em ordem por aqui. Bom dia! 💛"
fi

TEXTO="${SAUDACAO}

${LINHA_BK}
${BLOCO_LEMBRETES:+$BLOCO_LEMBRETES
}
${FECHO}"

if [ "$SEM_ENVIO" = "1" ]; then
  echo "--- MENSAGEM QUE SERIA ENVIADA ---"; echo "$TEXTO"; echo "--- fim ---"
  [ -n "$AVULSOS" ] && { echo "--- AVULSOS (uma mensagem cada) ---"; echo "$AVULSOS"; }
  exit 0
fi

# ---------- envia ----------
# ⚠️ LIMITE DO TELEGRAM: 4096 "caracteres" contados em UTF-16 (emoji conta 2).
# Cortar com `cut -c` não serve: no Mac ele conta BYTES. Em vez de cortar, divide
# em várias mensagens por linha (até 3500 unidades cada); se alguma parte falhar,
# manda um aviso curto, para a falha nunca ser silenciosa.
PARTES_DIR=$(mktemp -d)
printf '%s' "$TEXTO" | /usr/bin/python3 -I -c '
import sys
dir_ = sys.argv[1]
texto = sys.stdin.read()
u = lambda s: len(s.encode("utf-16-le")) // 2
partes, atual = [], ""
for linha in texto.split("\n"):
    while u(linha) > 3500:
        if atual: partes.append(atual)
        atual = ""
        partes.append(linha[:1700]); linha = linha[1700:]
    if atual and u(atual) + 1 + u(linha) > 3500:
        partes.append(atual); atual = linha
    else:
        atual = linha if not atual else atual + "\n" + linha
if atual.strip(): partes.append(atual)
for i, p in enumerate(partes):
    open("%s/%02d" % (dir_, i), "w", encoding="utf-8").write(p)
' "$PARTES_DIR"
N_PARTES=$(ls "$PARTES_DIR" | wc -l | tr -dc '0-9')
FALHAS=0
for f in "$PARTES_DIR"/*; do
  [ -f "$f" ] || continue
  if ! ERRO=$(avisar_telegram "$(cat "$f")" 2>&1); then
    FALHAS=$((FALHAS+1)); registrar "PARTE $(basename "$f") NAO ENTREGUE: $ERRO"
  fi
  sleep 1
done
rm -rf "$PARTES_DIR"
if [ "$FALHAS" = "0" ]; then
  registrar "bom-dia entregue em $N_PARTES parte(s), ${#TEXTO} caracteres"
else
  registrar "BOM-DIA NAO ENTREGUE: $FALHAS de $N_PARTES parte(s) falharam"
  avisar_telegram "⚠️ Bom dia! O estado da casa de hoje falhou na entrega ($FALHAS de $N_PARTES partes). Me chama que eu te conto o que tinha." >/dev/null 2>&1
fi

# ---------- lembretes avulsos: um por mensagem ----------
# Sem pipe para o while: num pipe o laço roda num subshell e a contagem de
# falhas se perderia (o bom-dia sairia "ok" com lembrete não entregue).
FALHAS_AV=0
if [ -n "$AVULSOS" ]; then
  while IFS= read -r av; do
    [ -n "$av" ] || continue
    sleep 3
    if avisar_telegram "🔔 ${av}" 2>/dev/null; then
      registrar "lembrete avulso entregue"
    else
      FALHAS_AV=$((FALHAS_AV+1))
      registrar "LEMBRETE AVULSO NAO ENTREGUE"
    fi
  done <<< "$AVULSOS"
fi
[ "$FALHAS" = "0" ] && [ "$FALHAS_AV" = "0" ]
