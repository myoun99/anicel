import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Canvas, PictureRecorder;

import 'package:anicel/src/models/canvas_point.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/text_cel_style.dart';
import 'package:anicel/src/services/font_library_service.dart';
import 'package:anicel/src/ui/text/canvas_letter_faces.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:anicel/src/ui/text/imported_fonts.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_faces.dart';
import '../../helpers/temp_dir.dart';

/// R9-rest (the text tool's faces): A FONT A PERSON BROUGHT IS WHAT THE
/// LETTERS ARE SET IN — asked of the real engine, with a real font.
///
/// The font is one of the app's own FILES, brought as a person would bring
/// it: its family is named 「NanumGothic」 in the file, which is not the
/// name the app registers it under (「Nanum Gothic」), so to the app it is a
/// face from outside like any other.
///
/// Measured in it and in the app's own BIZ UDPGothic, 「Hamburg ivy」 is not
/// the same width — which is how these tests tell which face letters were
/// set in.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const family = 'NanumGothic';
  late Directory room;
  late ImportedFonts fonts;
  late Uint8List regular;

  setUpAll(() async {
    await loadTheAppFaces();
    regular = File('assets/fonts/NanumGothic-Regular.ttf').readAsBytesSync();
  });

  setUp(() {
    room = Directory.systemTemp.createTempSync('anicel_brought_face_');
    fonts = ImportedFonts(
      service: FontLibraryService(directoryPath: '${room.path}/fonts'),
    );
  });
  tearDown(() {
    fonts.dispose();
    deleteTempQuietly(room);
  });

  CelTextContent said({String? face, bool bold = false}) => CelTextContent(
    spans: [
      CelTextSpan(
        text: 'Hamburg ivy',
        style: TextLetterStyle(fontFamily: face, fontSize: 40, bold: bold),
      ),
    ],
    anchor: CanvasPoint(x: 8, y: 8),
  );

  double widthSetOf(CelTextContent content) {
    final layout = layoutCelText(content);
    final width = layout.block.width;
    layout.dispose();
    return width;
  }

  double boxWidthOf(CelTextContent content) {
    final corners = celTextBoxOf(content).corners;
    return corners[1].dx - corners[0].dx;
  }

  /// Sends for [family], and waits until it is in the engine.
  Future<void> theFaceIsHere() async {
    await fonts.faces.whenHere([family]);
  }

  test('⛔fixture: the two faces set these letters to different widths, '
      'and the file names its family as these tests do', () async {
    final own = widthSetOf(said());

    expect(await fonts.importBytes(regular), (family: family, refusal: null));
    await theFaceIsHere();

    expect((widthSetOf(said(face: family)) - own).abs(), greaterThan(10));
  });

  test('🚨letters written in a brought face are set in IT once it is here '
      '— and in the app\'s own until then', () async {
    final own = widthSetOf(said());
    await fonts.importBytes(regular);

    expect(
      widthSetOf(said(face: family)),
      own,
      reason: 'on its way: the app\'s face stands in',
    );
    expect(celTextAwaitsAFace(said(face: family)), isTrue);

    await theFaceIsHere();

    expect(celTextAwaitsAFace(said(face: family)), isFalse);
    expect(widthSetOf(said(face: family)), isNot(own));
    // The very face: the file is the one the app's 「Nanum Gothic」 is, and
    // letters set in either are as wide. (⛔Not merely "another width": a
    // name the engine does not know is ALSO another width in a test, where
    // it draws every letter a whole size wide.)
    expect(
      widthSetOf(said(face: family)),
      widthSetOf(said(face: 'Nanum Gothic')),
    );
    // And the app's own letters are untouched by it.
    expect(widthSetOf(said()), own);
  });

  test('🚨a box kept from before the face arrived is set again: it was '
      'measured in other letters', () async {
    final text = said(face: family);
    final own = boxWidthOf(said());
    await fonts.importBytes(regular);
    final early = boxWidthOf(text);
    expect(early, own, reason: '⛔fixture: measured before the face was here');

    await theFaceIsHere();

    expect(boxWidthOf(text), isNot(early));
    expect(boxWidthOf(text), widthSetOf(text));
    // Asked again with nothing changed, it is the box that was kept.
    expect(celTextBoxOf(text), same(celTextBoxOf(text)));
  });

  test('🚨a face taken off this device is not drawn with from that '
      'moment: its letters are set in the app\'s own, and their kept box '
      'with them', () async {
    final text = said(face: family);
    final own = widthSetOf(said());
    await fonts.importBytes(regular);
    await theFaceIsHere();
    final inIt = boxWidthOf(text);
    expect(inIt, isNot(own), reason: '⛔fixture');

    await fonts.delete(family);

    expect(widthSetOf(text), own);
    expect(boxWidthOf(text), own);
    expect(celTextAwaitsAFace(text), isFalse);
  });

  test('a face nobody brought is the app\'s own, and is waited for by '
      'nobody', () {
    final elsewhere = said(face: 'Nobody Sans');

    expect(widthSetOf(elsewhere), widthSetOf(said()));
    expect(celTextAwaitsAFace(elsewhere), isFalse);
  });

  test('🚨a family\'s bold, brought after its regular, is what its bold '
      'letters are set in — the regular is not thickened in its place', () async {
    final bold = File('assets/fonts/NanumGothic-Bold.ttf').readAsBytesSync();
    await fonts.importBytes(regular);
    await theFaceIsHere();
    final thickened = await _inkOf(said(face: family, bold: true));

    await fonts.importBytes(bold);
    await theFaceIsHere();
    final drawn = await _inkOf(said(face: family, bold: true));

    expect(drawn, isNot(thickened));
    // The regular is still the regular's own file.
    final plain = await _inkOf(said(face: family));
    expect(plain, lessThan(thickened));
    expect(plain, lessThan(drawn));
    expect(CanvasLetterFaces.current, same(fonts.faces));
  });
}

/// How many pixels [content]'s letters ink.
Future<int> _inkOf(CelTextContent content) async {
  final layout = layoutCelText(content);
  final bounds = layout.inkBounds;
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)..translate(-bounds.left, -bounds.top);
  layout.paint(canvas);
  final image = await recorder.endRecording().toImage(
    bounds.width.ceil(),
    bounds.height.ceil(),
  );
  layout.dispose();
  final data = (await image.toByteData())!;
  image.dispose();
  var inked = 0;
  for (var at = 3; at < data.lengthInBytes; at += 4) {
    if (data.getUint8(at) > 127) {
      inked += 1;
    }
  }
  return inked;
}
