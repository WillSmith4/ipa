#pragma once

// Queue an immutable cursor position on the mouse channel, preserving its
// order relative to button events. Used only by the Single Point swipe drag.
int LiSendMousePositionEventOrdered(short x, short y, short width, short height);
