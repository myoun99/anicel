import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/timeline/property_lane_model.dart';

/// F-30 — **an attach row is indented with its base.**
///
/// 유저 2026-08-24: 「폴더 안 어태치 레이어의 들여쓰기가 어긋난다 — 아래쪽
/// 어태치 레이어의 화살표·버튼 위치가 폴더 바깥 레이어처럼 배치된다. 폴더
/// 화살표는 어태치 것과 생김새·색이 달라 같은 것을 재사용할 것」.
///
/// Indent is a DISPLAY fact — "what does this row hang off" — and an attach
/// row hangs off its base. Its own `folderId` answers a different question
/// (is it a MEMBER of the folder), and the two disagree the moment a row is
/// mounted by drag rather than added from the menu.
void main() {
  const folderId = LayerId('indent-folder');
  const baseId = LayerId('indent-base');
  const attachId = LayerId('indent-attach');
  const outsiderId = LayerId('indent-outsider');

  /// A folder, a base INSIDE it, an attach row on that base whose own
  /// `folderId` is null (what a drag-mounted row looks like), and a plain
  /// row outside everything.
  List<Layer> stack() => [
    Layer(
      id: folderId,
      name: 'Folder',
      kind: LayerKind.folder,
      frames: const [],
      timeline: const {},
    ),
    Layer(
      id: baseId,
      name: 'Base',
      frames: const [],
      timeline: const {},
      folderId: folderId,
    ),
    Layer(
      id: attachId,
      name: 'Attach',
      frames: const [],
      timeline: const {},
      attachedToLayerId: baseId,
      attachedPlacement: AttachedPlacement.below,
      attachedMode: AttachedMode.free,
    ),
    Layer(id: outsiderId, name: 'Outside', frames: const [], timeline: const {}),
  ];

  int depthOf(List<TimelineDisplayRow> rows, LayerId id) =>
      rows.firstWhere((row) => row.layer.id == id && !row.isLane).depth;

  test('the attach row starts on the same column as its base', () {
    final rows = buildTimelineDisplayRows(
      layers: stack(),
      expandedLayerIds: const {},
      lanesForLayer: (_) => const [],
    );

    expect(
      depthOf(rows, baseId),
      1,
      reason: 'fixture premise: the base really is inside the folder',
    );
    expect(
      depthOf(rows, outsiderId),
      0,
      reason: 'fixture premise: and a row outside it really is at 0',
    );
    expect(
      depthOf(rows, attachId),
      depthOf(rows, baseId),
      reason: 'it hangs off the base, so it indents with the base — its own '
          'folderId is a different question and says null here',
    );
  });

  test('an attach row outside any folder still sits at the left', () {
    final layers = [
      Layer(id: baseId, name: 'Base', frames: const [], timeline: const {}),
      Layer(
        id: attachId,
        name: 'Attach',
        frames: const [],
        timeline: const {},
        attachedToLayerId: baseId,
        attachedPlacement: AttachedPlacement.below,
        attachedMode: AttachedMode.free,
      ),
    ];
    final rows = buildTimelineDisplayRows(
      layers: layers,
      expandedLayerIds: const {},
      lanesForLayer: (_) => const [],
    );

    expect(depthOf(rows, attachId), 0);
  });

  // 🪦「the folder arrow and the attach arrow are ONE drawing」 lived here.
  //
  // It pinned the two glyphs to one size and one colour — 유저: 「생김새·색이
  // 달라 같은 것을 재사용할 것」, after 14px vs 16px and 55% alpha vs full
  // strength. The folder arrow is gone (2026-08-29: nesting moved into the
  // NAME column and the leading run lost its ↳ cell), so there is no second
  // arrow left to match. One drawing, by having one.
}
