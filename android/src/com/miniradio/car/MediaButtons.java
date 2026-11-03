package com.miniradio.car;

import android.view.KeyEvent;

final class MediaButtons {
    interface Navigation { void skip(int direction); }

    static boolean handle(KeyEvent event, Navigation navigation) {
        if (event == null) return false;
        int key = event.getKeyCode();
        int direction;
        if (key == KeyEvent.KEYCODE_MEDIA_NEXT || key == KeyEvent.KEYCODE_MEDIA_SKIP_FORWARD) direction = 1;
        else if (key == KeyEvent.KEYCODE_MEDIA_PREVIOUS || key == KeyEvent.KEYCODE_MEDIA_SKIP_BACKWARD) direction = -1;
        else return false;
        // Consume the whole press, but act once. A held key must not skip multiple stations.
        if (event.getAction() == KeyEvent.ACTION_DOWN && event.getRepeatCount() == 0 && !event.isCanceled()) navigation.skip(direction);
        return true;
    }

    static int adjacentIndex(int current, int size, int direction) {
        if (size <= 0) return -1;
        if (current < 0 || current >= size) return direction < 0 ? size - 1 : 0;
        return Math.floorMod(current + (direction < 0 ? -1 : 1), size);
    }
}
