import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/dart_sources.dart';
import '../helpers/source_ledger.dart';

/// A LAYER THAT ANSWERS SOME OF ITS PIXELS IS GATED BY ONE WIDGET:
/// [HitGate] (`lib/src/ui/input/hit_gate.dart`).
///
/// The storyboard's strip gesture, the rows' edit chrome and the canvas
/// box's press area each wrote the same proxy box by hand — hit the child
/// only where a predicate says — and a header graph's handles (I-89 ③) were
/// about to be the fourth. A behaviour test cannot see a fifth: two copies
/// that agree pass every test the one widget does.
///
/// So the scan counts the files that rewrite a proxy box's hit test. Those
/// that do it for a reason of their own stand in [ledger] with the reason;
/// a new one is either a [HitGate] or a reason written here.
void main() {
  const home = 'lib/src/ui/input/hit_gate.dart';
  const ledger = {
    // The playback view's actuation probe: it absorbs, and records where a
    // press landed — it lets nothing through to gate.
    'lib/src/ui/playback/playback_actuation_gate.dart',
    // The ink layer is hit where it paints: the clip it draws through
    // answers its hit test, as a clip's silhouette does.
    'lib/src/ui/sheet/sheet_ink_layer.dart',
    // A clip's silhouette: a pointer in a cut corner must miss.
    'lib/src/ui/widgets/superellipse_clip.dart',
    // The app tooltip, as Flutter's is (2026-10-25): its whole box takes a
    // press — its opaque listener — and only the innermost tooltip stands
    // on a hover's path — its exclusive mouse region. It gates nothing.
    'lib/src/ui/widgets/app_tooltip.dart',
  };
  final proxyBox = RegExp(r'extends RenderProxyBox\b');
  final hitTest = RegExp(r'bool hitTest\(BoxHitTestResult');
  bool rewritesAHitTest(String source) =>
      proxyBox.hasMatch(source) && hitTest.hasMatch(source);

  test('nothing but the gate rewrites a proxy box\'s hit test, but for the '
      'reasons the ledger names — and every file it names still does', () {
    expectSetMatchesLedger(
      [
        for (final file in dartFilesUnder('lib'))
          if (libPath(file) != home &&
              rewritesAHitTest(file.readAsStringSync()))
            libPath(file),
      ],
      ledger,
      unledgered:
          'a box hit only where a predicate says is `HitGate(admits: …)` — '
          'or a reason of its own, written in this test\'s ledger',
      paidOff: 'these no longer rewrite one, or are gone — drop them here',
    );
  });

  test('the scan sees what it guards: the gate still rewrites a proxy '
      'box\'s hit test', () {
    final gate = File(home);
    expect(gate.existsSync(), isTrue, reason: '$home is gone — drop it here');
    expect(
      rewritesAHitTest(gate.readAsStringSync()),
      isTrue,
      reason: '$home no longer rewrites one — drop it here',
    );
  });
}
