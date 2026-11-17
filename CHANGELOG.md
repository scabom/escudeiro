# Histórico de versões

## 1.0.1

Versão de consertos, depois de uma revisão de segurança e de funcionamento
feita antes da publicação. Nada muda no jeito de conversar com o agente; muda o
que acontece nos bastidores.

### Segurança
- **Rotinas do macOS fora do alcance do agente.** O `instalar-launchd.sh` agora
  copia os scripts do pacote para `~/Library/Application Support/Escudeiro/`,
  sem permissão de escrita, e as rotinas rodam de lá. Antes elas rodavam da
  pasta do agente, onde ele escreve: mudar um script ali virava código rodando
  mais tarde fora da cerca do Codex. Os logs e as marcas das rotinas foram para
  `~/Library/Logs/Escudeiro/`. **Mudou o `escudeiro.conf` ou atualizou o
  Escudeiro? Rode o instalador de novo.**
- **`escudeiro.conf` lido como dado, nunca executado.** Os scripts não fazem
  mais `source` dele: só `CHAVE="valor"` das chaves conhecidas, com `$HOME`
  expandido e nada mais. O instalador ainda recusa programa ou arquivo de token
  dentro da pasta do agente e destino de backup que não seja um remote com nome.
- **Segredo nunca na linha de comando.** Novo `ferramentas/transcrever-groq.sh`,
  que lê a chave do `audio.json` e a entrega ao `curl` pela entrada padrão. O
  manual agora manda usar ele e o `avisar-telegram.sh`, em vez de montar o
  `curl` com a chave ou o token escritos no comando.
- **`conferir-antes-do-github.sh` olha o histórico inteiro.** Procura dado
  pessoal e segredo no conteúdo de todas as versões de todos os arquivos
  (inclusive os apagados) e nas mensagens dos commits, e não diz "LIMPO" se a
  cópia de trabalho estiver diferente do último commit.
- **Memória sem perda:** antes de gravar, troca por `[SEGREDO REMOVIDO]` os
  segredos com formato conhecido (tokens, chaves de API, "senha: ..."). O texto
  agora diz com franqueza que isso não pega tudo, e há `arquivar.py --apagar
  <nº>` para tirar uma mensagem do arquivo.
- **`gerar-manuais.py`:** o JSON da memória sem perda é gravado com
  `json.dumps`, e os nomes do agente e do dono são conferidos (nada de aspas,
  `$`, barra ou `..`), porque também viram caminho e configuração.

### Consertos
- **Backup:** duas origens com o mesmo nome final (`/a/projeto` e `/b/projeto`)
  se apagavam uma à outra. Agora o backup recusa antes de copiar e aceita um
  apelido (`caminho=apelido` no `BACKUP_ORIGENS`). O histórico de versões passou
  a ser uma pasta por execução, e não por dia.
- **Falha não vira mais "ok" para o vigia:** o `bom-dia.sh` sai com erro quando
  algo não foi entregue (inclusive lembrete avulso); o `confere-backup.sh` sai
  com 3 (problema, aviso entregue) ou 4 (problema, aviso não entregue); e o
  `rotina-vigiada.sh` tenta avisar de novo quando o aviso anterior não chegou.
- **`arquivar.py --refazer`** não perde mais conversas antigas: monta o índice
  novo ao lado, a partir do índice atual mais os históricos que ainda existem,
  e só troca se não ficar menor (o antigo fica guardado).
- **`limpar-dados-pessoais.py`** recusa gravar por cima da entrada (mesmo por
  link) e não substitui uma saída que já existe sem `--substituir`.
- **`instalar-launchd.sh`** cria `~/Library/LaunchAgents` se ela não existir,
  gera os plists com o `plistlib` (caminho com `&` ou `<` não quebra mais o
  arquivo) e sai com erro se alguma rotina pedida não foi instalada. Os modelos
  `*.plist.modelo` saíram: o instalador gera tudo.
- **Lembrete mensal** atravessa a virada do mês ("MENSAL:31 | 2" aparece nos
  dias 1 e 2 do mês seguinte), e mês sem o dia pedido usa o último dia do mês.
- **Ponte do Codex:** acha o Codex instalado pelo Homebrew (Apple Silicon e
  Intel), por gerenciadores de versão do Node e pelo comando `codex` do PATH;
  `CODEX_JS` está documentado no `ponte.env.exemplo`. As mensagens de erro
  apontam para a nova seção "Socorro da ponte" do `codex/LEIA-ME.md`, em vez de
  arquivos que não vêm no pacote.
- **`INSTALAR.md`:** os passos que voltam para a pasta do Escudeiro (a ponte e
  o instalador das rotinas) agora dizem de qual pasta rodar, com caminho
  completo.

### Terceira revisão (ainda na 1.0.1)
- **Instalador das rotinas:** um link DENTRO da pasta do agente apontando para fora
  era aceito (o agente poderia trocá-lo depois). Agora o instalador segue o caminho
  pedaço por pedaço, link por link (inclusive cadeias externo → dentro → externo), e
  recusa se qualquer lugar dessa resolução cair na pasta do agente. A comparação é
  feita também pela identidade no disco, não só pela grafia (no macOS "Agente" e
  "agente" são a mesma pasta).
- **Arquivo sem perda:** o `--apagar` avisa que as cópias antigas do índice
  (`indice.db.antes-de-refazer-*`) também podem ter a mensagem.

### Segunda revisão (ainda na 1.0.1)
- **Instalador das rotinas:** `RCLONE`, `RCLONE_CACERT`, `TELEGRAM_ENV` e
  `TELEGRAM_ACESSO` só com caminho absoluto (`$HOME/...` ou `~/...` valem). Um
  caminho relativo era conferido a partir de uma pasta e usado a partir de
  outra. O caminho conferido (inclusive o do rclone achado sozinho) é o mesmo
  gravado na cópia instalada, e as rotinas recusam rodar com caminho relativo.
- **`conferir-antes-do-github.sh`:** passando uma subpasta, ele agora confere o
  repositório inteiro (a partir da raiz), e procura senha escrita também nas
  mensagens dos commits.
- **Memória sem perda:** mensagem apagada com `--apagar` entra numa lista de
  apagadas e não volta mais, nem com `--refazer`. A rodada normal, `--apagar`,
  `--refazer` (até a troca dos arquivos) e a importação do `lembrar.py` usam a
  mesma trava.
- **Rotina pausada:** "pausada" e "o aviso da pausa chegou" são marcas
  separadas. Se o aviso não chegou, cada chamada (e o vigia de atrasos) tenta
  de novo, sem rodar a rotina; as pausadas aparecem no bom-dia.
- **Áudio no Codex:** o socorro da ponte não sugere mais uma conta separada
  (o Codex roda com a mesma conta da ponte, então não adiantaria). Ficou
  documentada a limitação e o caminho seguro: no Mac, ponte sem áudio.

### Licença
- O Escudeiro passa a ser **MIT** (arquivo `LICENSE`). O aviso MIT do DG Claw
  continua em `licencas-de-terceiros/`.

## 1.0.0

Primeira versão do Escudeiro: o molde limpo, reaproveitável e sem dado pessoal
de um agente pessoal que roda no Claude Code (macOS) e conversa pelo Telegram,
com um modo para Codex.

### O que vem
- **Manual em fonte única** (`modelo/MANUAL-BASE.md`) com marcadores
  (`{{NOME_AGENTE}}`, `{{NOME_DONO}}`, `{{PERSONALIDADE}}`) e blocos por motor.
  `ferramentas/gerar-manuais.py` gera o `CLAUDE.md` (Claude Code) e o
  `AGENTS.md` (Codex), e batiza um agente novo com `--saida`.
- **Regra zero do Telegram**, foto, arquivo e áudio. Escuta pela **Groq** como
  caminho sugerido, com o passo a passo da chave grátis e o `audio.json.exemplo`.
- **Memória**: caderninho com gavetas (`working-memory.md`), livro com sumário
  (`memoria/`), diário com resumos de semana e mês, e o **arquivo sem perda**
  (`ferramentas/memoria-sem-perda/`, só no Claude Code).
- **Como anotar**, **manutenção diária**, **volta da compactação**, **corrente
  de avulsos** para tarefas recorrentes, **atalho para acordar**.
- **Hooks** (Claude Code): `fio-telegram.py`, `checar-memoria.py`,
  `arquivar.py`, todos com `$CLAUDE_PROJECT_DIR`.
- **Ferramentas**: `bom-dia.sh` + `lembretes.sh` (lembretes com data, mensal e a
  cada N dias), `vigia-atrasos.py` + `rotina-vigiada.sh`, `backup.sh` +
  `confere-backup.sh` (rclone, destino configurável, canário lido de volta),
  `conferir-antes-do-github.sh`, `limpar-dados-pessoais.py`,
  `avisar-telegram.sh`, `iniciar.sh`. Configuração num lugar só:
  `escudeiro.conf`.
- **Habilidades**: `dupla-checagem`, `lembrar`, `registrar`, `guardar-curso`,
  `lupa` (a lupa descreve o método; as ferramentas de fatiar e fundir mapas são
  dependência opcional, não incluída).
- **Segurança**: `memoria/regras-de-seguranca.md` e `.gitignore` do modelo.
- **macOS**: modelos de LaunchAgent (`mac/launchd/`) para bom-dia, backup,
  confere-backup e vigia-atrasos, com `instalar-launchd.sh`.
- **Codex**: a ponte Telegram ↔ Codex (`codex/ponte/`, versão no `VERSAO` dela)
  e o `codex/LEIA-ME.md` com o que muda.

### Ainda não (fica para depois)
- **Linux**: fica para a v1.1. Os scripts usam o `date -j` do macOS, o
  `pmset` e o launchd; no Linux é preciso trocar por `date -d`, systemd ou cron.
- **Windows** para o modo Claude: não testado no Escudeiro.
- **Memória sem perda no Codex**: o `arquivar.py` só lê o histórico do Claude
  Code.
- LaunchAgent pronto para manter a ponte do Codex ligada no Mac.
- Licença do projeto: pendente (resolvida na 1.0.1).
