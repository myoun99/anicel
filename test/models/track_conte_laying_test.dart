import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/attached_layer_resolve.dart'
    show attachedGroupSlice;
import 'package:anicel/src/models/attached_mode.dart';
import 'package:anicel/src/models/attached_placement.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cut.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer.dart';
import 'package:anicel/src/models/layer_effect.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/timeline_exposure.dart';
import 'package:anicel/src/models/track.dart';
import 'package:anicel/src/models/track_conte.dart';
import 'package:anicel/src/models/track_conte_laying.dart';
import 'package:anicel/src/models/track_id.dart';

/// 🗣️F-343 (유저 2026-10-14): 「콘티행을 확실하게 글로벌행으로 해버리는거.
/// 즉 어느정도 컷마다 프레임 독립? 하면서 구조 자체는 글로벌기준으로 해서
/// 컷마다 구조 동일하게 되는거」 — and of how (10-12): 「비슷한 버튼의
/// 로직을 바꾸란게아니라 구조적으로 결과적으로 그렇게 되도록」.
///
/// A track keeps its conte's STRUCTURE, and every write lays every cut's
/// conte from it ([trackWithItsConteLaid]) after taking what the write did
/// to one cut's. Cuts a and b each carry a conte; `X` rides over it.
void main() {
  Layer conte(String cut, {List<LayerEffect> effects = const []}) => Layer(
    id: LayerId('$cut-conte'),
    name: 'Conte',
    kind: LayerKind.storyboard,
    effects: effects,
    frames: [Frame(id: FrameId('$cut-panel'), duration: 12, strokes: const [])],
    timeline: {
      0: TimelineExposure.drawing(FrameId('$cut-panel'), length: 12),
    },
  );

  Layer rider(
    String cut,
    String suffix, {
    required String name,
    AttachedPlacement placement = AttachedPlacement.above,
    LayerId? folderId,
  }) => Layer(
    id: LayerId('$cut-$suffix'),
    name: name,
    kind: LayerKind.storyboard,
    attachedToLayerId: LayerId('$cut-conte'),
    attachedPlacement: placement,
    attachedMode: AttachedMode.free,
    folderId: folderId,
    frames: const [],
    timeline: const {},
  );

  Layer folder(String cut, String suffix, {required String name}) => Layer(
    id: LayerId('$cut-$suffix'),
    name: name,
    kind: LayerKind.folder,
    frames: const [],
    timeline: const {},
  );

  Layer cel(String cut) =>
      Layer(id: LayerId('$cut-cel'), name: 'A', frames: const []);

  Cut cutOf(String id, List<Layer> layers) => Cut(
    id: CutId(id),
    name: id,
    duration: 12,
    canvasSize: const CanvasSize(width: 640, height: 360),
    layers: layers,
  );

  Track trackOf(List<Cut> cuts) =>
      Track(id: const TrackId('t1'), name: 'V1', cuts: cuts);

  /// [track] as a write of it lays it, the last write having left [settled].
  Track write(Track track, {Track? settled}) => trackWithItsConteLaid(
    track,
    settledCut: (cutId) {
      for (final cut in settled?.cuts ?? const <Cut>[]) {
        if (cut.id == cutId) {
          return cut;
        }
      }
      return null;
    },
  );

  Cut cutIn(Track track, String id) =>
      track.cuts.firstWhere((cut) => cut.id == CutId(id));

  /// [cut]'s conte group bottom first, by name — a row the structure gave
  /// the cut marked `*`.
  List<String> conteOf(Track track, String cut) {
    final layers = cutIn(track, cut).layers;
    return [
      for (final row in attachedGroupSlice(LayerId('$cut-conte'), layers))
        '${isConteFill(row) ? '*' : ''}${row.name}',
    ];
  }

  Layer rowOf(Track track, String cut, String name) =>
      cutIn(track, cut).layers.firstWhere((layer) => layer.name == name);

  /// [track] with [cut]'s stack as [edit] leaves it — one verb's write.
  Track edited(
    Track track,
    String cut,
    List<Layer> Function(List<Layer> layers) edit,
  ) => track.copyWith(
    cuts: [
      for (final each in track.cuts)
        if (each.id == CutId(cut))
          each.copyWith(layers: edit(each.layers))
        else
          each,
    ],
  );

  List<Layer> renamed(List<Layer> layers, String from, String to) => [
    for (final layer in layers)
      if (layer.name == from) layer.copyWith(name: to) else layer,
  ];

  /// Cuts a and b, X riding over each conte, laid.
  Track twoCuts() => write(
    trackOf([
      cutOf('a', [cel('a'), conte('a'), rider('a', 'x', name: 'X')]),
      cutOf('b', [conte('b'), rider('b', 'x', name: 'X'), cel('b')]),
    ]),
  );

  group('a track written before it kept a structure', () {
    final legacy = trackOf([
      cutOf('a', [conte('a'), rider('a', 'x', name: 'X')]),
      cutOf('b', [
        rider('b', 'u', name: 'U', placement: AttachedPlacement.below),
        conte('b'),
        rider('b', 'p', name: 'P'),
        rider('b', 'q', name: 'Q'),
      ]),
    ]);

    test('lays every seat any cut has, worn as the first cut that has it '
        'wears it', () {
      final laid = write(legacy);

      expect(conteOf(laid, 'a'), ['*U', 'Conte', 'X', '*Q']);
      expect(
        conteOf(laid, 'b'),
        ['U', 'Conte', 'X', 'Q'],
        reason: 'P stands on X\'s seat, so it is X — and wears X\'s head',
      );
      expect(
        rowOf(laid, 'b', 'X').id,
        const LayerId('b-p'),
        reason: 'each cut keeps its own row',
      );
      expect(
        [for (final entry in laid.conte.above) entry.head.name],
        ['X', 'Q'],
      );
      expect([for (final entry in laid.conte.below) entry.head.name], ['U']);
      expect(laid.conte.base?.name, 'Conte');
    });

    test('gives a cut the row it has none of empty, riding its own conte on '
        'its side, off the timesheet, under an id the same every time', () {
      final laid = write(legacy);
      final q = rowOf(laid, 'a', 'Q');
      final u = rowOf(laid, 'a', 'U');

      expect(q.id, conteFillId(const ConteKey('b-q'), const CutId('a')));
      expect(q.conteKey, const ConteKey('b-q'));
      expect(q.attachedToLayerId, const LayerId('a-conte'));
      expect(q.attachedPlacement, AttachedPlacement.above);
      expect(q.attachedMode, AttachedMode.free, reason: 'the row it is of');
      expect(q.kind, LayerKind.storyboard);
      expect(q.frames, isEmpty);
      expect(q.onTimesheet, isFalse, reason: 'as the ＋ makes an attach row');
      expect(u.attachedPlacement, AttachedPlacement.below);
      expect(
        [for (final layer in cutIn(write(legacy), 'a').layers) layer.id],
        [for (final layer in cutIn(laid, 'a').layers) layer.id],
        reason: 'laid again from the same file, the same rows',
      );
    });
  });

  test('a row a write adds to one cut\'s conte is every cut\'s — on its side '
      'of the conte, where it stands', () {
    final before = twoCuts();
    final added = edited(
      before,
      'a',
      (layers) => [
        rider('a', 'under', name: 'Under', placement: AttachedPlacement.below),
        ...layers,
        rider('a', 'n', name: 'N'),
      ],
    );

    final laid = write(added, settled: before);

    expect(conteOf(laid, 'a'), ['Under', 'Conte', 'X', 'N']);
    expect(conteOf(laid, 'b'), ['*Under', 'Conte', 'X', '*N']);
    expect(rowOf(laid, 'a', 'N').conteKey, const ConteKey('a-n'));
    expect(rowOf(laid, 'b', 'N').conteKey, const ConteKey('a-n'));
  });

  group('what a write changes of a row\'s head', () {
    test('is every cut\'s — whichever cut it was changed in', () {
      final before = twoCuts();

      final laid = write(
        edited(before, 'b', (layers) => renamed(layers, 'X', 'Y')),
        settled: before,
      );

      expect(conteOf(laid, 'a'), ['Conte', 'Y']);
      expect(laid.conte.above.single.head.name, 'Y');
    });

    test('changed in two cuts at once, is the first cut\'s', () {
      final before = twoCuts();
      final both = edited(
        edited(before, 'a', (layers) => renamed(layers, 'X', 'From a')),
        'b',
        (layers) => renamed(layers, 'X', 'From b'),
      );

      final laid = write(both, settled: before);

      expect(conteOf(laid, 'a'), ['Conte', 'From a']);
      expect(conteOf(laid, 'b'), ['Conte', 'From a']);
    });

    test('— the eye, and the conte\'s own fx by their shape, each cut '
        'keeping its own numbers', () {
      final radius = effectParametersOf(EffectKind.blur).first.id;
      LayerEffect blur(double value) => LayerEffect(
        id: const EffectId('blur'),
        kind: EffectKind.blur,
        parameters: {radius: EffectParameter(value: value)},
      );
      final before = write(
        trackOf([
          cutOf('a', [
            conte('a', effects: [blur(8)]),
            rider('a', 'x', name: 'X'),
          ]),
          cutOf('b', [
            conte('b', effects: [blur(3)]),
            rider('b', 'x', name: 'X'),
          ]),
        ]),
      );
      final changed = edited(
        before,
        'a',
        (layers) => [
          for (final layer in layers)
            switch (layer.name) {
              'X' => layer.copyWith(isVisible: false),
              'Conte' => layer.copyWith(
                effects: [blur(8).copyWith(enabled: false)],
              ),
              _ => layer,
            },
        ],
      );

      final laid = write(changed, settled: before);

      expect(rowOf(laid, 'b', 'X').isVisible, isFalse);
      final effect = rowOf(laid, 'b', 'Conte').effects.single;
      expect(effect.enabled, isFalse, reason: 'the shape is the head\'s');
      expect(
        effect.parameterOf(radius).value,
        3,
        reason: 'the numbers are each cut\'s own',
      );
    });
  });

  test('a re-ordering in one cut is every cut\'s — a row crossing the conte '
      'taking the other side there too', () {
    final before = write(
      trackOf([
        cutOf('a', [
          conte('a'),
          rider('a', 'x', name: 'X'),
          rider('a', 'q', name: 'Q'),
        ]),
        cutOf('b', [
          conte('b'),
          rider('b', 'x', name: 'X'),
          rider('b', 'q', name: 'Q'),
        ]),
      ]),
    );
    final swapped = edited(before, 'b', (layers) {
      final byName = {for (final layer in layers) layer.name: layer};
      return [byName['Conte']!, byName['Q']!, byName['X']!];
    });

    final laid = write(swapped, settled: before);
    expect(conteOf(laid, 'a'), ['Conte', 'Q', 'X']);

    final crossed = edited(laid, 'a', (layers) {
      final byName = {for (final layer in layers) layer.name: layer};
      return [
        byName['X']!.copyWith(attachedPlacement: AttachedPlacement.below),
        byName['Conte']!,
        byName['Q']!,
      ];
    });
    final relaid = write(crossed, settled: laid);

    expect(conteOf(relaid, 'b'), ['X', 'Conte', 'Q']);
    expect(rowOf(relaid, 'b', 'X').attachedPlacement, AttachedPlacement.below);
  });

  group('a row gone', () {
    test('from every cut is gone from the structure', () {
      final before = twoCuts();
      final gone = edited(
        edited(before, 'a', (layers) => [...layers]..removeLast()),
        'b',
        (layers) => [
          for (final layer in layers)
            if (layer.name != 'X') layer,
        ],
      );

      final laid = write(gone, settled: before);

      expect(conteOf(laid, 'a'), ['Conte']);
      expect(conteOf(laid, 'b'), ['Conte']);
      expect(laid.conte.entries, isEmpty);
    });

    test('from one cut alone is given back to it, empty: the other cuts '
        'still hold it', () {
      final before = twoCuts();

      final laid = write(
        edited(before, 'a', (layers) => [...layers]..removeLast()),
        settled: before,
      );

      expect(conteOf(laid, 'a'), ['Conte', '*X']);
      expect(conteOf(laid, 'b'), ['Conte', 'X']);
    });
  });

  group('a 공정 folder', () {
    /// Cut a's X filed into the folder F — one verb's write.
    Track filed(Track before) => edited(
      before,
      'a',
      (layers) => [
        cel('a'),
        conte('a'),
        rider('a', 'x', name: 'X', folderId: const LayerId('a-f')),
        folder('a', 'f', name: 'F'),
      ],
    );

    test('made in one cut is every cut\'s, filing the same rows', () {
      final before = twoCuts();

      final laid = write(filed(before), settled: before);

      expect(conteOf(laid, 'b'), ['Conte', 'X', '*F']);
      expect(
        rowOf(laid, 'b', 'X').folderId,
        conteFillId(const ConteKey('a-f'), const CutId('b')),
      );
      expect(laid.conte.above.first.parent, const ConteKey('a-f'));
    });

    test('left filing nothing is forgotten — the one a cut was given goes, '
        'and a cut\'s own steps out of the group', () {
      final before = write(
        trackOf([
          cutOf('a', [
            conte('a'),
            rider('a', 'x', name: 'X', folderId: const LayerId('a-f')),
            folder('a', 'f', name: 'F'),
          ]),
          cutOf('b', [
            conte('b'),
            rider('b', 'x', name: 'X', folderId: const LayerId('b-f')),
            folder('b', 'f', name: 'F'),
          ]),
          cutOf('c', [conte('c')]),
        ]),
      );
      expect(conteOf(before, 'c'), ['Conte', '*X', '*F'], reason: 'fixture');
      final emptied = edited(
        before,
        'a',
        (layers) => [
          for (final layer in layers)
            if (layer.name == 'X') layer.copyWith(folderId: null) else layer,
        ],
      );

      final laid = write(emptied, settled: before);

      expect(conteOf(laid, 'a'), ['Conte', 'X']);
      expect(conteOf(laid, 'b'), ['Conte', 'X']);
      expect(conteOf(laid, 'c'), ['Conte', '*X']);
      expect(rowOf(laid, 'b', 'X').folderId, isNull);
      expect(
        [for (final layer in cutIn(laid, 'b').layers) layer.id],
        [const LayerId('b-conte'), const LayerId('b-x'), const LayerId('b-f')],
        reason: 'b\'s own folder stands over the group, out of it',
      );
      expect(
        cutIn(laid, 'c').layers.where(isConteFill),
        everyElement(isNot(predicate<Layer>((layer) => layer.name == 'F'))),
      );
      expect(laid.conte.entries.where((entry) => entry.isFolder), isEmpty);
    });
  });

  test('a copy of a row in its cut is a row of its own — nothing a cut holds '
      'is dropped', () {
    final before = twoCuts();
    final copied = edited(
      before,
      'a',
      (layers) => [
        ...layers,
        rowOf(before, 'a', 'X').copyWith(id: const LayerId('a-copy')),
      ],
    );

    final laid = write(copied, settled: before);

    expect(conteOf(laid, 'a'), ['Conte', 'X', 'X']);
    expect(conteOf(laid, 'b'), ['Conte', 'X', '*X']);
    expect(rowOf(laid, 'a', 'X').conteKey, const ConteKey('a-x'));
    expect(laid.conte.above, hasLength(2));
  });

  group('a cut', () {
    test('without a conte is left alone (F-343-Q1)', () {
      final before = twoCuts();
      final plain = before.copyWith(
        cuts: [
          ...before.cuts,
          cutOf('c', [cel('c')]),
        ],
      );

      final laid = write(plain, settled: before);

      expect(identical(cutIn(laid, 'c'), plain.cuts.last), isTrue);
    });

    test('that gains a conte wears the structure — its head and its rows', () {
      final before = twoCuts();
      final named = write(
        edited(before, 'a', (layers) => renamed(layers, 'Conte', 'Story')),
        settled: before,
      );
      final gained = named.copyWith(
        cuts: [
          ...named.cuts,
          cutOf('c', [cel('c'), conte('c')]),
        ],
      );

      final laid = write(gained, settled: named);

      expect(conteOf(laid, 'c'), ['Story', '*X']);
    });

    test('with no conte left on the track, the structure goes', () {
      final before = twoCuts();
      final none = before.copyWith(
        cuts: [
          cutOf('a', [cel('a')]),
          cutOf('b', [cel('b')]),
        ],
      );

      expect(write(none, settled: before).conte, TrackConte.none);
    });
  });

  group('a laid track', () {
    test('is handed back as the very track it is', () {
      final laid = twoCuts();

      expect(identical(write(laid, settled: laid), laid), isTrue);
    });

    test('reads back from its file as it was, and lays as itself', () {
      final laid = write(
        trackOf([
          cutOf('a', [
            rider('a', 'u', name: 'U', placement: AttachedPlacement.below),
            conte('a'),
            rider('a', 'x', name: 'X', folderId: const LayerId('a-f')),
            folder('a', 'f', name: 'F'),
          ]),
          cutOf('b', [conte('b')]),
        ]),
      );

      final read = Track.fromJson(laid.toJson());

      expect(read, laid);
      expect(read.conte, laid.conte);
      final relaid = write(read);
      expect(identical(relaid, read), isTrue);
    });
  });

  test('a row it gives takes the next free id when the cut holds one with '
      'its id already, outside its conte', () {
    final stray = Layer(
      id: conteFillId(const ConteKey('a-x'), const CutId('b')),
      name: 'Stray',
      frames: const [],
    );
    final track = trackOf([
      cutOf('a', [conte('a'), rider('a', 'x', name: 'X')]),
      cutOf('b', [stray, conte('b')]),
    ]);

    final laid = write(track);

    expect(conteOf(laid, 'b'), ['Conte', '*X']);
    expect(rowOf(laid, 'b', 'X').id, LayerId('${stray.id.value}~2'));
    expect(rowOf(laid, 'b', 'Stray'), same(stray));
  });
}
