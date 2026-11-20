import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/models/brush_frame_key.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart'
    show LiveCelScreen;

/// Whether a screen shows ink of [cel] — the screen a sheet's ink window
/// shows its cel on ([LiveCelScreen]), the brush on or off (F-215): what
/// its painter draws holds a pixel. None where no screen shows [cel].
bool aScreenShowsInkOf(WidgetTester tester, BrushFrameKey cel) => tester
    .widgetList<LiveCelScreen>(
      find.byWidgetPredicate(
        (widget) => widget is LiveCelScreen && widget.cel == cel,
      ),
    )
    .any((screen) => !screen.painter.surface.holdsNothing);
