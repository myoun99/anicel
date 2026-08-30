import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 🚨★★★「앱에 버튼은 한 종류」 — and this is what makes it true.
///
/// 유저 확정, and the tools panel wrote it in its own comment while being an
/// exception to it. An audit on 2026-08-28 found **36 hand-rolled
/// `IconButton`s across 22 files** at five glyph sizes, and 실측 said not one
/// of them could join without its box changing — so 유저 chose to grow the
/// size TOKENS rather than collapse every button to one size.
///
/// ⛔"ONE KIND" MEANS ONE PARENT, not one size: one shape, one selection
/// rule, one hit-target policy, with the size named rather than typed. The
/// audit's real catch was three buttons breaking the selection rule —
/// 「선택 표시는 색상만」 — with a filled chip or a check mark.
///
/// 🚨THIS SCAN READS `IconButton(` ONLY, AND THAT IS A REAL LIMIT. On
/// 2026-08-29 the bar's 1·2·3·4·N turned out to be hand-rolled TEXT buttons,
/// so they walked straight past the thing that exists to notice them. The
/// scan is deliberately not widened — a dialog's text action is not an icon
/// button and dragging twenty of them in here would say nothing — but the
/// LAW those buttons were missing has its own scan, over text buttons and
/// ink wells too: `every_button_claims_its_press_test`. Two lists,
/// because they answer two questions (this one licenses a BOX; that one
/// holds every button under `lib/src/ui` to the press claim).
///
/// ⚠️THE LEDGER BELOW IS THE POINT OF THIS TEST. A hand-rolled button is
/// allowed only where a PARENT has already promised the box, because
/// `AppIconButton` decides its own from a token and two owners of one box is
/// not a thing. Every entry says which parent and how wide.
void main() {
  /// Files that may still build a Material `IconButton` directly, and why.
  ///
  /// ⛔ADDING A LINE HERE IS A DECISION, not a formality: it says the parent
  /// owns the box. If the box is yours to pick, use a token.
  /// 🏁**IT IS EMPTY, and that is the round's result** (2026-08-29).
  ///
  /// It held four files whose only reason to hand-roll was the BOX: the
  /// rail's 20–22px slots and the top strip's promised 32. `AppIconButton`
  /// takes an [AppIconButtonBox] now, so the parent still owns the number
  /// and the app owns everything else — the shape, the selection rule, the
  /// hit-target policy and the press claim.
  ///
  /// 🧪The box was the whole risk, so the box is what was measured: **44
  /// buttons across both rails and both orientations, byte-identical
  /// rectangles before and after.** [[widget-between-slot-and-plate]] is the
  /// record of what a moved slot costs, and nothing moved.
  ///
  /// ⛔A NEW LINE HERE IS NOW A BIGGER DECISION THAN IT WAS. While four
  /// files sat in this map, adding a fifth was joining a crowd; with the map
  /// empty, it is the first exception again — and there is no box argument
  /// left to make, because a caller-owned box is no longer a reason to
  /// hand-roll.
  const ledger = <String, String>{};

  test('a hand-rolled IconButton argues for itself in the ledger', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      if (relative.endsWith('widgets/app_icon_button.dart')) {
        continue;
      }
      if (ledger.containsKey(relative)) {
        continue;
      }
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        // `AppIconButton(` and `StrapIconButton(` are the wrappers; only a
        // bare `IconButton(` is a hand-roll. `IconButton.styleFrom` is a
        // static, not a widget.
        if (RegExp(r'(^|[^A-Za-z])IconButton\(').hasMatch(line) &&
            !line.contains('IconButton.styleFrom')) {
          offenders.add('$relative:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'every icon button mounts AppIconButton, so the app\'s shape, '
          'selection rule and hit target land everywhere at once. If a '
          'parent genuinely owns the box, add the file to the ledger in '
          'this test with the width it promised',
    );
  });

  test('the ledger has no dead entries', () {
    // ⛔A ledger that outlives its reason is worse than none: the next reader
    // takes it as permission. Each entry must still have a hand-rolled
    // button in it.
    for (final entry in ledger.entries) {
      final file = File(entry.key);
      expect(file.existsSync(), isTrue, reason: '${entry.key} is gone');
      final source = file.readAsStringSync();
      expect(
        RegExp(r'(^|[^A-Za-z])IconButton\(').hasMatch(source),
        isTrue,
        reason: '${entry.key} no longer hand-rolls one — drop its ledger line '
            '(reason on file: ${entry.value})',
      );
    }
  });

  test('the selection rule reaches every button that has an on state', () {
    // 🚨THE AUDIT'S REAL CATCH. 「선택 표시는 색상만」 — an accent foreground,
    // never a check mark and never a filled chip. Three buttons broke it:
    // the tool rail and the selection-combine row painted
    // `surfaceContainerHigh` behind the selected glyph, and the guide panel
    // swapped `circle_outlined` for `check_circle`.
    //
    // ⛔SCANNED, because each of them looked local and reasonable in its own
    // file — which is how three of them happened.
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) {
        continue;
      }
      final path = file.path.replaceAll(r'\', '/');
      final relative = path.substring(path.indexOf('lib/'));
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) {
          continue;
        }
        if (line.contains('backgroundColor: selected') ||
            line.contains('backgroundColor: isSelected') ||
            line.contains('selectedIcon:')) {
          offenders.add('$relative:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'a selected button changes COLOUR, not shape — no filled chip, '
          'no check mark, no swapped glyph',
    );
  });
}
