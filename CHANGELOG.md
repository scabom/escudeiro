# Histórico de versões

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
- Licença do projeto: pendente (veja `LICENCA-PENDENTE.txt`).
