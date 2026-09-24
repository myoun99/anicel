import 'package:flutter_test/flutter_test.dart';
import '../helpers/dart_sources.dart';

/// 🚨★★★**WHAT THE START TOOK IS GIVEN BACK ON ALL THREE ARMS — LANDING,
/// OVERTAKING, REFUSAL — AND THE PLACE THAT GIVES IT BACK IS STRUCTURAL.**
///
/// A `ui.Picture` holds native memory that no GC reclaims and that no Dart
/// heap number shows. Releasing it on the line AFTER the raster is the shape
/// that leaks, because neither call the raster is made with lands on that
/// line when it fails:
///
///   * `toImageSync` **throws** — `static_raster.dart` says so where it wraps
///     the same call. ⚠️Not a Skia-only hazard: it throws where there is no
///     GPU context or the size is refused, on any backend. The sentence used
///     to end "and Skia is what Windows runs in debug AND release", which
///     stopped being true when 3.47 made Impeller the desktop default
///     (2026-09-16) and was never what made the `finally` necessary.
///   * `toImage` is **awaited**, and a throw inside an await skips every
///     statement after it.
///
/// So `final x = p.toImageSync(…); p.dispose();` releases on the landing arm
/// only. The fix is a `finally`, and the reason it is a `finally` rather than
/// a second `dispose()` on the failure path is [[make-the-invariant-
/// unrepresentable]]: two places that must agree are two places that can
/// disagree.
///
/// 🧪MEASURED 2026-09-10, and the audit had already been here twice: two
/// rounds declared 「every bytes→picture upload can say no」 and the sweep
/// still found six more of this exact shape. Five survived to this commit —
/// `raster_cel_import` · `provisional_tile_pictures` ·
/// `subtree_image_composite` (twice) · `timeline_grid_tile_store` — and this
/// scan finds all five in the code as it stood one commit ago and none in the
/// code as it stands now. ⛔A scan that has never been shown to fire is a
/// scan that measures nothing; that is not a hypothetical here, an opacity
/// ratchet in this repo spent weeks matching a parameter name that did not
/// exist yet.
///
/// ⛔A BEHAVIOUR TEST CANNOT CLOSE THIS. Nothing observable differs until the
/// raster fails, and a raster that fails is exactly what a test fixture does
/// not do. What fails is the sixth site, written next year by someone who
/// reached for the two-line shape because it reads fine. So the nail is a
/// source scan and the number is ZERO.
///
/// ⚠️WHAT IT DOES NOT CLAIM. It reads two adjacent lines, so it sees only the
/// immediate shape. A dispose three statements later, or one inside an `if`,
/// is the same bug and this does not see it — the scan is a floor, not a
/// proof. It also says nothing about the IMAGE the raster produced; that is
/// held on purpose in several places (a crossfade blits two scopes at once)
/// and belongs to whoever the raster was made for.
void main() {
  final assignment = RegExp(
    r'=\s*(?:await\s+)?([A-Za-z_][A-Za-z0-9_]*)\.toImage(?:Sync)?\(',
  );
  final release = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)\.dispose\(\);');

  test('🚨★★★래스터를 만든 것은 finally 에서 돌려준다 — 착지 팔에서만 놓는 자리 0', () {
    final found = <String>[];
    for (final entry in dartFilesUnder('lib/src')) {
      final relative = entry.path.replaceAll(r'\', '/');
      final key = relative.substring(relative.indexOf('lib/src'));
      final lines = entry.readAsLinesSync();
      for (var i = 0; i < lines.length - 1; i += 1) {
        final made = assignment.firstMatch(lines[i]);
        if (made == null) continue;
        // The next line that is not blank and not a comment. A `}` — which is
        // what a `try` block's close looks like — never matches [release], so
        // the corrected shape falls out here without a special case.
        var j = i + 1;
        while (j < lines.length) {
          final next = lines[j].trim();
          if (next.isEmpty || next.startsWith('//')) {
            j += 1;
            continue;
          }
          break;
        }
        if (j >= lines.length) break;
        final given = release.firstMatch(lines[j].trim());
        if (given == null) continue;
        if (given.group(1) != made.group(1)) continue;
        found.add('$key:${j + 1}  ${made.group(1)}');
      }
    }
    expect(
      found,
      isEmpty,
      reason:
          '이 자리들은 래스터가 성공했을 때만 놓아준다. `finally` 로 옮길 것 — '
          '무엇을 왜 그렇게 하는지는 이 파일 머리에 있다:\n${found.join('\n')}',
    );
  });
}
