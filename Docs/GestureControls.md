# Streaming camera gestures

The four bindings live in **Touch Control** in both the SwiftUI settings catalog
and the legacy UIKit menu. Defaults are pinch in → scroll down, pinch out →
scroll up, counterclockwise rotation → Q, clockwise rotation → E. Each direction
can be disabled, mapped to either wheel direction, or assigned a keyboard chord
using the existing `CommandManager` key names. The Edit segment changes a chord.
Pinch and rotation have independent sensitivity controls. Ctrl-modified pinch
scrolling remains an opt-in option.

## Input and persistence

- `StreamView` owns `StreamGestureController`. Its two UIKit recognizers can
  recognize together, accept direct finger touches on the stream surface, and
  exclude screen-edge menu gestures and on-screen controls. Recognition cancels
  the underlying native/mouse touches; cancellation never generates a click.
- `GestureActionEngine` owns the union of keys held by both gesture axes and
  sends only state transitions to the Moonlight transport. Motion extends an
  idle deadline (70–450 ms), with greater movement producing a longer hold.
  Reversing direction releases the old action before pressing the new action.
  Finger lift, cancellation, settings/profile changes, disabled input, loss of
  focus and session cleanup release gesture-owned keys. The timer only releases
  expired keys; it never repeats keydown events.
- Pinch uses incremental log scale; rotation uses incremental UIKit angles.
  Fractional wheel motion is accumulated before sending high-resolution scroll
  events. Keyboard inputs are binary: the host game controls angular speed;
  finger movement controls hold duration, not analog key pressure.
- `TouchPadGestureHandler` retains ordinary two-finger translation and scroll
  inertia. Local magnifier pinch is available when remote pinch is disabled.
- The v1.1 Core Data model adds four bindings and rotation sensitivity.
  Lightweight migration preserves the v1.0 model. A one-time nil-binding
  migration installs defaults and turns off the old automatic Ctrl modifier.
  `TemporarySettings` carries these values into each settings/session snapshot.
- The Drawing Toolkit is included. Pencil runtime, settings and editors no
  longer consult StoreKit or reset settings after an interrupted purchase.
  Hardware/OS requirements for specific Pencil interactions still apply.

## Verification

Run `bash BuildScripts/test-gestures.sh` on a machine with Swift. This executes
the actual engine against an event recorder and checks held keys, reversal,
overlapping chords, modifier ordering, idle release, proportional duration,
fractional scrolling and invalid input. GitHub Actions runs it before archiving
the iOS app and uploading `VoidLink-unsigned.ipa`.

Device acceptance: exercise pinch/rotation together, reverse direction, lift one
finger, add a third finger, open settings, background the app, disconnect, change
bindings, and restart. Check native/relative/absolute modes, ordinary two-finger
scrolling, widget/edge gestures, and a fresh install with no purchase receipt.
The IPA is unsigned and must be signed for installation on an iOS device.
