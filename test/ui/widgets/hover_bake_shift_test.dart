import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/widgets/static_raster.dart';

/// ② + R6-③ — **THE MEASUREMENT, not the fix.**
///
/// 유저: 「툴 라이브러리 +버튼쪽, 호버하면 버튼이 위로 1px정도 튀고 돌아옴」
/// and 「프레임 노출편집(1,2,3,4,N)버튼쪽에 커서올리면 간헐적으로 해당 영역
/// 버튼들이 1px정도 위로 튀었다가 돌아옴」 — the same symptom on two bars.
///
/// R6 left two candidates and one instruction: ⛔do not touch the shared
/// `static_raster.dart` without an A/B first, because it is the canvas
/// performance round's output. The A/B is exactly this file:
///
///   1. a hovered button inside a [StaticRaster] at a FRACTIONAL device
///      pixel ratio — the Windows 125%/150% case the report came from
///   2. the same tree with [StaticRaster.globallyEnabled] off
///
/// If the rect moves in (1) and holds in (2), the bake↔pass-through
/// transition is the cause and the fix belongs in the shared widget. If it
/// moves in both, the bake is innocent and it is the Material button.
///
/// 🚨 **RESULT (2026-08-12): both hold — and that is NOT a clean acquittal.**
/// The stand-down this is hunting needs `_streak >= maxConsecutiveCaptures`,
/// i.e. the child animating for three consecutive frames, and a hover overlay
/// in a widget test may settle instantly and never build that streak. So what
/// this file actually proves is narrower than the A/B it was written for:
/// **the grid fit keeps the rect stable across a hover at fractional DPR**.
/// It does not prove the transition is innocent, because it may never have
/// reached the transition.
///
/// ⛔Therefore the shared `static_raster.dart` still MUST NOT be edited on a
/// guess (R6's instruction stands, and [[canvas-raster-perf-round]] is what
/// would pay for it). The real A/B belongs on the device: toggle
/// `StaticRaster.globallyEnabled` from Preferences and hover the same button.
/// Keep this file anyway — if someone later "fixes" the raster for this
/// symptom, a green here says that was not where the pixel went.
void main() {
  /// A hovered `IconButton` baked inside a raster, the tool library's shape.
  Widget harness() => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        // The fractional OFFSET matters as much as the ratio: a surface
        // landing on a whole device pixel has no phase to lose.
        child: Padding(
          padding: const EdgeInsets.only(left: 10.4, top: 6.6),
          child: StaticRaster(
            debugLabel: 'hover-probe',
            child: IconButton(
              key: const ValueKey<String>('probe-button'),
              onPressed: () {},
              icon: const Icon(Icons.add),
            ),
          ),
        ),
      ),
    ),
  );

  /// The button's rect before, during and after a hover.
  Future<List<Rect>> hoverRects(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.25;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final button = find.byKey(const ValueKey<String>('probe-button'));
    final rects = <Rect>[tester.getRect(button)];

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
      pointer.hover(tester.getCenter(button)),
    );
    // The ink is what animates, and the raster stands down while it does —
    // so the rect is sampled ACROSS the animation, not only at its ends.
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 16));
      rects.add(tester.getRect(button));
    }
    await tester.pumpAndSettle();
    rects.add(tester.getRect(button));

    await tester.sendEventToBinding(pointer.hover(const Offset(600, 600)));
    await tester.pumpAndSettle();
    rects.add(tester.getRect(button));
    return rects;
  }

  testWidgets('a hovered button inside a raster does not move', (tester) async {
    final rects = await hoverRects(tester);
    final first = rects.first;
    for (final rect in rects) {
      expect(
        rect,
        first,
        reason: 'the button shifted while the pointer was over it — 유저: '
            '「호버하면 버튼이 위로 1px정도 튀고 돌아옴」',
      );
    }
  });

  testWidgets('…and it does not move with the bake switched off either — '
      'which is what tells the two candidates apart', (tester) async {
    StaticRaster.globallyEnabled.value = false;
    addTearDown(() => StaticRaster.globallyEnabled.value = true);

    final rects = await hoverRects(tester);
    final first = rects.first;
    for (final rect in rects) {
      expect(rect, first);
    }
  });
}
