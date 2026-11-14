---
name: dupla-checagem
description: Pede a um revisor de fora (outro agente, sem memória desta conversa) que confira uma pasta antes de ela sair da máquina do dono, usando teste cego. Use SEMPRE que algo for publicado, enviado ou entregue a alguém — código indo para o GitHub, um relatório, um documento, um pacote de arquivos para outra pessoa, qualquer coisa que passe a existir fora daqui. Use também quando o dono pedir "confere isso", "passa pelo revisor", "dá uma olhada antes de eu mandar", ou quando ele demonstrar receio com dados sensíveis num arquivo. NÃO use para conferir coisa que fica só na máquina dele.
---

# Dupla checagem antes de sair da máquina

Um segundo par de olhos, de fora, antes de qualquer coisa deixar esta máquina.

## Por que isto existe

A lição que gerou esta habilidade: um pacote preparado para o GitHub passou na
conferência do próprio agente, e a ferramenta dizia "LIMPO". O revisor de fora
encontrou o primeiro nome do dono em vários lugares, o nome de um profissional
de saúde dele (dado de saúde, e de terceiro), o nome completo de uma prestadora
de serviço, e valores bancários exatos.

A varredura do agente procurava o nome DO DONO. Não procurava os números dele,
nem os nomes das outras pessoas. **Quem revisa o próprio trabalho carrega os
próprios pontos cegos junto**: não por descuido, por definição.

## As sete regras

### 1. Teste cego, sempre

**Nunca diga ao revisor quais são os dados do dono.** Se você diz o que
procurar, recebe de volta o que já sabia. Descreva as CATEGORIAS (nomes,
documentos, valores, credenciais), nunca os valores concretos.

### 2. Mande o resultado, não os pedaços

A pasta entregue tem de ser **exatamente o que vai sair**. Se for código,
aplique as mudanças sobre a cópia real e mande o conjunto. Se mandar só os
trechos alterados, ele revisa um recorte e aprova algo que não existe.

E **não mande a pasta de trabalho**: ela tem dados que nunca sairiam, ele vai
achar montanha de coisa, estará certo, e o susto será à toa.

### 3. Um arquivo de instruções, sempre com o mesmo esqueleto

Grave `00-PARA-O-REVISOR.txt` na raiz da pasta, com:

1. **O que esta pasta é**, e que é exatamente o que vai sair
2. **O que mudou**, arquivo por arquivo
3. **O que procurar**: privacidade E, se for código, técnica
4. **Como quer a resposta**: lista de arquivo, linha, achado, gravidade

Categorias a listar em privacidade: nomes de pessoas (primeiro nome já conta),
documentos, contatos, dados bancários e de saúde, credenciais, caminhos com nome
de usuário, nomes de máquinas, endereços de rede e URLs internas, valores que
pareçam de extrato real, e **telemetria de base real** (quantidades e datas
concretas: "187 lançamentos, o mais antigo de junho" é vazamento).

### 4. Da segunda rodada em diante, isole o que é NOVO

Grave também `O-QUE-E-NOVO-DESDE-SUA-ANALISE.txt` com apenas o diff do que ele
ainda não viu. O conjunto completo continua na pasta, para conferir o encaixe.

### 5. Cite o apontamento anterior palavra por palavra

Copie o que ele escreveu, diga que foi acatado, e mostre o que resolveu. Um
revisor que vê o próprio apontamento virar código revisa melhor da próxima vez.

### 6. Confira cada achado ANTES de aceitar

O revisor pode errar, exagerar ou não ter a informação que só você tem. Um
achado marcado como "baixo, só preocupa se este for o dado real" pode ser
justamente o dado real: ele não tinha como saber; você tem. Abra o arquivo,
confirme, e só então corrija, e diga ao dono o que você confirmou.

### 7. Conserto novo é código novo. Volte para a rodada seguinte.

É comum a segunda rodada achar problema **no conserto da primeira** (um furo,
um alarme falso). Parar na primeira é publicar um conserto furado.

**Só pare quando uma rodada voltar limpa.**

## O que a aprovação do revisor NÃO é

**O parecer do revisor não é a autorização do dono.** O revisor diz "está
tecnicamente pronto"; quem decide publicar é o dono (veja
`memoria/regras-de-seguranca.md`).

E o parecer vale para a versão que ele VIU. Se você corrigiu algo depois, o
parecer não cobre o que mudou: diga isso ao dono e ofereça outra rodada.

## Quem revisa

Qualquer agente de fora, **sem memória desta conversa** (é o que torna o teste
cego de verdade), de preferência rodando só com leitura e sem internet. Exemplos:

- outro motor na mesma máquina (por exemplo, o Codex em modo efêmero e só
  leitura: `codex exec --ephemeral -s read-only -C <pasta> "<pedido>"`);
- uma sessão nova do Claude Code aberta na pasta que vai sair;
- uma pessoa de confiança do dono.

Antes de tudo, rode as peneiras automáticas desta pasta:
`bash ferramentas/conferir-antes-do-github.sh <repositório>` e, para textos,
`python3 ferramentas/limpar-dados-pessoais.py <arquivo> --conferir`.

## Como entregar ao dono

Mande o resumo do relatório em texto corrido (o que achou, o que você acatou, o
que conferiu e descartou) e o relatório anexo. O parecer do revisor continua NÃO
sendo a autorização dele.
