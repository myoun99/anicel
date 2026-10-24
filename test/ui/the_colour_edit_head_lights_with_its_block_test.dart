import 'dart:typed_data';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/controllers/default_project_helpers.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/pixel_clipboard_verb.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/cel_pixel_overwrite.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/editor_workspace.dart';
import 'package:anicel/src/ui/home_page.dart';
import 'package:anicel/src/ui/session/pixel_verbs.dart';
import 'package:anicel/src/ui/timeline/timeline_action_toolbar.dart';

import '../helpers/app_icon_button_probe.dart';
import '../helpers/panel_finders.dart' show visibleCanvasPoint;

/// pen-up-dock-tail-Q2 (유저 2026-10-24): 「블록과 같이 펜을 댈 때 켜고, 획
/// 도중에는 메뉴 줄을 막는다」.
///
/// The 색 편집 head asked the store whether the cel held a drawing, and the
/// store learns of a first stroke at pen-up — so the block went white at
/// pen-down and the head lit as the pen lifted, building the bar again and
/// throwing the timeline dock's still image away a second time.
///
/// The collaborator the gates live in, named so `tool/mutation_run.dart`
/// runs this file for it.
PixelVerbs pixelVerbsOf(EditorSessionManager s) => s.pixelVerbs;

final _head = find.byKey(const ValueKey<String>('shared-colour-edit-button'));
final _sharedPill = find.byKey(
  const ValueKey<String>('timeline-toolbar-shared-group'),
);

/// The timeline's bar, which its host keeps while it is built for the same
/// thing — its groups hear their own gates, the head's among them.
final _bar = find.ancestor(
  of: _sharedPill,
  matching: find.byType(TimelineActionToolbar),
);

void main() {
  /// The app on the bare project, standing on a cel made empty at frame 0.
  Future<EditorSessionManager> openOnAnEmptyCel(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: HomePage(initialProject: createDefaultProject())),
    );
    await tester.pumpAndSettle();
    final session = tester
        .widget<EditorWorkspace>(find.byType(EditorWorkspace))
        .session;
    session.selectFrameIndex(0);
    session.createDrawingAtCurrentFrame();
    await tester.pumpAndSettle();
    return session;
  }

  BrushFrameKey standingKey(EditorSessionManager s) => s.brushFrameKeyForCut(
    s.requireActiveCut,
    s.activeLayerId!,
    s.selectedFrame!.id,
  );

  bool blockIsWhite(EditorSessionManager s) =>
      s.layerStack.celHasContentForLayer(s.activeLayer!, 0);

  bool headIsLit(WidgetTester tester) =>
      tester.appIconButton(_head).onPressed != null;

  Future<TestGesture> penDown(WidgetTester tester) async {
    final press = await tester.startGesture(
      visibleCanvasPoint(tester),
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    await press.moveBy(const Offset(40, 30));
    await tester.pump();
    return press;
  }

  testWidgets('a first stroke lights the head at pen-down, with its block — '
      'and the pen lifting builds nothing on the bar again', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    expect(blockIsWhite(s), isFalse, reason: 'premise: an empty cel');
    expect(s.appClipboard.pixels.piece, isNull, reason: 'premise');
    expect(headIsLit(tester), isFalse, reason: 'premise: nothing to edit');

    final press = await penDown(tester);
    expect(s.brushInputActive.value, isTrue, reason: 'premise: a live stroke');
    expect(blockIsWhite(s), isTrue, reason: 'premise: the block went white');
    expect(headIsLit(tester), isTrue, reason: 'the head lights with it');

    final built = tester.widgetList(_sharedPill).toList();
    final bar = tester.widget(_bar);
    await press.moveBy(const Offset(30, 20));
    await tester.pump();
    await press.up();
    await tester.pumpAndSettle();
    expect(
      s.renderCaches.brushFrameStore.celHasRenderableContent(standingKey(s)),
      isTrue,
      reason: 'premise: the stroke landed',
    );
    expect(headIsLit(tester), isTrue);
    final rebuilt = tester.widgetList(_sharedPill).toList();
    expect(
      [for (var i = 0; i < built.length; i++) identical(built[i], rebuilt[i])],
      everyElement(isTrue),
      reason: 'the pen lifting moved no gate the pill shows',
    );
    expect(
      identical(tester.widget(_bar), bar),
      isTrue,
      reason: 'the head lit at pen-down in its own group, so the pen '
          'lifting builds no bar again',
    );

    s.playbackRig.prerenderScheduler.cancel();
  });

  testWidgets('under the pen every row waits — a press runs nothing until '
      'the stroke has landed', (tester) async {
    final s = await openOnAnEmptyCel(tester);
    // The cel holds a drawing before the stroke: the rows' wait is the
    // stroke's, not an empty cel's.
    const bytes = defaultCelTileSize * defaultCelTileSize * 4;
    s.renderCaches.brushFrameStore.storeBakedSurface(
      standingKey(s),
      BitmapSurface(
        canvasSize: s.requireActiveCut.canvasSize,
        tiles: {
          TileCoord(x: 0, y: 0): BitmapTile(
            size: defaultCelTileSize,
            pixels: Uint8List(bytes)..fillRange(0, bytes, 0xFF),
          ),
        },
      ),
    );
    await tester.pump();
    final verbs = pixelVerbsOf(s);
    expect(verbs.canRunPixelVerb, isTrue, reason: 'premise: a drawn cel');
    expect(
      verbs.canRunPixelClipboardVerb(PixelClipboardVerb.copy),
      isTrue,
      reason: 'premise',
    );

    final press = await penDown(tester);
    expect(s.brushInputActive.value, isTrue, reason: 'premise: a live stroke');
    expect(verbs.canOpenColourEdit, isTrue, reason: 'the head stays open');
    expect(verbs.canRunPixelVerb, isFalse);
    for (final verb in PixelClipboardVerb.values) {
      expect(verbs.canRunPixelClipboardVerb(verb), isFalse, reason: verb.name);
    }
    final steps = s.historyManager.undoCount;
    verbs.runPixelVerb(CelPixelVerb.clearPixels);
    verbs.runPixelClipboardVerb(PixelClipboardVerb.copy);
    expect(
      s.historyManager.undoCount,
      steps,
      reason: 'the clear pressed under the pen ran nothing',
    );
    expect(s.appClipboard.pixels.piece, isNull, reason: 'nor did the copy');

    await press.up();
    await tester.pumpAndSettle();
    expect(verbs.canRunPixelVerb, isTrue, reason: 'landed, the rows open');
    expect(verbs.canRunPixelClipboardVerb(PixelClipboardVerb.copy), isTrue);

    s.playbackRig.prerenderScheduler.cancel();
  });
}
