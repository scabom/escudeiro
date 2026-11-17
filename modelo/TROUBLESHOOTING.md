# Socorro — quando o agente não responde

> Guia rápido para você mesmo resolver, sem precisar de ninguém técnico.
> Regra de ouro: quase tudo se resolve FECHANDO a janela do agente e abrindo
> de novo com o comando de sempre. A conversa NÃO se perde.

O comando de sempre (o que acorda o agente no Claude Code) é **uma linha só**,
colada de uma vez no Terminal (Cmd + Espaço → "Terminal" → Enter):

    cd "<a pasta do agente>" && claude --continue --channels plugin:telegram@claude-plugins-official

Se o seu agente roda no **Codex**, quem precisa estar ligada é a ponte; veja o
`codex/LEIA-ME.md` do pacote do Escudeiro.

---

## 0. Ainda na instalação? Os tropeços mais comuns

**"command not found: claude"**: o computador ainda não sabe onde o Claude Code
foi instalado. Feche a janela do Terminal e abra uma nova. Se continuar, instale
o Claude Code de novo pelo site oficial (claude.com/claude-code).

**"/plugin isn't available in this environment"**: você não está no Claude Code,
e sim no chat comum do site ou do aplicativo. Abra o Claude Code pelo Terminal.

**"Confiança no workspace necessária"**: ele está perguntando se você confia nos
arquivos dessa pasta. É a sua própria pasta: responda que **sim, confia**.

## 1. O bot ficou mudo no Telegram

Cheque nesta ordem:

**A janela do agente está aberta?** O agente vive dentro daquela janela do
Terminal (ou de uma `screen`, se você usa o `iniciar.sh`). Fechou a janela = bot
mudo. O Mac dormiu ou desligou = bot mudo. Abra de novo com o comando de sempre.

**O `bun` está instalado?** O Telegram do Claude Code roda em cima de um
programa chamado **bun**. Sem ele o bot fica mudo e **nenhuma mensagem de erro
aparece**. No Terminal, digite `bun --version`: respondeu um número, está tudo
certo. Deu erro? Instale e **feche e reabra o Terminal** depois:

    curl -fsSL https://bun.sh/install | bash

**Você rodou o comando COM o `--channels`?** Este pedaço aqui:

    --channels plugin:telegram@claude-plugins-official

Sem ele, o Claude Code abre normalmente, mas o Telegram **não liga**. Fica tudo
parecendo certo e o bot mudo.

## 2. "Ele fica digitando e não responde" (ou o código de pareamento não chega)

Quase sempre é **duas janelas abertas ao mesmo tempo** (o erro 409). Dois
agentes brigando pelo mesmo bot = nenhum dos dois responde.

Feche **TODAS** as janelas de Terminal (e as `screen`: `screen -ls` lista,
`screen -X -S <nome> quit` fecha) e abra **UMA** só, com o comando de sempre.
Depois mande `/start` para o bot no Telegram. Se o código de pareamento ainda não
vier, tente pelo Telegram do **celular** (ou do computador): trocar de aparelho
costuma resolver.

## 3. Ficou mudo depois de reiniciar o Mac, com um aviso tipo "1 setup issue: MCP"

Problema conhecido: fica um arquivo de "cache" travado e o Telegram é pulado ao
ligar. Conserto (uma linha, no Terminal):

    rm ~/.claude/mcp-needs-auth-cache.json

Depois é só abrir o agente de novo com o comando de sempre.

## 4. "Ele esqueceu do que a gente falou"

**Você religou com `--continue`?** É esse pedacinho do comando que faz ele
retomar a MESMA conversa. Sem ele, o agente começa uma conversa nova e parece
que perdeu a memória.

Se religou certo e mesmo assim ele parece perdido, peça no Telegram: *"dá uma
olhada no seu working-memory antes de responder"*. Ele lê o caderninho e volta
ao normal.

## 5. "Mandei mensagem e ele nunca respondeu"

Se o agente estava desligado (janela fechada / Mac desligado) na hora em que
você mandou, a mensagem pode **se perder**. É normal e não quebrou nada. Acorde
ele com o comando de sempre e **mande a mensagem de novo**.

## 6. A rotina diária dele parou de chegar

Rotinas pedidas ao agente rodam em corrente: cada rodada faz o trabalho e marca a
próxima. Se o Mac estava desligado na hora, o elo seguinte não foi criado e a
corrente parou. É só pedir: *"a rotina de X parou, remarca para mim"*.

O **bom-dia**, o **backup** e os **vigias** são outra coisa: rodam pelo próprio
macOS (LaunchAgents). Se pararam, confira com `launchctl list | grep escudeiro`
e veja os logs em `~/Library/Logs/Escudeiro/<rótulo>/` (as rotinas instaladas
gravam lá, fora da pasta do agente). Rotina pausada depois de 10 falhas: apague
a marca `estado/<rotina>.pausada` dessa mesma pasta. Mudou o `escudeiro.conf`?
Rode o `mac/launchd/instalar-launchd.sh` do pacote de novo: as rotinas usam uma
cópia da configuração feita na instalação.

## 7. Ele avisou que ia "organizar a cabeça" (compactar)

Normal! De tempos em tempos ele resume a conversa para caber mais coisa na
memória. Some por alguns segundos e volta lembrando do que importa.

## 8. Mandei um áudio e ele não entendeu (ou disse que não escuta)

Abra o arquivo `audio.json`, na pasta do agente, e veja o que está escrito em
`provider`:

- **`"groq"`**: a chave (`groq_api_key`) pode ter sido apagada ou revogada.
  Crie outra em **console.groq.com/keys** (é grátis) e cole no `audio.json`
  você mesmo. Não mande a chave pelo Telegram.
- **`"local"`**: confira se o `transcrever.py` está na pasta.
- **`"off"`** ou arquivo ausente: está desligado mesmo. Peça: *"liga a
  transcrição de áudio"*.

Enquanto isso ele continua respondendo tudo por texto, normalmente.

## 9. Conectei o Google e ele diz que não vê meu e-mail, agenda ou Drive do Google

**As conexões só entram quando a janela é aberta de novo.** Feche a janela do
agente e abra com o comando de sempre. Se ainda assim ele não enxergar, rode
`/mcp` na janela dele e confira se as conexões aparecem como conectadas.

## Como reiniciar as coisas (passo a passo)

- **Fechar a janela do agente:** clique no **X** da janela do Terminal (ou
  Cmd + Q). Pode fechar sem medo: a conversa não se perde.
- **Abrir o Terminal:** Cmd + Espaço, digite `Terminal`, Enter.
- **Colar um comando:** clique dentro da janela, Cmd + V e depois Enter. Cole a
  linha inteira de uma vez só.
- **"Feche e reabra o Terminal"** (depois de instalar um programa novo):
  programa recém-instalado só passa a existir em janela nova.

## Nada disso resolveu

Peça ao próprio agente, pelo Telegram ou na janela dele: *"segue o
TROUBLESHOOTING comigo"*. Ele confere item por item, sem mudar nada sem
perguntar.
