import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/frame_id.dart';
import 'package:anicel/src/models/layer_id.dart';
import 'package:anicel/src/models/media_asset.dart';
import 'package:anicel/src/models/track_id.dart';
import 'package:anicel/src/services/media/media_asset_uses.dart';
import 'package:anicel/src/services/media/media_preset_sync.dart';
import 'package:anicel/src/services/persistence/cel_places.dart';
import 'package:anicel/src/ui/media/media_pool_words.dart';
import 'package:anicel/src/ui/media/media_sync_window.dart';
import 'package:anicel/src/ui/text/app_strings.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:anicel/src/ui/widgets/app_window.dart';

final _clap = MediaAsset(path: 'C:/snd/clap.wav', name: 'clap');
const _words = MediaPoolWords(framesPerSecond: 24);

/// Frames 2 to 7 of the clap, named 「Door」, its words 「bang」.
const SoundPreset _preset = (
  start: 2,
  length: 6,
  nameTag: 'Door',
  words: 'bang',
);

SoundPlace _place(
  String frame, {
  required int start,
  required int length,
  String nameTag = 'SE',
}) => SoundPlace(
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
  Future<MediaSyncAnswer? Function()> open(WidgetTester tester) async {
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
                    preset: _preset,
                    places: _places,
                    placeLines: const ['S1 · a', 'S1 · b', 'S1 · c'],
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
    expect(answer()?.fields, SoundSyncField.asked);
    expect(answer()?.places, [_places[1]]);

    answer = await open(tester);
    await press(tester, 'media-sync-place-0-ring');
    await press(tester, 'media-sync-apply-all');
    expect(answer()?.places, [_places[0], _places[1]]);
  });

  testWidgets('cancel answers nothing', (tester) async {
    final answer = await open(tester);
    await press(tester, 'media-sync-cancel');
    expect(answer(), isNull);
  });
}
