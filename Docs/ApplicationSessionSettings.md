# Settings during a stream

Opening Settings from the edge of the stream uses overrides for that host UUID
and application ID. The main application's Settings still edits the shared
defaults. Existing installations need no database migration.

The existing collapse button saves all session-editable settings, including
Touch Control, gesture assignments and the Settings-owned OSC/Pencil controls.
Codec, HDR, YUV 4:4:4, frame pacing, async dequeue, renderer and other
connection-only options remain shared. Widget layout persistence is unchanged.

Video Resolution, Custom Resolution and Frame Rate are available in the session
sidebar. Changing effective width, height or FPS reconnects to the same running
application after the old transport has fully stopped. Other edits use the
existing live update path. Closing an unchanged resolution selector does not
recalculate the stream size from a newly rotated window.

The ellipsis menu contains **Restore Defaults** only during a stream. It removes
the current application's override and displays the main settings. Collapse the
sidebar to apply them; reconnection is needed only if resolution or FPS changes.
Subsequent main-settings changes are inherited until another app override is saved.

`BuildScripts/test-app-settings.sh` checks persistence, host/app isolation,
restoring shared defaults, reconnect decisions, the real DataManager methods
against Core Data, and waiting for connection termination before reconnecting.
