import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/ui/brush/brush_canvas_panel.dart';
import 'package:anicel/src/ui/brush/brush_edit_cache_invalidation_sink.dart';
import 'package:anicel/src/ui/brush/canvas_floor_insets.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
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

    for (final size in PasteboardSize.values) {
      expect(pill('pasteboard-size-${size.name}'), findsOneWidget);
    }
    final strings = AppText.strings;
    expect(
      find.descendant(
        of: pill('pasteboard-in-use'),
        matching: find.text(strings.pasteboardInUse),
      ),
      findsOneWidget,
    );

    await tester.tap(pill('pasteboard-size-oneAndAHalf'));
    await tester.pumpAndSettle();
    expect(sizes, [PasteboardSize.oneAndAHalf]);

    await tester.tap(pill('pasteboard-in-use'));
    await tester.pumpAndSettle();
    expect(uses, [false]);
    expect(
      find.descendant(
        of: pill('pasteboard-in-use'),
        matching: find.text(strings.pasteboardNotInUse),
      ),
      findsOneWidget,
      reason: 'the pill says what it is now, as the window stays open',
    );

    // Off, the size is still the user's to pick for when it is on again.
    await tester.tap(pill('pasteboard-size-three'));
    await tester.pumpAndSettle();
    expect(sizes, [PasteboardSize.oneAndAHalf, PasteboardSize.three]);
  });

  testWidgets('the window opens on the project\'s values', (tester) async {
    await pumpPanel(
      tester,
      size: PasteboardSize.three,
      inUse: false,
      sizes: [],
      uses: [],
    );
    await tapInViewSettings(tester, 'canvas-pasteboard-color-button');
    expect(
      find.descendant(
        of: pill('pasteboard-in-use'),
        matching: find.text(AppText.strings.pasteboardNotInUse),
      ),
      findsOneWidget,
    );
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
