# Escudeiro no Codex

O Escudeiro nasceu no Claude Code, mas o mesmo agente (a mesma pasta, a mesma
memória) pode rodar no **Codex**, com a assinatura do ChatGPT. Este arquivo
explica o que muda.

## 1. O Telegram vai pela ponte

O Claude Code tem um canal de Telegram oficial (o plugin). O Codex não tem. Quem
faz esse papel é a **ponte** (`codex/ponte/ponte.mjs`), um programa em Node sem
dependências:

1. Fica escutando o bot do Telegram.
2. Mensagem do celular pareado? Entrega ao Codex (`codex exec`, continuando a
   mesma conversa com `codex exec resume`).
3. Manda a resposta FINAL do agente de volta pelo bot.

Ela já cuida de foto, arquivo (salvos em `entrada/` na pasta do agente), áudio
(com a chave da Groq no `ponte.env`, só onde a cerca do Codex consegue
proteger essa chave: veja o item S3 do Socorro; no Mac, hoje, fica sem áudio), mensagens em rajada, atraso e do comando
`/nova`. Na primeira mensagem de uma conversa nova, ela cola o
`working-memory.md` junto, para o agente começar sabendo do "agora".

### As travas da ponte (não tire nenhuma)
- Só conversa com quem foi pareado (`acesso.json`, criado pelo `--parear`).
- O Codex roda SEMPRE com a cerca (`sandbox_mode=workspace-write`): escreve só
  na pasta do agente, **sem internet nos comandos**.
- Desliga hooks, plugins, conectores (apps) e MCP em toda chamada.
- Recusa rodar como root/administrador e recusa uma pasta `.codex` dentro da
  pasta do agente.
- Uma ponte por bot (contra o erro 409).
- `node ponte.mjs --testar` confere o isolamento de verdade.

### Ligar no Mac
A ponte veio de um pacote pensado primeiro para Windows: o `ponte.env.exemplo`
fala em "Bloco de Notas" e traz um caminho de exemplo do Windows. No Mac:

    cp -R codex/ponte ~/ponte-aurora   # a ponte TEM de ficar FORA da pasta do agente
    cd ~/ponte-aurora
    cp ponte.env.exemplo ponte.env
    chmod 600 ponte.env
    # edite ponte.env: TELEGRAM_BOT_TOKEN=..., NOME_AGENTE=...,
    #   PASTA_AGENTE=/caminho/completo/da/pasta/do/agente
    node ponte.mjs --conferir
    node ponte.mjs --parear            # o dono manda pro bot o código de 6 dígitos da tela
    node ponte.mjs --testar
    node ponte.mjs                     # liga (fica rodando)

A pasta da ponte precisa ficar FORA da pasta do agente (a ponte se recusa a
ligar se estiver dentro): lá dentro o Codex escreve, e poderia mexer no
`acesso.json` ou no próprio programa. A conferência de "pasta trancada" da
ponte só existe no Windows; no Mac ela é pulada, em silêncio. Para mais
isolamento, rode a ponte e o agente numa conta de usuário separada do macOS,
padrão (sem administrador): a ponte recusa rodar como root. As mensagens de
erro da ponte citam caminhos do Windows (`C:\PonteAgente`, conta "Agente"):
no Mac, leia como "a pasta da ponte" e "a conta do agente".

A ponte acha o Codex sozinha (no Node que a roda, nos lugares comuns do npm e
no comando `codex` do PATH). Se ela disser "não achei o Codex", informe o
caminho no `ponte.env`, na linha `CODEX_JS=`: o caminho é o que sai de
`realpath "$(command -v codex)"` e termina em `bin/codex.js`.

A ponte também se recusa a ligar se o `~/.codex/config.toml` da conta pedir
algo que abre a cerca (modo sem cerca, `writable_roots`, `mcp_servers`,
`notify`). Use uma conta (ou um `CODEX_HOME`) só para o agente.

Atenção, dito com franqueza: a conta que roda a ponte precisa LER o token do bot
(`ponte.env`), e a cerca do Codex não impede leitura. Se o token vazar, revogue
no @BotFather e gere outro.

Para religar sozinho no Mac, um LaunchAgent com `node <pasta da ponte>/ponte.mjs`
e `KeepAlive` resolve; o Escudeiro 1.0 ainda não traz esse modelo pronto
(o `iniciar-ponte.cmd` do pacote original é só para Windows e ficou de fora).

## 2. Os hooks do Claude não rodam no Codex

No Claude Code, três hooks do `.claude/settings.json` trabalham sozinhos. No
Codex eles **não rodam**: o Codex tem um sistema de hooks próprio (com outro
formato e outra configuração, em `.codex/`), mas a ponte desliga os hooks em
toda chamada, de propósito, e recusa uma pasta `.codex` dentro da pasta do
agente. O que muda:

| Hook do Claude | O que fazia | No Codex |
| --- | --- | --- |
| `fio-telegram.py` | Injetava as últimas mensagens reais do Telegram antes de cada resposta | Não precisa: a ponte continua a mesma conversa e cola o `working-memory.md` na conversa nova. Se o agente perder o fio, ele lê o caderninho e o diário (está no `AGENTS.md`). |
| `checar-memoria.py` | Depois de cada gravação na memória, procurava texto malicioso e tamanho acima do teto | O agente roda à mão: `python3 ferramentas/checar-memoria.py --tamanhos` depois de gravar, e `--texto <arquivo>` quando o texto veio de fora. Está no `AGENTS.md`. |
| `memoria-sem-perda/arquivar.py` | Arquivava a conversa do Telegram com busca por palavra | **Não funciona no Codex na v1.0.** Ele lê o histórico no formato do Claude Code (`~/.claude/projects/`); o Codex guarda o dele em outro lugar e formato, e o agente nem deve abrir a pasta do Codex. A habilidade `lembrar` fica sem arquivo; use `memoria/` e `diario/`. |

Outras diferenças:
- **Sem internet nos comandos**: o agente não manda mensagem por `curl` nem
  transcreve áudio sozinho (quem transcreve é a ponte).
- **Sem agendamento próprio**: o agente só acorda com mensagem. Mas as rotinas
  do macOS (`mac/launchd/`: bom-dia, backup, vigias) rodam fora do Codex e
  funcionam igual. No `escudeiro.conf`, aponte o Telegram para a ponte:

      TELEGRAM_ENV="/caminho/da/ponte/ponte.env"
      TELEGRAM_ACESSO="/caminho/da/ponte/acesso.json"

  E o bom-dia confere se a ponte está de pé (`ponte.mjs` rodando).
- **Sem e-mail, agenda e Drive do Google** (a ponte desliga os conectores).
- O `TROUBLESHOOTING.md` do modelo é do Claude Code. Para a ponte, os sintomas
  mais comuns são: ponte desligada (bot mudo), duas pontes (erro 409) e
  `ponte.env` incompleto; o `node ponte.mjs --conferir` diz qual é.

## Socorro da ponte

As mensagens de erro da ponte apontam para estes itens. Em todos eles, rode
`node ponte.mjs --conferir` depois do conserto: ele diz se ficou tudo certo.

**S1. "Apareceu uma pasta .codex dentro da minha pasta".** Uma pasta `.codex`
dentro da pasta do agente poderia mudar a configuração do Codex (e abrir a
cerca). Ninguém da casa precisa dela ali. Na sua conta, apague a pasta
`.codex` de dentro da pasta do agente (`rm -r <pasta do agente>/.codex`),
confira que não sobrou nada (`ls -a <pasta do agente>`) e pergunte ao agente o
que ele estava fazendo quando ela apareceu.

**S2. "Da última vez o Codex não fechou nem à força".** A ponte deixou a marca
`estado/codex-preso.txt` (dentro da pasta da ponte) porque um Codex não fechou.
Reinicie o computador (garante que não sobrou Codex rodando), apague esse
arquivo e ligue a ponte de novo. Se repetir sempre, diminua o
`LIMITE_MINUTOS` do `ponte.env` e veja o `ponte.log`.

**S3. "Não consegui confirmar que a chave do áudio (Groq) está protegida".**
Com `GROQ_API_KEY` no `ponte.env`, a ponte só liga se confirmar que os comandos
do agente NÃO conseguem ler esse arquivo. A limitação, dita com franqueza: o
Codex que responde é um processo FILHO da ponte e roda com a mesma identidade
(a mesma conta de usuário) que ela. Tudo o que a ponte consegue ler, o Codex
filho também consegue, a menos que a cerca do Codex bloqueie a leitura. No Mac,
a cerca do Codex não bloqueia leitura; mudar a ponte de conta não resolve, porque
o filho iria junto para a mesma conta. No Windows, a cerca recomendada (com
administrador) do Codex pode bloquear, e o `node ponte.mjs --testar` confirma.

O caminho seguro, e o padrão no Mac: **ligar sem áudio**. Apague a linha
`GROQ_API_KEY` do `ponte.env` (e revogue a chave em console.groq.com/keys, se
ela já esteve ali), rode `node ponte.mjs --testar` e ligue de novo: o agente
volta a funcionar e responde aos áudios pedindo texto.

**S4. Trancar a pasta da ponte (só Windows).** No Windows, a ponte exige que a
conta do agente NÃO consiga escrever na pasta da ponte, mas consiga escrever na
subpasta `estado`. Na conta da dona, num Prompt de Comando aberto como
administrador (troque `Agente` pelo nome da conta do agente):

    icacls C:\PonteAgente /inheritance:r /grant:r *S-1-5-32-544:(OI)(CI)F *S-1-5-18:(OI)(CI)F Agente:(OI)(CI)RX
    icacls C:\PonteAgente\estado /grant Agente:(OI)(CI)M

(`*S-1-5-32-544` é o grupo Administradores e `*S-1-5-18` é o Sistema, em
qualquer idioma do Windows.) O Escudeiro é feito primeiro para o Mac: no
Windows, a ponte não foi testada nesta versão.

## 3. Onde ficam as habilidades no Codex

Pela documentação do Codex (página "Build skills", conferida na criação desta
versão), as habilidades ficam em:

- **na pasta do projeto**: `.agents/skills/<nome>/SKILL.md`, procuradas na pasta
  atual e em cada pasta acima, até a raiz do repositório;
- **do usuário**: `~/.agents/skills/<nome>/SKILL.md`.

O formato do `SKILL.md` é o mesmo das habilidades do Claude (cabeçalho com
`name` e `description`, depois as instruções). Então, para o agente do Codex:

    mkdir -p <pasta do agente>/.agents/skills
    cp -R <pasta do agente>/.claude/skills/* <pasta do agente>/.agents/skills/

**O que eu não consegui confirmar** (teste antes de confiar):
- se o `codex exec`, do jeito que a ponte chama (com `--disable plugins` e
  `--skip-git-repo-check`, numa pasta que talvez não seja repositório git),
  carrega as habilidades de `.agents/skills/`. A documentação fala do Codex
  interativo e da extensão; não diz nada sobre o `exec`. Se não carregar, o
  agente ainda pode abrir o `SKILL.md` à mão: o `AGENTS.md` aponta onde elas
  estão;
- se a pasta `.agents/` (diferente de `.codex/`) fica de fora da recusa da
  ponte. Pelo código da ponte, só `.codex` é recusada.

## O que vem nesta pasta

| Arquivo | O que é |
| --- | --- |
| `ponte/ponte.mjs` | A ponte Telegram ↔ Codex (versão em `ponte/VERSAO`) |
| `ponte/ponte.env.exemplo` | Modelo da configuração (token, pasta do agente, nome, chave da Groq, `CODEX_JS`) |
| `ponte/VERSAO` | A versão da ponte |
