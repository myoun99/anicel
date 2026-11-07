import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_camera.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_blend_mode.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/project.dart';
import 'package:anicel/src/models/project_id.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/ui/editor_session_manager.dart';

/// 🔬Card conte-one-eye-repaints-every-track (11-08): A ROW'S SWITCH LEAVES
/// EVERY OTHER TRACK AS IT WAS — the very objects, so every row kept while
/// its cuts and its track are the same objects (the conte's, the
/// timeline's) stays as it was — and an S row's leaves its own track's cuts
/// as they were too.
///
/// ↩️One S row's eye made every track and every cut of the project anew
/// (`project_tree_editor.dart`), and the conte's V and conte rows of every
/// track built again. Every switch a row has, on every kind of row a track
/// holds: what goes through the one walk goes through it alike.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Track track(int t) => Track(
    id: TrackId('t$t'),
    name: 'T$t',
    cuts: [
      for (var c = 0; c < 2; c += 1)
        Cut(
          id: CutId('t$t-c$c'),
          name: 't$t c$c',
          duration: 24,
          canvasSize: const CanvasSize(width: 1280, height: 720),
          camera: CutCamera.empty(),
          layers: [
            Layer(
              id: LayerId('t$t-c$c-conte'),
              name: 'conte',
              kind: LayerKind.storyboard,
              frames: const [],
            ),
            Layer(id: LayerId('t$t-c$c-a'), name: 'A', frames: const []),
          ],
        ),
    ],
    seLayers: [
      for (final s in ['S1', 'S2'])
        Layer(
          id: LayerId('t$t-$s'),
          name: 't$t $s',
          kind: LayerKind.se,
          frames: const [],
        ),
    ],
  );

  EditorSessionManager open() {
    final session = EditorSessionManager(
      initialProject: Project(
        id: const ProjectId('one-row-switch'),
        name: 'One row switch',
        createdAt: DateTime.utc(2026, 11, 8),
        tracks: [for (var t = 0; t < 3; t += 1) track(t)],
      ),
    );
    addTearDown(session.dispose);
    return session;
  }

  final switches = <String, void Function(EditorSessionManager, LayerId)>{
    'eye': (s, id) => s.layerSwitches.toggleLayerVisibility(id),
    'lanes': (s, id) => s.layerSwitches.toggleLayerLanes(id),
    'timesheet': (s, id) => s.layerSwitches.toggleLayerTimesheet(id),
    'name': (s, id) => s.layerVerbs.renameLayer(id, 'Renamed'),
  };
  final soundSwitches = {
    ...switches,
    'mute': (EditorSessionManager s, LayerId id) =>
        s.layerSwitches.toggleLayerMuted(id),
  };
  final pictureSwitches = {
    ...switches,
    'clip': (EditorSessionManager s, LayerId id) =>
        s.layerSwitches.toggleLayerClip(id),
    'blend': (EditorSessionManager s, LayerId id) =>
        s.layerSwitches.setLayerBlendMode(id, LayerBlendMode.multiply),
    'opacity': (EditorSessionManager s, LayerId id) =>
        s.opacityVerbs.setLayerOpacity(layerId: id, opacity: 0.5),
  };

  /// Whether [after] holds [before] as it was: the very track, or — built
  /// again round a change of its own rows, which wraps its lists anew — the
  /// very cuts.
  void expectAsItWas(Track after, Track before, {required String reason}) {
    if (identical(after, before)) {
      return;
    }
    expect(after.cuts, hasLength(before.cuts.length), reason: reason);
    for (final (index, cut) in after.cuts.indexed) {
      expect(cut, same(before.cuts[index]), reason: '$reason — cut $index');
    }
  }

  /// [press] on track t0: every other track as it was, and of its own
  /// track what [ownTrack] says stays.
  void pinPress(
    String label,
    void Function(EditorSessionManager) press, {
    required _OwnTrack ownTrack,
  }) {
    test(label, () {
      final session = open();
      final before = session.repository.requireProject();
      press(session);
      final after = session.repository.requireProject();
      expect(
        identical(after, before),
        isFalse,
        reason: '⛔premise: the press changed the project',
      );
      for (var t = 1; t < before.tracks.length; t += 1) {
        expect(
          after.tracks[t],
          same(before.tracks[t]),
          reason: 'track t$t is left as it was',
        );
      }
      switch (ownTrack) {
        case _OwnTrack.everyCut:
          expectAsItWas(
            after.tracks.first,
            before.tracks.first,
            reason: 'an S row\'s switch leaves its track\'s cuts as they '
                'were',
          );
        case _OwnTrack.theOtherCut:
          expect(
            after.tracks.first.cuts.last,
            same(before.tracks.first.cuts.last),
            reason: 'the other cut of its track is left as it was',
          );
        case _OwnTrack.none:
          break;
      }
    });
  }

  /// [each] switch pressed on [row] ([pinPress]).
  void pin(
    String row,
    LayerId id,
    Map<String, void Function(EditorSessionManager, LayerId)> each, {
    required _OwnTrack ownTrack,
  }) {
    for (final MapEntry(key: name, value: press) in each.entries) {
      pinPress(
        '$row · $name',
        (session) => press(session, id),
        ownTrack: ownTrack,
      );
    }
  }

  pin(
    'an S row',
    const LayerId('t0-S2'),
    soundSwitches,
    ownTrack: _OwnTrack.everyCut,
  );
  pin(
    'a drawing row',
    const LayerId('t0-c0-a'),
    pictureSwitches,
    ownTrack: _OwnTrack.theOtherCut,
  );
  // A track's conte rows wear one eye (I-73): the other cut's takes it too.
  pin(
    'a conte row',
    const LayerId('t0-c0-conte'),
    {'eye': switches['eye']!},
    ownTrack: _OwnTrack.none,
  );
  // A cut's own name goes through the cut walk (`updateCutAnywhere`) alike.
  // 🚨WHAT READS ANOTHER CUT KEYS ON WHAT IT READS: 🔬a rename on another
  // track left the timesheet's printed cut the same object, and its header
  // kept the 겸용 cut's old name (master red, 11-08) — pinned where it
  // prints (the_format_windows_set_the_fixed_text_test).
  pinPress(
    'a cut · name',
    (session) =>
        session.cutVerbs.renameCuts({const CutId('t0-c0'): 'Renamed'}),
    ownTrack: _OwnTrack.theOtherCut,
  );
}

/// What of the switched row's own track stays as it was.
enum _OwnTrack { everyCut, theOtherCut, none }
