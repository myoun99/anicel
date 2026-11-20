import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cut_id.dart';
import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/layer_kind.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/project_frame_rate.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/media/media_asset_uses.dart';
import 'package:anicel/src/services/media/media_preset_sync.dart';
import 'package:anicel/src/services/persistence/cel_places.dart';
import 'package:anicel/src/ui/import/import_file_settings.dart'
    show importFitLabel;
import 'package:anicel/src/ui/media/media_pool_words.dart';
import 'package:anicel/src/ui/media/media_sync_window.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/timeline/layer_label_controls.dart'
    show layerKindDisplayName;
import 'package:anicel/src/ui/timeline/scale_lane_form.dart' show TwoScales;
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_window.dart';

final _clap = MediaAsset(path: 'C:/snd/clap.wav', name: 'clap');
const _words = MediaPoolWords(
  clock: (rate: ProjectFrameRate.fps24, speed: noPull),
);

/// Frames 2 to 7 of the clap, named 「Door」, its words 「bang」.
const MediaSyncPreset _preset = (
  start: 2,
  length: 6,
  fit: MediaFitMode.none,
  kind: LayerKind.se,
  nameTag: 'Door',
  words: 'bang',
);

MediaSyncPlace _place(
  String frame, {
  required int start,
  required int length,
  String nameTag = 'SE',
}) => MediaSyncPlace(
  use: FrameMediaUse(
    trackId: const TrackId('t1'),
    cutId: null,
    layerId: const LayerId('s1'),
    frameId: FrameId(frame),
    place: DrawingCelPlace(
      owner: const PlaceOwner('t1'),
      layerName: 's1',
      celName: frame,
      blockStarts: const [],
    ),
  ),
  placed: _preset,
  starts: [start],
  lengths: [length],
  nameTag: nameTag,
  words: 'bang',
);

/// 「a」 parts at its start and its length, 「b」 at its length alone, 「c」
/// only at its name tag — which the window starts with off.
final _places = [
  _place('a', start: 0, length: 4),
  _place('b', start: 2, length: 3),
  _place('c', start: 2, length: 6, nameTag: 'Cat'),
];

/// 🗣️유저 2026-11-17 (card 「파일마다 배치 기본값」-Q5 · Q6 「시안대로」,
/// 시안 ③): the sync window picks the fields — the start and the length
/// on to begin — and the places, lists every use with how it parts, and
/// 「모두 적용」 takes every place that parts.
void main() {
  /// Opens the window and answers what it hands back.
  Future<MediaSyncAnswer? Function()> open(
    WidgetTester tester, {
    List<MediaSyncPlace>? places,
  }) async {
    MediaSyncAnswer? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                answer = await showDialog<MediaSyncAnswer>(
                  context: context,
                  builder: (_) => MediaSyncWindow(
                    asset: _clap,
                    places: places ?? _places,
                    placeLines: [
                      for (final place in places ?? _places)
                        'S1 · ${_places.indexOf(place)}',
                    ],
                    words: _words,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => answer;
  }

  Future<void> press(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey<String>(key)));
    await tester.pumpAndSettle();
  }

  /// The words of [index]'s place row — how it parts, or 「같음」.
  String partsOf(WidgetTester tester, int index) =>
      (tester
                  .widget<ListTile>(
                    find.byKey(ValueKey<String>('media-sync-place-$index')),
                  )
                  .title!
              as Text)
          .data!;

  testWidgets('it opens on the start and the length, says each field\'s '
      'preset value as the pool says it, and lists every place with how '
      'it parts — a place that parts at nothing asked is 「같음」', (
    tester,
  ) async {
    await open(tester);
    final strings = AppText.strings;
    expect(find.text(_words.frameWord(2)), findsOneWidget);
    expect(find.text(_words.framesWord(_clap, 6)), findsOneWidget);
    expect(
      find.text(strings.mediaSyncPlaces(total: 3, parting: 2)),
      findsOneWidget,
    );
    expect(
      partsOf(tester, 0),
      '${strings.mediaStart} ${_words.frameWord(0)} → ${_words.frameWord(2)}'
      ' · ${strings.mediaLength} ${_words.framesWord(_clap, 4)} → '
      '${_words.framesWord(_clap, 6)}',
    );
    expect(partsOf(tester, 2), strings.mediaSyncSame);
    expect(find.text(strings.mediaSyncApply(2)), findsOneWidget);
    expect(find.text(strings.mediaSyncApplyAllOf(2)), findsOneWidget);
    expect(
      tester
          .widget<AppWindowActionButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is AppWindowActionButton &&
                  widget.action.actionKey ==
                      const ValueKey<String>('media-sync-apply-all'),
            ),
          )
          .action
          .emphasis,
      AppWindowActionEmphasis.second,
      reason: '시안 ③ draws 「모두 적용」 as the second confirm',
    );
    final aLine = tester.getSize(
      find.byKey(const ValueKey<String>('media-sync-field-start')),
    );
    expect(
      aLine.height * 5,
      MediaSyncWindow.placesHeight,
      reason: 'the places list holds five rows of a line and scrolls past '
          'them',
    );
  });

  testWidgets('a field turned on counts in the list: the name tag lit, the '
      'place that parted at nothing parts', (tester) async {
    await open(tester);
    await press(tester, 'media-sync-field-nameTag-ring');
    expect(
      partsOf(tester, 2),
      '${AppText.strings.seNameLabel} Cat → Door',
    );
    expect(
      find.text(AppText.strings.mediaSyncPlaces(total: 3, parting: 3)),
      findsOneWidget,
    );
  });

  testWidgets('「적용」 answers the fields on and the places picked among '
      'those that part; 「모두 적용」 every one that parts', (tester) async {
    var answer = await open(tester);
    await press(tester, 'media-sync-place-0-ring');
    await press(tester, 'media-sync-apply');
    expect(answer()?.fields, MediaSyncField.asked);
    expect(answer()?.places, [_places[1]]);

    answer = await open(tester);
    await press(tester, 'media-sync-place-0-ring');
    await press(tester, 'media-sync-apply-all');
    expect(answer()?.places, [_places[0], _places[1]]);
  });

  testWidgets('a movie\'s row holds no name tag and no words — the window '
      'shows the fields its places hold, and says what the preset places '
      'at each, once each where a movie\'s sound and pictures count apart', (
    tester,
  ) async {
    /// A movie's row whose pictures cover seven frames where its sound
    /// covers six.
    const row = MediaSyncPlace(
      use: RowMediaUse(
        cutId: CutId('c1'),
        layerId: LayerId('m1'),
        owner: PlaceOwner('t1'),
        layerName: 'm1',
      ),
      placed: (
        start: 2,
        length: 7,
        fit: MediaFitMode.none,
        kind: LayerKind.animation,
        nameTag: 'SE',
        words: 'clap',
      ),
      starts: [0],
      lengths: [10],
    );
    await open(tester, places: [row]);
    for (final (field, shown) in [
      ('start', true),
      ('length', true),
      ('nameTag', false),
      ('words', false),
    ]) {
      expect(
        find.byKey(ValueKey<String>('media-sync-field-$field')),
        shown ? findsOneWidget : findsNothing,
        reason: field,
      );
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await open(tester, places: [_places.first, row]);
    const lengthLine = ValueKey<String>('media-sync-field-length');
    expect(
      (tester
                  .widget<ListTile>(
                    find.byKey(lengthLine),
                  )
                  .title!
              as Text)
          .data,
      '${_words.framesWord(_clap, 6)}, ${_words.framesWord(_clap, 7)}',
    );
    expect(
      partsOf(tester, 1),
      '${AppText.strings.mediaStart} ${_words.frameWord(0)} → '
      '${_words.frameWord(2)} · ${AppText.strings.mediaLength} '
      '${_words.framesWord(_clap, 10)} → ${_words.framesWord(_clap, 7)}',
      reason: 'a place parts from what its own preset places',
    );
  });

  testWidgets('🗣️Q7 · Q8 · Q10: a picture\'s row holds its fit and, where '
      'its preset keeps one picture, its kind — off to begin; on, each says '
      'how the row parts, and a row of more cels than an image holds says '
      'so with its ring dead', (tester) async {
    /// A row of a still placed 1:1, or at [held], where its preset fits it
    /// inside the cut at half its size; as an animation where its preset
    /// places an image, where the sync sets its kind.
    MediaSyncPlace still(
      String layer, {
      int cels = 1,
      CanvasPoint? held,
      MediaFitMode? heldFit = MediaFitMode.none,
      LayerKind? kind = LayerKind.animation,
    }) => MediaSyncPlace(
      use: RowMediaUse(
        cutId: const CutId('c1'),
        layerId: LayerId(layer),
        owner: const PlaceOwner('t1'),
        layerName: layer,
      ),
      placed: (
        start: null,
        length: null,
        fit: MediaFitMode.contain,
        kind: LayerKind.image,
        nameTag: '',
        words: '',
      ),
      size: (
        held: held ?? CanvasPoint(x: 1, y: 1),
        placed: CanvasPoint(x: 0.5, y: 0.5),
        heldFit: heldFit,
      ),
      kind: kind,
      cels: cels,
    );
    final places = [
      still('p1'),
      still('p2', cels: 2),
      still(
        'p3',
        held: CanvasPoint(x: 0.8, y: 0.8),
        heldFit: null,
        kind: null,
      ),
    ];
    final answer = await open(tester, places: places);
    final strings = AppText.strings;
    for (final (field, shown) in [
      ('start', false),
      ('length', false),
      ('fit', true),
      ('kind', true),
      ('nameTag', false),
    ]) {
      expect(
        find.byKey(ValueKey<String>('media-sync-field-$field')),
        shown ? findsOneWidget : findsNothing,
        reason: field,
      );
    }
    expect(partsOf(tester, 0), strings.mediaSyncSame, reason: 'both off');
    await press(tester, 'media-sync-field-fit-ring');
    await press(tester, 'media-sync-field-kind-ring');
    final fit =
        '${strings.imFit} ${importFitLabel(MediaFitMode.none)} → '
        '${importFitLabel(MediaFitMode.contain)}';
    final kind =
        '${strings.mediaKindOfLayer} '
        '${layerKindDisplayName(LayerKind.animation)} → '
        '${layerKindDisplayName(LayerKind.image)}';
    expect(partsOf(tester, 0), '$fit · $kind');
    expect(partsOf(tester, 1), '$fit · $kind');
    expect(
      partsOf(tester, 2),
      '${strings.imFit} '
      '${const TwoScales().label(CanvasPoint(x: 0.8, y: 0.8))} → '
      '${importFitLabel(MediaFitMode.contain)}',
      reason: 'a size no fit is says itself as its size lane prints it',
    );
    expect(
      find.text(strings.mediaSyncPlaces(total: 3, parting: 3)),
      findsOneWidget,
    );
    expect(
      find.text(strings.mediaSyncApplyAllOf(2)),
      findsOneWidget,
      reason: 'p2 holds two cels: an image holds one',
    );
    await press(tester, 'media-sync-place-1-ring');
    await press(tester, 'media-sync-apply-all');
    expect(answer()?.places, [places[0], places[2]]);
    expect(answer()?.fields, {
      ...MediaSyncField.asked,
      MediaSyncField.fit,
      MediaSyncField.kind,
    });
  });

  testWidgets('cancel answers nothing', (tester) async {
    final answer = await open(tester);
    await press(tester, 'media-sync-cancel');
    expect(answer(), isNull);
  });
}
