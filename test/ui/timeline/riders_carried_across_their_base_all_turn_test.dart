import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/timeline_row_address.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';
import 'package:anicel/src/ui/timeline/layer_row_drag.dart';

/// 🗣️F-322 (유저 2026-10-09): 「선택범위 드래그로 어태치 조정」.
///
/// A selection of riders carried across their base's picture all take the
/// other side — 「crossing the base's picture turns an above row into a
/// below one」, of every row that crosses. ↩️Only the row the pointer held
/// turned: measured 2026-10-10, two riders carried under their base left
/// the second one `above`, riding a side it no longer sat on.
///
/// The timeline's rail, by its own verbs: a base with two riders over it
/// (`over` nearest, `high` past it) and one under it.
void main() {
  Layer row(
    String id, {
    String? ridesOn,
    AttachedPlacement placement = AttachedPlacement.above,
  }) => Layer(
    id: LayerId(id),
    name: id,
    attachedToLayerId: ridesOn == null ? null : LayerId(ridesOn),
    attachedPlacement: placement,
    attachedMode: AttachedMode.free,
    frames: const [],
  );

  EditorSessionManager sessionOf() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('riders'),
        name: 'Riders',
        createdAt: DateTime.utc(2026, 10, 10),
        tracks: [
          Track(
            id: const TrackId('t'),
            name: 'V1',
            cuts: [
              Cut(
                id: const CutId('c'),
                name: 'c',
                duration: 8,
                canvasSize: const CanvasSize(width: 32, height: 32),
                layers: [
                  row('cel'),
                  row(
                    'under',
                    ridesOn: 'base',
                    placement: AttachedPlacement.below,
                  ),
                  row('base'),
                  row('over', ridesOn: 'base'),
                  row('high', ridesOn: 'base'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  /// [moving] — with [carried] selected — let go under `under`, as the
  /// rail's drag hands it: the rows top first.
  void carryUnderUnder(
    EditorSessionManager session, {
    required String moving,
    required List<String> carried,
  }) {
    session.rowSelection.value = [
      for (final id in carried) LayerRowAddress(LayerId(id)),
    ];
    final shown = session.layers.reversed.toList();
    session.layerRowDragVerbs.beginLayerRowDrag(
      LayerRowSubject(LayerId(moving)),
    );
    session.layerRowDragVerbs.updateLayerRowDrag(
      shown,
      shown.indexWhere((layer) => layer.id == const LayerId('under')) + 1,
    );
    expect(
      session.layerRowDragVerbs.inFlight.value?.legal,
      isTrue,
      reason: '⛔전제: a landing',
    );
    session.layerRowDragVerbs.endLayerRowDrag();
  }

  List<String> stack(EditorSessionManager session) => [
    for (final layer in session.repository
        .requireProject()
        .tracks
        .single
        .cuts
        .single
        .layers)
      layer.attachedToLayerId == null
          ? layer.id.value
          : '${layer.id.value}/${layer.attachedPlacement.name}',
  ];

  test('🚨two riders carried under their base both ride under it', () {
    final session = sessionOf();
    carryUnderUnder(session, moving: 'high', carried: ['high', 'over']);

    expect(stack(session), [
      'cel',
      'over/below',
      'high/below',
      'under/below',
      'base',
    ]);
  });

  test('…and one carried alone turns alone (the rule as it was)', () {
    final session = sessionOf();
    carryUnderUnder(session, moving: 'high', carried: const []);

    expect(stack(session), [
      'cel',
      'high/below',
      'under/below',
      'base',
      'over/above',
    ]);
  });
}
