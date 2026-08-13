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
      final groups = <String, dynamic>{
        'anicelProject': FileTypeGroups.anicelProject,
        // The iOS shape: that is the platform the identifiers are load
        // bearing on, and the one whose picker throws without them.
        'brushes': FileTypeGroups.brushesFor('ios'),
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

    // The brush group is the one that differs by platform, and it differs
    // because the two Apple pickers read the SAME two fields differently:
    // iOS filters on identifiers alone, macOS unions them with the
    // extensions. `public.data` is therefore the only thing that makes the
    // iOS picker usable and the only thing that makes the macOS one
    // useless.
    test('brushes: every platform but macOS carries the umbrella type', () {
      for (final os in const ['ios', 'windows', 'linux', 'android']) {
        expect(
          FileTypeGroups.brushesFor(os).uniformTypeIdentifiers,
          ['public.data'],
          reason: 'on $os the identifiers are either load-bearing or '
              'ignored — never a filter that narrows',
        );
      }
      expect(
        FileTypeGroups.brushesFor('macos').uniformTypeIdentifiers,
        isEmpty,
        reason: 'macOS takes the UNION of the two fields, so the umbrella '
            'would offer the whole disk instead of the brush packs',
      );
    });

    test('brushes: the extensions are the filter on every platform', () {
      for (final os in const ['ios', 'macos', 'windows', 'linux', 'android']) {
        expect(FileTypeGroups.brushesFor(os).extensions, brushFileExtensions);
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
    /// The `<dict>` that DECLARES [identifier], rather than any place the
    /// string happens to appear.
    ///
    /// A plain `contains` was not enough: `com.myoun.anicel.project` appears
    /// twice (the exported declaration and the document-type entry that
    /// references it), so deleting the declaration's conformance or its
    /// extension tag left the assertion green while `.anicel` — and `.flac`
    /// with it — went back to being unselectable in the picker.
    ///
    /// Sliced between `UTTypeIdentifier` keys rather than on `<dict>`: a
    /// declaration CONTAINS a nested dict (`UTTypeTagSpecification`), so
    /// splitting on the tag cuts the block in half and loses the extension.
    String? declarationFor(String contents, String identifier) {
      const marker = '<key>UTTypeIdentifier</key>';
      var from = 0;
      while (true) {
        final at = contents.indexOf(marker, from);
        if (at < 0) {
          return null;
        }
        final next = contents.indexOf(marker, at + marker.length);
        final block = contents.substring(
          at,
          next < 0 ? contents.length : next,
        );
        final after = block.substring(marker.length).trimLeft();
        if (after.startsWith('<string>$identifier</string>')) {
          return block;
        }
        from = at + marker.length;
      }
    }

    for (final platform in ['ios', 'macos']) {
      test('$platform exports the project type, conformance and all', () {
        final contents = plist('$platform/Runner/Info.plist');
        final block = declarationFor(contents, anicelProjectUti);
        expect(
          block,
          isNotNull,
          reason:
              'FileTypeGroups.anicelProject filters on $anicelProjectUti. '
              'Without a declaration the picker greys out every .anicel file '
              'with no error at all.',
        );
        expect(
          block,
          contains('<string>public.data</string>'),
          reason:
              'A document type must conform to public.data (or to '
              'com.apple.package, which the package round rejected) or the '
              'system does not recognise it as a document type.',
        );
        expect(
          block,
          contains('<string>$anicelProjectExtension</string>'),
          reason: 'The type must claim the .$anicelProjectExtension extension.',
        );
        // Exported, not imported: this type is ours.
        final exportedAt = contents.indexOf('UTExportedTypeDeclarations');
        final importedAt = contents.indexOf('UTImportedTypeDeclarations');
        final declaredAt = contents.indexOf(
          '<string>$anicelProjectUti</string>',
        );
        expect(exportedAt, greaterThanOrEqualTo(0));
        expect(declaredAt, greaterThan(exportedAt));
        if (importedAt >= 0) {
          expect(
            declaredAt,
            lessThan(importedAt),
            reason: 'the project type must sit under the EXPORTED block',
          );
        }
        // And something has to open it.
        expect(contents, contains('CFBundleDocumentTypes'));
      });

      test('$platform imports every format Apple ships no type for', () {
        final contents = plist('$platform/Runner/Info.plist');
        // Without a declaration these are UNSELECTABLE in the picker, not
        // merely unfiltered — and the umbrella filters the call sites pass
        // cannot reach them unless the declaration says which umbrella they
        // belong to. Both halves are asserted.
        const imported = {
          'org.xiph.flac': ('public.audio', 'flac'),
          'org.xiph.ogg': ('public.audio', 'ogg'),
          'org.matroska.mkv': ('public.movie', 'mkv'),
          'org.webmproject.webm': ('public.movie', 'webm'),
          // `.psd` needs no entry — Apple declares it and it conforms to
          // public.image. Its large sibling has no system type at all.
          'com.adobe.photoshop-large-image': ('public.image', 'psb'),
        };
        for (final entry in imported.entries) {
          final block = declarationFor(contents, entry.key);
          expect(
            block,
            isNotNull,
            reason: '$platform/Runner/Info.plist must import ${entry.key}.',
          );
          expect(
            block,
            contains('<string>${entry.value.$1}</string>'),
            reason:
                '${entry.key} must conform to ${entry.value.$1}, or the '
                'umbrella filter the pickers pass will never match it.',
          );
          expect(
            block,
            contains('<string>${entry.value.$2}</string>'),
            reason: '${entry.key} must claim the .${entry.value.$2} extension.',
          );
          expect(
            FileTypeGroups.poolMedia.extensions,
            contains(entry.value.$2),
          );
        }
      });
    }
  });
}
