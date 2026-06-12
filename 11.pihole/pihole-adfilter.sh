#!/usr/bin/env bash
#
# pihole-adfilter.sh
# Gestisce due gruppi di blocklist su Pi-hole: "ads" e "malware".
# Permette di spegnere le pubblicita tenendo attivo il filtro malware/phishing.
#
# Uso:
#   sudo ./pihole-adfilter.sh setup        # crea gruppi, liste e associazioni
#   sudo ./pihole-adfilter.sh ads off      # disabilita le pubblicita (malware resta)
#   sudo ./pihole-adfilter.sh ads on       # riabilita le pubblicita
#   sudo ./pihole-adfilter.sh status       # mostra stato gruppi e n. liste
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

# Aggiunge una lista (se non c'e) e la associa al gruppo indicato per nome.
add_list() {
  local url="$1" cat="$2" gname="$3"
  sql "INSERT OR IGNORE INTO adlist (address,enabled,comment) VALUES ('$url',1,'cat:$cat');"
  local gid
  gid=$(sql "SELECT id FROM 'group' WHERE name='$gname';")
  sql "INSERT OR IGNORE INTO adlist_by_group (adlist_id,group_id)
       SELECT id,$gid FROM adlist WHERE address='$url';"
}

# ---- Comandi ----------------------------------------------------------------
cmd_setup() {
  echo ">> Creo i gruppi 'ads' e 'malware'..."
  sql "INSERT OR IGNORE INTO 'group' (enabled,name,description)
       VALUES (1,'ads','Pubblicita'),(1,'malware','Malware e phishing');"

  echo ">> Aggiungo le liste ADS..."
  for u in "${ADS_LISTS[@]}"; do
    add_list "$u" "ads" "ads"
  done

  echo ">> Aggiungo le liste MALWARE..."
  for u in "${MALWARE_LISTS[@]}"; do
    add_list "$u" "malware" "malware"
  done

  echo ">> Ricostruisco gravity..."
  pihole -g
  echo ">> Fatto."
}

cmd_ads() {
  local state="$1" val
  case "$state" in
    on)  val=1 ;;
    off) val=0 ;;
    *)   echo "Uso: $0 ads on|off" >&2; exit 1 ;;
  esac
  echo ">> Imposto il gruppo 'ads' enabled=$val..."
  sql "UPDATE 'group' SET enabled=$val WHERE name='ads';"
  echo ">> Ricostruisco gravity..."
  pihole -g
  echo ">> Pubblicita $( [[ $val -eq 1 ]] && echo 'ATTIVE' || echo 'DISATTIVATE' ) (malware sempre attivo)."
}

cmd_status() {
  echo "Stato gruppi:"
  sql "SELECT name, CASE enabled WHEN 1 THEN 'ON' ELSE 'OFF' END AS stato
       FROM 'group' WHERE name IN ('ads','malware');" | column -t -s '|'
  echo
  echo "Liste per categoria:"
  sql "SELECT comment, COUNT(*) FROM adlist
       WHERE comment LIKE 'cat:%' GROUP BY comment;" | column -t -s '|'
}

# ---- Main -------------------------------------------------------------------
require_root
require_db

case "${1:-}" in
  setup)  cmd_setup ;;
  ads)    cmd_ads "${2:-}" ;;
  status) cmd_status ;;
  *)
    echo "Uso:"
    echo "  sudo $0 setup        # crea gruppi, liste e associazioni"
    echo "  sudo $0 ads off      # disabilita le pubblicita (malware resta)"
    echo "  sudo $0 ads on       # riabilita le pubblicita"
    echo "  sudo $0 status       # mostra stato gruppi e n. liste"
    exit 1
    ;;
esac
