import '../../models/bitmap_tile.dart';
import '../../models/brush_frame_key.dart';
import '../../models/cel_text.dart';
import '../../models/tile_coord.dart';
import '../../services/bitmap_surface_geometry.dart' show tilesBehindWall;
import '../../services/command.dart';
import '../../services/commands/cel_text_edit_command.dart';
import 'pixel_editing.dart';
import 'pixel_verbs.dart';
import 'render_caches.dart';
import 'session_roles.dart';

/// A text as a copy holds it: what it says and its pixels, the pair a cel
/// carries ([CelText]) without the id — a paste mints its own.
typedef TextCopy = ({CelTextContent content, Map<TileCoord, BitmapTile> plate});

/// What the canvas on screen tells the text clipboard, published by whoever
/// holds both it and the project ([TextClipboard.canvasText]).
typedef CanvasTextHand = ({
  /// The text the hand holds BY ITS BOX, as it is shown — null with none,
  /// or with one held by its letters (the keyboard is typing into it).
  TextCopy? Function() heldByItsBox,

  /// [landing] with the registering of the faces its letters are written
  /// in ([families]), as one step (`ProjectFonts.landingWith`).
  Command Function(Command landing, Set<String> families) landingWith,
});

/// THE TEXT BOARD — the text the last copy of one took, the APP's like the
/// frame, row and key boards beside it (`AppClipboard`: one copy in hand,
/// whichever board took it).
class TextBoard {
  TextCopy? _copy;

  /// What this board taking a copy lets go of: the pill's other boards
  /// (`AppClipboard`).
  void Function()? onTake;

  void _take(TextCopy copy) {
    _copy = copy;
    onTake?.call();
  }

  /// Lets go of what it holds: the hand took a copy of another kind.
  void letGo() => _copy = null;
}

/// The TEXT CLIPBOARD — copying the text the canvas holds by its box, and
/// putting it down on other cels.
///
/// 🗣️I-101 (유저 2026-10-15): 「텍스트 복사/붙여넣기. 텍스트를 선택한
/// 상태(변형박스로 변한 상태)에서 복사 가능. 다른 대응가능한 곳에
/// 붙여넣기로 붙여넣기」 — and, as everything on the pill, 「다른 프로젝트던
/// 다른 컷이던 프레임복사랑 같은 규칙/법으로」: the board is the app's.
class TextClipboard {
  TextClipboard({
    required TextBoard board,
    required ProjectAccess project,
    required PixelEditing pixelEditing,
    required PixelVerbs pixelVerbs,
    required RenderCaches renderCaches,
    required ChangeSink changes,
  }) : _board = board,
       _project = project,
       _pixelEditing = pixelEditing,
       _pixelVerbs = pixelVerbs,
       _renderCaches = renderCaches,
       _changes = changes;

  /// The app's text board — every open project's clipboard reads and writes
  /// the same one (I-7).
  final TextBoard _board;
  final ProjectAccess _project;
  final PixelEditing _pixelEditing;
  final PixelVerbs _pixelVerbs;
  final RenderCaches _renderCaches;
  final ChangeSink _changes;

  /// The canvas on screen, hung by the workspace that shows this project
  /// and taken off when another comes in front — a project behind has no
  /// canvas, and no text in hand.
  CanvasTextHand? canvasText;

  /// Whether a copy here takes a text: one is held by its box — the
  /// shared pill's copy asks this before anything else (the thing in hand
  /// first, as Delete does).
  bool get canCopy => canvasText?.heldByItsBox() != null;

  /// Takes the text held by its box AS IT IS SHOWN — its letters and their
  /// pixels together, never one ahead of the other (`CelTextSession`).
  void copy() {
    final copy = canvasText?.heldByItsBox();
    if (copy == null) {
      return;
    }
    _board._take(copy);
    _changes.notifyChanged();
  }

  /// Whether the hand holds a text.
  bool get holdsText => _board._copy != null;

  /// Whether a paste here puts the text in hand down: on the cels a held
  /// picture lands on ([PixelVerbs.pieceGround]).
  bool get canPasteIndependent =>
      holdsText &&
      _pixelEditing.coordinator != null &&
      _pixelVerbs.pieceGround().cels.isNotEmpty;

  /// 독립 붙여넣기 of the text in hand: a new text on every cel a held
  /// picture lands on — a frame range's whole block, or the cel you stand
  /// on — where it was copied from, as one undo.
  ///
  /// ★THE PIXEL PASTE'S GROUND (I-55, F-293): a range or none, the same
  /// code answers (절대명령 2), ONE landing per physical cel (C5: 「같은게
  /// 두개인곳에 붙여넣으면 한번만 발리도록」), and no cel is made (C6).
  /// ⛔No marquee cuts it: a text is not pixels of the cel.
  ///
  /// Its pixels are cut at THIS cel's wall: copied in a project whose
  /// pasteboard reaches further, they would stand past it here.
  void pasteIndependent() {
    final copy = _board._copy;
    final coordinator = _pixelEditing.coordinator;
    if (copy == null || coordinator == null) {
      return;
    }
    final wall = coordinator.sessionStore.pasteboard.region;
    final landings = <BrushFrameKey, Command>{};
    for (final key in _pixelVerbs.pieceGround().cels) {
      landings.putIfAbsent(
        coordinator.frameStore.canonicalKeyOf(key),
        () => CelTextEditCommand.put(
          coordinator: coordinator,
          frameKey: key,
          content: copy.content,
          plate: tilesBehindWall(
            copy.plate,
            wall: wall,
            tileSize: coordinator.currentSurfaceOf(key).tileSize,
          ),
          cacheInvalidationSink: _renderCaches.cacheInvalidationHub,
          description: 'Paste text',
        ),
      );
    }
    final step = oneStepOf('Paste text', [...landings.values]);
    if (step == null) {
      return;
    }
    final families = {
      for (final span in copy.content.spans) ?span.style.fontFamily,
    };
    _project.historyManager.execute(
      canvasText?.landingWith(step, families) ?? step,
    );
  }
}
