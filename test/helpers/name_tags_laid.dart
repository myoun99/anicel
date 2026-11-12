import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/core/tree_nodes.dart';
import 'package:anicel/src/models/composite_tree.dart';
import 'package:anicel/src/services/se_name_tag_plan.dart';
import 'package:anicel/src/ui/canvas/canvas_layer_stack_view.dart';
import 'package:anicel/src/ui/playback/canvas_track_stack_view.dart';
import 'package:anicel/src/ui/playback/frame_picture_view.dart';

/// The editing canvas's own pictures of its frame — not those of a track
/// stack it parks on or lays an O.L's other cut by ([CanvasTrackStackView]).
Finder theCanvasOwnPictures() => find.byElementPredicate(
  (element) =>
      element.widget is FramePictureView &&
      element.findAncestorWidgetOfExactType<CanvasTrackStackView>() == null,
);

/// The SE rows' name tags [pictures] lay, bottom to top — rows of their
/// frames ([CanvasNameTagRow]).
List<ResolvedSeNameTag> nameTagsLaidBy(
  WidgetTester tester,
  Finder pictures,
) => [
  for (final view in tester.widgetList<FramePictureView>(pictures))
    for (final node in preorderNodes(view.nodes))
      if (node case CompositeLeaf(payload: CanvasNameTagRow(:final tag))) tag,
];
