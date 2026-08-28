import 'package:flutter_test/flutter_test.dart';
import 'package:anicel/src/ui/session/attach_fx_confirm.dart';

/// **THE DROP IS HELD UNTIL THE QUESTION IS ANSWERED.**
///
/// 유저 2026-08-29: a folder joining an attach group stops authoring its own
/// fx, so 「기존 fx가 사라집니다. 실행하겠습니까?」 has to come BEFORE the
/// commit. The drag lives below the widget tree with no `BuildContext`, and
/// two surfaces end a row drag, so the session asks through this channel and
/// the workspace shows it — one sentence however many surfaces there are.
void main() {
  test('asking publishes a request and answering clears it', () {
    final controller = AttachFxConfirmController();
    addTearDown(controller.dispose);

    expect(controller.pending.value, isNull, reason: '전제: 조용한 상태');

    bool? answered;
    controller.ask(rowNames: const ['A'], answer: (v) => answered = v);

    final request = controller.pending.value;
    expect(request, isNotNull, reason: '물었으면 화면이 볼 것이 있어야 한다');
    expect(request!.rowNames, ['A']);
    expect(answered, isNull, reason: '아직 아무도 답하지 않았다 — 드롭은 붙잡힌 채다');

    request.answer(true);
    expect(answered, isTrue);
    expect(
      controller.pending.value,
      isNull,
      reason: '🚨답이 커밋을 부르고 행이 다시 그려지는데, 그 순간 요청이 남아 '
          '있으면 결과 위에 두 번째 창이 열린다',
    );
  });

  test('a second ask re-opens rather than looking like nothing happened', () {
    final controller = AttachFxConfirmController();
    addTearDown(controller.dispose);

    controller.ask(rowNames: const ['A'], answer: (_) {});
    final first = controller.pending.value!.seq;
    controller.pending.value!.answer(false);

    controller.ask(rowNames: const ['A'], answer: (_) {});
    expect(
      controller.pending.value!.seq,
      greaterThan(first),
      reason: '같은 행을 두 번 물어도 새 질문이다',
    );
  });

  test('cancelling answers false — a dismissed dialog must not strand the drop',
      () {
    final controller = AttachFxConfirmController();
    addTearDown(controller.dispose);

    bool? answered;
    controller.ask(rowNames: const ['A'], answer: (v) => answered = v);
    controller.pending.value!.answer(false);

    expect(answered, isFalse);
    expect(controller.pending.value, isNull);
  });
}
