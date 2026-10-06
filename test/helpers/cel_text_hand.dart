import 'package:anicel/src/models/bitmap_surface.dart';
import 'package:anicel/src/models/bitmap_tile.dart';
import 'package:anicel/src/models/canvas_size.dart';
import 'package:anicel/src/models/cel_text.dart';
import 'package:anicel/src/models/tile_coord.dart';
import 'package:anicel/src/services/command.dart';
import 'package:anicel/src/services/history_manager.dart';
import 'package:anicel/src/ui/brush/text_tool_options.dart';
import 'package:anicel/src/ui/canvas/text/cel_text_tool.dart';
import 'package:anicel/src/ui/text/cel_text_bake.dart';
import 'package:anicel/src/ui/text/cel_text_layout.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'cel_text_fixture.dart';
import 'cel_text_held_baker.dart';

/// THE TEXT TOOL'S HAND, WITH THE SETTINGS IT READS (R9-rest) — for the
/// tests of what reaches the hand from OUTSIDE it: the tool settings, their
/// values and their rows. The hand on one cel of the test stack, the next
/// text's values in a notifier a test can write, and a host that keeps what
/// it was asked to run.
typedef TextHand = ({
  CelTextTool tool,
  TextHandHost host,
  ValueNotifier<TextToolOptions> options,
  CelTextCel cel,
});

/// The hand over a cel that carries [text] — taken by its box — or carries
/// none; [next] is what the next text starts as, and [bake] the engine it
/// asks.
TextHand textHand({
  required CelTextBaker bake,
  CelTextContent? text,
  TextToolOptions next = TextToolOptions.defaults,
}) {
  final options = ValueNotifier(next);
  addTearDown(options.dispose);
  final host = TextHandHost(() => options.value);
  final tool = CelTextTool(host: host, bake: bake);
  final CelTextCel cel = (
    key: celTextTestKey,
    coordinator: editingStackOn(
      drawingOf(const {}).withTexts([
        if (text != null) CelText(id: 1, content: text, plate: plateOf(text)),
      ]),
    ),
    canvasSize: celTextTestCanvas,
    cacheInvalidationSink: null,
  );
  host.cel = cel;
  if (text != null) {
    tool.takeText(cel, pictureUnder(cel).texts.single);
  }
  return (tool: tool, host: host, options: options, cel: cel);
}

/// [cel]'s picture as it is stored.
BitmapSurface pictureUnder(CelTextCel cel) =>
    cel.coordinator.currentSurfaceOf(cel.key);

/// The one text [cel] carries, as it landed.
CelTextContent landedOn(CelTextCel cel) =>
    pictureUnder(cel).texts.single.content;

/// An engine that answers AT ONCE — for a test that is about something
/// other than the frames between a text being wanted and being made (those
/// are [HeldBaker]'s).
Future<Map<TileCoord, BitmapTile>> bakesAtOnce(
  CelTextLayout layout, {
  required CanvasSize canvasSize,
  required int tileSize,
  Map<TileCoord, BitmapTile> previous = const {},
}) async => layout.content.isEmpty ? const {} : plateOf(layout.content);

/// The canvas panel, as the hand sees it: where the next text's values are
/// read, and every step it was asked to run.
class TextHandHost implements CelTextToolHost {
  TextHandHost(this._next);

  final TextToolOptions Function() _next;
  final HistoryManager history = HistoryManager();

  /// Every step the hand ran, in order.
  final List<Command> ran = [];

  @override
  TextToolOptions get options => _next();

  /// The cel under the tool.
  @override
  CelTextCel? cel;

  @override
  HistoryMark? get historyMark => history.gestures.mark;

  @override
  void run(Command command, {HistoryMark? withCelMadeSince}) {
    ran.add(command);
    history.execute(command);
  }

  @override
  void shownChanged() {}
}
