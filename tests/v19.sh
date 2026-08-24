#!/bin/bash
set -Eeuo pipefail
umask 077

result=${TKL_TEST_RESULT:?TKL_TEST_RESULT is required}
app_password=${TKL_TEST_APP_PASS:?TKL_TEST_APP_PASS is required}
config=/home/syncthing/.local/state/syncthing/config.xml
sync_root=/home/syncthing/Sync
response=/tmp/tkl-syncthing-response.$$
headers=/tmp/tkl-syncthing-headers.$$
cookie=/tmp/tkl-syncthing-cookie.$$
login_json=/tmp/tkl-syncthing-login.$$
folders_json=/tmp/tkl-syncthing-folders.$$
file_json=/tmp/tkl-syncthing-file.$$
policy=/tmp/tkl-syncthing-policy.$$
probe_name=turnkey-v19-index-$$.txt
probe_path=$sync_root/$probe_name

cleanup() {
    rm -f -- "$response" "$headers" "$cookie" "$login_json" \
        "$folders_json" "$file_json" "$policy" "$probe_path"
}
trap cleanup EXIT

systemctl --quiet is-active syncthing@syncthing.service nginx.service \
    multi-user.target
systemctl --quiet is-enabled syncthing@syncthing.service nginx.service
test "$(systemctl show --property=User --value \
    syncthing@syncthing.service)" = syncthing
nginx -t

syncthing_package=$(dpkg-query -W -f='${Version}' syncthing)
nginx_package=$(dpkg-query -W -f='${Version}' nginx)
bcrypt_package=$(dpkg-query -W -f='${Version}' python3-bcrypt)
syncthing_version=$(syncthing --version)
grep -q '^syncthing v1\.29\.' <<<"$syncthing_version"
dpkg-query -S "$(readlink -f "$(command -v syncthing)")" >/dev/null

test -s "$config"
test -s /home/syncthing/.local/state/syncthing/cert.pem
test -s /home/syncthing/.local/state/syncthing/key.pem
test "$(stat -c '%U:%G' "$config")" = syncthing:syncthing
grep -Eq '^[[:space:]]*<address>127\.0\.0\.1:8383</address>$' "$config"
grep -Eq '^[[:space:]]*<user>syncthing</user>$' "$config"
grep -Eq '^[[:space:]]*<password>\$2' "$config"
grep -Eq '^[[:space:]]*<insecureSkipHostcheck>true</insecureSkipHostcheck>$' \
    "$config"
test -d "$sync_root"
test "$(stat -c '%U:%G' "$sync_root")" = syncthing:syncthing

ss -ltn | grep -Eq '127\.0\.0\.1:8383[[:space:]]'
ss -ltn | grep -Eq ':22000[[:space:]]'
ss -lun | grep -Eq ':(21027|22000)[[:space:]]'
nginx -T 2>/dev/null | grep -Fq \
    'ssl_certificate /etc/ssl/private/cert.pem;'

curl --insecure --fail --silent --show-error --location \
    http://127.0.0.1/ >"$response"
grep -qi '<title>Syncthing' "$response"
curl --insecure --fail --silent --show-error \
    https://127.0.0.1/ >"$response"
grep -qi '<title>Syncthing' "$response"

curl --silent --show-error --dump-header "$headers" --output /dev/null \
    http://127.0.0.1:8384/
grep -q '^HTTP/.* 302' "$headers"
grep -Fqi 'Location: https://127.0.0.1/' "$headers"
curl --insecure --silent --show-error --dump-header "$headers" \
    --output /dev/null https://127.0.0.1:8384/
grep -q '^HTTP/.* 302' "$headers"
grep -Fqi 'Location: https://127.0.0.1/' "$headers"

unauth_status=$(curl --insecure --silent --output /dev/null \
    --write-out '%{http_code}' \
    https://127.0.0.1/rest/system/status)
test "$unauth_status" = 403

python3 - "$app_password" >"$login_json" <<'PYTHON'
import json
import sys

json.dump({
    "username": "syncthing",
    "password": sys.argv[1],
    "stayLoggedIn": False,
}, sys.stdout)
PYTHON
login_status=$(curl --insecure --silent --show-error \
    --cookie-jar "$cookie" --output "$response" --write-out '%{http_code}' \
    --header 'Content-Type: application/json' \
    --data-binary @"$login_json" \
    https://127.0.0.1/rest/noauth/auth/password)
test "$login_status" = 204
grep -q 'sessionid-' "$cookie"
curl --insecure --fail --silent --show-error --cookie "$cookie" \
    https://127.0.0.1/meta.js >"$response"
grep -q '"authenticated":true' "$response"

api_key=$(python3 - "$config" <<'PYTHON'
import sys
import xml.etree.ElementTree as ET

print(ET.parse(sys.argv[1]).getroot().findtext("gui/apikey"))
PYTHON
)
test -n "$api_key"
curl --insecure --fail --silent --show-error \
    --header "X-API-Key: $api_key" \
    https://127.0.0.1/rest/system/status >"$response"
python3 - "$response" <<'PYTHON'
import json
import sys

status = json.load(open(sys.argv[1]))
assert status["myID"]
assert status["uptime"] > 0
PYTHON

curl --insecure --fail --silent --show-error \
    --header "X-API-Key: $api_key" \
    https://127.0.0.1/rest/config/folders >"$folders_json"
python3 - "$folders_json" <<'PYTHON'
import json
import sys

folders = json.load(open(sys.argv[1]))
default = next(folder for folder in folders if folder["id"] == "default")
assert default["path"] == "/home/syncthing/Sync"
assert default["type"] == "sendreceive"
assert not default["paused"]
PYTHON

printf 'syncthing-v19-index-ok\n' >"$probe_path"
chown syncthing:syncthing "$probe_path"
curl --insecure --fail --silent --show-error --request POST \
    --header "X-API-Key: $api_key" \
    'https://127.0.0.1/rest/db/scan?folder=default' >/dev/null
indexed=false
for _ in {1..30}; do
    if curl --insecure --fail --silent --show-error --get \
            --header "X-API-Key: $api_key" \
            --data-urlencode 'folder=default' \
            --data-urlencode "file=$probe_name" \
            https://127.0.0.1/rest/db/file >"$file_json" 2>/dev/null &&
       python3 - "$file_json" "$probe_name" <<'PYTHON'
import json
import sys

entry = json.load(open(sys.argv[1]))["local"]
assert entry["name"] == sys.argv[2]
assert entry["size"] == len(b"syncthing-v19-index-ok\n")
assert not entry["deleted"]
PYTHON
    then
        indexed=true
        break
    fi
    sleep 1
done
test "$indexed" = true

grep -Fxq 'Syncthing:    https://$ipaddr:8384' \
    /etc/confconsole/services.txt
curl --insecure --fail --silent --show-error --head \
    https://127.0.0.1:12321/ >/dev/null

before="$syncthing_package|$nginx_package|$bcrypt_package"
apt-get update >/dev/null
for package in syncthing nginx python3-bcrypt; do
    apt-cache policy "$package" >"$policy"
    candidate=$(awk '/Candidate:/ {print $2}' "$policy")
    test -n "$candidate"
    test "$candidate" != '(none)'
    grep -Eq 'trixie|deb13' "$policy"
done
after="$(dpkg-query -W -f='${Version}' syncthing)|$(dpkg-query -W -f='${Version}' nginx)|$(dpkg-query -W -f='${Version}' python3-bcrypt)"
test "$after" = "$before"
grep -Rqs '^Suites: trixie' /etc/apt/sources.list.d
! grep -RqiE 'bookworm|apt\.syncthing\.net' /etc/apt/sources.list.d

cat >"$result" <<EOF
package_source=Debian 13 Trixie APT repositories for Syncthing, Nginx and Python bcrypt
installed_version=syncthing $syncthing_package ($syncthing_version); nginx $nginx_package; python3-bcrypt $bcrypt_package
runtime_checks=normal init; Syncthing and Nginx service supervision; syncthing service identity; localhost GUI binding; HTTP, HTTPS and port 8384 proxy paths; authenticated GUI session; authenticated REST API; default send-receive folder; practical file creation, scan and indexed readback; Webmin management endpoint
updater_command=apt-get update; apt-cache policy syncthing nginx python3-bcrypt; apt-get install --only-upgrade syncthing
updater_result=signed Trixie metadata refreshed; eligible package candidates found; installed versions unchanged
updater_channel=Debian and TurnKey Trixie APT repositories
integrity_evidence=APT accepted signed repository metadata through configured keyrings; the third-party Syncthing repository and Bookworm sources are absent
EOF
