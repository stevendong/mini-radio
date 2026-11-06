package com.miniradio.car;

import android.app.AlertDialog;
import android.content.Context;
import android.graphics.Typeface;
import android.widget.Button;
import android.widget.TextView;

/** Explicit title/button colors also cover vendor widgets with fixed day colors. */
final class RadioDialogs {
    static AlertDialog.Builder builder(Context context, String title) {
        TextView heading = new TextView(context);
        heading.setText(title); heading.setTextSize(24); heading.setTypeface(null, Typeface.BOLD);
        heading.setTextColor(context.getColor(R.color.radio_foreground));
        float density = context.getResources().getDisplayMetrics().density;
        heading.setPadding(Math.round(24 * density), Math.round(20 * density),
            Math.round(24 * density), Math.round(12 * density));
        return new AlertDialog.Builder(context, R.style.RadioDialog).setCustomTitle(heading);
    }

    static void show(AlertDialog dialog) {
        dialog.show();
        int color = dialog.getContext().getColor(R.color.radio_accent);
        for (int which : new int[]{AlertDialog.BUTTON_POSITIVE, AlertDialog.BUTTON_NEGATIVE, AlertDialog.BUTTON_NEUTRAL}) {
            Button button = dialog.getButton(which);
            if (button != null) button.setTextColor(color);
        }
    }
}
