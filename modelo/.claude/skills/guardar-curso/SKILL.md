---
name: guardar-curso
description: Guarda um curso, aula, mentoria ou palestra que o dono está fazendo numa biblioteca local (~/Cursos) — recebe a gravação, transcreve (Groq), arquiva slides e prints, cruza PDF com a fala e resume pela régua pronto / adaptar / construir. Use quando ele mandar gravação de aula, PDF de slides ou print de curso, disser "grava/guarda/transcreve essa aula", ou perguntar "o que aquele curso falou sobre X?". NÃO use para redistribuir o material nem para baixar vídeo de plataforma.
---

# Guardar curso na biblioteca

Transcrições organizadas de cursos viram uma fonte de ideias que o dono e o
agente consultam depois. A biblioteca mora em `~/Cursos/`, FORA da pasta do
agente, do git e do backup em nuvem (material pago não se espalha).

Índice e regras da biblioteca: `~/Cursos/INDICE.md` (crie na primeira vez, com
uma linha por curso e a estrutura abaixo).

## Estrutura de um curso

    ~/Cursos/<Nome-do-Curso>/
      README.md          tabela de blocos (data, parte, resumo)
      gravacoes/         AAAA-MM-DD-parteN.m4a
      transcricoes/      AAAA-MM-DD-parteN.txt
      slides/            os PDFs
      prints/            prints com nome descritivo
      resumo-AAAA-MM-DD-parteN.md

Primeira aula de um curso novo: crie a pasta com `chmod go-rwx` (só o dono lê).

## O caminho que funciona
1. **Gravação:** o dono grava a aula (no Mac, o app Gravador serve), um arquivo
   por bloco. Arquivo pequeno vem pelo Telegram (o limite de download do bot é
   ~20 MB); maior, ele copia para uma pasta que você enxerga (Downloads, Mesa e
   Documentos costumam ser bloqueados pelo macOS para o terminal: combine uma
   pasta própria, como `~/Recebidos`).
2. **Transcrever:** mova para `gravacoes/AAAA-MM-DD-parteN.m4a` e transcreva com
   a Groq (mesma chave do `audio.json`, mesmo `curl` do manual, com
   `;filename=audio.m4a`). Limites do plano grátis: algumas horas de áudio por
   dia e por hora, e tamanho máximo por arquivo. Arquivo grande: divida (por
   exemplo, com `ffmpeg -i in.m4a -f segment -segment_time 1200 -c copy parte%02d.m4a`)
   e transcreva um bloco por vez.
   **Atalho:** o Gravador do macOS pode exportar a própria transcrição (.rtf);
   converta com `textutil -convert txt -output <saida>.txt <arquivo>.rtf`.
3. **Ler a transcrição inteira** e escrever `resumo-AAAA-MM-DD-parteN.md`: ideias
   principais, os trechos que o dono pediu atenção durante a aula (ele avisa ao
   vivo pelo Telegram: anote na hora e procure na transcrição depois), e "pela
   nossa régua":
   - **pronto**: o que dá para usar já, do jeito que veio;
   - **adaptar**: o que serve com ajuste para a realidade dele;
   - **construir**: o que exige montar algo novo.
4. **Slides (PDF):** guarde em `slides/`, extraia com `pdftotext -layout` (se
   vier vazio, é imagem: leia como imagem, página por página), e anexe ao resumo
   do bloco uma seção "Cruzamento com o PDF": só o que o PDF traz que a fala não
   deixou claro. Prints vão para `prints/` com nome descritivo.
5. **Atualize** o README.md do curso (tabela de blocos) e o INDICE.md.
6. **O que vira plano de vocês** vai para `memoria/` com as suas palavras, nunca o
   material pago copiado.

## Modo aula ao vivo
Enquanto ele está assistindo: reply curto de recebido, cruze em silêncio e mande
**um resumo único no fim do dia**. Só responda na hora se ele fizer uma pergunta.

## Regras que não se quebram
- Material pago: só em `~/Cursos`, fora do git e do backup em nuvem; nunca para
  outro agente ou pessoa; nunca redistribuir.
- Não baixar vídeo da plataforma nem entrar com a senha dele: só o que ele grava
  e manda.
- Transcrição automática erra nome próprio e número: confirme antes de agir em
  cima deles.
- Antes de mandar áudio para a Groq, o dono precisa saber que o áudio vai para os
  servidores dela.
