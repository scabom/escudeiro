# Rotinas do macOS (LaunchAgents)

Quatro rotinas que rodam pelo próprio macOS, sem depender da janela do agente:

| Rotina | O que faz | Horário padrão |
| --- | --- | --- |
| `bom-dia` | Estado da casa + lembretes do `lembretes.txt`, pelo Telegram | 7h10 |
| `backup` | Copia a pasta do agente (e as que você escolher) com o rclone | 22h00 |
| `confere-backup` | Segunda ronda: lê de volta a marca do backup no destino | 22h40 |
| `vigia-atrasos` | Avisa quando uma rotina devia ter rodado e não rodou | a cada 30 min |

Todas rodam embrulhadas pelo `rotina-vigiada.sh`: se falharem, o dono recebe
aviso; se falharem 10 vezes seguidas, são pausadas.

## Instalar

O instalador fica nesta pasta do pacote. Rode com o caminho completo (troque
`~/Downloads/escudeiro` pela pasta onde você baixou o Escudeiro):

    bash ~/Downloads/escudeiro/mac/launchd/instalar-launchd.sh ~/agentes/aurora              # mostra o que faria
    bash ~/Downloads/escudeiro/mac/launchd/instalar-launchd.sh ~/agentes/aurora --ligar      # instala e liga todas
    HORA_BOM_DIA=8 MINUTO_BOM_DIA=0 bash ~/Downloads/escudeiro/mac/launchd/instalar-launchd.sh ~/agentes/aurora --ligar bom-dia

Antes, configure o `escudeiro.conf` da pasta do agente (Telegram e, para o
backup, `BACKUP_DESTINO`). Teste cada script à mão primeiro:

    SEM_ENVIO=1 bash ~/agentes/aurora/ferramentas/bom-dia.sh

O instalador sai com código diferente de 0 se qualquer rotina pedida não foi
instalada ou ligada.

## Por que as rotinas não rodam da pasta do agente

O agente escreve na pasta dele (no Codex, é a única pasta onde a cerca deixa
escrever). Se o launchd rodasse um script de lá, bastaria o agente, ou um texto
malicioso que ele leu, mudar esse script para o código rodar mais tarde **fora
da cerca**, com rede e com as permissões da sua conta. Por isso o instalador:

1. copia os scripts **do pacote** (não os da pasta do agente) para
   `~/Library/Application Support/Escudeiro/<rótulo>/ferramentas/`, sem
   permissão de escrita;
2. grava ali uma **cópia conferida** do `escudeiro.conf`, que os scripts leem
   como dado (`CHAVE="valor"`), nunca como código. Ele recusa `RCLONE`,
   `RCLONE_CACERT`, `TELEGRAM_ENV` e `TELEGRAM_ACESSO` que apontem para dentro
   da pasta do agente, e um `BACKUP_DESTINO` que não seja um remote com nome do
   `rclone config`;
3. gera os plists com o `plistlib` (caminho com `&`, `<` ou acento não quebra
   nada), com a cópia instalada como pasta de trabalho;
4. manda os logs e as marcas das rotinas (falhas seguidas, pausa) para
   `~/Library/Logs/Escudeiro/<rótulo>/`.

Da pasta do agente, as rotinas só **leem** dados (`lembretes.txt`,
`lembretes-avulsos.txt`) e a enviam no backup.

**Consequência:** mudou o `escudeiro.conf`, ou atualizou o Escudeiro (baixou
uma versão nova)? **Rode o instalador de novo**, com `--ligar`. As rotinas não
enxergam mudança nos scripts ou na configuração da pasta do agente até lá; o
instalador avisa quando um script da pasta do agente é diferente do pacote.

Isso protege das mudanças feitas DENTRO da cerca do Codex. No Claude Code, que
não tem cerca por padrão, o que protege é a regra de segurança do manual e a
sua aprovação dos comandos.

## Códigos de saída que o vigia conta como falha

- `bom-dia`: 1 se alguma parte do bom-dia ou algum lembrete avulso não chegou.
- `backup`: 1 se alguma origem não foi copiada, se não deu para contar os
  arquivos no destino ou se duas origens iriam para o mesmo lugar.
- `confere-backup`: 3 se achou problema e avisou; 4 se achou problema e o
  aviso não chegou.

## Coisas para saber
- O Mac dormindo não roda nada. O launchd dispara ao acordar o que perdeu do
  `StartCalendarInterval` (uma vez), e o `vigia-atrasos` avisa se algo ficou
  para trás.
- Pasta do agente dentro de Documentos, Mesa ou Downloads pode ser bloqueada
  pelo macOS para rotinas em segundo plano. Prefira algo como `~/agentes/<nome>`.
- Rotina pausada (10 falhas seguidas): apague
  `~/Library/Logs/Escudeiro/<rótulo>/estado/<rotina>.pausada`. Enquanto o aviso
  da pausa não chegar ao dono, cada chamada da rotina (e o `vigia-atrasos`, a
  cada 30 min) tenta avisar de novo, sem rodar a rotina; as pausadas também
  aparecem no bom-dia.
- Para desligar: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/<rótulo>.<rotina>.plist`.
- Linux (systemd/cron) fica para a v1.1.
