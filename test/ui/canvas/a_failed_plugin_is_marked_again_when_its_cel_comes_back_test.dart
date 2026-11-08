@Tags(['gpu'])
library;

import 'dart:typed_data';

import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/fx_plugin_description.dart';
import 'package:anicel/src/models/fx_plugin_run.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/string_id.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/track_transform_lane_carrier.dart';
import 'package:anicel/src/services/fx_plugins/installed_fx_plugins.dart';
import 'package:anicel/src/ui/timeline/effect_lane_policy.dart'
    show effectGroupLaneId, effectLaneId, effectPropertyLanes;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/a_canvas_standing_on_a_frame.dart' show noFlutterGpu;
import '../../helpers/a_plugin_that_shifts.dart';
import '../../helpers/cel_text_tool_harness.dart';
import '../../helpers/key_chords.dart';
import '../../helpers/settle_async.dart';

/// card a-cached-failed-picture-loses-its-mark — A PLUGIN THAT FAILED IS
/// MARKED FAILED FOR AS LONG AS WHAT IT FAILED ON IS SHOWN
/// (🗣️a-failed-plugin-shows-the-cel-silently-Q1, 유저 2026-11-08: the
/// header greys with a ⚠ while the frame it stands on failed).
///
/// The record of a run is the last run's, of the effect as the project
/// holds it: a picture handed back without running the plugin again — the
/// cel it failed on brought back, or the effect made anew drawing the same
/// — leaves the header the record of another run, or none. This drives the
/// whole app: the plugin fails on a cel of paper alone.
void main() {
  const paper = [64, 192, 96, 255];
  const effectId = EffectId('shift');
  const textToolTrack = TrackId('text-tool-track');

  /// Whether [owner]'s header of [effect] marks the first frame failed,
  /// asked as the rails ask it ([effectPropertyLanes]).
  bool headerFailed(
    InstalledFxPlugins plugins,
    LayerEffect effect,
    StringId owner,
  ) => effectPropertyLanes(
    [effect],
    isExpanded: (_) => false,
    hasPlugin: plugins.has,
    pluginOutcomes: (outcomes: plugins.outcomes, owner: owner),
  ).first.pluginFailures!.failedAt(0);

  LayerEffect effectNow(WidgetTester tester) => sessionOf(
    tester,
  ).repository.requireProject().tracks.single.cuts.single.layers.first.effects
      .single;

  /// The stand-in with one number, [_DrawsOnlyOverInk.draws] by default.
  final withAnAmount = FxPluginDescription.fromJson({
    'spec': 1,
    'id': 'test.shift',
    'name': 'Shift',
    'vendor': 'Test',
    'version': '1',
    'can': ['cpu'],
    'params': [
      {
        'id': 'amount',
        'kind': 'number',
        'label': 'Amount',
        'default': 5,
        'min': 0,
        'max': 10,
      },
    ],
  });

  /// The app with [plugin] installed as the stand-in — described [as] —
  /// on the cut's row, over a cel of [paper] alone at the first frame, the
  /// brush in hand — and with [drawings] two, a cel of paper and ink at the
  /// second — and [onAnotherRow], another row in hand, the plugin's drawn
  /// from what the canvas keeps of it: where on the screen the paper is,
  /// and whether the effect the project holds failed at the first frame.
  Future<({Offset paper, bool Function() failed})> onPaper(
    WidgetTester tester,
    _DrawsOnlyOverInk plugin, {
    FxPluginDescription? as,
    int drawings = 1,
    bool onAnotherRow = false,
  }) async {
    final plugins = await installedShiftingFxPlugin(
      tester,
      as: as,
      runner: plugin,
    );
    await pumpTextToolApp(
      tester,
      project: textToolProject(
        drawings: drawings,
        emptyLayer: onAnotherRow,
        effects: [
          LayerEffect.defaults(
            id: effectId,
            kind: EffectKind.plugin,
            plugin: as ?? shiftingFxPluginDescription,
          ),
        ],
      ),
      fxPlugins: plugins,
    );
    await takeTextTool(tester);
    final c = canvasPixelInView(tester);
    final onTheScreen = onScreen(tester, c.dx, c.dy);
    final size = celOf(tester).tileSize;
    final coord = TileCoord(x: c.dx ~/ size, y: c.dy ~/ size);
    final sheet = [for (var i = 0; i < size * size; i += 1) ...paper];
    coordinatorOf(tester).restoreSurfaceSnapshot(
      textToolKey,
      celOf(tester).putTiles([
        (
          coord: coord,
          tile: BitmapTile(size: size, pixels: Uint8List.fromList(sheet)),
        ),
      ]),
    );
    if (drawings == 2) {
      coordinatorOf(tester).restoreSurfaceSnapshot(
        textToolSecondKey,
        celOf(tester, textToolSecondKey).putTiles([
          (
            coord: coord,
            tile: BitmapTile(
              size: size,
              pixels: Uint8List.fromList([0, 0, 0, 255, ...sheet.skip(4)]),
            ),
          ),
        ]),
      );
    }
    if (onAnotherRow) {
      sessionOf(tester).selectLayer(textToolEmptyLayerId);
    }
    await tester.tap(find.byKey(const ValueKey<String>('tool-brush-button')));
    await pumpFrames(tester, 12);
    bool failed() => headerFailed(plugins, effectNow(tester), textToolLayerId);

    expect(plugin.renders, greaterThan(0), reason: '⛔fixture: it runs');
    expect(failed(), isTrue, reason: '⛔fixture: no ink, it fails');
    return (paper: onTheScreen, failed: failed);
  }

  /// The app with [plugin] installed as the stand-in with an amount, on the
  /// V row's chain — run over the whole cut, a step of the frame's picture
  /// — at an amount it fails at: whether the effect the track holds failed
  /// at the first frame, once the picture is made.
  Future<bool Function()> onTheVRow(
    WidgetTester tester,
    _DrawsOnlyOverInk plugin,
  ) async {
    final plugins = await installedShiftingFxPlugin(
      tester,
      as: withAnAmount,
      runner: plugin,
    );
    final project = textToolProject();
    await pumpTextToolApp(
      tester,
      project: project.copyWith(
        tracks: [
          project.tracks.single.copyWith(
            effects: [
              LayerEffect.defaults(
                id: effectId,
                kind: EffectKind.plugin,
                plugin: withAnAmount,
              ),
            ],
          ),
        ],
      ),
      fxPlugins: plugins,
    );
    // Something on the cel: a frame of its page alone is no picture.
    final size = celOf(tester).tileSize;
    coordinatorOf(tester).restoreSurfaceSnapshot(
      textToolKey,
      celOf(tester).putTiles([
        (
          coord: TileCoord(x: 0, y: 0),
          tile: BitmapTile(
            size: size,
            pixels: Uint8List.fromList([
              for (var i = 0; i < size * size; i += 1) ...paper,
            ]),
          ),
        ),
      ]),
    );
    bool failed() => headerFailed(
      plugins,
      sessionOf(tester).repository.requireProject().tracks.single.effects
          .single,
      textToolTrack,
    );

    expect(
      await settleAsync(tester, failed),
      isTrue,
      reason: '⛔fixture: the frame is made, and the step fails',
    );
    return failed;
  }

  /// The V row's lanes as the session's lane verbs reach them.
  final vRow = trackTransformLaneCarrierId(textToolTrack);

  testWidgets('🚨a plugin that failed on a cel, drew under a stroke and once '
      'it was added, and is shown the cel again by an undo is marked failed '
      'again — and drawn again by a redo, it is not', (tester) async {
    final plugin = _DrawsOnlyOverInk(paper);
    final (paper: from, :failed) = await onPaper(tester, plugin);

    final pen = await tester.startGesture(
      from,
      kind: PointerDeviceKind.stylus,
    );
    await tester.pump();
    for (var i = 1; i <= 6; i += 1) {
      await pen.moveTo(from + Offset(6.0 * i, 4.0 * i));
      await tester.pump();
    }
    expect(failed(), isFalse,
        reason: 'mid-stroke, the ink is shown through it — not the cel as '
            'it stood, made beside it to know where it showed');
    await pen.up();
    await pumpFrames(tester, 12);
    expect(failed(), isFalse, reason: '⛔fixture: over the ink it draws');

    final drawnRuns = plugin.renders;
    final inked = celOf(tester);
    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    await pumpFrames(tester, 12);
    expect(
      identical(celOf(tester), inked),
      isFalse,
      reason: '⛔premise: the undo took the stroke back',
    );
    expect(
      failed(),
      isTrue,
      reason:
          'the cel it failed on is shown again — '
          '${plugin.renders - drawnRuns} runs since the stroke',
    );

    final undone = celOf(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await pumpFrames(tester, 12);
    expect(
      identical(celOf(tester), undone),
      isFalse,
      reason: '⛔premise: the redo put the stroke back',
    );
    expect(failed(), isFalse, reason: 'the inked cel is shown again');
  });

  for (final onAnotherRow in [false, true]) {
    testWidgets('🚨a plugin that failed is still marked failed once a key is '
        'set on it at the value it already had — the effect is made anew, '
        'and draws the same — another row in hand $onAnotherRow', (
      tester,
    ) async {
      final plugin = _DrawsOnlyOverInk(paper);
      final (paper: _, :failed) = await onPaper(
        tester,
        plugin,
        as: withAnAmount,
        onAnotherRow: onAnotherRow,
      );
      final unkeyed = effectNow(tester);

      sessionOf(tester).laneVerbs.toggleLaneKeyAt(
        textToolLayerId,
        effectLaneId(effectId, 'amount'),
        0,
        frameIsGlobal: false,
        description: 'Add key',
      );
      await pumpFrames(tester, 12);
      expect(
        identical(effectNow(tester), unkeyed),
        isFalse,
        reason: '⛔premise: the key made the effect anew',
      );
      expect(
        effectNow(tester).parameters['amount']!.track.keys,
        hasLength(1),
        reason: '⛔premise: at the value it had',
      );
      expect(failed(), isTrue, reason: 'it still fails on the paper');
    });
  }

  testWidgets('🚨a plugin that failed on a frame\'s cel, drew once the frame '
      'was joined onto an inked one, and is shown the cel again by an undo '
      'is marked failed again', (tester) async {
    final plugin = _DrawsOnlyOverInk(paper);
    final (paper: _, :failed) = await onPaper(tester, plugin, drawings: 2);
    final session = sessionOf(tester);
    FrameId shown() => session.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .single
        .layers
        .first
        .timeline[0]!
        .frameId!;

    final joined = session.frameVerbs.renameSelectedFrame('B');
    expect(joined, textToolSecondFrameId, reason: '⛔fixture: B is taken');
    session.frameVerbs.linkSelectedFrame(joined!);
    await pumpFrames(tester, 12);
    expect(shown(), textToolSecondFrameId, reason: '⛔premise: joined');
    expect(failed(), isFalse, reason: '⛔fixture: over the ink it draws');

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    await pumpFrames(tester, 12);
    expect(shown(), textToolFrameId, reason: '⛔premise: the undo split it');
    expect(failed(), isTrue, reason: 'the cel it failed on is shown again');
  });

  for (final onAnotherRow in [false, true]) {
    testWidgets('🚨a plugin that failed at a value, drew at another, and is '
        'given the first back by an undo is marked failed again — another '
        'row in hand $onAnotherRow', (tester) async {
      final plugin = _DrawsOnlyOverInk(paper);
      final (paper: _, :failed) = await onPaper(
        tester,
        plugin,
        as: withAnAmount,
        onAnotherRow: onAnotherRow,
      );

      sessionOf(tester).laneVerbs.setLaneValueAt(
        textToolLayerId,
        effectLaneId(effectId, 'amount'),
        0,
        '${_DrawsOnlyOverInk.draws}',
        frameIsGlobal: false,
        description: 'Set value',
        scaleLinked: false,
      );
      await pumpFrames(tester, 12);
      expect(failed(), isFalse, reason: '⛔fixture: at that value it draws');

      await pressCtrl(tester, LogicalKeyboardKey.keyZ);
      await pumpFrames(tester, 12);
      expect(
        effectNow(tester).parameters['amount']!.value,
        5,
        reason: '⛔premise: the undo gave the value back',
      );
      expect(failed(), isTrue, reason: 'the value it failed at is back');
    });
  }

  testWidgets('🚨a plugin on the V row that failed is marked failed again '
      'once it is switched off and on — the picture of the chain as it was '
      'comes back without a run', (tester) async {
    final failed = await onTheVRow(tester, _DrawsOnlyOverInk(null));
    final laneVerbs = sessionOf(tester).laneVerbs;

    laneVerbs.toggleLaneGroupEnabled(
      vRow,
      effectGroupLaneId(effectId),
      description: 'Switch fx',
    );
    await lendBothClocks(tester, rounds: 20);
    expect(failed(), isFalse, reason: 'switched off, it does not run');

    laneVerbs.toggleLaneGroupEnabled(
      vRow,
      effectGroupLaneId(effectId),
      description: 'Switch fx',
    );
    await lendBothClocks(tester, rounds: 20);
    expect(failed(), isTrue, reason: 'switched on, it fails as before');
  }, skip: noFlutterGpu != null);

  testWidgets('🚨a plugin on the V row that failed at a value, drew at '
      'another, and is given the first back by an undo is marked failed '
      'again', (tester) async {
    final failed = await onTheVRow(tester, _DrawsOnlyOverInk(null));

    sessionOf(tester).laneVerbs.setLaneValueAt(
      vRow,
      effectLaneId(effectId, 'amount'),
      0,
      '${_DrawsOnlyOverInk.draws}',
      frameIsGlobal: true,
      description: 'Set value',
      scaleLinked: false,
    );
    expect(
      await settleAsync(tester, () => !failed()),
      isTrue,
      reason: '⛔fixture: at that value it draws',
    );

    await pressCtrl(tester, LogicalKeyboardKey.keyZ);
    await lendBothClocks(tester, rounds: 20);
    expect(failed(), isTrue, reason: 'the value it failed at is back');
  }, skip: noFlutterGpu != null);
}

/// Fails at a first value under [draws] on a picture of [paper] alone —
/// any picture, where it is told no paper; draws it as it is over anything
/// else, or at [draws] and over.
final class _DrawsOnlyOverInk implements FxPluginRunner {
  _DrawsOnlyOverInk(this.paper);

  /// The first value it draws at whatever it is given.
  static const draws = 8;

  final List<int>? paper;
  int renders = 0;

  @override
  int? reach(Float64List values, FxPluginMoment moment) => 0;

  @override
  Uint8List? render({
    required FxPluginPicture input,
    required Float64List values,
    required List<FxPluginPicture> layers,
    required FxPluginMoment moment,
  }) {
    renders += 1;
    final pixels = input.pixels;
    var drawsIt = values.isNotEmpty && values[0] >= draws;
    final paper = this.paper;
    for (
      var i = 0;
      paper != null && i < pixels.length && !drawsIt;
      i += 4
    ) {
      drawsIt =
          pixels[i + 3] != 0 &&
          (pixels[i] != paper[0] ||
              pixels[i + 1] != paper[1] ||
              pixels[i + 2] != paper[2]);
    }
    return drawsIt ? Uint8List.fromList(pixels) : null;
  }

  @override
  void close() {}
}
