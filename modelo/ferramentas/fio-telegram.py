#!/usr/bin/env python3
"""
O fio do Telegram — hook UserPromptSubmit.

PROBLEMA QUE ELE RESOLVE
Quando a conversa fica longa, o sistema compacta e eu perco o texto original
da conversa. Hoje meu CLAUDE.md manda eu ir caçar o transcript no disco pra
lembrar onde paramos. Isso é lento, gasta contexto e às vezes eu nem percebo
que compactou.

Este hook injeta, antes de eu responder, as últimas mensagens REAIS da conversa
do Telegram: as dele e as minhas. Assim os dois lemos a mesma coisa.

Ideia emprestada do THREAD-HOOK do DG Claw (MIT), reescrita do zero e enxuta:
sem state file, sem variável de ambiente obrigatória, sem biblioteca externa.

REGRA DE OURO: nunca quebrar a conversa. Qualquer erro, qualquer ausência,
qualquer dúvida → sai calado com código 0. Um hook que falha alto me deixaria
mudo: o pior defeito possível para um agente de conversa.
"""

import json
import os
import sys
from datetime import datetime, timedelta, timezone

QUANTAS = int(os.environ.get("FIO_QUANTAS", "12"))       # mensagens a injetar
JANELA_H = int(os.environ.get("FIO_JANELA_H", "12"))     # só as últimas N horas
CORTE = int(os.environ.get("FIO_CORTE", "400"))          # corte por mensagem
MARCA = "<channel source="


def nomes():
    """Nome do dono e do agente, do escudeiro.conf (se houver)."""
    dono, agente = "Dono", "Agente"
    conf = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "escudeiro.conf")
    try:
        with open(conf, encoding="utf-8") as f:
            for linha in f:
                chave, _, valor = linha.strip().partition("=")
                valor = valor.strip().strip('"').strip("'")
                if not valor or "{{" in valor:
                    continue
                if chave == "NOME_DONO":
                    dono = valor
                elif chave == "NOME_AGENTE":
                    agente = valor
    except OSError:
        pass
    return dono, agente


def limpar(txt):
    """Tira a meta <channel ...> e deixa só o que ele escreveu."""
    if MARCA in txt:
        fim = txt.find(">", txt.find(MARCA))
        if fim != -1:
            txt = txt[fim + 1:]
        if "</channel>" in txt:
            txt = txt.split("</channel>")[0]
    return " ".join(txt.split())


def quando(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None


def ler_fio(caminho):
    """Devolve [(hora, quem, texto)] — o dele e o meu, em ordem de tempo."""
    dono, agente = nomes()
    fio = []
    with open(caminho, encoding="utf-8") as f:
        for linha in f:
            try:
                d = json.loads(linha)
            except Exception:
                continue
            tipo = d.get("type")
            msg = d.get("message") or {}
            corpo = msg.get("content")
            hora = quando(d.get("timestamp") or "")
            if hora is None:
                continue

            # o que ELE mandou pelo Telegram
            if tipo == "user" and isinstance(corpo, str) and MARCA in corpo:
                texto = limpar(corpo)
                if texto:
                    fio.append((hora, dono, texto))

            # o que EU mandei de volta pelo reply
            elif tipo == "assistant" and isinstance(corpo, list):
                for bloco in corpo:
                    if not isinstance(bloco, dict):
                        continue
                    if bloco.get("type") != "tool_use":
                        continue
                    nome = str(bloco.get("name", ""))
                    if "telegram" not in nome or "reply" not in nome:
                        continue
                    texto = " ".join(
                        str(bloco.get("input", {}).get("text", "")).split()
                    )
                    if texto:
                        fio.append((hora, agente, texto))
    return fio


def main():
    try:
        entrada = json.load(sys.stdin)
    except Exception:
        return

    # só faz sentido quando a mensagem veio mesmo do canal
    if MARCA not in (entrada.get("prompt") or ""):
        return

    caminho = entrada.get("transcript_path") or ""
    if not caminho or not os.path.exists(caminho):
        return

    fio = ler_fio(caminho)
    if not fio:
        return

    limite = datetime.now(timezone.utc) - timedelta(hours=JANELA_H)
    fio = [x for x in fio if x[0] >= limite]
    fio.sort(key=lambda x: x[0])
    fio = fio[-QUANTAS:]
    if not fio:
        return

    linhas = ["📱 O FIO REAL DO TELEGRAM (o que ele está vendo na tela dele):", ""]
    for hora, quem, texto in fio:
        if len(texto) > CORTE:
            texto = texto[:CORTE] + "…"
        linhas.append(f"[{hora.astimezone().strftime('%d/%m %H:%M')}] {quem}: {texto}")
    linhas += [
        "",
        "Isto é o histórico verdadeiro do chat, não a minha lembrança dele. "
        "Se meu contexto foi compactado, é aqui que está o fio da conversa.",
    ]

    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "UserPromptSubmit",
            "additionalContext": "\n".join(linhas),
        }
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # regra de ouro: falhar calada
    sys.exit(0)
