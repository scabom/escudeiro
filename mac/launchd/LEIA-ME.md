# Rotinas do macOS (LaunchAgents)

Quatro rotinas que rodam pelo próprio macOS, sem depender da janela do agente:

| Rotina | O que faz | Horário padrão |
| --- | --- | --- |
| `bom-dia` | Estado da casa + lembretes do `lembretes.txt`, pelo Telegram | 7h10 |
| `backup` | Copia a pasta do agente (e as que você escolher) com o rclone | 22h00 |
| `confere-backup` | Segunda ronda: lê de volta a marca do backup no destino | 22h40 |
| `vigia-atrasos` | Avisa quando uma rotina devia ter rodado e não rodou | a cada 30 min |

Todas rodam embrulhadas pelo `ferramentas/rotina-vigiada.sh` da pasta do agente:
se falharem, o dono recebe aviso; se falharem 10 vezes seguidas, são pausadas.

## Instalar

    bash mac/launchd/instalar-launchd.sh ~/agentes/aurora              # mostra o que faria
    bash mac/launchd/instalar-launchd.sh ~/agentes/aurora --ligar      # cria e liga todas
    HORA_BOM_DIA=8 MINUTO_BOM_DIA=0 bash mac/launchd/instalar-launchd.sh ~/agentes/aurora --ligar bom-dia

Antes, configure o `escudeiro.conf` da pasta do agente (Telegram e, para o
backup, `BACKUP_DESTINO`). Teste cada script à mão primeiro:

    SEM_ENVIO=1 bash ~/agentes/aurora/ferramentas/bom-dia.sh

## Coisas para saber
- O Mac dormindo não roda nada. O launchd dispara ao acordar o que perdeu do
  `StartCalendarInterval` (uma vez), e o `vigia-atrasos` avisa se algo ficou
  para trás.
- Pasta do agente dentro de Documentos, Mesa ou Downloads pode ser bloqueada
  pelo macOS para rotinas em segundo plano. Prefira algo como `~/agentes/<nome>`.
- Linux (systemd/cron) fica para a v1.1.
