#ifndef RUNNER_PEN_LEAVES_H_
#define RUNNER_PEN_LEAVES_H_

#include <windows.h>

// 🚨★★★F-427 — A VIEW THAT GOES DEAF LETS GO OF THE PENS IT HEARD.
//
// 유저 2026-10-21: 「펜으로는 그리거나 패널열거나 다 가능한데 마우스로 아무
// 조작도 안먹히는 상황이 찾아옴 … 입력 인스펙터 켜보니 펜은 정상인데
// 마우스는 움직여도 아예 아무 줄도 갱신안됨」.
//
// The app keeps a mouse out while a pen is in range (F-400,
// lib/src/ui/input/pen_echoes.dart): Windows echoes the pen as a mouse. A
// pen's range ends at its removal, which the engine (Flutter 3.47.4,
// flutter_window.cc) sends on the view's WM_POINTERLEAVE — and a window
// Windows has disabled hears no WM_POINTERLEAVE. A pen that taps open a
// file dialog and leaves while it is up was in range to the app until it
// restarted, and every real mouse was an echo there. 🧪tool/probe/
// pen_probe_main.dart drives that into this runner: before this, 「a pen
// that left while a modal window held the app」 heard no mouse, and kept
// three moves out as echoes.
//
// So the runner notes every pen pointer the view hears, before the engine
// does, and when the window is enabled again hands the engine the leave of
// each one it has not heard leave — the way F-411 hands the engine a key-up
// Windows did not. A pen still over the window then comes back with its
// next move, as a pen that arrives does.
//
// ⛔Not when the window is disabled: a pen pressed as the modal window came
// up is still heard after it — the view holds the pointer — so the engine
// takes it in again, and then never hears it leave (the probe: 「a pen
// pressed as a modal window came up」 stayed in range).
//
// ⛔Not by asking Windows whether the pen is in range, later: the thread's
// GetPointerInfo answers with the last frame the thread HEARD, and a deaf
// window heard none — the probe read 「in range」 for a pen long gone. That
// same answer is what lets the leave be handed over: the engine reads the
// pointer's information for it, and the thread still has it.

// Notes the pen a pointer message to the view speaks of.
void NotePenPointer(UINT message, WPARAM wparam);

// Hands |view| — through its subclass to the engine — the leave of every
// pen it heard and has not heard leave.
void LetPensGo(HWND view);

#endif  // RUNNER_PEN_LEAVES_H_
