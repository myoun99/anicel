import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The [Scrollable] inside the scroll view [viewport] finds — whichever
/// kind of scroll view it is.
///
/// ⚠️F-4 turned the timeline's rows and frames into sliver viewports
/// (`TimelineScrollViewport`) while the x-sheet and the storyboard kept
/// single-child ones, and nine pins that asked for the controller by the
/// scroll view's WIDGET TYPE broke with the swap though nothing they
/// measured had changed. Every scroll view is made of a [Scrollable], so
/// asking it keeps a pin about scrolling from being a pin about which widget
/// happens to scroll.
Scrollable scrollableOf(WidgetTester tester, Finder viewport) =>
    tester.widget<Scrollable>(
      find.descendant(of: viewport, matching: find.byType(Scrollable)).first,
    );
