#!/usr/bin/env python3
"""Memória sem perda: arquiva a conversa do agente antes que o Claude Code apague os históricos.

Lê os históricos brutos (.jsonl) da pasta do agente em ~/.claude/projects/, tira SÓ a conversa
(mensagens do Telegram que chegaram + respostas enviadas pelo reply) e grava num banco local com
busca por palavra (SQLite FTS5), mais um arquivo .md por dia, legível por gente.

Nada sai da máquina. Nada de imagem, saída de ferramenta ou "pensamento".

SEGREDOS: o texto da conversa é guardado como foi escrito. Antes de gravar, os segredos que
têm formato reconhecível (token de bot do Telegram, chaves gsk_/sk-/ghp_/AKIA..., chave
privada, "senha: ...") são trocados por [SEGREDO REMOVIDO]. Isso NÃO pega tudo: uma senha
solta no meio da frase passa. Se um segredo foi parar no arquivo, revogue o segredo (é o que
protege de verdade) e apague a mensagem com --apagar <nº> (o nº aparece no lembrar.py).
Inspirado no lossless-claw (Martian-Engineering, MIT) — ideia, não código.

Uso:
    python3 arquivar.py                 # arquiva o que for novo
    python3 arquivar.py --fundo         # dispara em segundo plano e sai na hora (pro hook)
    python3 arquivar.py --intervalo 3600  # só roda se a última rodada tiver mais de 1 h
    python3 arquivar.py --refazer       # reconstrói o índice SEM perder nada (veja abaixo)
    python3 arquivar.py --apagar 1234 [1235...]  # apaga mensagens do arquivo (banco e .md do dia)

--apagar guarda a CHAVE da mensagem numa lista de apagadas (tabela "apagadas" do banco): nem a
próxima rodada, nem o --refazer, nem uma releitura dos históricos traz a mensagem de volta.

Tudo o que mexe no banco (a rodada normal, --apagar, --refazer do começo até a troca dos
arquivos, e a importação que o lembrar.py faz antes de buscar) passa pela MESMA trava
(<arquivo>/.trava, trava do sistema, solta sozinha se o processo morrer).

--refazer monta um índice NOVO ao lado (indice.db.novo) com tudo o que o índice atual já tem
(inclusive conversas cujos históricos o Claude Code já apagou) mais o que ainda existe nos
históricos, passando de novo o filtro de segredos. Só troca se o novo tiver pelo menos as
mesmas mensagens; o antigo fica guardado como indice.db.antes-de-refazer-<data>. Descartar
o arquivo acumulado é outra coisa, e é decisão do dono: apagar a pasta do arquivo à mão.

Config opcional: memoria-sem-perda.json ao lado deste script:
    {"agente": "Aurora", "humano": "Ana", "arquivo": "~/Arquivo-Aurora"}
Sem config (ou com os marcadores {{...}} ainda no lugar), o agente é o nome da pasta e o
arquivo vai para ~/Arquivo-<agente>.
Python 3.9+ e só biblioteca padrão (roda no Mac, no Linux e no Windows).
"""
import contextlib
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


# Segredos com formato reconhecível. Não é rede de segurança completa: ver o topo do arquivo.
SEGREDOS = [
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(-----END [A-Z ]*PRIVATE KEY-----|\Z)", re.S),
    re.compile(r"(?<![\w])\d{8,10}:[A-Za-z0-9_-]{30,}"),          # token de bot do Telegram
    re.compile(r"\bgsk_[A-Za-z0-9]{20,}"),                         # Groq
    re.compile(r"\bsk-(?:ant-)?[A-Za-z0-9_-]{20,}"),               # OpenAI / Anthropic
    re.compile(r"\b(?:ghp|gho|ghs|ghu)_[A-Za-z0-9]{20,}|\bgithub_pat_[A-Za-z0-9_]{20,}"),  # GitHub
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),                           # AWS
    re.compile(r"\bxox[abposr]-[A-Za-z0-9-]{10,}"),                # Slack
    re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),                      # Google
]
SENHA = re.compile(r"(?i)\b(senha|password|passwd|pin|token|api[ _-]?key)(\s*(?:[:=]|é|eh)\s*)(\S+)")


def tirar_segredos(texto):
    for r in SEGREDOS:
        texto = r.sub("[SEGREDO REMOVIDO]", texto)
    return SENHA.sub(lambda m: m.group(1) + m.group(2) + "[SEGREDO REMOVIDO]", texto)


def abrir_banco(cfg, caminho=None):
    os.makedirs(cfg["arquivo"], exist_ok=True)
    try:
        os.chmod(cfg["arquivo"], 0o700)
    except OSError:
        pass
    db = sqlite3.connect(caminho or os.path.join(cfg["arquivo"], "indice.db"))
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
        CREATE TRIGGER IF NOT EXISTS mensagens_ad AFTER DELETE ON mensagens BEGIN
            INSERT INTO busca(busca, rowid, texto) VALUES ('delete', old.id, old.texto);
        END;
        CREATE TABLE IF NOT EXISTS lidos (arquivo TEXT PRIMARY KEY, posicao INTEGER);
        CREATE TABLE IF NOT EXISTS apagadas (chave TEXT PRIMARY KEY, quando TEXT);
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
                    # Mensagem que o dono mandou apagar (--apagar) nunca volta.
                    cur = db.execute(
                        "INSERT OR IGNORE INTO mensagens(chave, quando, dia, quem, texto) "
                        "SELECT ?,?,?,?,? WHERE NOT EXISTS (SELECT 1 FROM apagadas WHERE chave=?)",
                        (chave, local.isoformat(timespec="seconds"), local.strftime("%Y-%m-%d"), quem,
                         tirar_segredos(texto), chave),
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


@contextlib.contextmanager
def trava(cfg, esperar=0):
    """A trava única do banco. Rende True se conseguiu (esperando até `esperar` segundos)."""
    os.makedirs(cfg["arquivo"], exist_ok=True)
    f = open(os.path.join(cfg["arquivo"], ".trava"), "a+")
    pegou = False
    limite = time.time() + esperar
    try:
        while True:
            try:
                if os.name == "nt":
                    import msvcrt
                    f.seek(0)
                    msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                pegou = True
                break
            except OSError:
                if time.time() >= limite:
                    break
                time.sleep(0.5)
        yield pegou
    finally:
        if pegou:
            try:
                if os.name == "nt":
                    import msvcrt
                    f.seek(0)
                    msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
                else:
                    import fcntl
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            except OSError:
                pass
        f.close()


def refazer(cfg):
    """Reconstrói o índice ao lado, sem perder o que só existe no índice atual."""
    atual = os.path.join(cfg["arquivo"], "indice.db")
    novo = atual + ".novo"
    if os.path.exists(novo):
        os.remove(novo)
    db = abrir_banco(cfg, novo)
    antes = 0
    if os.path.exists(atual):
        velho = sqlite3.connect(atual)
        try:
            apagadas = velho.execute("SELECT chave, quando FROM apagadas").fetchall()
        except sqlite3.OperationalError:  # banco de antes da 1.0.1, sem a tabela
            apagadas = []
        linhas = velho.execute("SELECT chave, quando, dia, quem, texto FROM mensagens ORDER BY id").fetchall()
        velho.close()
        # A lista de apagadas vem PRIMEIRO: a releitura dos históricos logo abaixo a respeita.
        db.executemany("INSERT OR IGNORE INTO apagadas(chave, quando) VALUES (?,?)", apagadas)
        antes = len(linhas)
        db.executemany(
            "INSERT OR IGNORE INTO mensagens(chave, quando, dia, quem, texto) VALUES (?,?,?,?,?)",
            [(c, q, d, w, tirar_segredos(t)) for c, q, d, w, t in linhas],
        )
        db.commit()
    ler_novidades(db, cfg)
    depois = db.execute("SELECT COUNT(*) FROM mensagens").fetchone()[0]
    if depois < antes:
        db.close()
        raise RuntimeError("o índice novo ficou com %d mensagens e o atual tem %d: mantive o atual (o novo ficou em %s)"
                           % (depois, antes, novo))
    db.close()
    if os.path.exists(atual):
        os.replace(atual, atual + ".antes-de-refazer-" + datetime.now().strftime("%Y%m%d-%H%M%S"))
    os.replace(novo, atual)
    db = abrir_banco(cfg)
    return db, antes, depois


def apagar(cfg, ids):
    """Apaga mensagens pelo número (o #nº do lembrar.py) e reescreve o .md dos dias."""
    db = abrir_banco(cfg)
    dias = set()
    for i in ids:
        linha = db.execute("SELECT dia FROM mensagens WHERE id=?", (i,)).fetchone()
        if not linha:
            print("não achei a mensagem #%d" % i)
            continue
        chave = db.execute("SELECT chave FROM mensagens WHERE id=?", (i,)).fetchone()[0]
        db.execute("INSERT OR IGNORE INTO apagadas(chave, quando) VALUES (?,?)",
                   (chave, datetime.now().isoformat(timespec="seconds")))
        db.execute("DELETE FROM mensagens WHERE id=?", (i,))
        dias.add(linha[0])
        print("apaguei a mensagem #%d (%s)" % (i, linha[0]))
    db.commit()
    escrever_dias(db, cfg, dias)
    db.execute("VACUUM")
    db.close()
    if dias:
        print("Atenção: o histórico bruto do Claude Code (~/.claude/projects/) ainda tem a mensagem até ele "
              "ser limpo; se ela tinha um segredo, o que protege de verdade é revogar o segredo.")
        print("As cópias antigas do índice (indice.db.antes-de-refazer-*, na pasta do arquivo) também podem ter a "
              "mensagem. Com a autorização do dono, apague as que não forem mais necessárias.")


def main():
    argv = sys.argv[1:]
    if "--apagar" in argv:
        numeros = [a.lstrip("#") for a in argv[argv.index("--apagar") + 1:]]
        ids = [int(n) for n in numeros if n.isdigit()]
        if not ids:
            print("uso: arquivar.py --apagar <nº> [<nº>...]")
            return
        cfg = carregar_config()
        with trava(cfg, esperar=120) as ok:
            if not ok:
                print("o arquivo está ocupado (outra rodada em andamento); tente de novo daqui a pouco.")
                sys.exit(1)
            apagar(cfg, ids)
        return
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
    # A rodada normal (a do hook) não espera: se outra está mexendo no banco, fica para a
    # próxima. O --refazer espera, e segura a trava até a troca dos arquivos terminar.
    with trava(cfg, esperar=120 if "--refazer" in argv else 0) as ok:
        if not ok:
            if "--refazer" in argv:
                print("o arquivo está ocupado (outra rodada em andamento); tente de novo daqui a pouco.")
                sys.exit(1)
            return
        if "--refazer" in argv:
            db, antes, depois = refazer(cfg)
            novos = depois - antes
            dias = {d for (d,) in db.execute("SELECT DISTINCT dia FROM mensagens")}
        else:
            db = abrir_banco(cfg)
            novos, dias = ler_novidades(db, cfg)
        escrever_dias(db, cfg, dias)
        total = db.execute("SELECT COUNT(*) FROM mensagens").fetchone()[0]
        db.close()
        with open(marca, "w") as f:
            f.write(datetime.now().isoformat(timespec="seconds"))
    if sys.stdout.isatty() or "--falar" in argv:
        print("arquivadas %d mensagens novas (%d no total, %d dias) em %s" % (novos, total, len(dias), cfg["arquivo"]))


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
