#!/bin/bash
# Lê lembretes.txt e imprime os que já entraram na janela de aviso.
#
# POR QUE ASSIM, e não com tarefa agendada:
# um lembrete para daqui a meses, feito como tarefa única, é frágil: o
# computador precisa estar ligado naquele minuto exato, e agendamento
# repetitivo pode parar de rodar em silêncio.
# Aqui o mecanismo é outro: um arquivo de texto que o bom-dia lê TODA manhã.
# Se um dia falhar, no dia seguinte avisa de novo. E se a data passar sem
# ninguém ver, ele insiste marcando ATRASADO em vez de esquecer.
#
# Uso:   bash lembretes.sh            → só o que precisa ser dito hoje
#        bash lembretes.sh --todos    → tudo o que está agendado
#
# Sai vazio (e com código 0) quando não há nada a dizer: assim o bom-dia
# pode chamá-lo sem risco de sujar a mensagem.
#
# TRÊS FORMATOS DE LINHA:
#   AAAA-MM-DD | antecedência | texto   → data única (avisa ANTES; depois insiste ATRASADO)
#   MENSAL:15  | tolerância   | texto   → todo mês no dia 15
#   ACADA:2:AAAA-MM-DD | 0    | texto   → a cada 2 dias, a partir da data
#
# Por que o mensal existe: com data única, "todo dia 15" seriam 12 linhas por
# ano, e cada uma, depois de passar, ficaria gritando ATRASADO para sempre. No
# mensal, o segundo campo é a TOLERÂNCIA: quantos dias DEPOIS do dia 15 ele
# continua lembrando (para o caso de o computador estar desligado no dia 15).
#
# Outro arquivo:  LEMBRETES_ARQUIVO=/caminho/outro.txt bash lembretes.sh
# TESTE sem esperar o calendário:  LEMBRETES_HOJE=2030-01-15 bash lembretes.sh
#
# Feito para o macOS (usa o `date -j` do BSD). Linux fica para a v1.1.

ARQ="${LEMBRETES_ARQUIVO:-$(cd "$(dirname "$0")/.." && pwd)/lembretes.txt}"
TODOS="${1:-}"

# ⚠️ ANCORAR TUDO NA MEIA-NOITE (bug silencioso já visto na prática).
# O `date -j -f "%Y-%m-%d"` do macOS NÃO zera a hora quando o formato não tem
# hora: ele completa com a HORA ATUAL do instante em que roda. Se o "hoje" é
# pego uma vez e o alvo de cada linha é calculado depois, uma linha processada
# 1 segundo mais tarde dá -86399 em vez de -86400, e a divisão inteira trunca
# para 0: lembrete de ONTEM aparece como "É HOJE". Sintoma: linhas com a MESMA
# data saindo diferentes na mesma execução.
# Com as duas pontas fixadas em 00:00:00 a conta vira múltiplo exato de 86400.
meia_noite() { date -j -f "%Y-%m-%d %H:%M:%S" "$1 00:00:00" "+%s" 2>/dev/null; }
HOJE_TXT="${LEMBRETES_HOJE:-$(date +%Y-%m-%d)}"
HOJE_S=$(meia_noite "$HOJE_TXT")
HOJE_DIA=$((10#$(printf %s "$HOJE_TXT" | cut -d- -f3)))

[ -f "$ARQ" ] || exit 0

while IFS= read -r linha || [ -n "$linha" ]; do
  case "$linha" in ''|'#'*) continue ;; esac

  data=$(printf '%s' "$linha" | cut -d'|' -f1 | tr -d ' ')
  antec=$(printf '%s' "$linha" | cut -d'|' -f2 | tr -d ' ')
  texto=$(printf '%s' "$linha" | cut -d'|' -f3- | sed 's/^ *//')
  # ⚠️ O BOM-DIA TEM LIMITE: o Telegram recusa mensagem acima de 4096
  # caracteres ("message is too long"), e um bom-dia recusado some em silêncio.
  # Lembrete tende a virar dossiê (comando, caminho, justificativa): ótimo como
  # nota, péssimo como mensagem de manhã.
  # Então aqui o texto é ENCURTADO: vai até o primeiro ponto final, no máximo
  # 150 caracteres. O texto inteiro continua no lembretes.txt.
  # Abreviaturas com ponto ("Dr. ", "Dra. ", "Prof. ") não contam como fim de
  # frase: o ponto vira ¤ durante a busca e volta depois.
  texto=$(printf '%s' "$texto" | awk '{
      gsub(/Dra\. /, "Dra¤ "); gsub(/Dr\. /, "Dr¤ "); gsub(/Prof\. /, "Prof¤ ");
      gsub(/Sra\. /, "Sra¤ "); gsub(/Sr\. /, "Sr¤ ");
      n = index($0, ". ");
      gsub(/¤/, ".");
      s = (n > 0 && n <= 150) ? substr($0, 1, n) : $0;
      if (length(s) > 150) s = substr(s, 1, 147) "...";
      print s
  }')

  # --- lembrete MENSAL (MENSAL:15) ---
  case "$data" in
    MENSAL:*)
      dia=${data#MENSAL:}
      case "$dia" in ''|*[!0-9]*) continue ;; esac
      [ -n "$texto" ] || continue
      case "$antec" in ''|*[!0-9]*) antec=2 ;; esac
      if [ "$TODOS" = "--todos" ]; then
        printf 'todo dia %s (tolerância %s dias) — %s\n' "$dia" "$antec" "$texto"
        continue
      fi
      depois=$(( HOJE_DIA - 10#$dia ))
      if [ "$depois" -eq 0 ]; then
        printf 'É HOJE (todo dia %s) — %s\n' "$dia" "$texto"
      elif [ "$depois" -gt 0 ] && [ "$depois" -le "$antec" ]; then
        [ "$depois" -eq 1 ] && unid=dia || unid=dias
        printf 'Lembrete do dia %s (há %s %s) — %s\n' "$dia" "$depois" "$unid" "$texto"
      fi
      continue ;;
  esac

  # --- lembrete A CADA N DIAS (ACADA:2:AAAA-MM-DD) ---
  # Começa na data, repete a cada N dias e só para quando a linha for apagada.
  # Nunca fica ATRASADO. O 2º campo não é usado. O texto vai INTEIRO (sem o
  # corte de 150): costuma ser o próprio recado.
  case "$data" in
    ACADA:*)
      n=$(printf '%s' "$data" | cut -d: -f2)
      inicio=$(printf '%s' "$data" | cut -d: -f3)
      case "$n" in ''|*[!0-9]*|0) continue ;; esac
      ini_s=$(meia_noite "$inicio") || continue
      [ -n "$ini_s" ] || continue
      texto_inteiro=$(printf '%s' "$linha" | cut -d'|' -f3- | sed 's/^ *//')
      [ -n "$texto_inteiro" ] || continue
      if [ "$TODOS" = "--todos" ]; then
        printf 'a cada %s dias desde %s — %s\n' "$n" "$inicio" "$texto"
        continue
      fi
      desde=$(( (HOJE_S - ini_s) / 86400 ))
      if [ "$desde" -ge 0 ] && [ $(( desde % n )) -eq 0 ]; then
        printf 'Lembrete (a cada %s dias) — %s\n' "$n" "$texto_inteiro"
      fi
      continue ;;
  esac

  # data inválida ou linha malformada: ignora em silêncio, nunca quebra o bom-dia
  alvo_s=$(meia_noite "$data") || continue
  [ -n "$alvo_s" ] || continue
  [ -n "$texto" ] || continue
  case "$antec" in ''|*[!0-9]*) antec=7 ;; esac

  faltam=$(( (alvo_s - HOJE_S) / 86400 ))

  if [ "$TODOS" = "--todos" ]; then
    printf '%s (faltam %s dias) — %s\n' "$data" "$faltam" "$texto"
    continue
  fi

  if [ "$faltam" -lt 0 ]; then
    [ "$(( -faltam ))" -eq 1 ] && unid=dia || unid=dias
    printf 'ATRASADO desde %s (%s %s) — %s\n' \
      "$(date -j -f "%Y-%m-%d" "$data" "+%d/%m/%Y" 2>/dev/null)" "$(( -faltam ))" "$unid" "$texto"
  elif [ "$faltam" -le "$antec" ]; then
    if [ "$faltam" -eq 0 ]; then
      printf 'É HOJE — %s\n' "$texto"
    else
      printf 'Em %s dias (%s) — %s\n' \
        "$faltam" "$(date -j -f "%Y-%m-%d" "$data" "+%d/%m" 2>/dev/null)" "$texto"
    fi
  fi
done < "$ARQ"
