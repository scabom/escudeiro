#!/usr/bin/env python3
"""Memória sem perda: arquiva a conversa do agente antes que o Claude Code apague os históricos.

Lê os históricos brutos (.jsonl) da pasta do agente em ~/.claude/projects/, tira SÓ a conversa
(mensagens do Telegram que chegaram + respostas enviadas pelo reply) e grava num banco local com
busca por palavra (SQLite FTS5), mais um arquivo .md por dia, legível por gente.

Nada sai da máquina. Nada de imagem, saída de ferramenta, segredo ou "pensamento".
Inspirado no lossless-claw (Martian-Engineering, MIT) — ideia, não código.

Uso:
    python3 arquivar.py                 # arquiva o que for novo
    python3 arquivar.py --fundo         # dispara em segundo plano e sai na hora (pro hook)
    python3 arquivar.py --intervalo 3600  # só roda se a última rodada tiver mais de 1 h
    python3 arquivar.py --refazer       # apaga o índice e relê tudo desde o começo

Config opcional: memoria-sem-perda.json ao lado deste script:
    {"agente": "Aurora", "humano": "Ana", "arquivo": "~/Arquivo-Aurora"}
Sem config (ou com os marcadores {{...}} ainda no lugar), o agente é o nome da pasta e o
arquivo vai para ~/Arquivo-<agente>.
Python 3.9+ e só biblioteca padrão (roda no Mac, no Linux e no Windows).
"""
import json
import os
import re
import sqlite3
import subprocess
import sys
import time
from datetime import datetime, timezone

AQUI = os.path.dirname(os.path.abspath(__file__))
CANAL = re.compile(r"<channel\s+([^>]*)>(.*?)</channel>", re.S)
ATRIB = re.compile(r'(\w+)="([^"]*)"')


def carregar_config():
    cfg = {}
    caminho = os.path.join(AQUI, "memoria-sem-perda.json")
    if os.path.exists(caminho):
        with open(caminho, encoding="utf-8") as f:
            cfg = json.load(f)
    # Marcador ainda não preenchido ({{NOME_AGENTE}}) conta como vazio.
    cfg = {k: v for k, v in cfg.items() if not (isinstance(v, str) and "{{" in v)}
    # A pasta do agente é a que tem o .claude/ — duas acima de ferramentas/memoria-sem-perda/.
    projeto = os.environ.get("CLAUDE_PROJECT_DIR") or os.path.dirname(os.path.dirname(AQUI))
    projeto = os.path.abspath(projeto)
    agente = cfg.get("agente") or os.path.basename(projeto).capitalize()
    cfg["agente"] = agente
    cfg.setdefault("humano", "Dono")
    cfg["arquivo"] = os.path.expanduser(cfg.get("arquivo") or "~/Arquivo-" + agente)
    # Mesmo nome que o Claude Code dá à pasta: todo caractere que não é letra/número vira "-".
    cfg["historicos"] = os.path.join(
        os.path.expanduser("~"), ".claude", "projects", re.sub(r"[^A-Za-z0-9]", "-", projeto)
    )
    return cfg


def abrir_banco(cfg):
    os.makedirs(cfg["arquivo"], exist_ok=True)
    try:
        os.chmod(cfg["arquivo"], 0o700)
    except OSError:
        pass
    db = sqlite3.connect(os.path.join(cfg["arquivo"], "indice.db"))
    db.executescript(
        """
        CREATE TABLE IF NOT EXISTS mensagens (
            id INTEGER PRIMARY KEY,
            chave TEXT UNIQUE,
            quando TEXT,
            dia TEXT,
            quem TEXT,
            texto TEXT
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS busca USING fts5(
            texto, content='mensagens', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER IF NOT EXISTS mensagens_ai AFTER INSERT ON mensagens BEGIN
            INSERT INTO busca(rowid, texto) VALUES (new.id, new.texto);
        END;
        CREATE TABLE IF NOT EXISTS lidos (arquivo TEXT PRIMARY KEY, posicao INTEGER);
        """
    )
    return db


def hora_local(iso):
    dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone()


def textos_do_usuario(conteudo):
    if isinstance(conteudo, str):
        return [conteudo]
    if isinstance(conteudo, list):
        return [x.get("text", "") for x in conteudo if isinstance(x, dict) and x.get("type") == "text"]
    return []


def mensagens_da_linha(o, humano, agente):
    """Devolve [(chave, iso, quem, texto)] de uma linha do .jsonl."""
    # Não filtrar isMeta: as mensagens que chegam pelo canal do Telegram vêm marcadas assim.
    if o.get("isSidechain") or o.get("isCompactSummary"):
        return []
    saida = []
    msg = o.get("message") or {}
    if o.get("type") == "user":
        for t in textos_do_usuario(msg.get("content")):
            for atrs, corpo in CANAL.findall(t):
                a = dict(ATRIB.findall(atrs))
                corpo = corpo.strip()
                extra = []
                if a.get("image_path"):
                    extra.append("(foto)")
                tipo = a.get("attachment_kind")
                if tipo in ("voice", "audio"):
                    extra.append("(áudio)")
                elif tipo:
                    extra.append("(arquivo: %s)" % a.get("attachment_name", tipo))
                texto = " ".join(extra + ([corpo] if corpo else []))
                iso = a.get("ts") or o.get("timestamp")
                if texto and iso:
                    chave = "in:%s:%s" % (a.get("chat_id", ""), a.get("message_id") or iso)
                    saida.append((chave, iso, humano, texto))
    elif o.get("type") == "assistant":
        for i, x in enumerate(msg.get("content") or []):
            if not isinstance(x, dict) or x.get("type") != "tool_use":
                continue
            if not str(x.get("name", "")).endswith("__reply"):
                continue
            entrada = x.get("input") or {}
            texto = (entrada.get("text") or "").strip()
            if entrada.get("files"):
                texto += " (anexo: %s)" % ", ".join(os.path.basename(p) for p in entrada["files"])
            if texto and o.get("timestamp"):
                saida.append(("out:%s" % x.get("id", "%s:%d" % (o.get("uuid"), i)), o["timestamp"], agente, texto))
    return saida


def ler_novidades(db, cfg):
    dias_mexidos = set()
    novos = 0
    if not os.path.isdir(cfg["historicos"]):
        return novos, dias_mexidos
    for nome in sorted(os.listdir(cfg["historicos"])):
        if not nome.endswith(".jsonl"):
            continue
        caminho = os.path.join(cfg["historicos"], nome)
        linha_db = db.execute("SELECT posicao FROM lidos WHERE arquivo=?", (nome,)).fetchone()
        posicao = linha_db[0] if linha_db else 0
        tamanho = os.path.getsize(caminho)
        if tamanho < posicao:  # arquivo encolheu (foi trocado): relê do começo, o UNIQUE evita repetição
            posicao = 0
        if tamanho == posicao:
            continue
        with open(caminho, "rb") as f:
            f.seek(posicao)
            for bruto in f:
                if not bruto.endswith(b"\n"):
                    break  # linha ainda sendo escrita: fica pra próxima rodada
                posicao += len(bruto)
                try:
                    o = json.loads(bruto)
                except ValueError:
                    continue
                for chave, iso, quem, texto in mensagens_da_linha(o, cfg["humano"], cfg["agente"]):
                    try:
                        local = hora_local(iso)
                    except ValueError:
                        continue
                    cur = db.execute(
                        "INSERT OR IGNORE INTO mensagens(chave, quando, dia, quem, texto) VALUES (?,?,?,?,?)",
                        (chave, local.isoformat(timespec="seconds"), local.strftime("%Y-%m-%d"), quem, texto),
                    )
                    if cur.rowcount:
                        novos += 1
                        dias_mexidos.add(local.strftime("%Y-%m-%d"))
        db.execute("INSERT OR REPLACE INTO lidos(arquivo, posicao) VALUES (?,?)", (nome, posicao))
        db.commit()
    return novos, dias_mexidos


def escrever_dias(db, cfg, dias):
    """Reescreve o .md de cada dia mexido, a partir do banco (o banco é a fonte)."""
    for dia in sorted(dias):
        pasta = os.path.join(cfg["arquivo"], "conversas", dia[:4])
        os.makedirs(pasta, exist_ok=True)
        linhas = ["# Conversa de %s (%s e %s)" % (dia, cfg["humano"], cfg["agente"]), ""]
        for quando, quem, texto in db.execute(
            "SELECT quando, quem, texto FROM mensagens WHERE dia=? ORDER BY quando, id", (dia,)
        ):
            linhas.append("[%s] %s: %s" % (quando[11:16], quem, texto.replace("\n", "\n    ")))
            linhas.append("")
        with open(os.path.join(pasta, dia + ".md"), "w", encoding="utf-8") as f:
            f.write("\n".join(linhas))


def disparar_em_fundo():
    args = [sys.executable, os.path.abspath(__file__)] + [a for a in sys.argv[1:] if a != "--fundo"]
    opcoes = {"stdin": subprocess.DEVNULL, "stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
    if os.name == "nt":
        opcoes["creationflags"] = 0x00000008 | 0x00000200  # DETACHED_PROCESS | NEW_PROCESS_GROUP
    else:
        opcoes["start_new_session"] = True
    subprocess.Popen(args, **opcoes)


def main():
    argv = sys.argv[1:]
    if "--fundo" in argv:
        disparar_em_fundo()
        return
    cfg = carregar_config()
    os.makedirs(cfg["arquivo"], exist_ok=True)
    marca = os.path.join(cfg["arquivo"], ".ultima-rodada")
    if "--intervalo" in argv:
        segundos = int(argv[argv.index("--intervalo") + 1])
        if os.path.exists(marca) and time.time() - os.path.getmtime(marca) < segundos:
            return
    trava = os.path.join(cfg["arquivo"], ".rodando")
    try:
        fd = os.open(trava, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(fd)
    except FileExistsError:
        if time.time() - os.path.getmtime(trava) < 1800:
            return  # outra rodada em andamento
        os.utime(trava, None)  # trava velha (rodada que morreu): assume
    try:
        if "--refazer" in argv:
            caminho = os.path.join(cfg["arquivo"], "indice.db")
            if os.path.exists(caminho):
                os.remove(caminho)
        db = abrir_banco(cfg)
        novos, dias = ler_novidades(db, cfg)
        if "--refazer" in argv:
            dias = {d for (d,) in db.execute("SELECT DISTINCT dia FROM mensagens")}
        escrever_dias(db, cfg, dias)
        total = db.execute("SELECT COUNT(*) FROM mensagens").fetchone()[0]
        db.close()
        with open(marca, "w") as f:
            f.write(datetime.now().isoformat(timespec="seconds"))
        if sys.stdout.isatty() or "--falar" in argv:
            print("arquivadas %d mensagens novas (%d no total, %d dias) em %s" % (novos, total, len(dias), cfg["arquivo"]))
    finally:
        try:
            os.remove(trava)
        except OSError:
            pass


if __name__ == "__main__":
    try:
        main()
    except Exception as erro:  # nunca derruba o agente: registra e sai calado
        try:
            cfg = carregar_config()
            with open(os.path.join(cfg["arquivo"], "erros.log"), "a", encoding="utf-8") as f:
                f.write("%s %r\n" % (datetime.now().isoformat(timespec="seconds"), erro))
        except Exception:
            pass
        if sys.stdout.isatty():
            raise
