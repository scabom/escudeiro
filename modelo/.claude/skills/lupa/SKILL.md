---
name: lupa
description: Varre um documento grande inteiro (relatório anual, contrato longo, edital, prospecto, regulamento) e produz um MAPA do que tem dentro e do que merece um segundo olhar. Use quando o dono pedir para "varrer", "ler o documento inteiro", "procurar risco escondido", ou quando a pergunta for do tipo "tem alguma coisa aqui que eu não estou vendo?". NÃO use para responder pergunta pontual sobre um trecho ou um número (para isso, vá direto à seção).
---

# A lupa — varrer o documento inteiro

São duas leituras diferentes, e confundi-las é o erro que gerou esta habilidade:

1. **VARREDURA**: lê o documento inteiro, uma vez, e marca onde tem cheiro.
   Produz um **mapa**. É o que esta habilidade faz.
2. **ANÁLISE**: vai fundo, com o mapa na mão. Vem depois, e é do dono (ou de
   outra habilidade).

"Aponte a seção certa" serve para **analisar**, não para **caçar**: risco
escondido não avisa onde está.

## Dependência opcional, NÃO incluída no Escudeiro

A versão original desta habilidade usa um conjunto de ferramentas próprio
(um fatiador, um script de varredura por fatia e um de fusão de mapas), que não
vem neste pacote. Sem elas, siga o mesmo método à mão, como descrito abaixo: dá
mais trabalho, mas as garantias são as mesmas. Se o dono montar ferramentas
assim, documente aqui os comandos.

## A receita

1. **Converter para texto/markdown** antes de tudo (por exemplo, `pdftotext
   -layout`, ou um conversor de PDF para markdown). PDF não se fatia bem; texto
   sim.
2. **Guardar o documento** numa pasta própria (`documentos/<nome>/`), com o
   original ao lado.
3. **Fatiar.** Dois limites ao mesmo tempo: páginas **e** tamanho. Página é só
   um proxy do trabalho de leitura: poucas páginas de tabela pesam muito mais que
   muitas de texto corrido.
4. **Varrer fatia por fatia.** Para cada fatia: o que ela cobre, e o que merece
   um segundo olhar (com página/seção e o motivo). O mapa sai num arquivo com
   data e quem leu no nome. Nada é sobrescrito.
5. **Segundo leitor**, quando o documento for importante: outro modelo, ou uma
   sessão nova, sem ver o primeiro mapa. Dois leitores independentes acham
   coisas diferentes.
6. **Fundir os dois mapas**, separando o que **os dois viram** (tende a ser
   sólido) do que **só um viu** (pode ser achado fino, ou alarme falso), e
   marcando ⚠️ onde eles divergem de um valor.
7. **Ler o mapa com o dono e escolher** o que merece leitura humana de verdade.

## O que a lupa garante

- 🔪 **Corte no limite das seções.** Nunca no meio de uma tabela ou de um
  argumento: partir ao meio estraga as duas metades.
- ✅ **Integridade conferida.** Juntando as fatias, tem de dar o original, por
  igualdade. Ou é idêntico, ou não segue.
- 🕳️ **Buraco anunciado.** Fatia que falhou aparece no mapa como **NÃO FOI
  LIDA**. Mapa com buraco silencioso é pior que mapa nenhum: quem lê acredita
  que aquela parte foi examinada e estava limpa.
- ♻️ **Retomada.** Cada fatia tem a sua parte do mapa; refazer uma não apaga as
  outras.
- ⏱️ **Tempo por fatia anotado.** Número fora da curva é sintoma, não sorte.

## Regras que não se quebram

1. **Conferir pelo RESULTADO, nunca pelo código de saída.** Um leitor
   automático pode "terminar com sucesso" devolvendo só uma mensagem de
   permissão negada. Sucesso para o programa, fracasso para o trabalho: abra o
   texto de cada fatia.
2. **Fatia grande é lida em várias passadas**, sem atalho por comando.
3. **Na fusão, os dois mapas vão inteiros no pedido**, sem depender de abrir
   arquivo no meio.
4. **Uma rodada não é medição, é amostra.** O mesmo leitor, no mesmo arquivo,
   pode achar coisas diferentes em rodadas diferentes. Não afirme "o leitor X é
   melhor" com uma rodada só.
5. **Diga quem leu o quê**: marque no mapa qual leitor produziu cada achado e
   quanto tempo levou.

## O que o mapa NÃO é

O mapa **não é a análise** e não conclui nada. Ele diz onde cheirar. Quem
transforma cheiro em conclusão é o dono, com o documento aberto na página que o
mapa apontou.
