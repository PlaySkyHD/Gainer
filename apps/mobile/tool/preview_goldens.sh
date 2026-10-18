#!/usr/bin/env bash
# Rendert Golden-Tests mit echter Schrift, damit Layouts beurteilt werden können.
# Die echten Goldens unter test/ bleiben unverändert.
#
# Nutzung (aus apps/mobile):
#   tool/preview_goldens.sh test/ui/nutrition/nutrition_day_golden_test.dart
#   tool/preview_goldens.sh test/ui/body            # ganzer Ordner
# Ergebnis: PNGs unter test/zz_preview/<pfad>/goldens/. Danach aufräumen mit
#   rm -rf test/zz_preview
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Nutzung: $0 <test-datei-oder-ordner unter test/ui/> [...]" >&2
  exit 64
fi

cd "$(dirname "$0")/.."

export GAINER_PREVIEW_FONT="${GAINER_PREVIEW_FONT:-/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf}"
if [[ -z "${GAINER_PREVIEW_ICONS:-}" ]]; then
  GAINER_PREVIEW_ICONS="$(find "${PUB_CACHE:-$HOME/.pub-cache}" -path '*cupertino_icons*/assets/CupertinoIcons.ttf' 2>/dev/null | sort | tail -1)"
  export GAINER_PREVIEW_ICONS
fi
if [[ ! -f "$GAINER_PREVIEW_FONT" || ! -f "$GAINER_PREVIEW_ICONS" ]]; then
  echo "Schrift oder Icons fehlen: GAINER_PREVIEW_FONT / GAINER_PREVIEW_ICONS setzen." >&2
  exit 1
fi

rm -rf test/zz_preview
mkdir -p test/zz_preview
cp tool/golden_preview/flutter_test_config.dart.template test/zz_preview/flutter_test_config.dart
# test/ui/<x> wird zu test/zz_preview/<x>: gleiche Ordnertiefe, damit relative
# Imports (test/support, integration_test) weiter passen.
cp -r test/ui/. test/zz_preview/
find test/zz_preview -name '*.png' -delete

targets=()
for path in "$@"; do
  targets+=("test/zz_preview/${path#test/ui/}")
done
flutter test --update-goldens "${targets[@]}"
find test/zz_preview -path '*/goldens/*.png' | sort
