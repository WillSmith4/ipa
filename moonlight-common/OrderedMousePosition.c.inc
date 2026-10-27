// Included in the input stream translation unit; no separate queue or thread.
int LiSendMousePositionEventOrdered(short x, short y, short width, short height) {
    if (!initialized) return -2;
    if (width <= 1 || height <= 1) return -1;
    PPACKET_HOLDER holder = allocatePacketHolder(0);
    if (holder == NULL) return -1;

    holder->channelId = CTRL_CHANNEL_MOUSE;
    holder->enetPacketFlags = ENET_PACKET_FLAG_RELIABLE;
    holder->absolutePositionIsOrdered = true;
    holder->packet.mouseMoveAbs.header.size = BE32(sizeof(NV_ABS_MOUSE_MOVE_PACKET) - sizeof(uint32_t));
    holder->packet.mouseMoveAbs.header.magic = LE32(MOUSE_MOVE_ABS_MAGIC);
    holder->packet.mouseMoveAbs.unused = 0;
    holder->packet.mouseMoveAbs.x = BE16(x);
    holder->packet.mouseMoveAbs.y = BE16(y);
    holder->packet.mouseMoveAbs.width = BE16(width - 1);
    holder->packet.mouseMoveAbs.height = BE16(height - 1);

    int err = LbqOfferQueueItem(&packetQueue, holder, &holder->entry);
    if (err != LBQ_SUCCESS) {
        freePacketHolder(holder);
        return err;
    }
    absCurrentPosX = CLAMP(x, 0, width - 1) / (float)(width - 1);
    absCurrentPosY = CLAMP(y, 0, height - 1) / (float)(height - 1);
    return 0;
}
