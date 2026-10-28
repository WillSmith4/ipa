# Settings and application Game Profiles

The in-session sidebar uses the same settings as the main menu, as before
application overrides were introduced. Its collapse button closes the sidebar
and uses the original shared-settings/live-update path. Resolution, custom
resolution and frame rate are hidden during streaming. Restore Defaults and
settings-driven reconnection have been removed. Old per-app settings snapshots
are ignored; they are not converted into Game Profiles.

To assign an existing Game Profile, hold it in Game Profiles, tap outside with
another finger, navigate to a host and Applications, and drop it on an app tile.
The native iOS drag preview remains above the interface. Dropping inside the
profile list still reorders profiles; Default remains first. Controller reorder
is unchanged. Dropping another profile on the same app overwrites its assignment.

Assignments store only the stable profile identifier under a key made from the
trimmed/lowercase host UUID and trimmed app ID, each base64-encoded separately.
Renaming, reordering or editing the existing profile preserves the assignment.
Duplicates and imported copies receive their own identifiers. A missing/deleted
profile falls back to the current profile and clears its stale assignment.
Unassigned apps keep the original current-profile selection behavior.

When starting an assigned app, VoidLink selects that existing Game Profile
before constructing the stream. The profile's existing widget layout and
settings marked with a gamepad icon apply; no general settings are copied into
an app-specific record. Edits to that shared Game Profile also affect other apps
assigned to it.

Existing profile files (raw archives and compressed VLPR .bin exports) can be
dropped from Files into the profile list to import them. Dropping a file on an
app tile imports it and assigns it to that host/app. For an export containing
multiple profiles, all are imported and the exported selected profile is
assigned (or the first profile if the export has no selected profile). Import
and Export buttons remain available. Invalid files do not modify the collection.

`BuildScripts/test-app-settings.sh` checks assignment isolation/persistence,
shared Core Data settings, stable profile identity, import validation and
activation using the production persistence methods. Existing gesture,
localization, shortcut and status-bar tests remain in the macOS build workflow.
The multi-finger drag across Hosts/Applications also requires an iPad UI check.
