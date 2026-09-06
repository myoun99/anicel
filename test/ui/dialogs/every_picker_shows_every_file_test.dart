import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/dialogs/open_file_flow.dart';

/// 🚨★★★유저 2026-08-29: 「임포트든 열기든 뭐든 픽커는 pdf만 표시한다던가.
/// 특히 윈도우 열기시 anicel이랑 tvp만 설정따라서 보이게 되있는데 그게아니라
/// 픽커는 **어떤플랫폼이든 어떤 확장자던 선택할수 있게**하고, 대응만
/// 지원안되는 확장자면 **그 때** 안내창 띄우게」.
///
/// A behaviour test cannot see a native dialog's filter, so this is a
/// SOURCE scan — the ratchet, not the behaviour ([[no-copy-to-share]]: a
/// behaviour test passes a second picker that quietly filters again).

void main() {
  test('no opening picker passes a type filter — the dialog shows every '
      'file and the refusal comes after', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      for (final line in source.split('\n')) {
        final trimmed = line.trim();
        if (!trimmed.startsWith('acceptedTypeGroups:')) {
          continue;
        }
        // Declarations and pass-throughs are not pickers, and the SAVE
        // dialog is a different question: it proposes a suffix for a file
        // being created, and hides nothing the user came for.
        if (trimmed.contains('const []') ||
            _isSaveDialog(source, line) ||
            trimmed.endsWith('acceptedTypeGroups,') ||
            trimmed.contains('List<file_selector.XTypeGroup>') ||
            trimmed.contains('List<XTypeGroup>')) {
          continue;
        }
        offenders.add('${entity.path}: $trimmed');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'these pass a type filter to an OPEN dialog. Pass the extensions '
          'as supportedExtensions instead, so the file is refused with a '
          'notice rather than greyed out with no reason.',
    );
  });

  group('what the notice is about', () {
    test('an extension outside the list is refused, in any case', () {
      expect(fileIsSupported('C:/a/b/clip.MP4', const ['mp4']), isTrue);
      expect(fileIsSupported('C:/a/b/clip.mov', const ['mp4']), isFalse);
    });

    test('an EMPTY list accepts anything — for a caller that judges the '
        'content rather than the name', () {
      expect(fileIsSupported('C:/a/b/whatever.xyz', const []), isTrue);
    });

    test('a file with no extension at all is refused rather than crashing', () {
      expect(fileIsSupported('C:/a/b/README', const ['md']), isFalse);
      expect(fileIsSupported('C:/a/b/trailing.', const ['md']), isFalse);
    });
  });
}

/// The SAVE dialog is a different question: it PROPOSES a suffix for a file
/// being created and hides nothing the user came for, so its type group
/// stays. Detected by the call it sits inside rather than by file, so a new
/// save site is covered and a new OPEN site in the same file is not missed.
/// Whether this filter belongs to a dialog that CREATES a file rather than
/// one that opens one.
///
/// ⚠️A proximity heuristic, and it has to name every save door by hand —
/// `handWrittenFileToUser` was added later and this said nothing, so a
/// perfectly legal save filter came back as an offender. Growing the list
/// is not loosening the rule: the rule is「an OPEN picker must not filter」,
/// and a door that writes is simply not one.
bool _isSaveDialog(String source, String line) {
  final at = source.indexOf(line);
  if (at < 0) {
    return false;
  }
  final before = source.substring((at - 400).clamp(0, at), at);
  return before.contains('pickSaveDestination') ||
      before.contains('exportFile') ||
      before.contains('handWrittenFileToUser');
}
