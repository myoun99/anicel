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
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// #23 — 유저: 「주인 레이어의 이름 바꾸면 어태치레이어도 적용시키고싶음.
/// 다만 어태치레이어도 개별설정 가능하니까, 어태치레이어들은 **이름이
/// 기본값이면 바뀌도록**」
///
/// "Default" is DERIVED (`base±N`), never stored — so the rename is the
/// only moment the question can be answered, against the OLD base name.
/// A hand-touched name never matches and is never touched.
void main() {
  Layer layer(String id, String name, {LayerId? attachedTo}) => Layer(
    id: LayerId(id),
    name: name,
    frames: const [],
    timeline: const {},
    attachedToLayerId: attachedTo,
    attachedMode: attachedTo == null ? AttachedMode.synced : AttachedMode.free,
    attachedPlacement: AttachedPlacement.above,
  );

  EditorSessionManager session() => EditorSessionManager(
    initialProject: Project(
      id: const ProjectId('project'),
      name: 'P',
      createdAt: DateTime.utc(2026),
      tracks: [
        Track(
          id: const TrackId('track'),
          name: 'T',
          cuts: [
            Cut(
              id: const CutId('cut'),
              name: '1',
              duration: 4,
              canvasSize: const CanvasSize(width: 8, height: 8),
              layers: [
                layer('base', 'A'),
                layer('up', 'A+1', attachedTo: const LayerId('base')),
                layer('down', 'A-2', attachedTo: const LayerId('base')),
                // H5 (유저 2026-08-21): a rider the USER named, keeping the
                // owner's name in front — 「주인 B, 어태치 B_F 이어도 앞부분
                // B라는게 같으니 바꾸면 바뀌도록」.
                layer('prefixed', 'A_F', attachedTo: const LayerId('base')),
                layer('custom', '셀북따기', attachedTo: const LayerId('base')),
                // A LOOKALIKE on a different base: 'A+1' by name but not
                // A's attach — the pattern must only reach A's own rows.
                layer('other-base', 'X'),
                layer(
                  'other-attach',
                  'A+1',
                  attachedTo: const LayerId('other-base'),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  );

  String nameOf(EditorSessionManager s, String id) => s.repository
      .requireProject()
      .tracks
      .single
      .cuts
      .single
      .layers
      .firstWhere((layer) => layer.id == LayerId(id))
      .name;

  test('an attach whose name starts with the owner\'s follows the rename, '
      'others and strangers stay, and one undo restores everything', () {
    final s = session();
    addTearDown(s.dispose);

    s.renameLayer(const LayerId('base'), 'B');

    expect(nameOf(s, 'base'), 'B');
    expect(nameOf(s, 'up'), 'B+1', reason: 'the suffix rides verbatim');
    expect(
      nameOf(s, 'down'),
      'B-2',
      reason: 'non-contiguous numbers survive — re-numbering would invent '
          'state',
    );
    expect(
      nameOf(s, 'prefixed'),
      'B_F',
      reason: 'H5: the PREFIX is the rule, not the generated ±N shape — a '
          'rider the user named themselves keeps following its owner',
    );
    expect(
      nameOf(s, 'custom'),
      '셀북따기',
      reason: 'a name that does not start with the owner\'s stays put — the '
          'rule widened, it did not become "rename everything attached"',
    );
    expect(
      nameOf(s, 'other-attach'),
      'A+1',
      reason: 'a lookalike on another base is not this base\'s default',
    );

    s.undo();
    expect(nameOf(s, 'base'), 'A');
    expect(nameOf(s, 'up'), 'A+1');
    expect(nameOf(s, 'down'), 'A-2');
    expect(nameOf(s, 'prefixed'), 'A_F');
    expect(
      nameOf(s, 'custom'),
      '셀북따기',
      reason: 'ONE undo step covers the base and every follower',
    );
  });
}
