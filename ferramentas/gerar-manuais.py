#!/usr/bin/env python3
"""Gera os manuais do agente a partir da FONTE ÚNICA modelo/MANUAL-BASE.md.

    modelo/CLAUDE.md  → para o Claude Code (blocos "so:claude")
    modelo/AGENTS.md  → para o Codex       (blocos "so:codex")

Uso:
    python3 ferramentas/gerar-manuais.py
        Gera os dois em modelo/, com os marcadores {{...}} intactos (é o que vai
        para o repositório).

    python3 ferramentas/gerar-manuais.py --saida ~/agentes/aurora \\
        --nome Aurora --dono Ana --personalidade "Aurora é calma e direta..."
        Batiza um agente já copiado para a pasta --saida: escreve lá o CLAUDE.md e
        o AGENTS.md preenchidos e troca os marcadores também no working-memory.md,
        no memoria-sem-perda.json e no escudeiro.conf (se existirem).
        --personalidade-arquivo ARQ lê a personalidade de um arquivo de texto.
        --motor claude|codex|ambos escolhe qual manual gerar (padrão: ambos).

Só biblioteca padrão do Python 3.9+.
"""
import argparse
import datetime
import os
import re
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELO = os.path.join(RAIZ, "modelo")
FONTE = os.path.join(MODELO, "MANUAL-BASE.md")

ABRE = re.compile(r"^\s*<!--\s*so:(\w+)\s*-->\s*$")
FECHA = re.compile(r"^\s*<!--\s*/so\s*-->\s*$")
MOTORES = {"claude": "CLAUDE.md", "codex": "AGENTS.md"}

AVISO = ("<!-- Gerado por ferramentas/gerar-manuais.py a partir de MANUAL-BASE.md. "
         "Não edite à mão: edite a fonte e gere de novo. -->\n")


def tirar_cabecalho(texto):
    """Remove o primeiro comentário HTML do arquivo (as notas para quem edita)."""
    t = texto.lstrip()
    if t.startswith("<!--"):
        fim = t.find("-->")
        if fim != -1:
            return t[fim + 3:].lstrip("\n")
    return texto


def gerar(texto, motor):
    saida, dentro = [], None
    for n, linha in enumerate(texto.splitlines(), 1):
        m = ABRE.match(linha)
        if m:
            if dentro:
                raise SystemExit("linha %d: bloco so:%s aberto dentro de outro (so:%s)" % (n, m.group(1), dentro))
            if m.group(1) not in MOTORES:
                raise SystemExit("linha %d: motor desconhecido '%s'" % (n, m.group(1)))
            dentro = m.group(1)
            continue
        if FECHA.match(linha):
            if not dentro:
                raise SystemExit("linha %d: '/so' sem bloco aberto" % n)
            dentro = None
            continue
        if dentro is None or dentro == motor:
            saida.append(linha)
    if dentro:
        raise SystemExit("o arquivo terminou com o bloco so:%s aberto" % dentro)
    # Junta linhas em branco repetidas que sobram onde um bloco saiu.
    corpo = re.sub(r"\n{3,}", "\n\n", "\n".join(saida)).strip() + "\n"
    return corpo


def preencher(texto, valores):
    for chave, valor in valores.items():
        texto = texto.replace("{{%s}}" % chave, valor)
    return texto


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--saida", help="pasta do agente a batizar (padrão: gerar em modelo/ sem preencher)")
    ap.add_argument("--nome", help="nome do agente")
    ap.add_argument("--dono", help="nome (ou apelido) do dono")
    ap.add_argument("--personalidade", help="um parágrafo descrevendo a personalidade")
    ap.add_argument("--personalidade-arquivo", help="arquivo de texto com a personalidade")
    ap.add_argument("--motor", choices=["claude", "codex", "ambos"], default="ambos")
    a = ap.parse_args()

    with open(FONTE, encoding="utf-8") as f:
        base = tirar_cabecalho(f.read())

    motores = list(MOTORES) if a.motor == "ambos" else [a.motor]
    destino = os.path.abspath(os.path.expanduser(a.saida)) if a.saida else MODELO

    valores = {}
    if a.saida:
        pers = a.personalidade
        if a.personalidade_arquivo:
            with open(a.personalidade_arquivo, encoding="utf-8") as f:
                pers = f.read().strip()
        faltando = [n for n, v in (("--nome", a.nome), ("--dono", a.dono), ("--personalidade", pers)) if not v]
        if faltando:
            raise SystemExit("para batizar com --saida, informe também: " + ", ".join(faltando))
        if not os.path.isdir(destino):
            raise SystemExit("a pasta %s não existe: copie a pasta modelo/ para lá primeiro" % destino)
        valores = {"NOME_AGENTE": a.nome.strip(), "NOME_DONO": a.dono.strip(), "PERSONALIDADE": pers,
                   "DATA": datetime.date.today().strftime("%d/%m/%Y")}

    for motor in motores:
        texto = gerar(base, motor)
        if valores:
            texto = preencher(texto, valores)
        caminho = os.path.join(destino, MOTORES[motor])
        with open(caminho, "w", encoding="utf-8") as f:
            f.write(AVISO + "\n" + texto)
        print("gerado: %s (%d linhas)" % (caminho, texto.count("\n")))

    if valores:
        for rel in ("working-memory.md", "escudeiro.conf",
                    os.path.join("ferramentas", "memoria-sem-perda", "memoria-sem-perda.json")):
            arq = os.path.join(destino, rel)
            if os.path.isfile(arq):
                with open(arq, encoding="utf-8") as f:
                    antes = f.read()
                depois = preencher(antes, valores)
                if depois != antes:
                    with open(arq, "w", encoding="utf-8") as f:
                        f.write(depois)
                    print("preenchido: %s" % arq)
        sobra = []
        for motor in motores:
            with open(os.path.join(destino, MOTORES[motor]), encoding="utf-8") as f:
                sobra += re.findall(r"\{\{[A-Z_]+\}\}", f.read())
        if sobra:
            print("atenção: marcadores sem valor: %s" % ", ".join(sorted(set(sobra))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
