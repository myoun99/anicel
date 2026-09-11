import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/app_input_settings.dart';
import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/brush_anti_alias.dart';
import 'package:anicel/src/models/brush_dab_sequence.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/brush_commit_builder.dart';
import 'package:anicel/src/services/brush_frame_edit_session_store.dart';
import 'package:anicel/src/services/brush_preset_defaults.dart';
import 'package:anicel/src/services/brush_stroke_commit_data.dart';
import 'package:anicel/src/ui/brush/brush_tool_state.dart';
import 'package:anicel/src/ui/canvas/canvas_touch_contacts.dart';
import 'package:anicel/src/ui/canvas/interactive_brush_edit_canvas_view.dart';

/// H39 (유저 2026-09-11): 「그게아닌 원형인것들? G펜이나 뭐 펜 그룹에
/// 있는것들 … aa off시엔 진짜 안티앨리어싱 완전없었으면 좋겠는데. 지금
/// off했는데도 이상한 불투명도 남아있거든」.
///
/// `round_tip_aa_none_is_hard_test` holds the kernels to a hard edge for a
/// stroke of dabs it builds itself. This one starts where the hand does: the
/// pen group's round brushes as the roster ships them, the edge set to none
/// through the tool state, a pressure stroke through the real canvas —
/// interpolation, the pressure curves, the dynamics, the stamp cache, the
/// live rasterizer — and it lands what the pen-up hands over through the
/// production commit builder, whichever route that takes.
void main() {
  const canvasSize = CanvasSize(width: 256, height: 128);
  const key = BrushFrameKey(
    projectId: ProjectId('p'),
    trackId: TrackId('t'),
    cutId: CutId('c'),
    layerId: LayerId('layer'),
    frameId: FrameId('frame'),
  );

  setUp(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });
  tearDown(() {
    CanvasTouchContacts.reset();
    AppInput.settings.value = AppInputSettings.testCorpusBaseline;
  });

  /// One pen line, swelling and tapering along a wave, drawn with [state].
  Future<List<BrushStrokeCommitData>> strokeWith(
    WidgetTester tester,
    BrushToolState state,
  ) async {
    final commits = <BrushStrokeCommitData>[];
    final store = BrushFrameEditSessionStore(canvasSize: canvasSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 256,
              height: 128,
              child: InteractiveBrushEditCanvasView(
                key: const ValueKey<String>('ink'),
                sessionState: store.getOrCreate(key),
                layerId: const LayerId('layer'),
                frameId: const FrameId('frame'),
                inputSettings: state.toInputSettings(),
                onSourceStrokeCommitted: commits.add,
              ),
            ),
          ),
        ),
      ),
    );
    final origin = tester.getTopLeft(find.byKey(const ValueKey<String>('ink')));
    Offset at(double t) =>
        origin + Offset(24 + 208 * t, 64 + 28 * math.sin(t * 5));
    const steps = 48;
    for (var i = 0; i <= steps; i += 1) {
      final t = i / steps;
      final pressure = math.max(0.02, math.sin(t * math.pi));
      tester.binding.handlePointerEvent(
        i == 0
            ? PointerDownEvent(
                pointer: 1,
                kind: PointerDeviceKind.stylus,
                position: at(t),
                pressure: pressure,
                pressureMin: 0,
                pressureMax: 1,
              )
            : PointerMoveEvent(
                pointer: 1,
                kind: PointerDeviceKind.stylus,
                position: at(t),
                pressure: pressure,
                pressureMin: 0,
                pressureMax: 1,
              ),
      );
      await tester.pump();
    }
    tester.binding.handlePointerEvent(
      PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: at(1),
        pressure: 0,
        pressureMin: 0,
        pressureMax: 1,
      ),
    );
    await tester.pump();
    // R25-④: the pen-up commit lands one frame AFTER pen-up.
    await tester.pump();
    return commits;
  }

  ({int partly, int solid}) countAlpha(Uint8List rgba) {
    var partly = 0;
    var solid = 0;
    for (var i = 3; i < rgba.length; i += 4) {
      final alpha = rgba[i];
      if (alpha == 255) {
        solid += 1;
      } else if (alpha > 0) {
        partly += 1;
      }
    }
    return (partly: partly, solid: solid);
  }

  ({int partly, int solid}) surfaceAlpha(BitmapSurface surface) {
    var partly = 0;
    var solid = 0;
    for (final tile in surface.tiles.values) {
      tile.readPixels((_, view) {
        final counted = countAlpha(view);
        partly += counted.partly;
        solid += counted.solid;
      });
    }
    return (partly: partly, solid: solid);
  }

  /// What the cel holds after [commit] lands the way a pen-up lands it: the
  /// production builder, on the surface the stroke was drawn against, so the
  /// route it takes — the promoted tiles, the live raster, or the dabs — is
  /// the one the app takes.
  BitmapSurface land(BrushStrokeCommitData commit) =>
      brushCommitResultForBrushDabSequenceOnBitmapSurface(
        surface: commit.promotedBase ?? BitmapSurface(canvasSize: canvasSize),
        sequence: BrushDabSequence(commit.sourceDabs, commit.strokeOpacity),
        layerId: const LayerId('layer'),
        frameId: const FrameId('frame'),
        prerasterizedStrokePixels: commit.strokePixels,
        prerasterizedStrokeBounds: commit.strokeBounds,
        blendMode: commit.blendMode,
        promotedBase: commit.promotedBase,
        promotedTiles: commit.promotedTiles,
      ).afterSurface;

  BrushToolState penOf(String id, BrushAntiAlias edge) =>
      BrushToolState.defaults
          .withPreset(
            defaultBrushPresets.firstWhere((preset) => preset.id.value == id),
            tool: CanvasTool.brush,
          )
          .copyWith(antiAlias: edge);

  // The pen group's round brushes — the ones 유저 names.
  for (final id in ['builtin-g-pen', 'builtin-maru-pen', 'builtin-brush-pen']) {
    testWidgets('🚨AA none: $id lands NO partly covered pixel, end to end', (
      tester,
    ) async {
      final state = penOf(id, BrushAntiAlias.none);
      expect(state.shape.tipMask, isNull, reason: 'premise: a round tip');

      final commits = await strokeWith(tester, state);

      expect(commits, hasLength(1), reason: 'premise: the stroke landed');
      final commit = commits.single;
      expect(
        commit.strokePixels != null || commit.promotedTiles != null,
        isTrue,
        reason: 'premise: the canvas hands the commit what it drew live — '
            'otherwise this measures the fallback, not the landing',
      );
      expect(
        {for (final dab in commit.sourceDabs) dab.antiAlias},
        {BrushAntiAlias.none},
        reason: 'every dab the canvas made carries the setting',
      );
      final pixels = surfaceAlpha(land(commit));
      expect(pixels.solid, greaterThan(100), reason: 'premise: it drew');
      expect(pixels.partly, 0, reason: '「진짜 안티앨리어싱 완전없었으면」');
      final raster = commit.strokePixels;
      if (raster != null) {
        expect(
          countAlpha(raster).partly,
          0,
          reason: 'the live raster — the pixels on screen while drawing',
        );
      }
    });
  }

  testWidgets('premise: the same line at AA high DOES land a soft edge — the '
      'counter can see one', (tester) async {
    final commits = await strokeWith(
      tester,
      penOf('builtin-g-pen', BrushAntiAlias.high),
    );

    expect(surfaceAlpha(land(commits.single)).partly, greaterThan(0));
  });
}
