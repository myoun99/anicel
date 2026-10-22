import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/services/media/held_viewer_document.dart';
import 'package:anicel/src/services/media/media_byte_source.dart';

import '../../helpers/fake_pdf_document.dart';

/// The hold rides on the outside of every kind of document alike
/// ([HeldViewerDocument]): what a page IS — how far it renders sharper — is
/// the document's it holds, never the hold's.
void main() {
  test('a held document is drawn at any size exactly when what it holds '
      'is', () {
    for (final drawn in [true, false]) {
      late final HeldMediaBytes held;
      held = HeldMediaBytes(
        source: const MediaFileBytes('C:/work/held'),
        release: () {},
        moved: const Stream<HeldBytesMove>.empty(),
        again: () async => held,
      );
      final document = HeldViewerDocument(
        FakePdfDocument(
          pageSizes: const [ui.Size(4, 3)],
          drawnAtAnySize: drawn,
        ),
        held,
      );
      expect(document.drawnAtAnySize, drawn, reason: 'held over $drawn');
    }
  });
}
