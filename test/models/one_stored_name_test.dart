import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/media_asset.dart';

/// What [isOneStoredName] lets through — asked wherever a name read from a
/// project file becomes a file's name (card
/// `a-name-read-from-a-file-becomes-a-path`).
void main() {
  const path = 'C:/work/cut 12/take 한글.wav';

  group('every name this app gives stored bytes is one', () {
    test('a carry minted whole', () {
      final minted = mintMediaCarry(path);

      expect(isOneStoredName(minted), isTrue, reason: minted);
      expect(isOneStoredName('$minted.z'), isTrue, reason: 'its framed twin');
      expect(mediaCarryName((poolPath: path, token: minted)), minted);
    });

    test('whatever the file it was carried from is called', () {
      const files = ['C:/a/..', 'C:/a/.', 'C:/a/con', 'C:/a/nul.wav', ''];
      for (final from in files) {
        final name = mintMediaCarry(from);

        expect(isOneStoredName(name), isTrue, reason: '$from → $name');
      }
    });
  });

  group('a name with anything of a path in it is not', () {
    for (final name in [
      '../outside-file',
      '../../outside/victim-1.bin',
      r'..\outside-file',
      'a/b-c',
      r'a\b-c',
      '/abs-olute',
      r'C:\abs-olute',
      'C:abs-olute',
      'a-b/..',
      'a-b:stream',
    ]) {
      test('「$name」', () => expect(isOneStoredName(name), isFalse));
    }
  });

  group('nor is one the system could read as something else', () {
    for (final name in [
      '',
      '.',
      '..',
      'nul',
      'con.z',
      'aux.wav-x',
      '.hidden-file',
      '-leading',
      'plain',
      'a b-c',
      'a-b c',
      'a-b\n',
      'a-b\u0000',
      'a-한글',
      'a-b*',
      'a-b?',
    ]) {
      final shown = name.replaceAll('\n', r'\n').replaceAll('\u0000', r'\0');
      test('「$shown」', () => expect(isOneStoredName(name), isFalse));
    }
  });
}
