# Instalar o Escudeiro no Mac

Leva uns 30 a 40 minutos, com calma. Os comandos vão no **Terminal** (Cmd +
Espaço, digite "Terminal", Enter). Cole cada linha inteira e aperte Enter.

Nos exemplos, o agente se chama **Aurora**, o dono **Ana**, e a pasta do agente
fica em `~/agentes/aurora`. Troque pelos seus.

> Dica: evite pôr a pasta do agente dentro de Documentos, Mesa ou Downloads. O
> macOS bloqueia essas pastas para as rotinas em segundo plano.

---

## Parte A — comum aos dois jeitos

### A1. Programas
- **Python 3** (já vem com o macOS; teste com `python3 --version`. Se pedir para
  instalar as "ferramentas de linha de comando", aceite).
- **Node.js 18 ou mais novo** (nodejs.org, a versão LTS). Teste: `node --version`.

### A2. O bot do Telegram
1. No Telegram, abra uma conversa com **@BotFather**.
2. Mande `/newbot`, escolha um nome ("Aurora") e um usuário terminado em `bot`.
3. Ele te dá o **token** (algo como `1234567890:AAH...`). Guarde: é a chave do
   bot. Nunca mande o token por mensagem, e-mail ou print.

### A3. Copiar e batizar a pasta do agente
Na pasta onde você baixou o Escudeiro:

    mkdir -p ~/agentes
    cp -R modelo ~/agentes/aurora
    cp ~/agentes/aurora/escudeiro.conf.exemplo ~/agentes/aurora/escudeiro.conf
    python3 ferramentas/gerar-manuais.py --saida ~/agentes/aurora --nome Aurora --dono Ana \
      --personalidade "Aurora é calma, direta e bem-humorada. Explica sem complicar e sempre pergunta antes de mexer no que é importante."

Isso escreve o `CLAUDE.md` e o `AGENTS.md` já com o nome e a personalidade, e
preenche os nomes no caderninho, no `escudeiro.conf` e na memória sem perda.
Personalidade comprida? Escreva num arquivo e use `--personalidade-arquivo`.

Se não for usar o Codex, pode apagar o `AGENTS.md` (e vice-versa).

### A4. Escuta de áudio (opcional, sugerido)
1. Entre em **console.groq.com**, crie a conta (não pede cartão).
2. Em **API Keys**, clique em **Create API Key** e copie a chave (`gsk_...`).
3. Cole você mesmo, no computador (nunca pelo Telegram). No Claude Code:

       cd ~/agentes/aurora
       cp audio.json.exemplo audio.json
       open -e audio.json          # cole a chave no lugar de gsk_COLE_SUA_CHAVE_AQUI e salve
       chmod 600 audio.json

   No Codex, a chave vai no `ponte.env` (Parte C).

O áudio vai para os servidores da Groq para ser transcrito.

---

## Parte B — com o Claude Code (o jeito principal)

### B1. Claude Code e bun
1. Instale o Claude Code pelo site oficial (claude.com/claude-code) e entre na
   sua conta: `claude` no Terminal, e siga o login.
2. Instale o **bun** (o canal do Telegram roda em cima dele):

       curl -fsSL https://bun.sh/install | bash

   Feche o Terminal e abra de novo. Teste: `bun --version`.

### B2. O plugin do Telegram
Dentro do Claude Code (`claude` no Terminal), rode:

    /plugin install telegram@claude-plugins-official

Depois, ainda dentro dele, configure o token do bot (A2) com
`/telegram:configure` e siga as instruções. Saia com `/exit`.

### B3. Primeira vez acordando o agente

    cd ~/agentes/aurora && claude --channels plugin:telegram@claude-plugins-official

- Ele vai perguntar se você confia na pasta: **sim** (é a sua pasta).
- No Telegram, mande `/start` para o seu bot. Vai chegar um código de
  pareamento; aprove no Claude Code com `/telegram:access` (siga o que ele
  mostrar). Pronto: só você conversa com ele.
- Mande "oi". A primeira resposta tem de chegar no Telegram.

Das próximas vezes, use `--continue` (retoma a mesma conversa):

    cd ~/agentes/aurora && claude --continue --channels plugin:telegram@claude-plugins-official

Para deixar rodando sem janela: `screen -dmS aurora ~/agentes/aurora/iniciar.sh`
(espiar: `screen -r aurora`; sair sem desligar: Ctrl+A e depois D). Nunca deixe
duas janelas do agente abertas ao mesmo tempo (erro 409, bot mudo).

### B4. A memória sem perda
Rode uma vez à mão (os hooks já estão no `.claude/settings.json`):

    python3 ~/agentes/aurora/ferramentas/memoria-sem-perda/arquivar.py --falar

Recomendado: em `~/.claude/settings.json`, `"cleanupPeriodDays": 365`. Detalhes
em `ferramentas/memoria-sem-perda/INSTALAR.md`.

Continue na **Parte D**.

---

## Parte C — com o Codex (o jeito alternativo)

Leia antes o `codex/LEIA-ME.md`: ali está o que muda (sem hooks, sem internet
nos comandos, sem arquivo sem perda na v1.0).

1. Instale o Codex e entre com a conta do ChatGPT:

       npm install -g @openai/codex
       codex login

2. Habilidades no lugar que o Codex procura:

       mkdir -p ~/agentes/aurora/.agents/skills
       cp -R ~/agentes/aurora/.claude/skills/* ~/agentes/aurora/.agents/skills/

3. A ponte, FORA da pasta do agente:

       cp -R codex/ponte ~/ponte-aurora
       cd ~/ponte-aurora
       cp ponte.env.exemplo ponte.env && chmod 600 ponte.env
       open -e ponte.env

   Preencha `TELEGRAM_BOT_TOKEN=` (o token da A2), `PASTA_AGENTE=` com o caminho
   completo (o que aparecer quando você rodar `echo ~/agentes/aurora`),
   `NOME_AGENTE=Aurora` e, se quiser áudio,
   `GROQ_API_KEY=`. Salve.

4. Confira, pareie e ligue:

       node ponte.mjs --conferir
       node ponte.mjs --parear        # mande para o bot o código de 6 dígitos que aparece
       node ponte.mjs --testar
       node ponte.mjs                 # fica rodando; deixe esta janela aberta

5. No `~/agentes/aurora/escudeiro.conf`, aponte o Telegram para a ponte (para o
   bom-dia e os avisos):

       TELEGRAM_ENV="$HOME/ponte-aurora/ponte.env"
       TELEGRAM_ACESSO="$HOME/ponte-aurora/acesso.json"

---

## Parte D — as rotinas do Mac (bom-dia, backup e vigias)

### D1. Bom-dia e lembretes
Teste sem enviar:

    SEM_ENVIO=1 bash ~/agentes/aurora/ferramentas/bom-dia.sh

E com envio de verdade (tem de chegar no Telegram):

    bash ~/agentes/aurora/ferramentas/avisar-telegram.sh "teste do Escudeiro"

Se o chat não for achado sozinho, ponha o número do seu chat em
`TELEGRAM_CHAT_ID` no `escudeiro.conf`.

### D2. Backup (opcional)
1. Instale o rclone (rclone.org/install) e crie um destino com `rclone config`
   (Google Drive, Dropbox, outro disco...). Para o Google Drive, o mais seguro é
   um client_id próprio com o escopo `drive.file`.
2. No `escudeiro.conf`: `BACKUP_DESTINO="<nome do remote>:Backup-Aurora"` (e, se
   quiser, outras pastas em `BACKUP_ORIGENS`).
3. Teste: `bash ~/agentes/aurora/ferramentas/backup.sh` e depois
   `bash ~/agentes/aurora/ferramentas/confere-backup.sh`.

O arquivo sem perda (`~/Arquivo-Aurora`) NÃO entra no backup por padrão: é
conversa privada.

### D3. Ligar as rotinas

    bash mac/launchd/instalar-launchd.sh ~/agentes/aurora           # mostra o que faria
    bash mac/launchd/instalar-launchd.sh ~/agentes/aurora --ligar   # cria e liga

Só quer algumas? Diga quais no fim (`--ligar bom-dia vigia-atrasos`). Horários
e detalhes em `mac/launchd/LEIA-ME.md`.

### D4. Mac sempre acordado (recomendado)
Ajustes do Sistema → Bateria (ou Economia de Energia) → impedir que o Mac durma
sozinho com a tela desligada, se ele ficar na tomada. Mac dormindo = agente
dormindo.

---

## Parte E — a primeira conversa

Mande pelo Telegram algo como: *"oi! me conta quem você é e o que precisa saber
de mim"*. Ele vai começar a te conhecer e anotar no caderninho.

Se for guardar o seu agente num repositório git, lembre: **nada de commit sem
perguntar**, e memória, diário e registros nunca vão para repositório público
(o `.gitignore` do modelo tem as linhas prontas para descomentar).
