#!/usr/bin/env python3
"""Vigia de rotina ATRASADA — avisa quando uma rotina vigiada deveria ter rodado e não rodou.

Ideia inspirada no Hermes Agent ("OVERDUE"; NousResearch, MIT; só a ideia, código próprio).
Completa o rotina-vigiada.sh: aquele pega a rotina que roda e FALHA; este pega a que nem rodou
(Mac dormindo/desligado, launchd que não disparou, plist quebrado).

Como funciona:
- Lê os LaunchAgents (~/Library/LaunchAgents/*.plist) embrulhados pelo rotina-vigiada.sh DESTA
  pasta de agente e a agenda de cada um (StartCalendarInterval ou StartInterval).
- Calcula quando foi o último disparo ESPERADO e compara com o último "início" no log
  <pasta do agente>/logs/rotinas/<nome>.log.
- Atrasada (passou da tolerância): UM aviso por incidente, lembrete a cada 6 h.
  Voltou a rodar: avisa e encerra o incidente. Pausada de propósito (.pausada): ignora.
- Só cobra disparos depois que a rotina passou a ser vigiada (não acusa o passado).

Uso:  python3 vigia-atrasos.py            (rodado pelo LaunchAgent a cada 30 min)
      python3 vigia-atrasos.py --teste    (mostra o que faria, sem enviar nada)
      python3 vigia-atrasos.py --bom-dia  (uma linha pro bom-dia; vazio se está tudo em dia)
"""
import glob
import json
import os
import plistlib
import re
import sys
import subprocess
from datetime import datetime, timedelta

AQUI = os.path.dirname(os.path.abspath(__file__))
PASTA = os.path.dirname(AQUI)
LAUNCH = os.path.join(os.path.expanduser("~"), "Library/LaunchAgents")
LOGS = os.path.join(PASTA, "logs", "rotinas")
ESTADO = os.path.join(PASTA, "logs", "estado")
EMBRULHO = os.path.realpath(os.path.join(AQUI, "rotina-vigiada.sh"))


def nome_agente():
    try:
        with open(os.path.join(PASTA, "escudeiro.conf"), encoding="utf-8") as fh:
            for l in fh:
                k, _, v = l.strip().partition("=")
                v = v.strip().strip('"').strip("'")
                if k == "NOME_AGENTE" and v and "{{" not in v:
                    return v
    except OSError:
        pass
    return "seu agente"


ASSINA = nome_agente()
TOLERANCIA_AGENDA = timedelta(minutes=45)   # launchd dispara ao acordar; rotina pode demorar a logar
LEMBRETE = timedelta(hours=6)
TESTE = "--teste" in sys.argv
SO_LER = TESTE or "--bom-dia" in sys.argv  # bom-dia só lê: quem avisa é a rodada de 30 em 30 min


def rotinas_vigiadas():
    for f in sorted(glob.glob(os.path.join(LAUNCH, "*.plist"))):
        try:
            with open(f, "rb") as fh:
                d = plistlib.load(fh)
        except Exception:
            continue
        args = d.get("ProgramArguments") or []
        # Só as rotinas embrulhadas pelo rotina-vigiada.sh DESTA pasta (pode haver outros agentes).
        if len(args) < 3 or os.path.realpath(os.path.expanduser(str(args[1]))) != EMBRULHO:
            continue
        yield args[2], d, f


def ultimo_inicio(nome):
    try:
        with open(os.path.join(LOGS, nome + ".log"), encoding="utf-8") as fh:
            linhas = [l for l in fh if l.rstrip().endswith(" início")]
        if linhas:
            return datetime.strptime(linhas[-1][:19], "%Y-%m-%d %H:%M:%S")
    except OSError:
        pass
    return None


def casa_agenda(dt, item):
    # launchd: Weekday 0 ou 7 = domingo; Python: segunda=0 ... domingo=6
    wd = (dt.weekday() + 1) % 7
    for chave, valor in (("Minute", dt.minute), ("Hour", dt.hour), ("Day", dt.day), ("Month", dt.month)):
        if chave in item and item[chave] != valor:
            return False
    if "Weekday" in item and item["Weekday"] % 7 != wd:
        return False
    return True


def ultimo_esperado(d, agora):
    """Último horário em que a rotina deveria ter disparado, e a tolerância pra ela."""
    if "StartInterval" in d:
        # Rotina de intervalo: atrasada se não deu "início" nos últimos 10 intervalos (mín. 15 min).
        intervalo = timedelta(seconds=int(d["StartInterval"]))
        return agora - max(intervalo * 10, timedelta(minutes=15)), timedelta(0)
    agenda = d.get("StartCalendarInterval")
    if not agenda:
        return None, None
    itens = agenda if isinstance(agenda, list) else [agenda]
    t = agora.replace(second=0, microsecond=0)
    for _ in range(60 * 24 * 32):  # olha até ~1 mês pra trás, minuto a minuto
        if any(casa_agenda(t, i) for i in itens):
            return t, TOLERANCIA_AGENDA
        t -= timedelta(minutes=1)
    return None, None


def ler_estado(nome):
    try:
        with open(os.path.join(ESTADO, nome + ".atraso.json")) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def gravar_estado(nome, dados):
    caminho = os.path.join(ESTADO, nome + ".atraso.json")
    if dados:
        with open(caminho, "w") as fh:
            json.dump(dados, fh)
    elif os.path.exists(caminho):
        os.remove(caminho)


def avisar(texto):
    if SO_LER:
        if TESTE:
            print("[teste, não enviado] " + texto)
        return False
    try:
        r = subprocess.run(["/bin/bash", os.path.join(AQUI, "avisar-telegram.sh"), texto],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=40)
        return r.returncode == 0
    except Exception:
        return False


def registrar(texto):
    if SO_LER:
        return
    os.makedirs(LOGS, exist_ok=True)
    with open(os.path.join(LOGS, "vigia-atrasos.log"), "a", encoding="utf-8") as fh:
        fh.write("%s %s\n" % (datetime.now().strftime("%Y-%m-%d %H:%M:%S"), texto))


def hhmm(dt):
    return dt.strftime("%d/%m %H:%M")


def main():
    os.makedirs(ESTADO, exist_ok=True)
    agora = datetime.now()
    atrasadas = []
    for nome, d, caminho in rotinas_vigiadas():
        if nome == "vigia-atrasos" or os.path.exists(os.path.join(ESTADO, nome + ".pausada")):
            continue
        esperado, tol = ultimo_esperado(d, agora)
        if esperado is None:
            continue
        # Só cobra o que é posterior ao embrulho (data do plist = quando passou a ser vigiada).
        desde = datetime.fromtimestamp(os.path.getmtime(caminho))
        rodou = ultimo_inicio(nome)
        estado = ler_estado(nome)
        atrasada = esperado > desde and agora - esperado > tol and (rodou is None or rodou < esperado - timedelta(minutes=1))
        if atrasada:
            atrasadas.append("%s (devia ter rodado %s)" % (nome, hhmm(esperado)))
            ultimo_aviso = datetime.fromisoformat(estado["avisado"]) if estado.get("avisado") else None
            if not estado:
                texto = ("⏰ A rotina \"%s\" está ATRASADA: devia ter rodado %s e não rodou%s. "
                         "Pode ser o Mac dormindo ou o agendamento travado. — %s"
                         % (nome, hhmm(esperado), "" if rodou is None else " (a última vez foi %s)" % hhmm(rodou), ASSINA))
                if avisar(texto):
                    gravar_estado(nome, {"esperado": esperado.isoformat(), "avisado": agora.isoformat()})
                    registrar("ATRASADA, avisei: %s" % nome)
            elif ultimo_aviso and agora - ultimo_aviso > LEMBRETE:
                if avisar("⏰ Lembrete: a rotina \"%s\" continua atrasada (devia ter rodado %s). — %s" % (nome, hhmm(esperado), ASSINA)):
                    estado["avisado"] = agora.isoformat()
                    gravar_estado(nome, estado)
                    registrar("ATRASADA, lembrei: %s" % nome)
        elif estado:
            if avisar("✅ A rotina \"%s\" voltou a rodar (último início %s). Atraso encerrado. — %s"
                      % (nome, hhmm(rodou) if rodou else "?", ASSINA)):
                gravar_estado(nome, {})
                registrar("voltou: %s" % nome)
    registrar("conferi; atrasadas: %s" % (", ".join(atrasadas) or "nenhuma"))
    if "--bom-dia" in sys.argv and atrasadas:
        print("Rotinas atrasadas: " + "; ".join(atrasadas))
    if TESTE:
        print("atrasadas:", atrasadas or "nenhuma")


if __name__ == "__main__":
    main()
