import 'package:flutter/material.dart';

import '../text/app_strings.dart';
import 'app_confirm_dialog.dart';
import 'dialog_verb.dart';

/// Asks whether to link frames to the frames already using the names they
/// were given, so identical names share the same material. Pops `true` to
/// link.
///
/// 🗣️I-18 (유저): 「이제 링크프레임이나 링크레이어 발동할때 뜨는 안내메시지를
/// 단일 변경만 대응하는게 아니라 복수 대응을 기본으로. 대상의 프레임을
/// 리스트로서 보여주도록」. One frame renamed or a whole 자동 이름 지정 press,
/// it is the same window: the sentence reads for one or many, and the frames
/// the link takes are listed under it — OPEN, because which ones is what the
/// window asks about (F-118's rule, [AppConfirmDialog.detailsOpen]).
class FrameNameConflictDialog extends StatelessWidget {
  const FrameNameConflictDialog({
    super.key,
    required this.targets,
    this.message,
  });

  /// The frames the link takes, one line each.
  final List<String> targets;

  /// What the window says of them; null is the rename's sentence
  /// ([AppStrings.frameNameConflictBody]). A linked paste lists the frames
  /// that already HOLD the names and says so
  /// ([AppStrings.linkedPasteConflictBody], I-71).
  final String? message;

  @override
  Widget build(BuildContext context) {
    final strings = AppText.strings;
    // ⚠️Spelled out rather than `confirmDialogKeys`: the accept answers
    // `-link-button`, not `-confirm-button`, so this window is not that
    // convention and keeps its own trio.
    const keys = (
      window: ValueKey<String>('frame-name-conflict-dialog'),
      decline: ValueKey<String>('frame-name-conflict-cancel-button'),
      accept: ValueKey<String>('frame-name-conflict-link-button'),
    );
    return AppConfirmDialog(
      windowKey: keys.window,
      title: strings.frameNameConflictTitle,
      titleIcon: Icons.link_outlined,
      message: message ?? strings.frameNameConflictBody,
      details: targets,
      detailsHeading: strings.frameNameConflictListHeading,
      detailsOpen: true,
      actions: confirmActions(
        context,
        keys: keys,
        decline: ConfirmChoice(strings.commonCancel),
        accept: ConfirmChoice(strings.commonLink),
      ),
    );
  }
}

/// What a link offer needs of the press that makes it: the lines its
/// conflict lists, and the two answers to the question — `join` takes the
/// name that is taken, and `decline` is what the flow still owes when the
/// user keeps things as they were (the part of the window that did not
/// collide).
typedef LinkOffer<C extends Object> = ({
  List<String> Function(C conflict) lines,
  void Function(C conflict) join,
  VoidCallback? decline,
});

/// THE ONE GUARD BETWEEN A NAME AND ITS LINK: asks ONCE — never once per
/// key, never once per drawing — whether to join what holds the names
/// [conflict] stands for, listing what the join takes.
///
/// [notice] is the press's own wording of the window; null is the rename's.
///
/// ↩️It was the tail of [nameThenOfferLink], private to the rename commands.
/// A fourth press makes the offer since I-71 — 링크 붙여넣기 onto another row
/// (`pasteLinkedAskingFirst`), with no window before it: the press is the
/// question — so the guard stands HERE, beside the window it opens. The
/// panel context that fires the paste cannot import the rename commands
/// (they import it).
Future<void> offerLink<C extends Object>(
  BuildContext context,
  C conflict, {
  required LinkOffer<C> onConflict,
  String? notice,
}) async {
  final shouldLink = await showDialogVerb<bool>(
    context,
    (_) => FrameNameConflictDialog(
      targets: onConflict.lines(conflict),
      message: notice,
    ),
  );
  if (shouldLink != true) {
    onConflict.decline?.call();
    return;
  }
  onConflict.join(conflict);
}

/// THE NAME-THEN-OFFER-TO-LINK FLOW, once: ask, attempt the naming, and
/// when a name is already taken make the offer ([offerLink]).
///
/// The three presses that wear it — a frame's rename, a lane key's and
/// 자동 이름 지정 (I-18) — differ only in the question they ask, in what the
/// naming hands back when it collides (the conflicting [FrameId] for a
/// frame, the taken name for a key, the whole plan for a press — one
/// nullable conflict token either way), in the lines that conflict lists
/// and in which link verb takes it. All are collaborators, not modes; this
/// template is the ONE place holding the guard between the two windows.
Future<void> nameThenOfferLink<A extends Object, C extends Object>(
  BuildContext context, {
  required Future<A?> Function() ask,
  required C? Function(A answer) name,
  required LinkOffer<C> onConflict,
}) async {
  final answer = await ask();
  if (answer == null) {
    return;
  }
  final conflict = name(answer);
  if (conflict == null || !context.mounted) {
    return;
  }
  await offerLink(context, conflict, onConflict: onConflict);
}
