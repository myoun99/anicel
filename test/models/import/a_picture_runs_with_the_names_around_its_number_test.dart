import 'package:flutter_test/flutter_test.dart';

import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/import/picture_run.dart';

/// F-392 (유저 2026-10-17): a picked picture's NUMBERED RUN is the pictures
/// named the same but for their last number — 「그냥 A면 이라는거 없이
/// 숫자면 연속되도록 … 숫자뒤 s가 붙은거끼리 이어져야함」 — and it holds one
/// size: 「중간에 해상도 다른거만나면 항목으로서 독립시키도록」.
void main() {
  List<String> filesOf(PictureRun? run) => [
    for (final picture in run!.pictures) picture.file,
  ];

  test('numbers alone run — in their numbers\' order, 2 before 10 — and '
      'the layer takes the folder\'s name, nothing standing around them', () {
    final run = pictureRunOf('2.jpg', [
      '10.jpg',
      '1.jpg',
      '2.jpg',
      'notes.txt',
    ], folderName: 'walk');

    expect(filesOf(run), ['1.jpg', '2.jpg', '10.jpg']);
    expect([for (final picture in run!.pictures) picture.number], [
      '1',
      '2',
      '10',
    ]);
    expect(run.name, 'walk');
  });

  test('A1 · A2 run as A, and A1s · A2s · A3s as As apart from them — what '
      'follows the number is the name\'s', () {
    const names = ['A1.jpg', 'A2.jpg', 'A1s.jpg', 'A2s.jpg', 'A3s.jpg'];

    final plain = pictureRunOf('A1.jpg', names, folderName: 'cut');
    expect(filesOf(plain), ['A1.jpg', 'A2.jpg']);
    expect(plain!.name, 'A');

    final suffixed = pictureRunOf('A2s.jpg', names, folderName: 'cut');
    expect(filesOf(suffixed), ['A1s.jpg', 'A2s.jpg', 'A3s.jpg']);
    expect(suffixed!.name, 'As');
    expect(suffixed.pictures.first.shown, 'A1s');
  });

  test('the LAST number is the run\'s, and what only stood between the name '
      'and it falls away', () {
    final run = pictureRunOf('shot_012_0002.png', [
      'shot_012_0001.png',
      'shot_012_0002.png',
      'shot_013_0001.png',
    ], folderName: 'cut');

    expect(filesOf(run), ['shot_012_0001.png', 'shot_012_0002.png']);
    expect(run!.name, 'shot_012');
  });

  test('a picture alone in its name runs with nothing — another extension '
      'is another name, a `_` name is no picture of a run (rule E), and a '
      'name with no number has none', () {
    const names = [
      'A1.png',
      'A2.jpg',
      '_BOOK2.png',
      '_BOOK3.png',
      'BG.png',
      'BG2.png',
    ];

    for (final picked in ['A1.png', '_BOOK2.png', 'BG.png']) {
      expect(
        pictureRunOf(picked, names, folderName: 'cut'),
        isNull,
        reason: picked,
      );
    }
  });

  group('a run holds one size', () {
    final run = pictureRunOf('1.png', [
      '1.png',
      '2.png',
      '3.png',
      '4.png',
      '5.png',
    ], folderName: 'cut')!;
    const small = CanvasSize(width: 8, height: 8);
    const large = CanvasSize(width: 16, height: 8);

    test('a picture of another size stops it — on the picked one\'s side, '
        'and stood alone it is no run', () {
      CanvasSize sizeOf(String file) => file == '3.png' ? large : small;

      expect(filesOf(sameSizeRunOf(run, '1.png', sizeOf)), ['1.png', '2.png']);
      expect(filesOf(sameSizeRunOf(run, '5.png', sizeOf)), ['4.png', '5.png']);
      expect(sameSizeRunOf(run, '3.png', sizeOf), isNull);
    });

    test('a picture whose size cannot be read holds none — it stops the run '
        'as another size does, and two of them are no run', () {
      CanvasSize? sizeOf(String file) =>
          file == '4.png' || file == '5.png' ? null : small;

      expect(filesOf(sameSizeRunOf(run, '2.png', sizeOf)), [
        '1.png',
        '2.png',
        '3.png',
      ]);
      expect(sameSizeRunOf(run, '5.png', sizeOf), isNull);
      expect(sameSizeRunOf(run, '4.png', sizeOf), isNull);
    });

    test('the two sides of a stop are two runs though they share a name — '
        'what the window tells one picked run\'s layer from another by', () {
      CanvasSize sizeOf(String file) => file == '3.png' ? large : small;

      final before = sameSizeRunOf(run, '1.png', sizeOf)!;
      final after = sameSizeRunOf(run, '5.png', sizeOf)!;
      expect(after.name, before.name, reason: '⛔fixture: one name');
      expect(after, isNot(before));
    });
  });
}
