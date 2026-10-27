#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "Input.h"

// Exercise the production queueing functions and absolute send-thread branch.
// Leave the sender stopped until the entire fast swipe has been queued.
#define BE16(x) (x)
#define BE32(x) (x)
#define LE32(x) (x)
#define CLAMP(x, lo, hi) ((x) < (lo) ? (lo) : (x) > (hi) ? (hi) : (x))
#define LC_ASSERT assert
#define Limelog(...) ((void)0)
#define LBQ_SUCCESS 0
#define LBQ_BOUND_EXCEEDED 1
#define CTRL_CHANNEL_MOUSE 3
#define ENET_PACKET_FLAG_RELIABLE 1
#define MOUSE_BATCHING_INTERVAL_MS 1
typedef int LINKED_BLOCKING_QUEUE_ENTRY;
#include "MousePacketHolder.inc"

static bool initialized = true, failAllocation;
static int packetQueue, batchedInputMutex, AppVersionQuad[] = {7};
static float absCurrentPosX, absCurrentPosY;
static struct { int x, y, width, height; bool dirty; } currentAbsoluteMouseState;
static PPACKET_HOLDER queue[32];
static int queueCount, freed;
static uint64_t lastMousePacketTime;
static void PltLockMutex(int *m) { (void)m; }
static void PltUnlockMutex(int *m) { (void)m; }
static uint64_t PltGetMillis(void) { return 100; }
static void PltSleepMs(int ms) { (void)ms; }
static void flushInputOnControlStream(void) {}
static PPACKET_HOLDER allocatePacketHolder(int extra) {
    (void)extra;
    PPACKET_HOLDER holder = failAllocation ? NULL : malloc(sizeof(*holder));
    if (holder) memset(holder, 0xff, sizeof(*holder)); // reused memory is not zeroed
    return holder;
}
static void freePacketHolder(PPACKET_HOLDER holder) { freed++; free(holder); }
static int LbqOfferQueueItem(int *q, PPACKET_HOLDER holder, int *entry) {
    (void)q; (void)entry;
    if (queueCount == 32) return LBQ_BOUND_EXCEEDED;
    queue[queueCount++] = holder;
    return LBQ_SUCCESS;
}
#include "MousePositionMethods.inc"

static void prepare(PPACKET_HOLDER holder) {
    if (false) {}
    #include "MousePositionSendBranch.inc"
}
static bool moreDataSent;
static int LbqGetItemCount(int *q) { (void)q; return queueCount; }
static bool sendInputPacket(PPACKET_HOLDER holder, bool moreData) {
    (void)holder; moreDataSent = moreData; return true;
}
static void sendPrepared(PPACKET_HOLDER holder) {
    #include "MousePositionFlush.inc"
}
static void position(int index, int x, int y) {
    PPACKET_HOLDER holder = queue[index];
    prepare(holder);
    assert(holder->channelId == CTRL_CHANNEL_MOUSE);
    assert(holder->enetPacketFlags == ENET_PACKET_FLAG_RELIABLE);
    assert(holder->packet.header.magic == MOUSE_MOVE_ABS_MAGIC);
    assert(holder->packet.mouseMoveAbs.x == x && holder->packet.mouseMoveAbs.y == y);
    assert(holder->packet.mouseMoveAbs.width == 999 && holder->packet.mouseMoveAbs.height == 799);
    assert(holder->packet.mouseMoveAbs.unused == 0);
    sendPrepared(holder);
    assert(moreDataSent == !holder->absolutePositionIsOrdered);
}
static void reset(void) {
    for (int i = 0; i < queueCount; i++) freePacketHolder(queue[i]);
    queueCount = 0;
    memset(&currentAbsoluteMouseState, 0, sizeof(currentAbsoluteMouseState));
}

int main(void) {
    // Reproduce the bug: the later move replaces the origin before button down.
    LiSendMousePositionEvent(100, 200, 1000, 800);
    LiSendMouseButtonEvent(7, 3);
    LiSendMousePositionEvent(160, 250, 1000, 800);
    assert(queueCount == 2);
    position(0, 160, 250); // original point (100,200) was lost
    reset();

    for (int button = 1; button <= 3; button++) {
        // An earlier legacy move must not absorb either swipe position.
        LiSendMousePositionEvent(10, 20, 1000, 800);
        LiSendMousePositionEventOrdered(100, 200, 1000, 800);
        LiSendMouseButtonEvent(7, button);
        LiSendMousePositionEventOrdered(160, 250, 1000, 800);
        LiSendMousePositionEventOrdered(180, 290, 1000, 800);
        LiSendMouseButtonEvent(8, button);
        assert(queueCount == 6);
        position(0, 10, 20);
        position(1, 100, 200);
        assert(queue[2]->packet.header.magic == MOUSE_BUTTON_DOWN_EVENT_MAGIC_GEN5);
        assert(queue[2]->packet.mouseButton.button == button);
        position(3, 160, 250);
        position(4, 180, 290);
        assert(queue[5]->packet.header.magic == MOUSE_BUTTON_UP_EVENT_MAGIC_GEN5);
        assert(queue[5]->packet.mouseButton.button == button);
        assert(absCurrentPosX == 180 / 999.0f && absCurrentPosY == 290 / 799.0f);
        reset();
    }
    initialized = false;
    assert(LiSendMousePositionEventOrdered(1, 1, 1000, 800) == -2);
    initialized = true;
    assert(LiSendMousePositionEventOrdered(1, 1, 1, 800) == -1);
    failAllocation = true;
    assert(LiSendMousePositionEventOrdered(1, 1, 1000, 800) == -1);
    failAllocation = false;
    for (int i = 0; i < 32; i++) assert(LiSendMousePositionEventOrdered(i, i, 1000, 800) == 0);
    int before = freed;
    assert(LiSendMousePositionEventOrdered(1, 1, 1000, 800) == LBQ_BOUND_EXCEEDED);
    assert(freed == before + 1);
    reset();
    puts("Single Point swipe: origin, button down, absolute drag, release retain order; legacy batching unchanged");
}
