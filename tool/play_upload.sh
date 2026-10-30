#!/usr/bin/env bash
# Publishes a release bundle on Google Play's closed test, through the Google
# Play Developer API and a service account.
#
#   bash tool/play_upload.sh <bundle.aab> <build number> <key.json>
#   bash tool/play_upload.sh <bundle.aab> <build number> <key.json> --check
#
# --check does all of it but publish: the bundle goes into an edit, Play
# validates the edit, and the edit is thrown away.
#
# play-auto-upload (유저 2026-10-31 「지금 빌드시 자동으로 올리는것도
# 할수있나? 플레이스토어쪽?」). The control tower's round calls this once a
# build has shipped. ⛔The key lives in the user's `app key` folder, so its
# path is an argument. ⛔A testing track only: production is the user's own
# call (「릴리즈 할때도 같은방식으로」 is a command of its own, not the round),
# and the account holds no right to it.

set -uo pipefail

die() {
  echo "::error::$*" >&2
  exit 1
}

bundle=${1:-}
number=${2:-}
key=${3:-}
mode=${4:-publish}

[ -f "$bundle" ] || die "no bundle at '$bundle'"
case "$number" in
  ''|*[!0-9]*) die "build number must be digits, got '$number'" ;;
esac
[ -f "$key" ] || die "no key at '$key'"
case "$mode" in
  publish|--check) ;;
  *) die "unknown option '$mode'" ;;
esac

package=com.myoun.anicel
# The API's name for the closed test: 1084 stood there, read 2026-10-31.
track=alpha
api_root=${PLAY_API_ROOT:-https://androidpublisher.googleapis.com}
token_url=${PLAY_TOKEN_URL:-https://oauth2.googleapis.com/token}
version=$(tr -d '\r' < "$(dirname "$0")/../pubspec.yaml" |
  sed -n 's/^version: *\([^+]*\).*/\1/p')

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Google writes the key one field a line.
field() {
  tr -d '\r' < "$key" | sed -n "s/^ *\"$1\": *\"\(.*\)\",\{0,1\}\$/\1/p"
}

value() {
  sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p" | head -n 1
}

b64url() {
  openssl base64 -A | tr '+/' '-_' | tr -d '='
}

email=$(field client_email)
[ -n "$email" ] || die "no client_email in the key"
printf '%b' "$(field private_key)" > "$work/key.pem"

now=$(date +%s)
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
claim=$(printf '{"iss":"%s","scope":"%s","aud":"%s","iat":%d,"exp":%d}' \
  "$email" \
  'https://www.googleapis.com/auth/androidpublisher' \
  'https://oauth2.googleapis.com/token' \
  "$now" "$((now + 3600))" | b64url)
signature=$(printf '%s.%s' "$header" "$claim" |
  openssl dgst -sha256 -sign "$work/key.pem" -binary | b64url)
[ -n "$signature" ] || die "the key would not sign"

token=$(curl -sS --max-time 60 "$token_url" \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer' \
  --data-urlencode "assertion=$header.$claim.$signature" | value access_token)
[ -n "$token" ] || die "Google gave no token"

# The response, or Play's own words and a failure.
call() {
  local what=$1 body
  shift
  body=$(curl -sS --fail-with-body --max-time 1800 \
    -H "authorization: Bearer $token" "$@" 2>&1) || die "$what: $body"
  printf '%s' "$body"
}

app="$api_root/androidpublisher/v3/applications/$package"

edit=$(call 'opening an edit' -X POST -H 'content-type: application/json' \
  -d '{}' "$app/edits" | value id) || exit 1
[ -n "$edit" ] || die "Play opened no edit"

call 'uploading the bundle' -X POST -T "$bundle" -H 'expect:' \
  -H 'content-type: application/octet-stream' \
  "$api_root/upload/androidpublisher/v3/applications/$package/edits/$edit/bundles?uploadType=media" \
  > /dev/null || exit 1

release="{\"name\":\"$number ($version)\",\"versionCodes\":[\"$number\"],\"status\":\"completed\"}"
call 'naming the release' -X PUT -H 'content-type: application/json' \
  -d "{\"track\":\"$track\",\"releases\":[$release]}" \
  "$app/edits/$edit/tracks/$track" > /dev/null || exit 1

call 'validating the edit' -X POST -d '' "$app/edits/$edit:validate" \
  > /dev/null || exit 1

if [ "$mode" = --check ]; then
  call 'throwing the edit away' -X DELETE "$app/edits/$edit" > /dev/null || exit 1
  echo "play: $number ($version) validates for the closed test; nothing published"
  exit 0
fi

call 'publishing' -X POST -d '' "$app/edits/$edit:commit" > /dev/null || exit 1
echo "play: $number ($version) sent to the closed test"
