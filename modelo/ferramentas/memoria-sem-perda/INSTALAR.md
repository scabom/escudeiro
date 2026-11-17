# Memória sem perda — como instalar num agente (Claude Code + Telegram)

Inspirado no lossless-claw (Martian-Engineering, MIT): só a ideia, nenhum código
de lá. Funciona no Claude Code. No Codex ainda não (veja `codex/LEIA-ME.md` do
pacote).

## O que faz
- O Claude Code apaga os históricos de conversa depois de um tempo (padrão: 30
  dias). O que o agente não anotou, se perde.
- Este módulo copia SÓ a conversa (mensagens que chegam pelo Telegram +
  respostas do agente pelo reply) para um banco local com busca por palavra,
  mais um `.md` por dia que qualquer pessoa consegue abrir.
- Nada sai da máquina, não usa API nem crédito. Sem imagem, sem saída de
  comando, sem "pensamento".

## Segredos e mensagens sensíveis (leia)
- O arquivo guarda a conversa **como ela foi escrita**, e guarda por tempo
  indeterminado (é para isso que ele existe). Se o dono mandar uma senha ou uma
  chave pelo Telegram, ela entra na conversa.
- Antes de gravar, o `arquivar.py` troca por `[SEGREDO REMOVIDO]` o que tem
  formato reconhecível: token de bot do Telegram, chaves `gsk_`, `sk-`, `ghp_`,
  `AKIA`..., chave privada e "senha: ...". **Não pega tudo**: uma senha solta
  no meio de uma frase passa. Não trate o arquivo como livre de segredos.
- Segredo foi parar no arquivo? Nesta ordem:
  1. **revogue o segredo** (troque a senha, apague a chave e crie outra): é o
     que protege de verdade;
  2. ache o número da mensagem (`lembrar.py <palavra>` mostra `#1234`) e apague:

         python3 ferramentas/memoria-sem-perda/arquivar.py --apagar 1234

     Isso tira a mensagem do banco, da busca e do `.md` do dia, e guarda a
     chave dela numa lista de apagadas: nem a próxima rodada, nem o
     `--refazer` a trazem de volta. Os números (`#1234`) podem mudar depois de
     um `--refazer`: procure de novo com o `lembrar.py` antes de apagar;
  3. o histórico bruto do Claude Code (`~/.claude/projects/`) ainda tem a
     mensagem até ser limpo pelo próprio Claude Code.

## Requisitos
- Python 3.9+ (só biblioteca padrão; o SQLite precisa ter FTS5, e o do macOS
  atual tem). Teste:

      python3 -c "import sqlite3;sqlite3.connect(':memory:').execute('create virtual table t using fts5(x)');print('ok')"

## Instalação
No Escudeiro ele já vem instalado em `ferramentas/memoria-sem-perda/` e ligado
no `.claude/settings.json`. Só falta:

1. Conferir `memoria-sem-perda.json` (o `gerar-manuais.py --saida` já preenche):

       {"agente": "Aurora", "humano": "Ana", "arquivo": "~/Arquivo-Aurora"}

   `arquivo` é a pasta onde a conversa fica guardada. O padrão é
   `~/Arquivo-<agente>`, na pasta do usuário e FORA da pasta do agente: assim
   não vai para git nem para backup em nuvem sem o dono decidir. Pode apontar
   para outro lugar (um disco cifrado, por exemplo).
2. Rodar uma vez à mão (arquiva tudo o que ainda existe):

       python3 ferramentas/memoria-sem-perda/arquivar.py --falar

3. O hook (já está no `settings.json` do modelo) é este item, dentro de
   `hooks.UserPromptSubmit[0].hooks`:

       {
         "type": "command",
         "command": "/usr/bin/python3 \"$CLAUDE_PROJECT_DIR/ferramentas/memoria-sem-perda/arquivar.py\" --fundo --intervalo 1800"
       }

   `--fundo` = roda em segundo plano (não atrasa a resposta); `--intervalo 1800`
   = no máximo a cada 30 min.

Recomendado: em `~/.claude/settings.json` da máquina, `"cleanupPeriodDays": 365`
(o Claude Code guarda os históricos por 1 ano em vez de 30 dias: rede de
segurança enquanto o arquivo não roda).

## Uso
    python3 ferramentas/memoria-sem-perda/lembrar.py palavra1 palavra2
    python3 ferramentas/memoria-sem-perda/lembrar.py '"frase exata"' --de 2030-01-01 --ate 2030-01-31
    python3 ferramentas/memoria-sem-perda/lembrar.py --contexto 1234
    python3 ferramentas/memoria-sem-perda/lembrar.py --dia 2030-01-15

## Se der problema
- Nada aparece: rode `arquivar.py --falar` à mão e veja a mensagem; erros do
  modo hook ficam em `<arquivo>/erros.log`.
- Índice estranho ou corrompido: `arquivar.py --refazer`. Ele monta um índice
  novo ao lado, com **tudo** o que o índice atual tem (inclusive conversas cujos
  históricos o Claude Code já apagou) mais o que ainda existe nos históricos, e
  passa de novo o filtro de segredos. Só troca se o novo não tiver menos
  mensagens; o antigo fica guardado como `indice.db.antes-de-refazer-<data>`
  (apague à mão quando tiver certeza).
- Descartar o arquivo acumulado é outra coisa, e decisão do dono: apagar a
  pasta do arquivo (`~/Arquivo-<agente>`) à mão. Nenhum comando faz isso sozinho.
- Tudo o que mexe no banco (a rodada do hook, `--apagar`, `--refazer` e a
  importação do `lembrar.py`) usa a mesma trava (`<arquivo>/.trava`). A rodada
  do hook não espera: se o arquivo estiver ocupado, fica para a próxima.
- O módulo nunca derruba o agente: qualquer erro no hook é registrado e ele sai
  calado.

## Cópia de segurança do arquivo
O arquivo tem conversa privada. Ele NÃO entra no `backup.sh` por padrão. Se o
dono quiser cópia, que seja cifrada (por exemplo, um remote `crypt` do rclone
com senha dele) ou para outra máquina da casa.
