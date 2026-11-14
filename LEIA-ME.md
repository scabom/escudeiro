# Escudeiro

Um molde para você ter o seu próprio **agente pessoal**: um assistente com nome,
personalidade e memória, que mora no seu computador e conversa com você pelo
**Telegram**, como se fosse uma pessoa de confiança que te conhece.

Ele lembra do que vocês conversaram, anota o que importa, te dá bom-dia contando
se está tudo em ordem, lembra das datas que você pediu (mesmo daqui a meses),
escuta seus áudios e cuida para que nada seu saia da máquina sem você saber.

## Para quem é

Para quem quer um agente assim e topa seguir um passo a passo no Terminal do
Mac, com calma. Você não precisa ser programador. Precisa de:

- um **Mac** (macOS) que fique ligado a maior parte do tempo;
- uma assinatura do **Claude** com o **Claude Code** (o jeito principal), ou do
  **ChatGPT** com o **Codex** (o jeito alternativo, com a "ponte");
- uma conta no **Telegram** (e um bot, que você cria em 2 minutos no
  @BotFather);
- se quiser que ele escute áudio: uma chave **grátis** da Groq.

## Como ele funciona, em uma frase

**A pasta é o agente.** Tudo o que ele é (o manual), lembra (a memória) e sabe
fazer (as habilidades e as ferramentas) mora numa pasta comum, com arquivos de
texto que você pode abrir e ler quando quiser.

## O que vem no pacote

| Pasta | O que é |
| --- | --- |
| `modelo/` | A pasta do agente, pronta para copiar e batizar: o manual, a memória vazia, as habilidades, as ferramentas e os hooks |
| `ferramentas/gerar-manuais.py` | Gera o manual do Claude Code e o do Codex a partir de uma fonte só, e batiza o seu agente |
| `mac/launchd/` | As rotinas do macOS: bom-dia, backup, conferência do backup e vigia de atrasos |
| `codex/` | A ponte Telegram ↔ Codex e o que muda quando o agente roda no Codex |
| `INSTALAR.md` | O passo a passo |

## Por onde começar

Abra o `INSTALAR.md` e vá no seu ritmo. Se algo der errado, o
`modelo/TROUBLESHOOTING.md` tem os tropeços mais comuns e o conserto de cada um.

## Um cuidado importante

O seu agente vai acumular coisas muito pessoais: o que você conta para ele, quem
são as pessoas da sua vida, seus planos. Por isso:

- a memória dele fica **no seu computador**, em arquivos seus;
- ele tem **regras de segurança** que valem acima de qualquer pedido de fora
  (`modelo/memoria/regras-de-seguranca.md`): nada de senha, compra, envio ou
  publicação sem o seu OK;
- se um dia você quiser publicar a pasta do **seu** agente, passe antes pela
  dupla checagem: memória, diário e registros nunca vão para repositório público.

## Versão

Veja `VERSION` e `CHANGELOG.md`. Créditos e inspirações em `AGRADECIMENTOS.md`.
A licença do projeto ainda vai ser escolhida (`LICENCA-PENDENTE.txt`).
