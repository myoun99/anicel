import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/widgets/pill_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/brush_canvas_fixture.dart';
import '../../helpers/canvas_pill.dart';

/// 🗣️I-109 (유저 2026-10-18): 「캔버스패널의 페이스트보드 색 고르는 창 안에
/// 크기 지정이랑 사용 불리언 버튼 두도록」 — the pasteboard's colour window
/// carries its size (Q3: 1.5x · 2x · 3x) and whether it is in use, and
/// hands each change on.
void main() {
  Future<void> pumpPanel(
    WidgetTester tester, {
    required PasteboardSize size,
    required bool inUse,
    List<PasteboardSize>? sizes,
    List<bool>? uses,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final frameKeys = BrushCanvasFixture.createFrameKeys();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CanvasStageColors(
            backdropArgb: 0xFF202020,
            pasteboardArgb: 0xFF808080,
            pasteboardSize: size,
            pasteboardInUse: inUse,
            child: BrushCanvasPanel(
              coordinator: BrushCanvasFixture.createCoordinator(
                frameKeys: frameKeys,
              ),
              availableFrameKeys: frameKeys,
              cacheInvalidationSink: BrushEditCacheInvalidationSink(),
              floorCover: EdgeInsets.zero,
              onPaperColorChanged: (_) {},
              onPasteboardColorChanged: (_) {},
              onPasteboardSizeChanged: sizes?.add,
              onPasteboardInUseChanged: uses?.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder pill(String keyValue) => find.byKey(ValueKey<String>(keyValue));

  /// The pill as it stands — read off the widget, not its words: a toggle
  /// sets its other word too, unseen, to keep its width
  /// ([PillItem.otherLabel]), so both words are always found.
  Pill pillOf(WidgetTester tester, String keyValue) =>
      tester.widget<Pill>(pill(keyValue));

  void expectInUse(WidgetTester tester, {required bool inUse}) {
    final toggle = pillOf(tester, 'pasteboard-in-use');
    expect(toggle.selected, inUse);
    expect(
      toggle.label,
      inUse
          ? AppText.strings.pasteboardInUse
          : AppText.strings.pasteboardNotInUse,
    );
  }

  void expectSize(WidgetTester tester, PasteboardSize chosen) {
    for (final size in PasteboardSize.values) {
      expect(
        pillOf(tester, 'pasteboard-size-${size.name}').selected,
        size == chosen,
        reason: size.label,
      );
    }
  }

  testWidgets('the size and the use are in the window and hand on', (
    tester,
  ) async {
    final sizes = <PasteboardSize>[];
    final uses = <bool>[];
    await pumpPanel(
      tester,
      size: PasteboardSize.two,
      inUse: true,
      sizes: sizes,
      uses: uses,
    );
    await tapInViewSettings(tester, 'canvas-pasteboard-color-button');
    expectInUse(tester, inUse: true);
    expectSize(tester, PasteboardSize.two);

    await tester.tap(pill('pasteboard-size-oneAndAHalf'));
    await tester.pumpAndSettle();
    expect(sizes, [PasteboardSize.oneAndAHalf]);
    expectSize(tester, PasteboardSize.oneAndAHalf);

    await tester.tap(pill('pasteboard-in-use'));
    await tester.pumpAndSettle();
    expect(uses, [false]);
    expectInUse(tester, inUse: false);

    // Off, the size is still the user's to pick for when it is on again.
    await tester.tap(pill('pasteboard-size-three'));
    await tester.pumpAndSettle();
    expect(sizes, [PasteboardSize.oneAndAHalf, PasteboardSize.three]);
    expectSize(tester, PasteboardSize.three);
  });

  testWidgets('the window opens on the project\'s values', (tester) async {
    await pumpPanel(
      tester,
      size: PasteboardSize.oneAndAHalf,
      inUse: false,
      sizes: [],
      uses: [],
    );
    await tapInViewSettings(tester, 'canvas-pasteboard-color-button');
    expectInUse(tester, inUse: false);
    expectSize(tester, PasteboardSize.oneAndAHalf);
  });

  testWidgets('the paper\'s window has no pasteboard row', (tester) async {
    await pumpPanel(
      tester,
      size: PasteboardSize.three,
      inUse: true,
      sizes: [],
      uses: [],
    );
    await tapInViewSettings(tester, 'canvas-paper-color-button');
    expect(
      find.byKey(const ValueKey<String>('color-picker-wheel')),
      findsOneWidget,
    );
    expect(pill('pasteboard-in-use'), findsNothing);
    expect(pill('pasteboard-size'), findsNothing);
  });
}
