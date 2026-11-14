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
(com a chave da Groq no `ponte.env`), mensagens em rajada, atraso e do comando
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
| `ponte/ponte.env.exemplo` | Modelo da configuração (token, pasta do agente, nome, chave da Groq) |
| `ponte/VERSAO` | A versão da ponte |
