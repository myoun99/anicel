import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/pasteboard_bounds.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/persistence/session_scratch.dart';
import 'package:anicel/src/ui/cut_command_group.dart';
import 'package:anicel/src/ui/editor_canvas_area.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';

import '../helpers/cels_kept_in_a_file.dart';
import '../helpers/files_written_under.dart';
import '../helpers/panel_finders.dart';
import 'flyout_test_helpers.dart' show flyoutOwnerByItemKey;

/// D3 (R7): the cut-canvas resize runs behind the app's ONE wait-for-this
/// window — the same [AppProgressDialog] save wears, held across BOTH
/// halves of the resize (the synchronous command and the next frame's
/// canvas-host adoption), so no input can slip between them.
///
/// Driven through the REAL entry: the CUT pill's flyout item → the
/// canvas-size dialog → confirm (parity-tests-must-drive-real-input).
void main() {
  testWidgets('confirming a resize shows the shared progress window and '
      'lands the new size', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;

    // The resize entry lives in the CUT pill's flyout.
    final owner = flyoutOwnerByItemKey['resize-cut-canvas-button'];
    if (owner != null) {
      await tester.tap(find.byKey(ValueKey<String>(owner)));
      await tester.pumpAndSettle();
    }
    await tester.tap(
      find.byKey(const ValueKey<String>('resize-cut-canvas-button')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-size-width-field')),
      '1280',
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('canvas-size-height-field')),
      '720',
    );
    // The confirm action pops the request CAPTURED AT BUILD — a real
    // keystroke rebuilds per onChanged, so the frame between entry and
    // press exists for a hand too.
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('canvas-size-confirm-button')),
    );
    // One pump: the progress window mounts BEFORE the work runs (its
    // own endOfFrame law) — the freeze happens behind a painted window.
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('resize-progress-dialog')),
      findsOneWidget,
      reason: 'the ONE shared window, up before the synchronous command',
    );

    await tester.pumpAndSettle();
    expect(
      session.activeCutOrNull!.canvasSize,
      const CanvasSize(width: 1280, height: 720),
    );
    // The done label lingers, then the window removes itself.
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('resize-progress-dialog')),
      findsNothing,
    );
  });

  // 🗣️F-432 (유저 2026-10-21): 「페이스트 보드 배율 전환이 너무 느리고, 이런
  // 시간 걸리는 로직은 규칙으로서 공용 로딩창 표시해야함」.
  testWidgets('a pasteboard size or use, pressed in its window, lands behind '
      'the same wait window, under the pasteboard\'s name', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(theme: buildAppTheme(), home: const HomePage()),
    );
    await tester.pumpAndSettle();

    final session = tester
        .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
        .session;
    // The floor lays its controls out rather than behind a gear.
    await tester.tap(
      find.descendant(
        of: mainCanvasPanelShell(),
        matching: find.byKey(
          const ValueKey<String>('canvas-pasteboard-color-button'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final (press, landed) in [
      (
        'pasteboard-size-oneAndAHalf',
        () => session.repository.requireProject().pasteboardSize ==
            PasteboardSize.oneAndAHalf,
      ),
      (
        'pasteboard-in-use',
        () => !session.repository.requireProject().pasteboardInUse,
      ),
    ]) {
      await tester.tap(find.byKey(ValueKey<String>(press)));
      await tester.pump();
      final window = find.byKey(
        const ValueKey<String>('resize-progress-dialog'),
      );
      expect(window, findsOneWidget, reason: press);
      expect(
        find.descendant(
          of: window,
          matching: find.text(AppText.strings.pasteboardTitle),
        ),
        findsOneWidget,
        reason: press,
      );
      await tester.pumpAndSettle();
      expect(landed(), isTrue, reason: press);
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pumpAndSettle();
      expect(window, findsNothing, reason: press);
    }
  });

  // 🗣️F-432: what a move of the wall can work out off the UI thread is
  // worked out first, behind the same window, and the window counts it.
  testWidgets('what is worked out ahead runs first, behind the window, and '
      'the window counts it', (tester) async {
    final gate = Completer<void>();
    var moved = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => resizeBehindTheWaitWindow(
              context,
              () => moved = true,
              title: 'wall',
              ahead: (report) async {
                report(0.5);
                await gate.future;
              },
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump();
    final window = find.byKey(const ValueKey<String>('resize-progress-dialog'));
    expect(window, findsOneWidget);
    expect(find.descendant(of: window, matching: find.text('50%')), findsOne);
    expect(moved, isFalse, reason: 'the move waits for what runs ahead');

    gate.complete();
    await tester.pumpAndSettle();
    expect(moved, isTrue);
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
  });

  // Both doors of the pasteboard row run ahead: its size, and whether it is
  // in use at all — each a smaller wall from 3x.
  for (final press in ['pasteboard-size-oneAndAHalf', 'pasteboard-in-use']) {
    testWidgets('$press, pressed in its window, cuts the cels kept in files '
        'ahead of the move', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const HomePage()),
      );
      await tester.pumpAndSettle();
      final session = tester
          .widget<EditorCanvasArea>(find.byType(EditorCanvasArea))
          .session;
      expect(
        session.repository.requireProject().pasteboardSize,
        PasteboardSize.three,
        reason: 'premise: 1.5x, and none, are smaller walls',
      );
      // A cel kept in a file, wholly past the 1.5x wall — x -16..-13 of a
      // paper 16 wide, inside the 3x one.
      keepInAFile(session.renderCaches.brushFrameStore, {
        const BrushFrameKey(
          projectId: ProjectId('p'),
          trackId: TrackId('t'),
          cutId: CutId('c'),
          layerId: LayerId('l'),
          frameId: FrameId('kept'),
        ): BitmapSurface(
          canvasSize: const CanvasSize(width: 16, height: 8),
          tileSize: 4,
        ).putTiles([
          (
            coord: TileCoord(x: -4, y: 0),
            tile: BitmapTile(
              size: 4,
              pixels: Uint8List(64)..fillRange(0, 64, 50),
            ),
          ),
        ]),
      });
      Set<String> parkedAhead() => {
        for (final path in filesWrittenUnder(
          Directory(SessionScratch.stagedFolder()),
        ))
          if (path.contains('-ahead')) path,
      };

      final before = parkedAhead();
      await tester.tap(
        find.descendant(
          of: mainCanvasPanelShell(),
          matching: find.byKey(
            const ValueKey<String>('canvas-pasteboard-color-button'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey<String>(press)));
      await tester.pumpAndSettle();
      expect(
        parkedAhead().difference(before),
        hasLength(1),
        reason: 'the cut was worked out ahead, and the move took it',
      );
      await tester.pump(const Duration(milliseconds: 950));
      await tester.pumpAndSettle();
    });
  }
}
