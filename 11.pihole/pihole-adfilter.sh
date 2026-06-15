#!/usr/bin/env bash
#
# pihole-adfilter.sh
# Gestisce le blocklist di Pi-hole per categoria ("ads", "malware") usando i
# gruppi, con un filtro globale applicato a TUTTI i client tramite il Default.
#
# MODELLO (v3 - per-gruppo):
#   In Pi-hole una lista blocca un client solo se la lista e' associata a un
#   gruppo di cui il client e' membro. I client non assegnati appartengono
#   implicitamente al gruppo Default (id 0): e' l'unico modo per "tutti".
#
#   - Le liste restano sempre enabled=1; cio' che decide il blocco GLOBALE e'
#     l'appartenenza al gruppo Default, non il flag enabled.
#   - Gruppi creati e popolati: 'ads', 'malware'. In piu' un gruppo 'pihole'
#     che PARCHEGGIA le liste originali/migrate di Pi-hole (es. StevenBlack,
#     mista ads+malware): restano nel DB ma fuori dal Default, quindi non
#     bloccano nessuno finche' non le sposti o assegni un client al gruppo.
#   - Il Default(0) contiene SOLO le categorie passate a 'setup' (default
#     'malware'): quelle sono il filtro globale per tutta la rete.
#   - I gruppi 'ads'/'malware' restano utili per regole per-client: assegna un
#     client a un gruppo e ricevera' anche quelle liste (vedi README).
#
# Questo script e' SOLO il bootstrap iniziale (primo install / dopo un wipe del
# volume). La gestione corrente (accendere/spegnere gli ads per tutti, assegnare
# client ai gruppi, ecc.) si fa dalla UI di Pi-hole.
#
# Uso:
#   sudo ./pihole-adfilter.sh setup [categorie...]   # default: malware
#                                                    # es: setup malware ads
#   sudo ./pihole-adfilter.sh status     # mostra cosa filtra la rete e i gruppi
#
set -euo pipefail

DB="/etc/pihole/gravity.db"

# ---- Liste solo-ADS ---------------------------------------------------------
ADS_LISTS=(
  "https://adaway.org/hosts.txt"
  "https://v.firebog.net/hosts/AdguardDNS.txt"
  "https://v.firebog.net/hosts/Admiral.txt"
  "https://v.firebog.net/hosts/Easylist.txt"
  "https://v.firebog.net/hosts/Prigent-Ads.txt"
  "https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0&mimetype=plaintext"
)

# ---- Liste solo-MALWARE/PHISHING -------------------------------------------
MALWARE_LISTS=(
  "https://urlhaus.abuse.ch/downloads/hostfile/"
  "https://v.firebog.net/hosts/RPiList-Malware.txt"
  "https://raw.githubusercontent.com/RPiList/specials/master/Blocklisten/Phishing-Angriffe"
  "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/Alternate%20versions%20Anti-Malware%20List/AntiMalwareHosts.txt"
  "https://v.firebog.net/hosts/Prigent-Crypto.txt"
  "https://phishing.army/download/phishing_army_blocklist_extended.txt"
)

# ---- Helper -----------------------------------------------------------------
# Il container Pi-hole non ha il binario sqlite3 standalone: SQLite e' incluso
# dentro pihole-FTL e si invoca con "pihole-FTL sqlite3".
sql() {
  pihole-FTL sqlite3 "$DB" "$1"
}

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "Errore: esegui con sudo (serve scrivere su $DB e lanciare pihole -g)." >&2
    exit 1
  fi
}

require_db() {
  if [[ ! -f "$DB" ]]; then
    echo "Errore: database non trovato in $DB. Pi-hole e installato?" >&2
    exit 1
  fi
}

# id di un gruppo dato il nome.
gid_of() {
  sql "SELECT id FROM 'group' WHERE name='$1';"
}

# Aggiunge una lista (se non c'e), la tagga per categoria, e la associa SOLO al
# gruppo categoria indicato (non al Default: ci pensa set_default_categories).
add_list() {
  local url="$1" cat="$2"
  sql "INSERT OR IGNORE INTO adlist (address,enabled,comment) VALUES ('$url',1,'cat:$cat');"
  sql "UPDATE adlist SET enabled=1 WHERE address='$url';"
  local gid; gid=$(gid_of "$cat")
  sql "INSERT OR IGNORE INTO adlist_by_group (adlist_id,group_id)
       SELECT id,$gid FROM adlist WHERE address='$url';"
}

# Rende il Default(0) = unione delle liste delle categorie indicate.
# Ricostruisce da zero l'appartenenza al Default per non lasciare residui.
set_default_categories() {
  sql "DELETE FROM adlist_by_group WHERE group_id=0;"
  local cat
  for cat in "$@"; do
    sql "INSERT OR IGNORE INTO adlist_by_group (adlist_id,group_id)
         SELECT id,0 FROM adlist WHERE comment='cat:$cat';"
  done
}

# ---- Comandi ----------------------------------------------------------------
cmd_setup() {
  local cats=("$@")
  [[ ${#cats[@]} -eq 0 ]] && cats=("malware")
  local c
  for c in "${cats[@]}"; do
    case "$c" in
      ads|malware) ;;
      *) echo "Categoria sconosciuta: '$c' (ammesse: ads, malware)" >&2; exit 1 ;;
    esac
  done

  echo ">> Creo i gruppi 'pihole', 'ads', 'malware'..."
  sql "INSERT OR IGNORE INTO 'group' (enabled,name,description) VALUES
         (1,'pihole','Liste originali/migrate di Pi-hole (parcheggio, fuori dal Default)'),
         (1,'ads','Pubblicita'),
         (1,'malware','Malware e phishing');"

  echo ">> Abilito il gruppo Default (applica i filtri a tutti i client)..."
  sql "UPDATE 'group' SET enabled=1 WHERE id=0;"

  echo ">> Aggiungo le liste ADS..."
  for u in "${ADS_LISTS[@]}"; do add_list "$u" "ads"; done

  echo ">> Aggiungo le liste MALWARE..."
  for u in "${MALWARE_LISTS[@]}"; do add_list "$u" "malware"; done

  echo ">> Parcheggio le liste originali (senza tag cat:) nel gruppo 'pihole'..."
  local pgid; pgid=$(gid_of "pihole")
  sql "INSERT OR IGNORE INTO adlist_by_group (adlist_id,group_id)
       SELECT id,$pgid FROM adlist WHERE comment IS NULL OR comment NOT LIKE 'cat:%';"
  # ...e le tolgo dal Default (restano solo nel gruppo 'pihole').
  sql "DELETE FROM adlist_by_group WHERE group_id=0 AND adlist_id IN
       (SELECT id FROM adlist WHERE comment IS NULL OR comment NOT LIKE 'cat:%');"

  echo ">> Metto nel Default le categorie: ${cats[*]}"
  set_default_categories "${cats[@]}"

  echo ">> Ricostruisco gravity..."
  pihole -g
  echo ">> Fatto. Filtro globale (Default): ${cats[*]}."
}

# Conta quante liste di una categoria sono nel Default(0) su quante totali.
in_default_ratio() {
  local cat="$1"
  sql "SELECT
         (SELECT COUNT(*) FROM adlist a JOIN adlist_by_group bg ON a.id=bg.adlist_id
            WHERE a.comment='cat:$cat' AND bg.group_id=0)
         || '/' ||
         (SELECT COUNT(*) FROM adlist WHERE comment='cat:$cat');"
}

cmd_status() {
  local def ads mal parked
  def=$(sql "SELECT CASE enabled WHEN 1 THEN 'ON' ELSE 'OFF' END FROM 'group' WHERE id=0;")
  ads=$(in_default_ratio ads)
  mal=$(in_default_ratio malware)
  parked=$(sql "SELECT COUNT(*) FROM adlist a JOIN adlist_by_group bg ON a.id=bg.adlist_id
                JOIN 'group' g ON g.id=bg.group_id WHERE g.name='pihole';")
  echo "Gruppo Default (filtro globale per tutti i client): $def"
  echo
  echo "Liste nel Default (= attive per tutta la rete) / totali per categoria:"
  printf "  %-10s %s\n" "malware" "$mal"
  printf "  %-10s %s\n" "ads" "$ads"
  echo
  echo "Parcheggiate nel gruppo 'pihole' (NON nel Default): $parked"
}

# ---- Main -------------------------------------------------------------------
require_root
require_db

case "${1:-}" in
  setup)  shift; cmd_setup "$@" ;;
  status) cmd_status ;;
  *)
    echo "Uso:"
    echo "  sudo $0 setup [categorie...]   # bootstrap; default: malware  (es: setup malware ads)"
    echo "  sudo $0 status                # mostra cosa filtra la rete e i gruppi"
    echo
    echo "Gli ads e le regole per-client si gestiscono dalla UI di Pi-hole."
    exit 1
    ;;
esac
