import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/persistence/anicel_project_archive.dart';
import 'package:anicel/src/services/persistence/file_type_groups.dart';

/// PICK-1. Two of these assertions are unusual and deliberate: they read the
/// Apple Info.plists off disk and compare them to the Dart constants.
///
/// The reason is that the two halves fail in opposite, silent ways. A Dart
/// group naming a UTI the plist never declared produces a picker where every
/// file is greyed out — no error, just an empty-looking Files window. A plist
/// declaring a type no group ever asks for produces nothing at all. Neither
/// shows up in `flutter analyze`, neither shows up in a widget test, and
/// neither is reproducible on the Windows workstation this app is written on.
/// A string comparison is the only place the drift can be caught at desk.
void main() {
  final repoRoot = Directory.current.path;

  String plist(String relative) =>
      File('$repoRoot/$relative').readAsStringSync();

  group('picker filters carry both halves', () {
    test('every group sets extensions AND uniformTypeIdentifiers', () {
      const groups = <String, dynamic>{
        'anicelProject': FileTypeGroups.anicelProject,
        'brushes': FileTypeGroups.brushes,
        'images': FileTypeGroups.images,
        'viewableMedia': FileTypeGroups.viewableMedia,
        'importableMedia': FileTypeGroups.importableMedia,
        'poolMedia': FileTypeGroups.poolMedia,
      };
      for (final entry in groups.entries) {
        final group = entry.value;
        expect(
          group.extensions,
          isNotEmpty,
          reason:
              '${entry.key} needs extensions — file_selector_android throws '
              'ArgumentError on a group with neither extensions nor mimeTypes.',
        );
        expect(
          group.uniformTypeIdentifiers,
          isNotEmpty,
          reason:
              '${entry.key} needs uniformTypeIdentifiers — file_selector_ios '
              'throws ArgumentError on an extension-only group.',
        );
      }
    });

    test('the project group filters on the project extension', () {
      expect(FileTypeGroups.anicelProject.extensions, [anicelProjectExtension]);
      expect(FileTypeGroups.anicelProject.uniformTypeIdentifiers, [
        anicelProjectUti,
      ]);
    });

    test('the pool group is the widest and covers every media kind', () {
      final pool = FileTypeGroups.poolMedia.extensions!;
      for (final extension in [
        ...imageFileExtensions,
        ...audioFileExtensions,
        ...videoFileExtensions,
        'pdf',
      ]) {
        expect(pool, contains(extension));
      }
    });

    test('the import group offers no video, because placement refuses it', () {
      final importable = FileTypeGroups.importableMedia.extensions!;
      for (final extension in videoFileExtensions) {
        expect(importable, isNot(contains(extension)));
      }
    });
  });

  group('the Apple plists agree with the Dart constants', () {
    for (final platform in ['ios', 'macos']) {
      test('$platform exports the project UTI the pickers ask for', () {
        final contents = plist('$platform/Runner/Info.plist');
        expect(
          contents,
          contains('<string>$anicelProjectUti</string>'),
          reason:
              'FileTypeGroups.anicelProject filters on $anicelProjectUti. '
              'If $platform/Runner/Info.plist does not export it, the picker '
              'greys out every .anicel file with no error.',
        );
        expect(
          contents,
          contains('<string>$anicelProjectExtension</string>'),
          reason: 'The exported type must claim the .$anicelProjectExtension '
              'extension or nothing maps onto it.',
        );
      });

      test('$platform imports every format Apple ships no type for', () {
        final contents = plist('$platform/Runner/Info.plist');
        // These four are the whole reason UTImportedTypeDeclarations exists
        // here: without a declaration they are UNSELECTABLE in the picker,
        // not merely unfiltered, and the umbrella filters below cannot see
        // them because nothing tells the system they are audio or movies.
        for (final identifier in [
          'org.xiph.flac',
          'org.xiph.ogg',
          'org.matroska.mkv',
          'org.webmproject.webm',
        ]) {
          expect(
            contents,
            contains('<string>$identifier</string>'),
            reason: '$platform/Runner/Info.plist must import $identifier.',
          );
        }
        for (final extension in ['flac', 'ogg', 'mkv', 'webm']) {
          expect(FileTypeGroups.poolMedia.extensions, contains(extension));
        }
      });
    }
  });
}
