# Agradecimentos

O Escudeiro não nasceu do zero. Ele é o molde limpo de um agente pessoal que já
funciona há meses no dia a dia, e esse agente, por sua vez, se apoiou no trabalho
de outras pessoas.

## DG Claw (licença MIT)

- Repositório: github.com/DGatoM/DG-Claw
- Licença: MIT. Texto completo e aviso de copyright em
  `licencas-de-terceiros/DG-Claw-LICENSE-MIT.txt`.

O DG Claw (e a sua versão "Lite") foi a inspiração principal: a ideia de que **a
pasta é o agente**, o manual carregado em toda sessão, a memória em camadas com
caderninho do "agora", livro de longo prazo e diário, a reflexão diária, o canal
do Telegram como conversa principal, e o hook que injeta o fio real do Telegram
(o `THREAD-HOOK` do DG Claw).

O que é derivado dele, e por isso leva o aviso da licença MIT junto:
- `modelo/MANUAL-BASE.md` (e os gerados `modelo/CLAUDE.md` e `modelo/AGENTS.md`):
  a estrutura e várias seções vêm do manual do DG Claw Lite, adaptadas e
  reescritas;
- `modelo/TROUBLESHOOTING.md`: derivado do guia de socorro do DG Claw Lite;
- `codex/ponte/` e o modo Codex: inspirados na versão para Codex do DG Claw
  Lite.

O `modelo/ferramentas/fio-telegram.py` pega emprestada a ideia do THREAD-HOOK,
reescrita do zero.

## Hermes Agent (NousResearch, licença MIT)

Ideias, não código. Do Hermes Agent vieram:
- o formato fixo do caderninho, com gavetas (objetivo, em andamento, esperando,
  decisões, próximos passos, crítico);
- o "como anotar" (lição e não diário, causa e não "X não funciona", corrigir
  no lugar);
- o detector de instrução maliciosa e o teto de tamanho da memória
  (`checar-memoria.py`);
- o vigia de rotina atrasada ("overdue", `vigia-atrasos.py`);
- os resumos de semana e de mês no diário.

O código dessas peças foi escrito do zero para este projeto.

## lossless-claw (Martian-Engineering, licença MIT)

A ideia da "memória sem perda" (`modelo/ferramentas/memoria-sem-perda/`):
arquivar a conversa inteira com busca por palavra antes que o sistema apague os
históricos. Só a ideia; o código é próprio.

## E a quem usa

Cada lição escrita nos comentários dos scripts ("ancorar na meia-noite",
"terminou não é o mesmo que deu certo", "verde sem olhar é pior que nada") veio
de um tropeço de verdade. Se você achar um tropeço novo, ele merece virar lição
também.
