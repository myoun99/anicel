import 'dart:io';
import 'dart:typed_data';

import 'package:anicel/src/models/font_face_facts.dart';
import 'package:anicel/src/services/font_file_reader.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

/// text-letters-lean-and-underline (유저 2026-10-17: 「기울임/밑줄같은것도 어차피
/// 넣어야할 기능이니까 넣도록」): WHERE A FACE DRAWS ITS LINES — under its
/// letters and through them — is its file's to say, and the lines of a run
/// are the face's that was ASKED FOR, whatever face catches a letter it
/// lacks (`CanvasLetterFaces.linesOf`).
void main() {
  final bundled = {
    AppTypography.bundledFamily: AppTypography.bundledFiles,
    AppTypography.bundledFallback.single: AppTypography.bundledFallbackFiles,
  };

  Uint8List fileOf(String path) => File(path).readAsBytesSync();

  group('the app\'s own faces', () {
    for (final MapEntry(key: family, value: files) in bundled.entries) {
      test('🚨$family\'s lines are what its files say, in both weights — '
          'written in the app, not read at run time', () {
        for (final path in [files.regular, files.bold]) {
          expect(
            readFontLines(fileOf(path)),
            CanvasLetterFaces.appFaceLines[family],
            reason: path,
          );
        }
      });
    }

    test('the two say different lines — so which face a run asked for is '
        'what places its line (premise)', () {
      final biz = CanvasLetterFaces.appFaceLines[AppTypography.bundledFamily]!;
      final nanum =
          CanvasLetterFaces.appFaceLines[AppTypography.bundledFallback.single]!;

      expect(nanum.underline, greaterThan(biz.underline * 2));
      expect(nanum.strikethrough, greaterThan(biz.strikethrough));
    });
  });

  group('a face asked for', () {
    late Map<String, List<Uint8List>> files;
    late CanvasLetterFaces faces;

    setUp(() {
      files = {};
      faces = CanvasLetterFaces(
        files: (family) async => files[family] ?? const [],
        register: (bytes, {required engineFamily}) async {},
      );
    });

    final biz = CanvasLetterFaces.appFaceLines[AppTypography.bundledFamily];
    final nanum =
        CanvasLetterFaces.appFaceLines[AppTypography.bundledFallback.single];

    test('none, or the app\'s first, draws the app\'s first face\'s lines; '
        'its second, its own', () {
      expect(faces.linesOf(null), biz);
      expect(faces.linesOf(AppTypography.bundledFamily), biz);
      expect(faces.linesOf(AppTypography.bundledFallback.single), nanum);
    });

    test('one this device does not hold draws the lines of the face its '
        'letters ARE set in — the app\'s first', () {
      expect(faces.linesOf('Probe Sans'), biz);
    });

    test('🚨one brought to the device draws the app\'s lines while it is on '
        'its way, and its own file\'s once it is in the engine', () async {
      files['Probe Sans'] = [
        fileOf(AppTypography.bundledFallbackFiles.regular),
      ];
      faces.setHeld({'Probe Sans': 'probe'});

      expect(faces.linesOf('Probe Sans'), biz, reason: 'on its way');
      expect(faces.isOnItsWay('Probe Sans'), isTrue);

      await faces.whenHere(['Probe Sans']);

      expect(faces.linesOf('Probe Sans'), nanum);
    });

    test('a set whose first file says nothing of its lines draws as the '
        'first of its files that does — whatever the ones after it say', () async {
      files['Probe Sans'] = [
        Uint8List.fromList([1, 2, 3]),
        fileOf(AppTypography.bundledFallbackFiles.regular),
        fileOf(AppTypography.bundledFiles.regular),
      ];
      faces.setHeld({'Probe Sans': 'probe'});
      faces.sendFor('Probe Sans');
      await faces.whenHere(['Probe Sans']);

      expect(faces.linesOf('Probe Sans'), nanum);
    });

    test('a set none of whose files says draws the app\'s first face\'s '
        'lines', () async {
      files['Probe Sans'] = [
        Uint8List.fromList([1, 2, 3]),
      ];
      faces.setHeld({'Probe Sans': 'probe'});
      faces.sendFor('Probe Sans');
      await faces.whenHere(['Probe Sans']);

      expect(faces.engineFamilyOf('Probe Sans'), isNotNull, reason: 'held');
      expect(faces.linesOf('Probe Sans'), biz);
    });
  });

  test('bytes that are no font say no lines', () {
    expect(readFontLines(Uint8List.fromList([0, 1, 0, 0])), isNull);
    expect(readFontLines(Uint8List(0)), isNull);
  });

  test('a face that says a line is no thicker than nothing says no lines',
      () {
    final font = fileOf(AppTypography.bundledFallbackFiles.regular);
    expect(readFontLines(font), isNotNull, reason: '⛔fixture');

    expect(
      readFontLines(_withTableWord(font, 'post', 10, 0)),
      isNull,
      reason: 'the underline',
    );
    expect(
      readFontLines(_withTableWord(font, 'OS/2', 26, 0)),
      isNull,
      reason: 'the strikethrough',
    );
  });

  test('a face\'s lines are a value', () {
    const lines = FontLines(
      underline: 0.1,
      underlineThickness: 0.05,
      strikethrough: 0.3,
      strikethroughThickness: 0.05,
    );

    expect(
      lines,
      const FontLines(
        underline: 0.1,
        underlineThickness: 0.05,
        strikethrough: 0.3,
        strikethroughThickness: 0.05,
      ),
    );
    expect(
      lines,
      isNot(
        const FontLines(
          underline: 0.1,
          underlineThickness: 0.05,
          strikethrough: 0.3,
          strikethroughThickness: 0.06,
        ),
      ),
    );
  });
}

/// [font] with the 16-bit word at [at] of its table [tag] made [value].
Uint8List _withTableWord(Uint8List font, String tag, int at, int value) {
  final bytes = Uint8List.fromList(font);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < data.getUint16(4); index += 1) {
    final record = 12 + index * 16;
    if (String.fromCharCodes(bytes.sublist(record, record + 4)) == tag) {
      data.setInt16(data.getUint32(record + 8) + at, value);
      return bytes;
    }
  }
  throw StateError('no $tag table');
}
