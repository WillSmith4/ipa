# Streaming camera gestures

The five bindings live in **Touch Control** in both the SwiftUI settings catalog
and the legacy UIKit menu. Defaults are pinch in → scroll down, pinch out →
scroll up, counterclockwise rotation → Q, clockwise rotation → E. Each direction
can be disabled, mapped to either wheel direction, or assigned a keyboard chord
using the existing `CommandManager` key names. `W+D` holds both keys together;
`CTRL+Q` holds the modifier and key. `MOUSE_LEFT`, `MOUSE_MIDDLE` and `MOUSE_RIGHT`
hold mouse buttons, and can be combined with keys, e.g. `CTRL+MOUSE_MIDDLE`.
The Edit segment changes a chord.
Pinch and rotation have independent sensitivity controls. Ctrl-modified pinch
scrolling remains an opt-in option.

**Swipe (one finger)** recognizes movement beyond the existing touchpad slide
threshold in any direction. Its default is Off. Each of the five bindings has
its own **Move Cursor** switch, initially off, so upgrading preserves existing
controls. Enabling cursor movement with the action Off also works.
At the start of a recognized swipe with Move Cursor enabled, the cursor is
positioned once at the original finger-down location using Single Point's
video-area coordinate conversion. This happens before pressing the assigned
mouse button; subsequent motion remains relative. Cancellation clears any
queued initial position, and cursor-disabled actions do not reposition it.

For free camera orbit, set **Swipe → Edit → MOUSE_MIDDLE**, then enable
**Swipe — Move Cursor**. Move your finger horizontally or vertically to produce
the same input as dragging a mouse with its middle button held. The game's own
camera controls determine how those mouse movements affect its view.

For pinch/rotation, cursor movement follows the centre of both fingers: moving
the whole hand up moves the cursor up, while symmetric pinching/rotation around
a stationary centre does not move it. Simultaneous pinch and rotation send only
one cursor movement per touch sample. Adding/lifting a finger rebases tracking
without jumping. Cursor speed uses the existing touchpad speed setting and
retains fractional movement at low speeds.

**Move Stream Image** and **Zoom Stream Image** in Touch Control independently
enable the existing local viewport pan and zoom. Both default to On, including
when upgrading. They gate the two-finger scroll-view gestures and the Magnifier
widget's translation/zoom, under the existing touch-mode and host-pinch priority
rules. Turning either off retains the current framing and saved profile.
These switches do not change host mouse or camera bindings.

## Input and persistence

- `StreamView` owns `StreamGestureController`. Its gesture recognizers can
  recognize together, accept direct finger touches on the stream surface, and
  exclude screen-edge menu gestures and on-screen controls. Recognition cancels
  the underlying native/mouse touches; cancellation never generates a click.
- `GestureActionEngine` owns the union of keys held by both gesture axes and
  sends only state transitions to the Moonlight transport. Motion extends an
  idle deadline (70–450 ms), with greater movement producing a longer hold.
  Reversing direction releases the old action before pressing the new action.
  Mouse actions (including mixed keyboard/mouse chords) remain held through
  pauses until the gesture ends, allowing uninterrupted camera drags.
  Finger lift, cancellation, settings/profile changes, disabled input, loss of
  focus and session cleanup release gesture-owned keys. The timer only releases
  expired keys; it never repeats keydown events.
- Pinch uses incremental log scale. One custom rotation recognizer tracks the
  same two touches, starting with their vector when the second finger lands.
  Every move computes the signed angle between the previous and current vectors
  using atan2(cross, dot), with no minimum-angle threshold. Positive screen
  rotation selects the right binding, negative selects left; either finger can
  act as the pivot. Zero-angle motion does not activate rotation. Touch changes
  or coincident fingers rebase the vector to prevent angle jumps. Existing
  sensitivity units and separate left/right settings are preserved.
  Fractional wheel motion is accumulated before sending high-resolution scroll
  events. Keyboard inputs are binary: the host game controls angular speed;
  finger movement controls hold duration, not analog key pressure.
- `TouchPadGestureHandler` retains ordinary two-finger translation and scroll
  inertia. Local magnifier pinch is available when remote pinch is disabled.
- The v1.1 Core Data model adds four bindings and rotation sensitivity.
  Lightweight migration preserves the v1.0 model. A one-time nil-binding
  migration installs defaults and turns off the old automatic Ctrl modifier.
  `TemporarySettings` carries these values into each settings/session snapshot.
- The v1.2 model adds the swipe action and five cursor switches, preserving the
  v1.1 model and all existing bindings. Both settings front ends load/save them.
- The v1.3 model adds the two local viewport switches. Migration tests cover
  both v1.1 and v1.2 stores, preserve existing mouse bindings and verify that
  pan and zoom can be saved independently across reopening the store.
- Legacy delayed tap callbacks are invalidated when a gesture takes over.
  Gesture presses run after UIKit has cancelled old touches so a stale mouse
  release cannot interrupt the new drag. The swipe recognizer delays ordinary
  touch delivery until it knows whether the movement is a swipe; taps still
  reach the original handler when recognition fails.
- The Drawing Toolkit is included. Pencil runtime, settings and editors no
  longer consult StoreKit or reset settings after an interrupted purchase.
  Hardware/OS requirements for specific Pencil interactions still apply.

## Verification

Run `bash BuildScripts/test-gestures.sh` on a machine with Swift. This executes
the actual engine against an event recorder and checks held keys, reversal,
overlapping chords, modifier ordering, idle release, proportional duration,
fractional scrolling, mouse/mixed chords, continuous drag through pauses,
centroid movement, touch-set changes, fractional cursor motion and invalid input.
GitHub Actions runs it before archiving
the iOS app and uploading `VoidLink-unsigned.ipa`.

Device acceptance: exercise pinch/rotation together, reverse direction, lift one
finger, add a third finger, open settings, background the app, disconnect, change
bindings, and restart. Check native/relative/absolute modes, ordinary two-finger
scrolling, widget/edge gestures, and a fresh install with no purchase receipt.
Also check Swipe + MOUSE_MIDDLE with Move Cursor on/off, W+D, mixed chords,
simultaneous pinch/rotation with the same button, hand translation up/down,
and taps/double taps when Swipe is Off and when it is enabled.
The IPA is unsigned and must be signed for installation on an iOS device.
