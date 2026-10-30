#!/usr/bin/env bash
# Packs the Windows release build into the Microsoft Store's package,
# build/windows/msix/Anicel.msix — unsigned, as the Store takes it: it signs
# what it publishes (Microsoft Learn, "App package requirements").
#
#   bash tool/release_build.sh windows <build number>    the build, first
#   bash tool/msix_pack.sh <build number>
#
# Exits 2, packing nothing, while the Store identity below is empty.
#
# store-distribution-plan-Q2 (유저 2026-10-30 「MS 스토어도 지금 시작」).
# The manifest is windows/msix/AppxManifest.xml and its logos are drawn by
# tool/app_art/render_app_art_test.dart; the Windows SDK's makepri and
# makeappx pack them. The control tower's round calls this after its
# Windows build.

# Partner Center ▸ the app ▸ Product identity: Package/Identity/Name,
# Package/Identity/Publisher and Package/Properties/PublisherDisplayName.
# Every package the Store publishes carries them, so they are written here
# rather than kept secret. Empty until the user reserves the name.
store_name=''
store_publisher=''
store_publisher_display_name=''

number=$1
case "$number" in
  ''|*[!0-9]*)
    echo "::error::build number must be digits, got '$number'"
    exit 1
    ;;
esac
if [ -z "$store_name" ] || [ -z "$store_publisher" ] \
    || [ -z "$store_publisher_display_name" ]; then
  echo "no Store identity yet (Partner Center ▸ Product identity)"
  exit 2
fi

# The Store refuses a first part of 0 and a fourth that is not 0, so the
# app's 0.1.0+<N> cannot pass as it is. ⏳store-distribution-plan-Q3 is the
# user's to answer; until then its recommendation, 1.0.<N>.0 — the round's
# number, the one the About box and the feedback forms show.
if [ "$number" -gt 65535 ]; then
  echo "::error::a version part stops at 65535, got $number"
  exit 1
fi
version="1.0.$number.0"

build=build/windows/x64/runner/Release
if [ ! -f "$build/Anicel.exe" ]; then
  echo "::error::no $build/Anicel.exe — build Windows first"
  exit 1
fi
kit=$(ls -d "/c/Program Files (x86)/Windows Kits/10/bin/10."*/x64 \
  2>/dev/null | sort -V | tail -n 1)
if [ ! -x "$kit/makeappx.exe" ] || [ ! -x "$kit/makepri.exe" ]; then
  echo "::error::no makeappx and makepri — install the Windows SDK"
  exit 1
fi

# A value in the manifest is XML text, and sed's replacement besides.
xml() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e 's/[\\|&]/\\&/g'
}

out=build/windows/msix
rm -rf "$out"
mkdir -p "$out/layout" "$out/pri"
cp -r "$build/." "$out/layout/" || exit 1
# The resource index is built from the manifest and the logos alone: the
# build's own files (data/flutter_assets) are no resources of the package.
for dir in "$out/layout" "$out/pri"; do
  sed -e "s|@NAME@|$(xml "$store_name")|" \
    -e "s|@PUBLISHER@|$(xml "$store_publisher")|" \
    -e "s|@PUBLISHER_DISPLAY_NAME@|$(xml "$store_publisher_display_name")|" \
    -e "s|@VERSION@|$version|" \
    windows/msix/AppxManifest.xml > "$dir/AppxManifest.xml" || exit 1
  cp -r windows/msix/Assets "$dir/" || exit 1
done
echo "store package: $version"

# ⚠️The SDK's switches start with a slash, which Git Bash would otherwise
# turn into a path under its own install folder.
win() { cygpath -w "$1"; }
export MSYS_NO_PATHCONV=1
"$kit/makepri.exe" createconfig /cf "$(win "$out/priconfig.xml")" \
  /dq en-US /pv 10.0.0 /o || exit 1
# One index, holding every scale: the config's <packaging> splits them into
# resources.scale-200.pri for the resource packs of a bundle, and this is
# one package with none.
sed -i '/<packaging>/,/<\/packaging>/d' "$out/priconfig.xml" || exit 1
"$kit/makepri.exe" new /pr "$(win "$out/pri")" \
  /cf "$(win "$out/priconfig.xml")" \
  /mn "$(win "$out/pri/AppxManifest.xml")" \
  /of "$(win "$out/layout/resources.pri")" /o || exit 1
"$kit/makeappx.exe" pack /d "$(win "$out/layout")" \
  /p "$(win "$out/Anicel.msix")" /o || exit 1
echo "packed: $out/Anicel.msix"
