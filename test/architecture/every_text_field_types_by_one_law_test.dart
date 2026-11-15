import 'package:flutter_test/flutter_test.dart';

import '../../tool/source_brackets.dart';
import '../helpers/dart_sources.dart';

/// 🚨EVERY TEXT FIELD THE APP BUILDS TYPES BY ONE LAW — its formatters are
/// `typedText`'s (`lib/src/ui/text/typed_text.dart`): no carriage return
/// is text the app takes.
///
/// 🐛F-584 (검증/서피스 2026-11-15, 서피스 프로 11): two lines copied on
/// Windows and pasted into a block's dialogue left a ⊠ where they broke.
/// 🔬The day this was written every text field under lib/ — 29 of them,
/// over 19 files — took the CR through, the dialogue's one among them:
/// none had a law of its own to forget, so the law is the one they share.
///
/// ⛔A behaviour test cannot hold this: a field built tomorrow without the
/// law passes every test of the fields there are. This reads the source.
void main() {
  test('no text field under lib/ is built without typedText for its '
      'formatters', () {
    expect(
      [
        for (final file in dartFilesUnder('lib'))
          ..._untyped(libPath(file), file.readAsStringSync()),
      ],
      isEmpty,
      reason:
          'hand each field `inputFormatters: typedText(…)` — its own '
          'formatters inside the call, the law before them',
    );
  });

  test('premise: the scan sees the fields the app builds', () {
    final fields = [
      for (final file in dartFilesUnder('lib'))
        ..._fieldsIn(withoutComments(file.readAsStringSync())),
    ];
    expect(fields.length, greaterThanOrEqualTo(25));
  });

  test('the scan sees a planted field of each kind, and not one typing by '
      'the law, a call that only ends in a field\'s name, or a comment', () {
    const planted = '''
final a = TextField(controller: c);
final b = TextField(inputFormatters: halfWidthDigitsOnly);
final c = TextFormField(
  maxLines: null,
);
final d = EditableText(controller: c, inputFormatters: typedText());
final e = CupertinoTextField();
final f = TextField(
  inputFormatters: typedText(halfWidthDigitsOnly),
);
final g = focusedTextField();
final h = CelTextField(controller: c);
// final i = TextField();
''';
    expect(_untyped('planted.dart', planted), [
      'planted.dart:1',
      'planted.dart:2',
      'planted.dart:3',
      'planted.dart:7',
    ]);
  });
}

/// The `(` of every text field [code] builds.
Iterable<int> _fieldsIn(String code) => [
  for (final call in RegExp(
    r'(?<![\w$])(?:TextField|TextFormField|EditableText|CupertinoTextField)\(',
  ).allMatches(code))
    call.end - 1,
];

/// Where [source] builds a text field whose formatters are not typedText's,
/// as `path:line`.
List<String> _untyped(String path, String source) {
  final code = withoutComments(source);
  return [
    for (final openAt in _fieldsIn(code))
      if (!(namedArgument(code, openAt, 'inputFormatters') ?? '').startsWith(
        'typedText(',
      ))
        '$path:${'\n'.allMatches(code.substring(0, openAt)).length + 1}',
  ];
}
