#!/usr/bin/env python3
"""Memória sem perda: busca por palavra no arquivo de conversas (o "lembra quando...").

Uso:
    python3 lembrar.py viagem passagem        # trechos com as duas palavras (acento não importa)
    python3 lembrar.py '"conta de luz"'       # frase exata
    python3 lembrar.py wifi OR modem          # uma ou outra
    python3 lembrar.py viagem --de 2030-01-01 --ate 2030-01-31 -n 30
    python3 lembrar.py --dia 2030-01-15       # o dia inteiro
    python3 lembrar.py --contexto 1234        # a mensagem 1234 com 5 antes e 5 depois

Antes de buscar, arquiva o que for novo (rapidinho), pra achar até a conversa de agora há pouco.
"""
import os
import sqlite3
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import arquivar  # noqa: E402


def opcao(argv, nome, padrao=None):
    if nome in argv:
        i = argv.index(nome)
        valor = argv[i + 1]
        del argv[i:i + 2]
        return valor
    return padrao


def mostrar(linhas):
    for id_, quando, quem, texto in linhas:
        print("#%d  %s %s  %s: %s" % (id_, quando[:10], quando[11:16], quem, texto))
        print()


def registrar_uso(cfg, argv, saida_chars=None):
    """Uma linha por busca em <arquivo>/uso.log, pra medir quanto a memória sem perda pesa."""
    try:
        from datetime import datetime
        with open(os.path.join(cfg["arquivo"], "uso.log"), "a", encoding="utf-8") as f:
            f.write("%s\t%s\n" % (datetime.now().isoformat(timespec="seconds"), " ".join(argv)[:80]))
    except OSError:
        pass


def main():
    argv = sys.argv[1:]
    cfg = arquivar.carregar_config()
    registrar_uso(cfg, argv)
    db = arquivar.abrir_banco(cfg)
    novos, dias = arquivar.ler_novidades(db, cfg)
    arquivar.escrever_dias(db, cfg, dias)

    dia = opcao(argv, "--dia")
    if dia:
        mostrar(db.execute("SELECT id, quando, quem, texto FROM mensagens WHERE dia=? ORDER BY quando, id", (dia,)))
        return
    ctx = opcao(argv, "--contexto")
    if ctx:
        # Vizinhança por horário, não por id: os ids seguem a ordem de leitura dos arquivos.
        alvo = db.execute("SELECT quando FROM mensagens WHERE id=?", (int(ctx),)).fetchone()
        if not alvo:
            print("Não achei a mensagem #%s." % ctx)
            return
        antes = db.execute(
            "SELECT id, quando, quem, texto FROM mensagens WHERE quando <= ? AND id != ? "
            "ORDER BY quando DESC, id DESC LIMIT 5", (alvo[0], int(ctx))).fetchall()
        alvo_e_depois = db.execute(
            "SELECT id, quando, quem, texto FROM mensagens WHERE (quando > ? OR id = ?) "
            "ORDER BY quando, id LIMIT 6", (alvo[0], int(ctx))).fetchall()
        mostrar(list(reversed(antes)) + alvo_e_depois)
        return

    de = opcao(argv, "--de", "0000")
    ate = opcao(argv, "--ate", "9999")
    limite = int(opcao(argv, "-n", "15"))
    if not argv:
        print(__doc__)
        return
    consulta = " ".join(argv)
    sql = (
        "SELECT m.id, m.quando, m.quem, snippet(busca, 0, '[', ']', ' … ', 40) "
        "FROM busca JOIN mensagens m ON m.id = busca.rowid "
        "WHERE busca MATCH ? AND m.dia BETWEEN ? AND ? ORDER BY m.quando DESC LIMIT ?"
    )
    try:
        linhas = db.execute(sql, (consulta, de, ate, limite)).fetchall()
    except sqlite3.OperationalError:
        # Consulta com caractere especial (ponto, hífen...): busca como frase literal.
        linhas = db.execute(sql, ('"%s"' % consulta.replace('"', ""), de, ate, limite)).fetchall()
    total = db.execute("SELECT MIN(dia), MAX(dia), COUNT(*) FROM mensagens").fetchone()
    print("Arquivo: %s a %s, %d mensagens. Achei %d (mais novas primeiro, limite %d).\n"
          % (total[0], total[1], total[2], len(linhas), limite))
    mostrar(linhas)


if __name__ == "__main__":
    main()
