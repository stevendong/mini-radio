package com.miniradio.car;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.text.InputType;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.TextView;
import android.widget.Toast;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public final class MainActivity extends Activity {
    private static final int BG = Color.rgb(16, 27, 34), CARD = Color.rgb(25, 42, 50),
        MINT = Color.rgb(103, 226, 195), WHITE = Color.rgb(235, 243, 245), MUTED = Color.rgb(153, 175, 185);
    private final Handler handler = new Handler();
    private final ExecutorService network = Executors.newFixedThreadPool(2);
    private final RadioDirectory api = new RadioDirectory();
    private final List<Station> found = new ArrayList<>(), rows = new ArrayList<>();
    private final List<Button> tabs = new ArrayList<>();
    private Future<?> pending;
    private int tab, generation, offset, seenVersion = -1;
    private boolean loading, more = true, destroyed;
    private String query = "", country = "", notice = "目录由 Radio Browser 提供";
    private TextView title, detail, playbackStatus, footer;
    private Button play, favorite, region, loadMore;
    private EditText search;
    private StationAdapter adapter;
    private RadioService previousService;
    private CarSystemBars systemBars;
    private final Runnable tick = new Runnable() {
        @Override public void run() {
            RadioService service = RadioService.current;
            if (service != null) {
                if (service != previousService) {
                    previousService = service; seenVersion = -1;
                    if (found.isEmpty()) { found.addAll(service.directory); refreshRows(); }
                }
                if (service.version != seenVersion) { seenVersion = service.version; renderPlayer(); refreshRows(); }
            }
            handler.postDelayed(this, 400);
        }
    };

    @Override public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setVolumeControlStream(android.media.AudioManager.STREAM_MUSIC);
        android.content.SharedPreferences browsing = getSharedPreferences("radio-browsing", MODE_PRIVATE);
        tab = browsing.getInt("tab", StationQueue.DISCOVER); query = browsing.getString("query", "");
        country = browsing.getString("country", "");
        if (savedInstanceState != null) {
            tab = savedInstanceState.getInt("tab"); query = savedInstanceState.getString("query", "");
            country = savedInstanceState.getString("country", "");
        }
        startService(new Intent(this, RadioService.class));
        build(); fetch(false);
    }
    @Override protected void onResume() { super.onResume(); handler.post(tick); }
    @Override public void onWindowFocusChanged(boolean focused) {
        super.onWindowFocusChanged(focused);
        if (focused && systemBars != null) systemBars.showBars(true);
    }
    @Override public boolean dispatchKeyEvent(KeyEvent event) {
        // Some head units inject media keys into the foreground window instead of MediaSession.
        RadioService service = RadioService.current;
        if (service != null && service.handleMediaButton(event)) return true;
        return super.dispatchKeyEvent(event);
    }
    @Override protected void onPause() { handler.removeCallbacks(tick); super.onPause(); }
    @Override protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out); out.putInt("tab", tab); out.putString("query", query); out.putString("country", country);
    }
    @Override public void onConfigurationChanged(Configuration configuration) {
        super.onConfigurationChanged(configuration); build(); renderPlayer(); refreshRows();
    }
    @Override public void onDestroy() {
        if (systemBars != null) systemBars.close();
        destroyed = true; generation++; handler.removeCallbacksAndMessages(null); network.shutdownNow(); super.onDestroy();
    }

    // Low-density head units otherwise render phone-sized controls unusually small.
    private float scale() { return getResources().getDisplayMetrics().density < 1.25f ? 1.3f : 1f; }
    private int dp(float value) { return Math.round(value * getResources().getDisplayMetrics().density * scale()); }
    private LinearLayout column() { LinearLayout view = new LinearLayout(this); view.setOrientation(LinearLayout.VERTICAL); return view; }
    private LinearLayout row() { LinearLayout view = new LinearLayout(this); view.setGravity(Gravity.CENTER_VERTICAL); return view; }
    private GradientDrawable rounded(int color, int radius) {
        GradientDrawable drawable = new GradientDrawable(); drawable.setColor(color); drawable.setCornerRadius(dp(radius)); return drawable;
    }
    private TextView text(String value, int size, int color) {
        TextView view = new TextView(this); view.setText(value); view.setTextSize(size * scale()); view.setTextColor(color);
        view.setGravity(Gravity.CENTER_VERTICAL); return view;
    }
    private Button button(String label, boolean primary, Runnable action) {
        Button view = new Button(this); view.setText(label); view.setTextSize(18 * scale()); view.setAllCaps(false);
        view.setTextColor(primary ? BG : WHITE); view.setBackground(rounded(primary ? MINT : CARD, 16));
        view.setMinHeight(dp(64)); view.setMinimumWidth(0); view.setMinWidth(0);
        view.setPadding(dp(14), dp(4), dp(14), dp(4));
        view.setContentDescription(label); view.setOnClickListener(v -> action.run());
        return view;
    }
    private LinearLayout.LayoutParams weight(float value, int height) { return new LinearLayout.LayoutParams(0, height < 0 ? height : dp(height), value); }
    private void gap(LinearLayout parent, int width, int height) { parent.addView(new View(this), new LinearLayout.LayoutParams(dp(width), dp(height))); }

    private void build() {
        if (systemBars != null) systemBars.close();
        LinearLayout root = column(); root.setPadding(dp(24), dp(12), dp(24), dp(16)); root.setBackgroundColor(BG);
        FrameLayout frame = new FrameLayout(this);
        frame.addView(root, new FrameLayout.LayoutParams(-1, -1));
        setContentView(frame);
        systemBars = CarSystemBars.attach(this, frame, root);
        LinearLayout header = row();
        TextView brand = text("MINI RADIO  /  听见远方", 22, WHITE); brand.setTypeface(null, Typeface.BOLD);
        header.addView(brand, weight(1, 64));
        header.addView(button("＋ 添加", false, this::addStation), new LinearLayout.LayoutParams(dp(112), dp(60)));
        gap(header, 10, 1);
        header.addView(button("更多", false, this::menu), new LinearLayout.LayoutParams(dp(88), dp(60)));
        root.addView(header); gap(root, 1, 16);
        LinearLayout body = new LinearLayout(this);
        boolean wide = getResources().getConfiguration().screenWidthDp / scale() >= 1200;
        body.setOrientation(wide ? LinearLayout.HORIZONTAL : LinearLayout.VERTICAL);
        root.addView(body, new LinearLayout.LayoutParams(-1, 0, 1));
        LinearLayout player = playerCard(wide);
        if (wide) {
            body.addView(player, new LinearLayout.LayoutParams(0, -1, 0.39f)); gap(body, 24, 1);
        } else {
            int height = getResources().getConfiguration().screenHeightDp;
            body.addView(player, new LinearLayout.LayoutParams(-1, dp(height < 650 ? 210 : 280))); gap(body, 1, 16);
        }
        LinearLayout browser = column();
        body.addView(browser, wide ? new LinearLayout.LayoutParams(0, -1, 0.61f) : new LinearLayout.LayoutParams(-1, 0, 1));
        LinearLayout navigation = row(); tabs.clear();
        String[] names = {"发现", "收藏", "最近"};
        for (int i = 0; i < names.length; i++) {
            final int index = i;
            Button item = button(names[i], tab == i, () -> { tab = index; refreshRows(); });
            tabs.add(item); navigation.addView(item, weight(1, 60)); gap(navigation, 8, 1);
        }
        region = button(country.isEmpty() ? "全球 ▾" : country + " ▾", false, this::countries);
        navigation.addView(region, new LinearLayout.LayoutParams(dp(112), dp(60))); browser.addView(navigation);
        gap(browser, 1, 12);
        LinearLayout searchRow = row();
        search = new EditText(this); search.setText(query); search.setTextSize(18 * scale()); search.setTextColor(WHITE);
        search.setHintTextColor(MUTED); search.setHint("搜索电台名称"); search.setSingleLine(true);
        search.setPadding(dp(18), 0, dp(12), 0); search.setBackground(rounded(CARD, 14)); search.setImeOptions(EditorInfo.IME_ACTION_SEARCH);
        search.setOnEditorActionListener((v, action, event) -> { if (action == EditorInfo.IME_ACTION_SEARCH) { doSearch(); return true; } return false; });
        searchRow.addView(search, weight(1, 60)); gap(searchRow, 10, 1);
        searchRow.addView(button("搜索", false, this::doSearch), new LinearLayout.LayoutParams(dp(92), dp(60)));
        browser.addView(searchRow); gap(browser, 1, 12);
        ListView list = new ListView(this); list.setDivider(null); list.setCacheColorHint(Color.TRANSPARENT);
        list.setClipToPadding(false); list.setPadding(0, 0, 0, dp(8));
        loadMore = button("加载更多电台", false, () -> fetch(true)); list.addFooterView(loadMore, null, true);
        adapter = new StationAdapter(); list.setAdapter(adapter);
        list.setOnItemClickListener((parent, view, position, id) -> { if (position < rows.size()) use(service -> service.play(rows.get(position))); });
        browser.addView(list, new LinearLayout.LayoutParams(-1, 0, 1));
        footer = text(notice, 14, MUTED); footer.setMaxLines(2); browser.addView(footer, new LinearLayout.LayoutParams(-1, dp(44)));
        renderPlayer(); refreshRows();
    }

    private LinearLayout playerCard(boolean wide) {
        LinearLayout card = column(); card.setPadding(dp(24), dp(18), dp(24), dp(18)); card.setBackground(rounded(CARD, 24));
        TextView caption = text("●  LIVE RADIO", 14, MINT); caption.setLetterSpacing(0.12f); card.addView(caption);
        if (wide) card.addView(new DialView(), new LinearLayout.LayoutParams(-1, 0, 1));
        title = text("把日常，调到另一座城市。", wide ? 32 : 26, WHITE); title.setTypeface(null, Typeface.BOLD);
        title.setMaxLines(2); title.setEllipsize(TextUtils.TruncateAt.END);
        card.addView(title, new LinearLayout.LayoutParams(-1, 0, wide ? 0.28f : 1));
        detail = text("一段旋律，一扇通往远方的小窗。", 16, MUTED); detail.setSingleLine(true); detail.setEllipsize(TextUtils.TruncateAt.END); card.addView(detail);
        playbackStatus = text("选择电台，听见远方", 16, MINT); card.addView(playbackStatus, new LinearLayout.LayoutParams(-1, dp(36)));
        LinearLayout controls = row();
        play = button("▶ 播放", true, () -> use(service -> { if (service.active()) service.pause(); else service.resume(); }));
        controls.addView(play, weight(1.15f, 64)); gap(controls, 10, 1);
        controls.addView(button("下一站", false, () -> use(service -> service.next(1))), weight(1, 64)); gap(controls, 10, 1);
        favorite = button("☆ 收藏", false, () -> use(service -> { if (service.station != null) service.toggleFavorite(service.station); }));
        controls.addView(favorite, weight(1, 64)); card.addView(controls);
        if (wide) {
            gap(card, 1, 16);
            card.addView(button("随心漫游  ↗", false, () -> use(RadioService::shuffle)), new LinearLayout.LayoutParams(-1, dp(64)));
            TextView note = text("音量使用车机或方向盘控制", 14, MUTED); card.addView(note, new LinearLayout.LayoutParams(-1, dp(44)));
        }
        return card;
    }

    private interface Action { void run(RadioService service); }
    private void use(Action action) {
        RadioService service = RadioService.current;
        if (service != null) { action.run(service); renderPlayer(); refreshRows(); }
        else Toast.makeText(this, "播放器正在启动，请稍后重试", Toast.LENGTH_SHORT).show();
    }
    private void renderPlayer() {
        RadioService service = RadioService.current;
        if (service == null || title == null) return;
        Station station = service.station;
        title.setText(station == null ? "把日常，调到另一座城市。" : station.name);
        detail.setText(station == null ? "一段旋律，一扇通往远方的小窗。" : station.detail());
        playbackStatus.setText(service.status);
        play.setText(service.active() ? "Ⅱ 暂停" : "▶ 播放"); play.setContentDescription(service.active() ? "暂停" : "播放");
        favorite.setText(station != null && service.store.isFavorite(station) ? "★ 已收藏" : "☆ 收藏");
        favorite.setContentDescription(station != null && service.store.isFavorite(station) ? "取消收藏" : "收藏当前电台");
    }
    private void refreshRows() {
        if (adapter == null) return;
        RadioService service = RadioService.current;
        rows.clear();
        List<Station> source = tab == 0 ? found : service == null ? new ArrayList<>() : tab == 1 ? service.store.favorites : service.store.recent;
        for (Station station : source) {
            if (tab == 0 || station.name.toLowerCase(java.util.Locale.ROOT).contains(query.toLowerCase(java.util.Locale.ROOT))) rows.add(station);
        }
        if (service != null) {
            service.setBrowseContext(tab, query, country, rows);
            rows.clear(); rows.addAll(service.queue.stations);
        }
        for (int i = 0; i < tabs.size(); i++) {
            tabs.get(i).setBackground(rounded(i == tab ? MINT : CARD, 16)); tabs.get(i).setTextColor(i == tab ? BG : WHITE);
        }
        adapter.notifyDataSetChanged();
        loadMore.setVisibility(tab == 0 && more && !found.isEmpty() ? View.VISIBLE : View.GONE);
        loadMore.setEnabled(!loading); loadMore.setText(loading ? "正在加载…" : "加载更多电台");
        String message = tab == 0 ? (loading ? "正在寻找电台…" : rows.size() + " 个电台 · " + notice) : rows.isEmpty()
            ? (tab == 1 ? "点亮星标，将喜欢的电台留在这里。" : "成功播放的电台会出现在这里。") : rows.size() + " 个电台";
        footer.setText(message + (service != null && service.sync != null ? "\n" + service.sync.status : ""));
    }
    private void doSearch() {
        query = search.getText().toString().trim();
        ((InputMethodManager) getSystemService(INPUT_METHOD_SERVICE)).hideSoftInputFromWindow(search.getWindowToken(), 0);
        search.clearFocus(); if (tab == 0) fetch(false); else refreshRows();
    }
    private void fetch(boolean append) {
        if (append && loading) return;
        if (pending != null) pending.cancel(true);
        int request = ++generation;
        String name = query, code = country, key = query + "|" + country;
        if (!append) {
            offset = 0; more = true; found.clear();
            RadioService service = RadioService.current;
            if (service != null) found.addAll(service.store.cache(key));
            if (found.isEmpty()) { found.addAll(RadioDirectory.starters(name, code)); more = false; }
        }
        loading = true; refreshRows();
        int start = offset;
        pending = network.submit(() -> {
            try {
                RadioDirectory.Page page = api.search(name, code, start);
                List<Station> result = page.stations;
                handler.post(() -> {
                    if (destroyed || request != generation) return;
                    if (!append) found.clear();
                    java.util.Set<String> ids = new java.util.HashSet<>(); for (Station item : found) ids.add(item.id);
                    for (Station item : result) if (ids.add(item.id)) found.add(item);
                    offset = start + page.count; more = page.count == 60; loading = false;
                    notice = result.isEmpty() && !append ? "没有匹配的电台，试试其他名称或地区。" : "目录由 Radio Browser 提供";
                    RadioService service = RadioService.current;
                    if (service != null) {
                        service.directory.clear(); service.directory.addAll(found); service.store.cache(key, found);
                        service.notifyChildrenChanged("discover");
                    }
                    refreshRows();
                });
            } catch (Exception error) {
                handler.post(() -> {
                    if (destroyed || request != generation) return;
                    loading = false; notice = found.isEmpty() ? "目录连接失败，可刷新、播放收藏或添加直播地址。" : "目录暂不可用，显示本机缓存或预置电台。";
                    refreshRows();
                });
            }
        });
    }
    private void countries() {
        String[] names = {"全球电台", "中国", "美国", "英国", "日本", "德国", "法国", "加拿大", "澳大利亚"};
        String[] codes = {"", "CN", "US", "GB", "JP", "DE", "FR", "CA", "AU"};
        new AlertDialog.Builder(this).setTitle("选择电台地区").setItems(names, (dialog, which) -> {
            country = codes[which]; region.setText(country.isEmpty() ? "全球 ▾" : country + " ▾"); tab = 0; fetch(false);
        }).setNegativeButton("取消", null).show();
    }
    private void addStation() {
        LinearLayout form = column(); form.setPadding(dp(24), dp(12), dp(24), 0);
        EditText name = new EditText(this); name.setHint("电台名称"); name.setSingleLine(true); form.addView(name);
        EditText address = new EditText(this); address.setHint("https://… 直播地址"); address.setSingleLine(true);
        address.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI); form.addView(address);
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle("添加直播电台").setView(form)
            .setNegativeButton("取消", null).setPositiveButton("收藏并播放", null).create();
        dialog.setOnShowListener(v -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(button -> {
            Station station = Station.manual(name.getText().toString(), address.getText().toString());
            if (station == null) { address.setError("请输入有效的 HTTP 或 HTTPS 直播地址"); return; }
            use(service -> { service.toggleFavorite(station); service.play(station); }); dialog.dismiss();
        })); dialog.show();
    }
    private void menu() {
        new AlertDialog.Builder(this).setTitle("Mini Radio").setItems(new String[]{"收藏与收听同步", "刷新目录", "随心漫游", "睡眠定时", "停止播放", "数据来源与隐私"}, (dialog, which) -> {
            if (which == 0) syncSettings();
            else if (which == 1) { tab = 0; fetch(false); }
            else if (which == 2) use(RadioService::shuffle);
            else if (which == 3) new AlertDialog.Builder(this).setTitle("睡眠定时").setItems(new String[]{"关闭定时", "15 分钟", "30 分钟", "60 分钟", "90 分钟"}, (d, index) -> {
                int[] minutes = {0, 15, 30, 60, 90}; use(service -> service.setSleep(minutes[index]));
                Toast.makeText(this, index == 0 ? "已关闭定时" : "将在 " + minutes[index] + " 分钟后停止", Toast.LENGTH_SHORT).show();
            }).show();
            else if (which == 4) use(RadioService::stopPlayback);
            else new AlertDialog.Builder(this).setTitle("数据来源与隐私").setMessage("电台目录由 Radio Browser 提供，预置电台和音频来自各广播服务。\n\n收藏、最近收听和目录缓存保存在本机。启用同步后，收藏、取消收藏记录及最近收听通过 HTTPS 与所选服务同步。同步密钥由 Android Keystore 加密保存。直播服务会收到播放请求，无广告或分析 SDK。\n\nMini Radio 0.4.0 · Android 8.0+\ngithub.com/stevendong/mini-radio").setPositiveButton("知道了", null).show();
        }).show();
    }

    private void syncSettings() {
        RadioService service = RadioService.current; if (service == null || service.sync == null) return;
        SyncController sync = service.sync;
        LinearLayout form = column(); form.setPadding(dp(24), dp(12), dp(24), dp(12));
        TextView state = text(sync.status, 18, MINT); form.addView(state);
        EditText address = new EditText(this); address.setHint("HTTPS 同步服务地址"); address.setText(sync.server); address.setSingleLine(true);
        address.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI); form.addView(address);
        EditText token = new EditText(this); token.setHint("同步密钥（已保存时可留空）"); token.setSingleLine(true);
        token.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_PASSWORD); form.addView(token);
        TextView note = text("同步收藏和最近 50 个收听记录，不切换正在播放的电台。", 15, MUTED); form.addView(note);
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle("收藏与收听同步").setView(form)
            .setNegativeButton("关闭", null).setNeutralButton("停用同步", (d, which) -> { sync.disable(); refreshRows(); })
            .setPositiveButton("保存并同步", null).create();
        dialog.setOnShowListener(v -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(button -> {
            try {
                sync.configure(address.getText().toString().trim(), token.getText().toString().trim()); sync.sync();
                dialog.dismiss(); refreshRows();
            } catch (Exception error) { token.setError("请检查 HTTPS 服务地址和同步密钥"); }
        })); dialog.show();
    }

    private final class StationAdapter extends BaseAdapter {
        @Override public int getCount() { return rows.size(); }
        @Override public Object getItem(int position) { return rows.get(position); }
        @Override public long getItemId(int position) { return position; }
        @Override public View getView(int position, View recycled, ViewGroup parent) {
            Station item = rows.get(position);
            LinearLayout outer = column(); outer.setPadding(0, 0, 0, dp(10));
            LinearLayout card = row(); card.setPadding(dp(18), dp(12), dp(10), dp(12)); card.setBackground(rounded(CARD, 16));
            TextView number = text(String.format(java.util.Locale.ROOT, "%02d", position + 1), 16, MINT);
            card.addView(number, new LinearLayout.LayoutParams(dp(48), dp(64)));
            LinearLayout labels = column(); TextView name = text(item.name, 21, WHITE); name.setMaxLines(1); name.setEllipsize(TextUtils.TruncateAt.END);
            RadioService service = RadioService.current;
            if (service != null && service.station != null && service.station.id.equals(item.id)) name.setTextColor(MINT);
            labels.addView(name); TextView subtitle = text(item.detail(), 14, MUTED); subtitle.setSingleLine(true); subtitle.setEllipsize(TextUtils.TruncateAt.END); labels.addView(subtitle);
            card.addView(labels, weight(1, -2));
            Button star = button(service != null && service.store.isFavorite(item) ? "★" : "☆", false, () -> use(s -> s.toggleFavorite(item)));
            star.setTextSize(28 * scale()); star.setTextColor(MINT); star.setContentDescription((service != null && service.store.isFavorite(item) ? "取消收藏 " : "收藏 ") + item.name);
            star.setFocusable(false); card.addView(star, new LinearLayout.LayoutParams(dp(64), dp(64)));
            outer.addView(card, new LinearLayout.LayoutParams(-1, -2)); outer.setContentDescription("播放 " + item.name);
            return outer;
        }
    }

    private final class DialView extends View {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        DialView() { super(MainActivity.this); setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO); }
        @Override protected void onDraw(Canvas canvas) {
            float x = getWidth() / 2f, y = getHeight() / 2f, radius = Math.min(getWidth(), getHeight()) * 0.34f;
            paint.setStyle(Paint.Style.STROKE); paint.setStrokeWidth(dp(1)); paint.setColor(Color.rgb(48, 74, 81));
            canvas.drawCircle(x, y, radius, paint); canvas.drawCircle(x, y, radius * 0.72f, paint);
            for (int i = 0; i < 40; i++) {
                double angle = i * Math.PI / 20; float inner = radius * (i % 5 == 0 ? 0.88f : 0.94f);
                canvas.drawLine(x + (float)Math.cos(angle) * inner, y + (float)Math.sin(angle) * inner,
                    x + (float)Math.cos(angle) * radius, y + (float)Math.sin(angle) * radius, paint);
            }
            paint.setColor(MINT); paint.setStrokeWidth(dp(3));
            canvas.drawLine(x, y, x + radius * 0.45f, y - radius * 0.45f, paint);
            paint.setStyle(Paint.Style.FILL); canvas.drawCircle(x, y, dp(6), paint);
            paint.setTextSize(dp(13)); paint.setTextAlign(Paint.Align.CENTER); canvas.drawText("TUNE INTO THE WORLD", x, y + radius * 0.45f, paint);
        }
    }
}
