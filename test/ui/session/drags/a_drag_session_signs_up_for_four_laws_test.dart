import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/audio_clip.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/ui/session/drags/audio_clip_offset_drag.dart';
import 'package:anicel/src/ui/session/drags/movie_end_drag.dart';
import 'package:anicel/src/ui/timeline/timeline_drag_preview.dart';

/// 🚨THE DRAG SESSION'S FOUR LAWS, ON THE TWO FAMILIES NOTHING NAMED.
///
/// A session is begun by CONSTRUCTING it, driven by `update`, and closed by
/// exactly one of `commit` or `cancel`. What each subtype signs up for:
///
/// * a begin that must refuse is a factory returning null — no object, no
///   drag;
/// * `commit` lands AT MOST ONE undo step, built from the object's OWN
///   after-state, never read back out of the preview channel (the
///   invariant movie-end violated until 2026-08-16);
/// * `cancel` drops the preview and touches no history;
/// * both closers leave the preview channel null.
void main() {
  group('MovieEndDrag — the line edits the movie length, never the cuts', () {
    ({
      MovieEndDrag drag,
      ValueNotifier<TimelineDragPreview?> preview,
      List<int> committed,
    })
    open({int before = 10}) {
      final preview = ValueNotifier<TimelineDragPreview?>(null);
      addTearDown(preview.dispose);
      final committed = <int>[];
      return (
        drag: MovieEndDrag(
          beforeTrailing: before,
          preview: preview,
          commitTrailing: committed.add,
        ),
        preview: preview,
        committed: committed,
      );
    }

    test('a drag out previews the new trailing gap', () {
      final session = open();

      session.drag.update(5);

      final preview = session.preview.value;
      expect(preview, isA<MovieEndDragPreview>());
      expect((preview! as MovieEndDragPreview).trailingFrames, 15);
      expect(session.committed, isEmpty, reason: 'nothing lands mid-drag');
    });

    test('⛔the movie end never dips below the content end — the trailing '
        'gap clamps at 0', () {
      final session = open();

      session.drag.update(-999);
      session.drag.commit();

      expect(session.committed, [0]);
    });

    test('commit lands ONE step, from the drag\'s own after-state', () {
      final session = open();

      session.drag.update(5);
      session.drag.commit();

      expect(session.committed, [15]);
      expect(session.preview.value, isNull, reason: 'the closer clears it');
    });

    test('🚨a drag that ends back where it STARTED commits nothing — "no '
        'change" is not an undo step', () {
      final session = open();

      session.drag.update(5);
      session.drag.update(0);
      session.drag.commit();

      expect(session.committed, isEmpty);
      expect(session.preview.value, isNull);
    });

    test('cancel drops the preview and touches no history', () {
      final session = open();

      session.drag.update(5);
      session.drag.cancel();

      expect(session.committed, isEmpty);
      expect(session.preview.value, isNull);
    });
  });

  group('AudioClipOffsetDrag — the one legitimate repo-direct previewer', () {
    Layer seRow(List<AudioClip> clips) => Layer(
      id: const LayerId('se'),
      name: 'SE',
      frames: const [],
      timeline: const {},
      kind: LayerKind.se,
      audioClips: clips,
    );

    AudioClip clip(int offset) => AudioClip(
      filePath: '/take.wav',
      frameId: const FrameId('f1'),
      offsetFrames: offset,
    );

    /// A stand-in repository: the drag writes into it and re-reads it every
    /// step, which is the whole point of this family.
    ({
      AudioClipOffsetDrag? drag,
      List<List<AudioClip>> previews,
      List<List<AudioClip>> commits,
      Layer? Function() row,
    })
    open({Layer? row, int clipIndex = 0}) {
      var current = row ?? seRow([clip(4)]);
      final previews = <List<AudioClip>>[];
      final commits = <List<AudioClip>>[];
      Layer? lookup(LayerId id) =>
          id == const LayerId('se') && current.kind != LayerKind.image
          ? current
          : (id == const LayerId('se') ? current : null);
      return (
        drag: AudioClipOffsetDrag.begin(
          layerId: const LayerId('se'),
          clipIndex: clipIndex,
          layerById: lookup,
          previewClips: ({required layerId, required audioClips}) {
            previews.add(audioClips);
            current = current.copyWith(audioClips: audioClips);
          },
          commitClips: ({required layerId, required audioClips}) =>
              commits.add(audioClips),
          notify: () {},
        ),
        previews: previews,
        commits: commits,
        row: () => current,
      );
    }

    test('⛔a begin on a row that is not an SE lane returns NULL — no '
        'object, no drag', () {
      final session = open(
        row: Layer(
          id: const LayerId('se'),
          name: 'not SE',
          frames: const [],
          timeline: const {},
          kind: LayerKind.image,
          audioClips: [clip(4)],
        ),
      );

      expect(session.drag, isNull);
    });

    test('⛔a begin on an index that names no clip returns null', () {
      expect(open(clipIndex: 9).drag, isNull);
      expect(open(clipIndex: -1).drag, isNull);
    });

    test('🚨the drag WRITES the repository per move — every waveform view '
        'repaints from the model in real time', () {
      final session = open();

      session.drag!.update(12);

      expect(session.row()!.audioClips.single.offsetFrames, 12);
      expect(session.commits, isEmpty, reason: 'no history mid-drag');
    });

    test('its input is the ABSOLUTE offset, clamped at zero', () {
      final session = open();

      session.drag!.update(-5);

      expect(session.row()!.audioClips.single.offsetFrames, 0);
    });

    test('a move to where it already is writes nothing', () {
      final session = open();

      session.drag!.update(4);

      expect(session.previews, isEmpty);
    });

    test('🚨commit REVERTS silently to the before-snapshot, then applies '
        'the final list as one ordinary command — so the command\'s own '
        'before-snapshot stays correct', () {
      final session = open();

      session.drag!.update(12);
      session.drag!.commit();

      expect(
        session.previews.last.single.offsetFrames,
        4,
        reason: 'the silent revert is the LAST direct write',
      );
      expect(session.commits.single.single.offsetFrames, 12);
    });

    test('a drag that ends where it started commits nothing', () {
      final session = open();

      session.drag!.update(12);
      session.drag!.update(4);
      session.drag!.commit();

      expect(session.commits, isEmpty);
    });

    test('cancel puts the clips back and touches no history', () {
      final session = open();

      session.drag!.update(12);
      session.drag!.cancel();

      expect(session.row()!.audioClips.single.offsetFrames, 4);
      expect(session.commits, isEmpty);
    });

    test('cancel on an untouched drag writes nothing at all', () {
      final session = open();

      session.drag!.cancel();

      expect(session.previews, isEmpty);
    });
  });
}
