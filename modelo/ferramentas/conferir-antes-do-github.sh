#!/bin/bash
# Vasculha um repositório procurando dado sensível do dono ANTES de enviar
# qualquer coisa para o GitHub. Barra o envio se achar.
#
# ⚠️ POR QUE UM SCRIPT E NÃO UMA PROMESSA DO AGENTE: no GitHub, o que sobe fica
# no histórico mesmo depois de apagado: não existe desfazer de verdade. Uma
# regra que depende de alguém lembrar é uma regra que um dia falha, e esse dia
# custa caro. Script não esquece.
#
# Vale MESMO em repositório privado: privado hoje pode virar público amanhã,
# por engano de um clique, e aí o histórico inteiro vai junto.
#
# NOMES: nome não tem formato, e por isso escapa de qualquer regex de CPF ou
# chave. Este script procura também os nomes que você listar em
#   <pasta do agente>/nomes-proibidos.txt   (um por linha; fica FORA do git)
# mais o NOME_DONO do escudeiro.conf. Ponha ali o nome e o sobrenome do dono, da
# família, de quem aparece nas conversas, o nome da máquina, o usuário do Mac.
#
# Uso:  bash conferir-antes-do-github.sh <pasta do repositório>
# Sai 0 se está limpo, 1 se achou algo. Feito para rodar ANTES do git push.
# E não substitui a dupla checagem (habilidade dupla-checagem): é a primeira peneira.

set -u
REPO="${1:-}"
[ -n "$REPO" ] || { echo "uso: $0 <pasta do repositório>"; exit 1; }
AGENTE="$(cd "$(dirname "$0")/.." && pwd)"
LISTA_NOMES="${NOMES_PROIBIDOS_ARQUIVO:-$AGENTE/nomes-proibidos.txt}"
DONO=$(sed -n 's/^NOME_DONO="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' "$AGENTE/escudeiro.conf" 2>/dev/null | grep -v '{{' | head -1)
# Junta os nomes num padrão só (a|b|c), ignorando linhas vazias e comentários.
NOMES_PADRAO=$( { [ -n "$DONO" ] && echo "$DONO"; grep -vE '^\s*(#|$)' "$LISTA_NOMES" 2>/dev/null; } \
  | sed 's/[][\.*^$+?(){}|/]/\\&/g' | paste -sd'|' -)
cd "$REPO" 2>/dev/null || { echo "❌ pasta não encontrada: $REPO"; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "❌ não é repositório git: $REPO"; exit 1; }

echo "🔍 Conferindo o que está versionado em: $REPO"
echo

ACHOU=0

# --- 1. Arquivos que nunca deveriam estar versionados, pelo NOME -------------
echo "1) Arquivos de dado ou segredo pelo nome:"
# Lição: padrão largo demais dá ALARME FALSO (ex.: "forgot-password.php", uma
# tela normal sem segredo nenhum). Falso alarme não é inofensivo: um verificador
# que reclama do que está certo ensina a pessoa a ignorá-lo. Então casa só o que
# é dado ou segredo DE VERDADE pelo nome.
SUSPEITOS=$(git ls-files | grep -iE '\.(sql|sqlite|db|xlsx|xls|csv|ofx)$|(^|/)config\.php$|(^|/)\.env|(^|/)(audio\.json|ponte\.env|acesso\.json|access\.json|escudeiro\.conf|nomes-proibidos\.txt)$|(^|/)(working-memory\.md|memoria/|diario/|registros/|logs/)' | grep -vE '(^|/)modelo/' || true)
if [ -n "$SUSPEITOS" ]; then
  echo "$SUSPEITOS" | sed 's/^/   ⚠️  /'
  ACHOU=1
else
  echo "   ✅ nenhum"
fi
echo

# --- 2. Conteúdo: padrões que denunciam dado pessoal -------------------------
# Procura no CONTEÚDO dos arquivos versionados, porque dado sensível também
# entra colado dentro de um .php ou .md — não só em arquivo de planilha.
echo "2) Dado pessoal dentro dos arquivos:"
PADROES=(
  '[0-9]{3}\.[0-9]{3}\.[0-9]{3}-[0-9]{2}'          # CPF
  '[0-9]{2}\.[0-9]{3}\.[0-9]{3}/[0-9]{4}-[0-9]{2}' # CNPJ
  'ag[êe]ncia[^a-z]{0,3}[0-9]{4}'                  # agência bancária
  'sk-[A-Za-z0-9_-]{20,}'                          # chave de API
  'gsk_[A-Za-z0-9]{20,}'                           # chave da Groq
  'sk-ant-[A-Za-z0-9_-]{20,}'                      # chave da Anthropic
  'AKIA[0-9A-Z]{16}'                               # chave da AWS
  'ghp_[A-Za-z0-9]{20,}'                           # token do GitHub
  '[0-9]{8,10}:[A-Za-z0-9_-]{30,}'                 # token de bot do Telegram
  '/Users/[A-Za-z0-9._-]+'                         # caminho com nome de usuário (Mac)
  '/home/[A-Za-z0-9._-]+'                          # caminho com nome de usuário (Linux)
  '[A-Za-z0-9-]+\.ts\.net'                         # endereço de tailnet
  '(^|[^0-9.])(100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])|192\.168|10)\.[0-9]{1,3}\.[0-9]{1,3}'  # IP de rede interna
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'  # e-mail
)

ENCONTRADO=""
for p in "${PADROES[@]}"; do
  r=$(git grep -InE "$p" -- $(git ls-files | grep -vE '\.(png|jpg|jpeg|gif|ico|woff2?|ttf)$') 2>/dev/null | head -5 || true)
  [ -n "$r" ] && ENCONTRADO="${ENCONTRADO}${r}"$'\n'
done
if [ -n "$ENCONTRADO" ]; then
  printf '%s' "$ENCONTRADO" | sed 's/^/   ⚠️  /' | head -12
  ACHOU=1
else
  echo "   ✅ nenhum"
fi
echo

# --- 2b. NOMES, que não têm formato e escapam das regexes acima -------------
#
# Lição: uma conferência que só procura o que tem formato (CPF, chave) devolve
# "LIMPO" num repositório com o primeiro nome do dono em vários lugares e o
# e-mail dele assinando os commits. Verde sem olhar é pior que nada: dá
# confiança onde não há.
echo "2b) Nomes da lista (nomes-proibidos.txt + NOME_DONO) dentro dos arquivos:"
if [ -z "$NOMES_PADRAO" ]; then
  echo "   ⚠️  lista de nomes vazia: crie $LISTA_NOMES (um nome por linha). Sem ela, nome escapa."
  ACHOU=1
else
  ARQS=$(git ls-files | grep -vE '\.(png|jpg|jpeg|gif|ico|woff2?|ttf|pdf)$|(composer|package-lock)\.(lock|json)$')
  NOMES=$(echo "$ARQS" | tr '\n' '\0' | xargs -0 git grep -InEiw "$NOMES_PADRAO" -- 2>/dev/null | head -8 || true)
  if [ -n "$NOMES" ]; then
    echo "$NOMES" | sed 's/^/   ⚠️  /'
    ACHOU=1
  else
    echo "   ✅ nenhum"
  fi
fi
echo

# --- 2c. O nome e o e-mail dele assinando os COMMITS -------------------------
#
# O código pode estar limpo e o histórico não. Todo commit carrega nome, e-mail
# e, quando o git monta o endereço sozinho, até o nome da máquina.
# Dica: antes do primeiro commit, use um autor neutro neste repositório:
#   git config user.name "<seu usuário público>"; git config user.email "<o e-mail noreply que o GitHub te dá>"
echo "2c) Quem assina os commits:"
AUTORES=$(git log --format='%an <%ae>' 2>/dev/null | sort -u)
if echo "$AUTORES" | grep -qiE "${NOMES_PADRAO:+$NOMES_PADRAO|}@gmail|@hotmail|@outlook|@icloud|@yahoo|MacBook|iMac|Mac-mini|\\.local>"; then
  echo "$AUTORES" | sed 's/^/   ⚠️  /'
  echo "   → isto vive no HISTÓRICO. Trocar exige reescrever os commits."
  ACHOU=1
else
  echo "$AUTORES" | sed 's/^/   ✅ /'
fi
echo
# --- 3. Senha escrita no código ----------------------------------------------
echo "3) Senha escrita direto no código:"
SENHAS=$(git grep -InE "(password|senha|passwd|secret)\s*(=>|=|:)\s*['\"][^'\"]{4,}['\"]" -- '*.php' '*.js' '*.sh' '*.json' '*.yml' 2>/dev/null \
         | grep -viE "example|exemplo|placeholder|sua_senha|senha_aqui|xxx|\*\*\*" | head -6 || true)
if [ -n "$SENHAS" ]; then
  echo "$SENHAS" | sed 's/^/   ⚠️  /'
  ACHOU=1
else
  echo "   ✅ nenhuma"
fi
echo

# --- 4. O histórico também conta ---------------------------------------------
# Apagar o arquivo hoje não basta: se ele já foi commitado um dia, continua
# recuperável no histórico, e é isso que sobe no push.
echo "4) Dado sensível no HISTÓRICO (mesmo que já apagado):"
HIST=$(git log --all --pretty=format: --name-only 2>/dev/null | sort -u \
       | grep -iE '\.(sql|xlsx|xls|csv|ofx)$|config\.php|^\.env' | grep -v '^$' || true)
if [ -n "$HIST" ]; then
  echo "$HIST" | sed 's/^/   ⚠️  já esteve versionado: /'
  echo "   → apagar agora NÃO resolve: o histórico vai junto no push."
  ACHOU=1
else
  echo "   ✅ nada"
fi
echo

echo "-----------------------------------------------------"
if [ "$ACHOU" -eq 0 ]; then
  echo "✅ LIMPO — pode enviar para o GitHub."
  echo "   ($(git ls-files | wc -l | tr -d ' ') arquivos versionados)"
  exit 0
fi
echo "🚫 NÃO ENVIE. Achei coisa que não pode subir (acima)."
echo "   Conserte o .gitignore, tire do versionamento, e rode de novo."
exit 1
