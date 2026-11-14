#!/usr/bin/env python3
"""Apaga dado pessoal de um arquivo de texto ANTES de o agente ler.

POR QUE EXISTE: material que o dono recebe (apostila, comprovante, extrato)
costuma trazer CPF, e-mail ou IP dele como marca d'água. Se o agente lê o
arquivo, o conteúdo entra na conversa e vai para os servidores do modelo.

A SOLUÇÃO É A ORDEM DAS COISAS: este script roda na máquina do dono, sozinho, e
produz um arquivo limpo. O agente lê SÓ o limpo. O dado nunca entra na conversa.

⚠️ POR QUE ELE NÃO IMPRIME O QUE ACHOU: um verificador que mostra o dado
sensível para provar que o encontrou derrota o próprio propósito. Aqui ele diz
QUANTOS achou e de que tipo — nunca o valor.

Uso:
    python3 limpar-dados-pessoais.py entrada.md            → entrada.limpo.md
    python3 limpar-dados-pessoais.py entrada.md saida.md
    python3 limpar-dados-pessoais.py entrada.md --conferir  → só relata, não grava
"""

import re
import sys
from pathlib import Path

# Cada padrão é (nome legível, regex, substituto).
# O substituto mantém o tamanho da informação ("havia algo aqui") sem o valor.
PADROES = [
    ("CPF",            r"\b\d{3}\.\d{3}\.\d{3}-\d{2}\b",                 "[CPF REMOVIDO]"),
    ("CPF sem pontos", r"(?<!\d)\d{11}(?!\d)",                           "[CPF REMOVIDO]"),
    ("CNPJ",           r"\b\d{2}\.\d{3}\.\d{3}/\d{4}-\d{2}\b",           "[CNPJ REMOVIDO]"),
    ("RG",             r"\bRG[:\s]*[\d.\-]{7,12}\b",                     "[RG REMOVIDO]"),
    ("e-mail",         r"\b[\w.+-]+@[\w-]+\.[\w.]+\b",                   "[EMAIL REMOVIDO]"),
    ("telefone",       r"\(?\b\d{2}\)?\s?9?\d{4}[-\s]?\d{4}\b",          "[TELEFONE REMOVIDO]"),
    ("cartão",         r"\b\d{4}[\s.-]?\d{4}[\s.-]?\d{4}[\s.-]?\d{4}\b", "[CARTAO REMOVIDO]"),
    # ⚠️ IP entrou depois de uma falha real: uma marca d'água do tipo
    # "<número> - <IP> - <CPF>" teve o CPF removido e o IP deixado passar, em
    # todas as páginas. IP identifica cidade e provedor: é dado pessoal. Só se
    # percebe olhando o resultado, em vez de confiar no "✅ limpo" impresso.
    ("IP",             r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])",     "[IP REMOVIDO]"),

    # ── comprovante de BANCO tem dado que apostila não tem ──
    # Prefira comprovante em PDF (convertido para texto) a print: print o agente
    # lê como imagem e NENHUM filtro alcança; texto passa por aqui.
    ("agência",        r"(?i)\bag[êe]ncia\b\.?[:\s]*\d{3,5}[-\s]?\d?",     "agência [REMOVIDA]"),
    ("conta",          r"(?i)\b(?:conta(?:\s+corrente)?|c/c)\b\.?[:\s]*[\d.]{3,12}[-\s]?\d",
                                                                          "conta [REMOVIDA]"),
    ("chave Pix aleatória",
                       r"(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b",
                                                                          "[CHAVE PIX REMOVIDA]"),
    # linha digitável de boleto: 47-48 dígitos, com ou sem pontos e espaços.
    # Não é só "número" — dá para rastrear e até pagar com ela.
    ("linha digitável",
                       r"(?<!\d)(?:\d[ .]?){44,48}(?!\d)",               "[LINHA DIGITÁVEL REMOVIDA]"),
]


def limpar(texto: str) -> tuple[str, list[tuple[str, int]]]:
    """Devolve (texto limpo, [(nome do padrão, quantas vezes)])."""
    achados = []
    for nome, regex, substituto in PADROES:
        texto, n = re.subn(regex, substituto, texto)
        if n:
            achados.append((nome, n))
    return texto, achados


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    so_conferir = "--conferir" in sys.argv

    if not args:
        print(__doc__)
        return 1

    entrada = Path(args[0])
    if not entrada.is_file():
        print(f"❌ não achei o arquivo: {entrada}")
        return 1

    # Nunca sobrescreve o original: o de fora é a fonte, e fonte não se perde.
    if len(args) > 1:
        saida = Path(args[1])
    else:
        saida = entrada.with_suffix(f".limpo{entrada.suffix}")

    texto = entrada.read_text(encoding="utf-8", errors="replace")
    limpo, achados = limpar(texto)

    print(f"📄 {entrada.name}  ({len(texto):,} caracteres)".replace(",", "."))
    if achados:
        print("🔒 dado pessoal encontrado e removido:")
        for nome, n in achados:
            print(f"   {nome}: {n}x")
    else:
        print("✅ nenhum dado pessoal encontrado nos padrões que eu conheço")

    if so_conferir:
        print("\n(--conferir: nada foi gravado)")
        return 0

    saida.write_text(limpo, encoding="utf-8")
    print(f"\n💾 arquivo limpo: {saida}")

    # Conferência de verdade: reler o que foi gravado e garantir que ficou limpo.
    # Confiar que a substituição funcionou é o tipo de suposição que custa
    # caro: melhor abrir o arquivo e olhar.
    _, sobrou = limpar(saida.read_text(encoding="utf-8", errors="replace"))
    if sobrou:
        print("🚨 ATENÇÃO: ainda sobrou dado pessoal no arquivo gravado:")
        for nome, n in sobrou:
            print(f"   {nome}: {n}x")
        return 1
    print("✅ conferido depois de gravar: o arquivo de saída está limpo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
