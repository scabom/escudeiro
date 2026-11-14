---
name: lembrar
description: Busca na conversa inteira já arquivada (Telegram) antes de responder — a "memória sem perda". Use SEMPRE que o dono perguntar "lembra quando...", "o que a gente decidiu sobre...", "quando foi que...", "o que eu te falei de...", ou citar algo do passado que não está no working-memory nem em memoria/. Use também antes de afirmar uma data, um número ou uma decisão antiga de que você não tem certeza. NÃO use para o assunto de agora (está no contexto) nem como substituto de anotar na memória.
---

# Lembrar — busca no arquivo de conversas

O arquivo mora em `~/Arquivo-<nome do agente>/` (ou na pasta definida em
`ferramentas/memoria-sem-perda/memoria-sem-perda.json`), FORA do git e do backup
em nuvem, de propósito: é conversa privada. O hook arquiva sozinho a cada 30
min; o `lembrar.py` também arquiva o que for novo antes de buscar.

Só existe no Claude Code. No Codex, os hooks ficam desligados e o arquivo não é
alimentado: use só `memoria/` e `diario/`.

## Como buscar (nessa ordem)
1. Primeiro o que já está resumido: `memoria/MEMORY.md` → a seção;
   `diario/meses/`, `diario/semanas/` e `diario/AAAA-MM-DD.md` do período.
2. Depois o arquivo, por palavra (acento e maiúscula não importam):

       python3 ferramentas/memoria-sem-perda/lembrar.py viagem passagem
       python3 ferramentas/memoria-sem-perda/lembrar.py '"conta de luz"'          # frase exata
       python3 ferramentas/memoria-sem-perda/lembrar.py wifi OR modem --de 2030-01-01 --ate 2030-01-31 -n 30
       python3 ferramentas/memoria-sem-perda/lembrar.py --contexto 2698           # a conversa em volta da #2698
       python3 ferramentas/memoria-sem-perda/lembrar.py --dia 2030-01-15          # o dia inteiro

3. Achou? Abra o `--contexto` antes de concluir: uma frase solta engana (pode
   ter sido corrigida duas mensagens depois).

## Regras
- Responda com a DATA do trecho ("em 15/01 às 19h22 você disse...").
- Achou algo importante que não estava anotado? Promova para `memoria/` na hora.
- Não achou? Diga que não achou. O arquivo só começa no dia em que foi
  instalado (antes disso, só `diario/` e `memoria/`).
- Nunca copie trecho do arquivo para fora da máquina, para o git ou para outro
  agente: é conversa privada.
- Palavras com ponto ou hífen (`site.com.br`, `PLANO-2030`) viram frase exata
  automaticamente.
