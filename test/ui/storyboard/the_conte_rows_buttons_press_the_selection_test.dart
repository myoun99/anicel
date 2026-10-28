import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/conte_group.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/layer_process.dart';
import 'package:anicel/src/models/pill_subject.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte_row.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/models/working_panel.dart';
import 'package:anicel/src/services/project_lookup.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/widgets/field_slider.dart';

import '../../helpers/named_finders.dart';
import '../../helpers/storyboard_host.dart';

/// THE CONTE ROWS' BUTTONS PRESS THE SELECTION (row-buttons-act-on-the-
/// selection, 유저 2026-09-25: 「선택범위 내부 레이어 조절하면 선택범위
/// 레이어 모두 적용」), and the shared verbs on a selection of them act on
/// their rows — the 10-10 audit of the conte panel's overhaul.
///
/// A storyboard conte row is ONE row over every cut, so the selection holds
/// it by its address; its buttons and the selection's verbs land on its row
/// in hand: the cut the session stands in's. ↩️They pressed the layer the
/// label wore — the first cut's — and read the selection as cut layers, so
/// a press on a selected conte row changed that row alone and Delete took
/// the block under the playhead instead of the rows.
///
/// Cuts a [0, 12) and b [12, 24) hold the same group: the conte, Over (+1)
/// and High (+2). The session stands in cut b, whose rows do not speak for
/// the seats — the first cut's do.
const _trackId = TrackId('t1');

LayerRowAddress _seat(int seat) =>
    LayerRowAddress(trackConteRowId(_trackId, seat: seat));

Layer _drawn(String id, {LayerKind kind = LayerKind.storyboard, String? on}) =>
    Layer(
      id: LayerId(id),
      name: id,
      kind: kind,
      attachedToLayerId: on == null ? null : LayerId(on),
      attachedPlacement: AttachedPlacement.above,
      attachedMode: AttachedMode.free,
      frames: const [],
    );

Cut _cut(String id) => Cut(
  id: CutId(id),
  name: id,
  duration: 12,
  canvasSize: const CanvasSize(width: 640, height: 360),
  camera: CutCamera.empty(),
  layers: [
    _drawn('$id-cel', kind: LayerKind.animation),
    _drawn('$id-conte'),
    _drawn('$id-over', on: '$id-conte'),
    _drawn('$id-high', on: '$id-conte'),
    Layer(
      id: LayerId('$id-cam'),
      name: 'Camera',
      kind: LayerKind.camera,
      frames: const [],
    ),
  ],
);

Layer _row(EditorSessionManager s, String id) =>
    requireLayerAnywhere(s.repository.requireProject(), LayerId(id));

const _selected = ['a-over', 'b-over', 'a-high', 'b-high'];

/// The storyboard tab standing in cut b, with the conte rows at seats +1
/// and +2 selected.
Future<EditorSessionManager> _storyboard(WidgetTester tester) async {
  final s = await pumpStoryboardHost(
    tester,
    Project(
      id: const ProjectId('conte-presses'),
      name: 'Conte presses',
      createdAt: DateTime.utc(2026, 10, 10),
      tracks: [
        Track(id: _trackId, name: 'V1', cuts: [_cut('a'), _cut('b')]),
      ],
    ),
    surface: const Size(1600, 1000),
    pixelsPerFrame: 12,
  );
  s.standOnRow(_seat(1), panel: WorkingPanel.storyboard, globalFrameIndex: 15);
  await tester.pumpAndSettle();
  expect(s.activeCutId, const CutId('b'), reason: '⛔전제: standing in b');
  s.rowSelection.value = [_seat(1), _seat(2)];
  await tester.pumpAndSettle();
  return s;
}

Finder _button(String button, String layer) =>
    find.named('storyboard-layer-$button-$layer').first;

void main() {
  testWidgets('🚨the label wears the row in hand — the cut stood in\'s row at '
      'its seat, not the first cut\'s', (tester) async {
    await _storyboard(tester);
    expect(
      find.named('storyboard-layer-visibility-b-over'),
      findsWidgets,
    );
    expect(
      find.named('storyboard-layer-visibility-a-over'),
      findsNothing,
    );
  });

  testWidgets('🚨its eye, pressed on a selected conte row, presses every '
      'selected row — in every cut', (tester) async {
    final s = await _storyboard(tester);

    await tester.tap(_button('visibility', 'b-over'));
    await tester.pumpAndSettle();

    expect({for (final id in _selected) _row(s, id).isVisible}, {false});
    expect(
      _row(s, 'b-conte').isVisible,
      isTrue,
      reason: 'outside the selection',
    );
  });

  testWidgets('…and outside the selection, that row alone', (tester) async {
    final s = await _storyboard(tester);
    s.rowSelection.value = [_seat(2)];
    await tester.pumpAndSettle();

    await tester.tap(_button('visibility', 'b-over'));
    await tester.pumpAndSettle();

    expect(
      [
        for (final id in ['a-over', 'b-over', 'a-high', 'b-high'])
          _row(s, id).isVisible,
      ],
      [false, false, true, true],
    );
  });

  testWidgets('its colour label, picked on a selected conte row, labels '
      'every selected row', (tester) async {
    final s = await _storyboard(tester);

    await tester.tap(_button('mark', 'b-over'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('layer-mark-option-paper')),
    );
    await tester.pumpAndSettle();

    expect({
      for (final id in _selected) _row(s, id).mark.process,
    }, {LayerProcess.paper});
  });

  testWidgets('its blend, picked on a selected conte row, blends every '
      'selected row', (tester) async {
    final s = await _storyboard(tester);

    await tester.tap(_button('blend', 'b-over'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        const ValueKey<String>('storyboard-layer-blend-option-multiply'),
      ),
    );
    await tester.pumpAndSettle();

    expect({
      for (final id in _selected) _row(s, id).blendMode,
    }, {LayerBlendMode.multiply});
  });

  testWidgets('its opacity slider, dragged on a selected conte row, '
      'previews the rows in hand — the canvas\'s cut — and moves every '
      'selected row', (tester) async {
    final s = await _storyboard(tester);
    final slider = tester.widget<FieldSlider>(_button('opacity', 'b-over'));

    slider.onChanged!(0.3);
    expect(s.opacityVerbs.dragPreview.value?.layerIds, {
      const LayerId('b-over'),
      const LayerId('b-high'),
    });
    slider.onChangeEnd!(0.3);
    await tester.pumpAndSettle();

    expect({for (final id in _selected) _row(s, id).opacity}, {0.3});
  });

  testWidgets('🚨Delete with conte rows selected deletes those rows — their '
      'seats, in every cut — not the block under the playhead', (
    tester,
  ) async {
    final s = await _storyboard(tester);
    expect(
      s.deleteSubjectFor(cutsAreThisPanels: true),
      PillSubject.layers,
    );

    s.deleteSelectionSubject();
    await tester.pumpAndSettle();

    expect(
      [
        for (final cut in s.repository.requireProject().tracks.single.cuts)
          [for (final entry in conteGroupOf(cut)) entry.row.id.value],
      ],
      [
        ['a-conte'],
        ['b-conte'],
      ],
    );
  });

  testWidgets('a copy with the conte row selected takes its row', (
    tester,
  ) async {
    final s = await _storyboard(tester);
    s.rowSelection.value = [_seat(0)];
    await tester.pumpAndSettle();

    expect(s.layerClipboard.canCopySelectedRows, isTrue);
  });
}
