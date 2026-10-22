import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../widgets/drop_entrance_frame.dart';
import 'hit_path.dart';

/// 🚨A FILE DROPPED FROM THE OS ON A PLACE THAT OPENS FILES OPENS THERE.
///
/// 🗣️F-378 (유저 2026-10-17): 「윈도우등 os에서 드래그앤 드롭으로 파일을
/// 뷰어패널에 떨어트리면 바로 뷰어패널에서 열리도록. 서브뷰어던
/// 메인뷰어던」 — anywhere else a drop goes through the one door, as it
/// always has (`EditorWorkspace`).
///
/// ⚠️THE WINDOW HAS ONE DROP TARGET, and a place does not get one of its
/// own: the drop plugin hands every drop to every target there is, each
/// judging by its own box alone, so a target inside the window's would hear
/// the drop the window's hears — the file would open here AND knock on the
/// door. The window's target asks what is under the drop instead
/// ([osFileDropPlaceAt]), as a press is found: the place on top takes it,
/// and a place under a dialog or behind another panel does not.
abstract interface class OsFileDropPlace {
  /// A drag from the OS has come over this place, or has left it — told
  /// only as that changes.
  void hover({required bool over});

  /// Files dropped here, as the OS handed them over.
  void take(List<String> paths);
}

/// The [OsFileDropPlace] under [globalPosition] in [viewId]'s view — the
/// deepest — or null.
OsFileDropPlace? osFileDropPlaceAt(Offset globalPosition, int viewId) =>
    hitPathInView(globalPosition, viewId)
        .whereType<RenderMetaData>()
        .map((target) => target.metaData)
        .whereType<OsFileDropPlace>()
        .firstOrNull;

/// A place over all of [child] that files dropped from the OS open in —
/// [onDrop] — lit while a drag from the OS is over it, as it is for a pool
/// row ([DropEntranceFrame]).
class OsFileDropEntrance extends StatefulWidget {
  const OsFileDropEntrance({
    super.key,
    required this.onDrop,
    required this.child,
  });

  final void Function(List<String> paths) onDrop;
  final Widget child;

  @override
  State<OsFileDropEntrance> createState() => _OsFileDropEntranceState();
}

class _OsFileDropEntranceState extends State<OsFileDropEntrance>
    implements OsFileDropPlace {
  bool _over = false;

  @override
  void hover({required bool over}) {
    if (mounted) {
      setState(() => _over = over);
    }
  }

  @override
  void take(List<String> paths) => widget.onDrop(paths);

  @override
  Widget build(BuildContext context) => MetaData(
    metaData: this,
    // PASSTHROUGH: [child] is laid out as it would be with no place around
    // it — a loose stack would hand a panel room it could shrink in.
    child: Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(child: DropEntranceFrame(lit: _over)),
      ],
    ),
  );
}
