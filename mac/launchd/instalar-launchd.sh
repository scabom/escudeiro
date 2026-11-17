#!/bin/bash
# Instala as rotinas do macOS (LaunchAgents) de um agente e, com --ligar, liga.
#
# Uso:
#   bash <pasta do Escudeiro>/mac/launchd/instalar-launchd.sh <pasta do agente> [rotinas...]          → só mostra o que faria
#   bash <pasta do Escudeiro>/mac/launchd/instalar-launchd.sh <pasta do agente> --ligar [rotinas...]
#
# Rotinas: bom-dia backup confere-backup vigia-atrasos (padrão: todas).
# Horários (variáveis de ambiente, opcionais):
#   HORA_BOM_DIA=7 MINUTO_BOM_DIA=10 HORA_BACKUP=22 MINUTO_BACKUP=0 HORA_CONFERE=22 MINUTO_CONFERE=40
# Rótulo: ROTULO=com.escudeiro.<nome-da-pasta-em-minúsculas> (padrão).
#
# ⚠️ POR QUE AS ROTINAS NÃO RODAM DA PASTA DO AGENTE: o agente escreve na pasta
# dele (no Codex, é a única pasta onde a cerca deixa escrever). Se o launchd
# rodasse um script de lá, bastaria o agente (ou um texto malicioso que ele leu)
# mudar esse script para o código rodar mais tarde FORA da cerca, com rede e com
# as permissões da sua conta. Por isso este instalador:
#   1. copia os scripts DO PACOTE (não os da pasta do agente) para
#      ~/Library/Application Support/Escudeiro/<rótulo>/ e tira a permissão de escrita;
#   2. faz ali uma cópia conferida do escudeiro.conf (lida como dado, nunca
#      executada) e recusa programa ou arquivo de token DENTRO da pasta do agente;
#   3. manda os logs e as marcas das rotinas para ~/Library/Logs/Escudeiro/<rótulo>/.
# Da pasta do agente as rotinas só LEEM dados (lembretes.txt) e enviam a pasta no backup.
# Consequência: mudou o escudeiro.conf ou atualizou o Escudeiro? Rode este instalador de novo.
#
# Para desligar uma rotina depois:
#   launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/<rótulo>.<rotina>.plist
#
# Para testar sem mexer no sistema (gera tudo numa pasta de teste, sem launchctl):
#   ESCUDEIRO_TESTE_EM=/tmp/teste-escudeiro bash .../instalar-launchd.sh <pasta do agente> --ligar
set -u
AQUI="$(cd "$(dirname "$0")" && pwd)"
PACOTE="$(cd "$AQUI/../.." && pwd)"
PASTA="${1:-}"
[ -n "$PASTA" ] && [ -d "$PASTA" ] || { echo "uso: $0 <pasta do agente> [--ligar] [rotinas...]"; exit 1; }
PASTA="$(cd "$PASTA" && pwd -P)"
shift
LIGAR=0
[ "${1:-}" = "--ligar" ] && { LIGAR=1; shift; }
ROTINAS=("$@")
[ ${#ROTINAS[@]} -gt 0 ] || ROTINAS=(bom-dia backup confere-backup vigia-atrasos)

BASE=$(basename "$PASTA" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9\n' '-')
ROTULO="${ROTULO:-com.escudeiro.$BASE}"
case "$ROTULO" in ''|.*|*[!A-Za-z0-9._-]*) echo "❌ rótulo inválido: $ROTULO (só letras, números, ponto e hífen)"; exit 1 ;; esac

if [ -n "${ESCUDEIRO_TESTE_EM:-}" ]; then
  DESTINO="$ESCUDEIRO_TESTE_EM/LaunchAgents"
  INSTALADO="$ESCUDEIRO_TESTE_EM/Application Support/Escudeiro/$ROTULO"
  LOGS_ROTINAS="$ESCUDEIRO_TESTE_EM/Logs/Escudeiro/$ROTULO"
else
  DESTINO="$HOME/Library/LaunchAgents"
  INSTALADO="$HOME/Library/Application Support/Escudeiro/$ROTULO"
  LOGS_ROTINAS="$HOME/Library/Logs/Escudeiro/$ROTULO"
fi

# Tudo o que exige cuidado (conferir a configuração, copiar, gerar os plists com
# um serializador de verdade, o plistlib) fica no Python da Apple, isolado (-I).
# Ele grava, um por linha, os plists que gerou.
GERADOS_ARQ=$(mktemp -t escudeiro-plists) || exit 1
trap 'rm -f "$GERADOS_ARQ"' EXIT
/usr/bin/python3 -I - "$PACOTE" "$PASTA" "$INSTALADO" "$LOGS_ROTINAS" "$DESTINO" "$ROTULO" "$LIGAR" "${ROTINAS[@]}" > "$GERADOS_ARQ" <<'PY'
import os, plistlib, re, shutil, sys

pacote, pasta, instalado, logs, destino, rotulo, ligar = sys.argv[1:8]
rotinas = sys.argv[8:]
ligar = ligar == "1"
home = os.path.expanduser("~")
origem = os.path.join(pacote, "modelo", "ferramentas")
COPIAR = ["comum.sh", "rotina-vigiada.sh", "bom-dia.sh", "backup.sh", "confere-backup.sh",
          "lembretes.sh", "vigia-atrasos.py", "avisar-telegram.sh"]
CHAVES = ["NOME_AGENTE", "NOME_DONO", "TELEGRAM_ENV", "TELEGRAM_CHAT_ID", "TELEGRAM_ACESSO",
          "BACKUP_DESTINO", "BACKUP_ORIGENS", "RCLONE", "RCLONE_CACERT"]
PATH = "%s/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" % home


def erro(msg):
    print("❌ " + msg, file=sys.stderr)
    sys.exit(1)


def _sob(a, b):
    return a == b or a.startswith(b.rstrip(os.sep) + os.sep)


def dentro(caminho, de):
    return _sob(os.path.realpath(caminho), os.path.realpath(de))


def elos(caminho, limite=40):
    """Todos os lugares por onde a resolução do caminho passa, um pedaço por vez, seguindo
    cada link (inclusive links que apontam para outros links). Se qualquer um desses lugares
    estiver na pasta do agente, ele pode trocar o que é executado."""
    vistos, pedacos, atual, saltos = [], [p for p in caminho.split(os.sep) if p], os.sep, 0
    while pedacos:
        p = pedacos.pop(0)
        if p == ".":
            continue
        if p == "..":
            atual = os.path.dirname(atual)
            continue
        cand = os.path.join(atual, p)
        vistos.append(cand)
        if os.path.islink(cand):
            saltos += 1
            if saltos > limite:
                raise ValueError("links demais (laço?)")
            alvo = os.readlink(cand)
            if os.path.isabs(alvo):
                atual = os.sep
            pedacos = [q for q in alvo.split(os.sep) if q] + pedacos
        else:
            atual = cand
    vistos.append(atual)
    return vistos


def mexivel_pelo_agente(caminho, pasta_agente):
    """Verdadeiro se o agente consegue trocar o que está neste caminho: o lugar escrito, cada
    pasta do meio, cada link da cadeia (externo -> interno -> externo também) ou o destino
    final caem dentro da pasta do agente. Na dúvida (laço de links), recusa."""
    bases = {os.path.normpath(pasta_agente), os.path.realpath(pasta_agente)}
    try:
        lugares = elos(os.path.normpath(caminho))
    except (OSError, ValueError):
        return True
    lugares.append(os.path.realpath(caminho))
    if any(_sob(os.path.normpath(l), b) for l in lugares for b in bases):
        return True
    # Comparar só a grafia não basta: no macOS "Agente" e "agente" são a mesma pasta.
    # Por isso cada lugar (e cada pasta acima dele) também é comparado pela IDENTIDADE no
    # disco com a pasta do agente.
    return any(_sob_identidade(l, pasta_agente) for l in lugares)


def _sob_identidade(lugar, pasta_agente):
    q = os.path.normpath(lugar)
    while True:
        try:
            if os.path.exists(q) and os.path.samefile(q, pasta_agente):
                return True
        except OSError:
            return True
        pai = os.path.dirname(q)
        if pai == q:
            return False
        q = pai


def hora(var, padrao, maximo):
    v = os.environ.get(var, str(padrao))
    if not re.fullmatch(r"\d{1,2}", v) or int(v) > maximo:
        erro("%s=%s não é um horário válido (0 a %d)" % (var, v, maximo))
    return int(v)


# --- 1. a configuração, lida como DADO (as mesmas regras do ler_conf do comum.sh) ---
def ler_conf(arq):
    conf = {}
    if not os.path.isfile(arq):
        return conf
    with open(arq, encoding="utf-8") as f:
        for linha in f:
            m = re.match(r"^\s*([A-Z_][A-Z0-9_]*)=(.*)$", linha.rstrip("\r\n"))
            if not m or m.group(1) not in CHAVES:
                continue
            v = m.group(2)
            if v.startswith('"'):
                v = v[1:].split('"', 1)[0]
            elif v.startswith("'"):
                v = v[1:].split("'", 1)[0]
            else:
                v = re.split(r"\s#", v, 1)[0].rstrip()
            v = v.replace("${HOME}", home).replace("$HOME", home)
            if v == "~" or v.startswith("~/"):
                v = home + v[1:]
            conf[m.group(1)] = v
    return conf


conf = ler_conf(os.path.join(pasta, "escudeiro.conf"))
for k, v in list(conf.items()):
    if '"' in v or any(ord(c) < 32 for c in v):
        erro("escudeiro.conf: %s tem aspas ou caractere de controle" % k)
    if "{{" in v:
        conf[k] = ""
# Programas e arquivos de token/chat que as rotinas usam NÃO podem morar na pasta do agente:
# o agente poderia trocá-los (programa = código fora da cerca; token = desviar as mensagens).
# Só caminho ABSOLUTO: um relativo seria conferido a partir desta pasta e usado, depois, a
# partir da pasta de trabalho da rotina (outro lugar). O caminho conferido é exatamente o
# que vai gravado na cópia instalada.
CAMINHOS = ("TELEGRAM_ENV", "TELEGRAM_ACESSO", "RCLONE", "RCLONE_CACERT")


def caminho_seguro(k, v):
    if not os.path.isabs(v):
        erro("escudeiro.conf: %s=%s não é caminho absoluto. Use o caminho completo (pode começar com $HOME ou ~/)." % (k, v))
    v = os.path.normpath(v)
    # Confere o lugar escrito (sem resolver link), o destino real e as pastas do meio.
    if mexivel_pelo_agente(v, pasta):
        erro("escudeiro.conf: %s aponta para DENTRO da pasta do agente (%s). Mova para fora e rode de novo." % (k, v))
    return v


for k in CAMINHOS:
    if conf.get(k):
        conf[k] = caminho_seguro(k, conf[k])
if conf.get("TELEGRAM_CHAT_ID") and not re.fullmatch(r"-?\d+", conf["TELEGRAM_CHAT_ID"]):
    erro("escudeiro.conf: TELEGRAM_CHAT_ID tem de ser só números")
# Destino do backup: só remote com nome ("meu-drive:pasta"). Nada de remote montado na hora
# (":sftp,host=...:"), que mandaria seus arquivos para um lugar que não está no rclone config.
dest = conf.get("BACKUP_DESTINO", "")
if dest and not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.+@ -]*:.*", dest):
    erro('escudeiro.conf: BACKUP_DESTINO tem de ser "<nome do remote>:<pasta>" (remote criado com rclone config)')
if dest and not conf.get("RCLONE"):
    for d in PATH.split(":"):
        c = os.path.join(d, "rclone")
        if os.path.isfile(c) and os.access(c, os.X_OK):
            conf["RCLONE"] = c
            break
if conf.get("RCLONE"):
    # Vale também para o rclone achado sozinho no PATH (que pode ter pasta relativa).
    conf["RCLONE"] = caminho_seguro("RCLONE", conf["RCLONE"])

# --- 2. onde instalar ---
if dentro(instalado, pasta) or dentro(pasta, instalado) or dentro(logs, pasta):
    erro("a cópia instalada e os logs precisam ficar FORA da pasta do agente")
modelos = {
    "bom-dia":        ("bom-dia.sh", "/bin/bash", {"Hour": hora("HORA_BOM_DIA", 7, 23), "Minute": hora("MINUTO_BOM_DIA", 10, 59)}),
    "backup":         ("backup.sh", "/bin/bash", {"Hour": hora("HORA_BACKUP", 22, 23), "Minute": hora("MINUTO_BACKUP", 0, 59)}),
    "confere-backup": ("confere-backup.sh", "/bin/bash", {"Hour": hora("HORA_CONFERE", 22, 23), "Minute": hora("MINUTO_CONFERE", 40, 59)}),
    "vigia-atrasos":  ("vigia-atrasos.py", "/usr/bin/python3", None),
}
for r in rotinas:
    if r not in modelos:
        erro("não existe rotina '%s' (as que existem: %s)" % (r, " ".join(modelos)))
for nome in COPIAR:
    if not os.path.isfile(os.path.join(origem, nome)):
        erro("o pacote está incompleto: falta %s" % os.path.join(origem, nome))

ferr = os.path.join(instalado, "ferramentas")
conf_inst = os.path.join(instalado, "escudeiro.conf")

print("Pasta do agente:  %s" % pasta, file=sys.stderr)
print("Cópia instalada:  %s" % instalado, file=sys.stderr)
print("Logs das rotinas: %s" % logs, file=sys.stderr)
print("Configuração que as rotinas vão usar (confira):", file=sys.stderr)
for k in ("TELEGRAM_ENV", "TELEGRAM_ACESSO", "TELEGRAM_CHAT_ID", "BACKUP_DESTINO", "BACKUP_ORIGENS", "RCLONE"):
    print("   %s = %s" % (k, conf.get(k) or "(vazio)"), file=sys.stderr)
for nome in COPIAR:
    meu = os.path.join(pasta, "ferramentas", nome)
    if os.path.isfile(meu):
        with open(meu, "rb") as a, open(os.path.join(origem, nome), "rb") as b:
            if a.read() != b.read():
                print("⚠️  ferramentas/%s da pasta do agente é diferente da do pacote: as rotinas usam a do PACOTE." % nome,
                      file=sys.stderr)

if not ligar:
    for r in rotinas:
        print("→ criaria %s" % os.path.join(destino, "%s.%s.plist" % (rotulo, r)), file=sys.stderr)
    sys.exit(0)


# --- 3. copiar, e tirar a permissão de escrita ---
def destravar(p):
    if os.path.isdir(p):
        for raiz, _dirs, arqs in os.walk(p):
            os.chmod(raiz, 0o700)
            for a in arqs:
                os.chmod(os.path.join(raiz, a), 0o600)


for p in (os.path.dirname(instalado), logs, destino):
    os.makedirs(p, exist_ok=True)
destravar(instalado)
os.makedirs(ferr, exist_ok=True)
for nome in COPIAR:
    shutil.copyfile(os.path.join(origem, nome), os.path.join(ferr, nome))
    os.chmod(os.path.join(ferr, nome), 0o500)
with open(conf_inst, "w", encoding="utf-8") as f:
    f.write("# Cópia conferida do escudeiro.conf, feita pelo instalar-launchd.sh. NÃO edite aqui:\n"
            "# edite o escudeiro.conf da pasta do agente e rode o instalador de novo.\n")
    for k in CHAVES:
        if conf.get(k):
            f.write('%s="%s"\n' % (k, conf[k]))
os.chmod(conf_inst, 0o400)
os.chmod(ferr, 0o500)
os.chmod(instalado, 0o500)
os.chmod(logs, 0o700)

# --- 4. os plists, gerados pelo plistlib (caminho com &, < ou acento não quebra nada) ---
for r in rotinas:
    script, interp, agenda = modelos[r]
    cmd = [interp] + (["-I"] if interp.endswith("python3") else []) + [os.path.join(ferr, script)]
    d = {
        "Label": "%s.%s" % (rotulo, r),
        "ProgramArguments": ["/bin/bash", os.path.join(ferr, "rotina-vigiada.sh"), r, "--avisar", "1", "--"] + cmd,
        # A pasta de trabalho é a cópia instalada, não a do agente: nada de lá entra
        # por acidente (um "python3 -c" procura módulos na pasta atual).
        "WorkingDirectory": instalado,
        "EnvironmentVariables": {
            "PATH": PATH,
            "LANG": "pt_BR.UTF-8",
            "ESCUDEIRO_PASTA": pasta,
            "ESCUDEIRO_CONF": conf_inst,
            "ESCUDEIRO_LOGS": logs,
        },
        "StandardOutPath": os.path.join(logs, "launchd-%s.log" % r),
        "StandardErrorPath": os.path.join(logs, "launchd-%s.log" % r),
    }
    if agenda:
        d["StartCalendarInterval"] = agenda
    else:
        d["StartInterval"] = 1800
    saida = os.path.join(destino, "%s.%s.plist" % (rotulo, r))
    with open(saida, "wb") as f:
        plistlib.dump(d, f)
    print(saida)
PY
[ $? -eq 0 ] || { echo "❌ nada foi ligado (veja a mensagem acima)."; exit 1; }

if [ "$LIGAR" = "0" ]; then
  echo "(só mostrei. Para instalar e ligar de verdade, rode de novo com --ligar)"
  exit 0
fi

FALHAS=0
N=0
while IFS= read -r saida; do
  [ -n "$saida" ] || continue
  N=$((N+1))
  r=$(basename "$saida" .plist); r="${r#"$ROTULO".}"
  if ! plutil -lint "$saida" >/dev/null; then
    echo "❌ plist inválido: $saida"; FALHAS=$((FALHAS+1)); continue
  fi
  if [ -n "${ESCUDEIRO_TESTE_EM:-}" ]; then
    echo "✅ gerado (teste, sem launchctl): $saida"; continue
  fi
  launchctl bootout "gui/$(id -u)" "$saida" 2>/dev/null
  if launchctl bootstrap "gui/$(id -u)" "$saida"; then echo "✅ ligado: $ROTULO.$r"
  else echo "❌ não consegui ligar $saida (veja: launchctl print gui/$(id -u)/$ROTULO.$r)"; FALHAS=$((FALHAS+1)); fi
done < "$GERADOS_ARQ"

if [ "$N" -ne "${#ROTINAS[@]}" ] || [ "$FALHAS" -gt 0 ]; then
  echo "❌ $FALHAS rotina(s) com problema (de ${#ROTINAS[@]} pedida(s))."
  exit 1
fi
echo "Pronto. Mudou o escudeiro.conf ou atualizou o Escudeiro? Rode este instalador de novo."
exit 0
