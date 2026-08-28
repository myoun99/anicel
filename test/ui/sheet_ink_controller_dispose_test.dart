import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/conte/conte_sheet_layout.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/envelope/cut_envelope_ink_keys.dart';
import 'package:anicel/src/ui/conte/conte_ink.dart';
import 'package:anicel/src/ui/envelope/cut_envelope_ink.dart';

/// 🚨★★★CLOSING A SHEET PANEL MID-COMPOSE MUST NOT THROW.
///
/// `displayImageFor` composes a baked surface's tiles asynchronously and
/// notifies when the image lands. If the panel closes first, that notify
/// hits a disposed `ChangeNotifier` — Flutter throws — and the composed
/// image is stored into a map nobody will ever dispose.
///
/// 🚨THIS IS THE BUG A COPY HID. The envelope's controller checked
/// `_disposed`; the conte's, written first, never got the fix — the two
/// were the same object typed out twice, and the repair reached one of
/// them. The audit on 2026-08-28 (유저: 「사본은 특히 위험한대상이야」)
/// found it by diffing them, not by anything failing.
///
/// ⛔SO THE FIX WAS THE MERGE, and this file guards the merged guard.
void main() {
  test('a disposed conte controller does not throw on a late compose', () {
    final controller = ConteInkController();
    controller.syncGeometry(
      const ConteSheetMetrics(pageWidth: 200, pageHeight: 280),
    );
    // Touch the plane so the coordinator and its store really exist — a
    // controller that never woke up cannot exercise the race.
    controller.sessionStateFor(
      ConteInkPlane.page,
      ConteInkController.pageKey(0),
    );
    controller.dispose();

    expect(
      () => controller.displayImageFor(
        ConteInkPlane.page,
        ConteInkController.pageKey(0),
      ),
      returnsNormally,
      reason: 'a closed panel still answers "no image" rather than throwing',
    );
  });

  test('a disposed envelope controller behaves the same way', () {
    final controller = CutEnvelopeInkController();
    controller.syncGeometry(aspectRatio: 1.4);
    controller.dispose();
    expect(
      () => controller.displayImageFor(
        null,
        envelopeInkBoxKey(const CutId('c'), 'box'),
      ),
      returnsNormally,
      reason: 'the two sheets share one implementation, so they share this',
    );
  });

  test('the guard lives in ONE place', () {
    // ⛔SOURCE SCAN. Behaviour cannot see the defect this file exists for:
    // two copies that both carry the guard pass, and so do two copies where
    // only one does — until the day the wrong one runs. The invariant worth
    // holding is that there is nothing to keep in sync.
    expect(
      File(
        'lib/src/ui/sheet/sheet_ink_controller.dart',
      ).readAsStringSync().contains('_disposed'),
      isTrue,
      reason: 'the shared controller is where the guard belongs',
    );
    for (final path in const [
      'lib/src/ui/conte/conte_ink.dart',
      'lib/src/ui/envelope/cut_envelope_ink.dart',
    ]) {
      expect(
        File(path).readAsStringSync().contains('_disposed'),
        isFalse,
        reason: '$path must inherit the guard, not carry its own copy',
      );
    }
  });
}
