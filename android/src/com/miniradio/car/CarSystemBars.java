package com.miniradio.car;

import android.app.Activity;
import android.os.Build;
import android.util.Log;
import android.view.View;
import android.view.ViewTreeObserver;
import android.view.WindowManager;
import android.widget.FrameLayout;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

/** E28 reports zero Android insets for its native side Dock and bottom controls. */
final class CarSystemBars implements ViewTreeObserver.OnPreDrawListener {
    private static final String TAG = "CarSystemBars";
    private static final int DOCK_SIZE = 120, HIDDEN_BAR_MASK = 0x3000;
    private final Activity activity;
    private final FrameLayout frame;
    private final View content;
    private final Field screenId, areaType, windowFlags;
    private final Method activityBars, managerBars;
    private final Object manager;
    private final int statusHeight, displayHeight;
    private final int[] position = new int[2];
    private String requestedArea;
    private boolean disabled;

    static CarSystemBars attach(Activity activity, FrameLayout frame, View content) {
        if (Build.VERSION.SDK_INT != 28 || !"E28".equalsIgnoreCase(Build.MODEL)) return null;
        android.view.Display.Mode mode = activity.getWindowManager().getDefaultDisplay().getMode();
        if (mode.getPhysicalWidth() != 2400 || mode.getPhysicalHeight() != 1200) return null;
        try {
            return new CarSystemBars(activity, frame, content, mode.getPhysicalHeight());
        } catch (ReflectiveOperationException | RuntimeException error) {
            Log.w(TAG, "Native system bars unavailable: " + error.getClass().getSimpleName());
            return null;
        }
    }

    private CarSystemBars(Activity activity, FrameLayout frame, View content, int displayHeight)
            throws ReflectiveOperationException {
        this.activity = activity; this.frame = frame; this.content = content; this.displayHeight = displayHeight;
        screenId = WindowManager.LayoutParams.class.getField("screenId");
        areaType = WindowManager.LayoutParams.class.getField("areaType");
        windowFlags = WindowManager.LayoutParams.class.getField("windowFlags");
        activityBars = Activity.class.getMethod("setSystemBarVisibility", int.class, int.class);
        Class<?> factory = Class.forName("com.xiaopeng.screen.ScreenTaskManagerFactory");
        manager = factory.getMethod("get").invoke(null);
        managerBars = factory.getMethod("setSystemBarVisibility", int.class, int.class, int.class);
        int id = activity.getResources().getIdentifier("status_bar_height", "dimen", "android");
        statusHeight = id == 0 ? 0 : activity.getResources().getDimensionPixelSize(id);
        frame.getViewTreeObserver().addOnPreDrawListener(this);
    }

    private String area() throws ReflectiveOperationException {
        if (screenId.getInt(activity.getWindow().getAttributes()) != 0) return null;
        String value = (String) areaType.get(activity.getWindow().getAttributes());
        return "primary".equals(value) || "secondary".equals(value) || "logical".equals(value)
            || "physical".equals(value) || "immersion".equals(value) ? value : null;
    }

    void showBars(boolean force) {
        // The vendor manager acts on the focused window, including when a dialog is open.
        if (disabled || !activity.hasWindowFocus()) return;
        try {
            String area = area();
            if (area == null) return;
            boolean hidden = (windowFlags.getInt(activity.getWindow().getAttributes()) & HIDDEN_BAR_MASK) != 0;
            if (hidden) activityBars.invoke(activity, -1, View.VISIBLE);
            if (!force && !hidden && area.equals(requestedArea)) return;
            activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);
            activity.getWindow().getDecorView().setSystemUiVisibility(
                activity.getResources().getBoolean(R.bool.radio_light_system_bars)
                    ? View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR | View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR
                    : View.SYSTEM_UI_FLAG_VISIBLE);
            managerBars.invoke(manager, 0, 2000, View.VISIBLE);
            managerBars.invoke(manager, 0, 2019, View.VISIBLE);
            requestedArea = area;
        } catch (ReflectiveOperationException | RuntimeException error) {
            disable(error);
        }
    }

    @Override public boolean onPreDraw() {
        showBars(false);
        if (disabled) return true;
        try {
            if (area() == null || frame.getWidth() == 0 || frame.getHeight() == 0) return true;
            frame.getLocationOnScreen(position);
            // Intersections avoid reserving the Dock twice in a split window.
            int left = Math.max(0, Math.min(frame.getWidth(), DOCK_SIZE - position[0]));
            int top = Math.max(0, Math.min(frame.getHeight(), statusHeight - position[1]));
            int bottom = Math.max(0, Math.min(frame.getHeight(),
                position[1] + frame.getHeight() - (displayHeight - DOCK_SIZE)));
            frame.setBackgroundColor(activity.getColor(R.color.radio_system_bar));
            FrameLayout.LayoutParams layout = (FrameLayout.LayoutParams) content.getLayoutParams();
            if (layout.leftMargin == left && layout.topMargin == top && layout.bottomMargin == bottom) return true;
            layout.setMargins(left, top, 0, bottom);
            content.setLayoutParams(layout);
            return false;
        } catch (ReflectiveOperationException | RuntimeException error) {
            disable(error);
            return true;
        }
    }

    private void disable(Exception error) {
        disabled = true;
        Log.w(TAG, "Native system bars unavailable: " + error.getClass().getSimpleName());
    }

    void close() {
        if (frame.getViewTreeObserver().isAlive()) frame.getViewTreeObserver().removeOnPreDrawListener(this);
    }
}
