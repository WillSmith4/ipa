# Streaming camera gestures

The gesture bindings live in **Touch Control** in both the SwiftUI settings catalog
and the legacy UIKit menu. Defaults are pinch in → scroll down, pinch out →
scroll up, rotation in either direction → MOUSE_MIDDLE, and Long Press →
MOUSE_RIGHT. Double Tap and Hold to Drag defaults to MOUSE_LEFT in Touchpad and
Single Point. Long Press is available in Single Point mode. Each action
can be disabled, mapped to either wheel direction, or assigned a keyboard chord
using the existing `CommandManager` key names. `W+D` holds both keys together;
`CTRL+Q` holds the modifier and key. `MOUSE_LEFT`, `MOUSE_MIDDLE` and `MOUSE_RIGHT`
hold mouse buttons, and can be combined with keys, e.g. `CTRL+MOUSE_MIDDLE`.
The Edit segment changes a chord.
Every existing key name is accepted, including letters, digits, navigation,
media and numpad keys, and the gesture editor also accepts F13-F24. Punctuation
can be entered directly: `-` is MINUS, `=` is EQUALS, and `+` / `PLUS` is
SHIFT+EQUALS, consistent with KeyboardSupport's US-symbol input. `ADD` and
`SUBTRACT` retain their distinct numpad codes. Other shifted symbols also add
SHIFT, e.g. `?` is SHIFT+FORWARD_SLASH. Use `CTRL+PLUS` or `CTRL++` to combine
Ctrl with plus; `CTRL+-` combines Ctrl with minus. A trailing separator such as
`CTRL+` is still rejected. Smart quotes/dashes are disabled in the editor so
typed punctuation is preserved. These additions do not change existing bindings.
Pinch and rotation have independent sensitivity controls. Ctrl-modified pinch
scrolling remains an opt-in option. The Pinch Gesture master switch is removed;
Pinch In/Out selectors are the sole enable controls. The stored legacy switch
is ignored, preserving the actual bindings. Scroll Sensitivity is no longer
shown in any touch mode; ordinary two-finger scrolling retains its saved value.

Native Touch exposes only Divider Position, Touch Pointer Velocity, On-Screen
Widgets, Button Visual Feedback and Touch Point Tracking. Custom mouse/camera
gestures do not intercept native input. Disabled exposes only the last three.
The local stream pan/zoom switches appear and take effect only in Single Point;
other modes retain their built-in magnifier behavior.

**Swipe (one finger)** recognizes movement beyond the existing touchpad slide
threshold in any direction. Its assigned input defaults to Off. Cursor movement
is always on for Swipe and Rotation, even if their assigned input is Off; there
are no Move Cursor switches. Pinch and Long Press have no continuous cursor
movement. At the start of Swipe in Single Point, the cursor is positioned at the original
finger-down location. Touchpad one-finger motion never teleports: with Swipe Off
it uses RelativeTouchHandler, and with a binding it sends relative gesture motion. Pinch and Rotation use the midpoint captured when the
second finger lands. This happens once per touch sequence, before sending the
assigned input, using Single Point's existing video-area coordinate conversion.
Simultaneous pinch and rotation share one anchor; cancellation discards it.

For free camera orbit, set **Swipe → Edit → MOUSE_MIDDLE**. Move your finger
horizontally or vertically to produce the same input as dragging a mouse with
its middle button held. The game's own camera controls determine the result.

For **Rotation**, the signed angle between consecutive two-finger
vectors drives relative horizontal mouse motion, like a camera's yaw input.
Clockwise twist sends positive mouse X; counterclockwise sends negative X.
A complete circle keeps the same direction throughout every quadrant. Finger
spacing, choice of pivot and translation of the whole hand do not affect the
horizontal rotation. During an active rotation, moving both fingers up/down
also moves the mouse vertically, following the centre between the fingers.
This still works while the twist angle is steady. A centred twist has no vertical
translation. Crossing +/-180 degrees follows the short arc without a jump.
The mapping uses 100 mouse-motion units per radian, multiplied by Rotation
Sensitivity and the existing pointer speed (including its 1.35 factor).
Fractional output is retained across samples. The game's mouse sensitivity and
camera controls determine the resulting yaw; this is not a universal degrees-to-
degrees mapping. Use **MOUSE_MIDDLE** for
games that rotate the camera while dragging with the middle button held.

The transport has relative/absolute mouse motion, buttons and scrolling, but no
mouse-rotation or camera-yaw event. The existing gyro-to-mouse path in
MotionHandler.swift likewise maps yaw/pitch to LiSendMouseMoveEvent(dx, dy).
Touch/pen rotation fields describe contact or stylus orientation, not camera yaw.
VoidLink cannot set the remote game's target_yaw or lerp_angle directly.

During Rotation, one combined mouse movement is sent per sample: horizontal
motion from twist and vertical motion from the two-finger centre. Pinch does
not add continuous cursor motion. Adding/lifting fingers rebases tracking.

**Move Stream Image** and **Zoom Stream Image** in Touch Control independently
enable the existing local viewport pan and zoom. Both default to On, including
when upgrading. In Single Point they gate the two-finger scroll-view gestures and the
Magnifier widget's translation/zoom, under the existing host-pinch priority rules. Turning either off retains the current framing and saved profile.
These switches do not change host mouse or camera bindings.

**Long Press** uses the same action selector and key/chord editor as the other
gestures, with Off inside that selector. Its default is MOUSE_RIGHT. Holding one
finger stationary for 0.65 seconds sends the selected key/chord or mouse click
once, keeping the previous short press/release timing. A wheel binding sends one
notch. Off prevents the timer from starting. There is no separate enable switch
or cursor-movement switch. Existing disabled settings migrate to Off; enabled
settings migrate to MOUSE_RIGHT. Ordinary taps and the existing Delay Left Click
settings are preserved. Cancelling, changing profiles, disabling input or losing
focus clears pending holds and releases any key/button owned by Long Press.

**Double Tap and Hold to Drag** reuses the original Touchpad test: the second
finger-down must occur less than 0.2 seconds after the first finger-down, within
300 points. Both mouse modes use the same test, without waiting to deliver a
single tap. Touchpad keeps the first left click held through the second touch
for the default MOUSE_LEFT binding. A custom key/chord or mouse button replaces
that hold; Off keeps ordinary clicks without holding an input for dragging.
Single Point keeps its absolute pointer motion and completes any delayed first
click before holding the selected second-touch input. Pending old click callbacks
cannot release the new drag. An active double-tap drag takes priority over Swipe
and Long Press. Lifting, another finger or cancellation releases its input.

## Input and persistence

- `StreamView` owns `StreamGestureController`. Its gesture recognizers can
  recognize together, accept direct finger touches on the stream surface, and
  exclude screen-edge menu gestures and on-screen controls. Recognition cancels
  the underlying mouse touches; cancellation never generates a click.
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
  rotation is clockwise, negative counterclockwise; both use the same binding.
  Either finger can act as the pivot. Zero-angle motion does not activate
  rotation. Touch changes or coincident fingers rebase the vector to prevent
  angle jumps. Existing sensitivity units are preserved.
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
- The v1.4 model adds unified rotation and the default-on Single Point double-tap
  switch. Equal old rotation bindings (including Off) are retained; conflicting
  bindings become MOUSE_MIDDLE. Either old cursor switch enables the unified
  cursor switch. Legacy attributes remain in the model for migration. Tests
  migrate real v1.1/v1.2/v1.3 SQLite stores using the application's initializer,
  and verify later edits and independent switches survive reopening.
- The v1.5 model renames the Single Point switch to long-press right click using
  Core Data's renaming identifier, preserving both On and Off from v1.4. Tests
  also cover direct migration from v1.1/v1.2/v1.3, the default for a fresh install,
  both switch states after reopening, and preservation of existing rotation settings.
- The v1.6 model adds the optional longPressAction binding. Its one-time
  initializer converts the v1.5 switch to MOUSE_RIGHT or NONE and defaults fresh
  installs to MOUSE_RIGHT. Legacy cursor fields remain only for compatibility;
  runtime cursor policy is fixed to Swipe/Rotation on and Pinch off. Migration
  tests cover v1.1 through v1.5, custom keyboard/mouse bindings, Off and reopening.
- The v1.7 model adds doubleTapDragAction, defaulting to MOUSE_LEFT. Migration
  tests upgrade actual SQLite stores from v1.1 through v1.6 and verify custom
  bindings, Off, reopening, and preservation of every previous gesture setting.
- Legacy delayed tap callbacks are invalidated when a gesture takes over.
  Gesture presses run after UIKit has cancelled old touches so a stale mouse
  release cannot interrupt the new drag. The swipe recognizer delays ordinary
  touch delivery until it knows whether the movement is a swipe only when
  Single Point has both Long Press and Double Tap Drag Off. Otherwise touch down arrives immediately
  so the existing hold timer and double-tap test can run. A recognized swipe still cancels the hold
  before sending its binding. The hold timer runs in common run-loop modes so
  scroll-view touch tracking does not suspend it. Other taps still reach the
  original handler when recognition fails.
- The Drawing Toolkit is included. Pencil runtime, settings and editors no
  longer consult StoreKit or reset settings after an interrupted purchase.
  Hardware/OS requirements for specific Pencil interactions still apply.

## Verification

Run `bash BuildScripts/test-gestures.sh` on a machine with Swift. This executes
the actual engine against an event recorder and checks held keys, reversal,
overlapping chords, modifier ordering, idle release, proportional duration,
fractional scrolling, mouse/mixed chords, continuous drag through pauses,
centroid movement, full clockwise/counterclockwise twist, angle-boundary reversal,
finger-spacing and sample-rate independence, sensitivity, touch-set changes,
fractional cursor motion and invalid input.
GitHub Actions runs it before archiving
the iOS app and uploading `VoidLink-unsigned.ipa`.

Device acceptance: exercise pinch/rotation together, reverse direction, lift one
finger, add a third finger, open settings, background the app, disconnect, change
bindings, and restart. Check native/relative/absolute modes, ordinary two-finger
scrolling, widget/edge gestures, and a fresh install with no purchase receipt.
Also check Swipe + MOUSE_MIDDLE, W+D, mixed chords,
simultaneous pinch/rotation with the same button, full circles in both directions,
vertical hand translation during rotation (vertical mouse motion with unchanged yaw),
and taps/double taps when Swipe is Off and when it is enabled. In Single Point,
verify taps no longer wait for a second tap or turn into a right click, and that
a stationary 0.65-second hold sends the selected click/chord exactly once, with
no action when Off. Verify all four Move Cursor switches are absent, Swipe and
Rotation always move, Pinch never continuously moves, and pinch/rotation teleport
once to the initial midpoint before sending the selected action.
Check that movement, a second finger, lift and gesture cancellation stop the hold.
Repeat with Swipe + MOUSE_RIGHT: a stationary hold must
click without lifting; movement before the deadline must start only the swipe
binding and must not generate another right click at the hold deadline.
Test dragging and long press with Delay Left Click both On and Off.
The IPA is unsigned and must be signed for installation on an iOS device.
The gesture tests load the actual CommandManager key map and verify that every
existing key name still works, along with symbol parsing, F1-F24, modifier
ordering, plus/minus reversal, cancellation and overlapping Shift ownership.

LongPressActionTests compiles the actual action bridge with a recording transport
and checks mouse buttons, keyboard chords, wheel notches, Off and cleanup. Anchor
tests cover original positions, shared midpoint, cancellation and new touch sets.

Double-tap tests exercise the shared original time/distance limits, immediate
first-click output, uninterrupted default left drag, custom keyboard/mouse holds,
Off and cancellation. The Single Point handoff test compiles the actual delayed
click methods and verifies that neither a pending click nor a stale release can
interrupt the drag. On device, test both mouse modes with Swipe mapped and Off,
Double Tap Drag mapped and Off, plus Delay Left Click enabled/disabled; Native
and Disabled must show only their allowed settings and must not emit custom gestures.
