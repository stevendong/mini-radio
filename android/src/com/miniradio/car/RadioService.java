package com.miniradio.car;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.media.MediaDescription;
import android.media.MediaMetadata;
import android.media.MediaPlayer;
import android.media.browse.MediaBrowser;
import android.media.session.MediaSession;
import android.media.session.PlaybackState;
import android.os.Bundle;
import android.os.Handler;
import android.os.PowerManager;
import android.service.media.MediaBrowserService;
import android.view.KeyEvent;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class RadioService extends MediaBrowserService {
    static RadioService current;
    RadioStore store;
    SyncController sync;
    final List<Station> directory = new ArrayList<>();
    final StationQueue queue = new StationQueue();
    private android.content.SharedPreferences browsing;
    private String browseQuery, browseCountry;
    Station station;
    int state = PlaybackState.STATE_NONE, version;
    String status = "选择电台，听见远方";
    private MediaSession session;
    private MediaPlayer player;
    private AudioManager audio;
    private AudioFocusRequest focus;
    private boolean focusHeld, wantsPlay, prepared, recorded, closed;
    private int streamIndex;
    private final Handler handler = new Handler();
    private final ExecutorService network = Executors.newSingleThreadExecutor();
    private final Runnable timeout = () -> failStream();
    private final Runnable sleep = () -> stopPlayback();
    private final Runnable playbackCheck = new Runnable() {
        @Override public void run() {
            if (player == null || !prepared || !wantsPlay || !focusHeld) return;
            try { if (player.isPlaying() && player.getCurrentPosition() > 0) heard(); }
            catch (IllegalStateException ignored) { return; }
            if (!recorded) handler.postDelayed(this, 1000);
        }
    };
    long sleepUntil;
    private final BroadcastReceiver noisy = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { pause(); }
    };

    @Override public void onCreate() {
        super.onCreate(); current = this;
        store = new RadioStore(this); station = store.last;
        browsing = getSharedPreferences("radio-browsing", MODE_PRIVATE);
        queue.tab = browsing.getInt("tab", StationQueue.DISCOVER);
        browseQuery = browsing.getString("query", ""); browseCountry = browsing.getString("country", "");
        directory.addAll(store.cache(browseQuery + "|" + browseCountry));
        if (directory.isEmpty()) directory.addAll(RadioDirectory.starters(browseQuery, browseCountry));
        refreshQueue();
        audio = (AudioManager) getSystemService(AUDIO_SERVICE);
        AudioAttributes attributes = new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build();
        focus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener(this::focusChanged, handler).build();
        NotificationManager notifications = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        notifications.createNotificationChannel(new NotificationChannel("playback", "电台播放", NotificationManager.IMPORTANCE_LOW));
        session = new MediaSession(this, "MiniRadio");
        session.setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS | MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS);
        session.setSessionActivity(openApp());
        session.setCallback(new MediaSession.Callback() {
            @Override public boolean onMediaButtonEvent(Intent intent) {
                KeyEvent event = intent == null ? null : intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT);
                return handleMediaButton(event) || super.onMediaButtonEvent(intent);
            }
            @Override public void onPlay() { resume(); }
            @Override public void onPause() { pause(); }
            @Override public void onStop() { stopPlayback(); }
            @Override public void onSkipToNext() { next(1); }
            @Override public void onSkipToPrevious() { next(-1); }
            @Override public void onPlayFromMediaId(String id, Bundle extras) {
                for (Station item : allStations()) if (item.id.equals(id)) { play(item); return; }
            }
            @Override public void onPlayFromSearch(String query, Bundle extras) { voiceSearch(query); }
            @Override public void onCustomAction(String action, Bundle extras) {
                if ("favorite".equals(action) && station != null) toggleFavorite(station);
            }
        });
        setSessionToken(session.getSessionToken());
        registerReceiver(noisy, new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY));
        publish();
        sync = new SyncController(this);
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null) {
            String action = intent.getAction();
            if ("play".equals(action)) resume();
            else if ("pause".equals(action)) pause();
            else if ("next".equals(action)) next(1);
            else if ("previous".equals(action)) next(-1);
            else if ("stop".equals(action)) stopPlayback();
        }
        return START_NOT_STICKY;
    }

    boolean active() { return state == PlaybackState.STATE_PLAYING || state == PlaybackState.STATE_BUFFERING; }
    boolean handleMediaButton(KeyEvent event) { return MediaButtons.handle(event, this::next); }

    void play(Station selected) {
        if (selected == null || selected.streams().isEmpty()) return;
        handler.removeCallbacks(timeout); releasePlayer();
        station = selected; streamIndex = 0; recorded = false; wantsPlay = true;
        // Begin foreground execution before focus acquisition, including from media browser commands.
        state = PlaybackState.STATE_BUFFERING; status = "正在连接直播…";
        session.setActive(true); publish(); startForeground(1, notification());
        focusHeld = audio.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
        if (!focusHeld) {
            wantsPlay = false; state = PlaybackState.STATE_PAUSED; status = "其他音源正在使用音频，请稍后播放";
            publish(); stopForeground(false); return;
        }
        connect();
    }

    private void connect() {
        releasePlayer();
        state = PlaybackState.STATE_BUFFERING; status = "正在连接直播…"; publish();
        MediaPlayer candidate = new MediaPlayer(); player = candidate;
        candidate.setAudioAttributes(new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build());
        candidate.setWakeMode(this, PowerManager.PARTIAL_WAKE_LOCK);
        candidate.setOnPreparedListener(mp -> {
            if (player != mp) return;
            handler.removeCallbacks(timeout); prepared = true;
            if (!wantsPlay || !focusHeld) { state = PlaybackState.STATE_PAUSED; status = "已暂停"; publish(); return; }
            try {
                mp.start(); state = PlaybackState.STATE_PLAYING; status = "正在直播"; publish();
                handler.postDelayed(playbackCheck, 2000);
            } catch (IllegalStateException error) { failStream(); }
        });
        candidate.setOnInfoListener((mp, what, extra) -> {
            if (player != mp) return true;
            if (what == MediaPlayer.MEDIA_INFO_BUFFERING_START && wantsPlay) {
                state = PlaybackState.STATE_BUFFERING; status = "正在缓冲…";
                handler.removeCallbacks(timeout); handler.postDelayed(timeout, 25000); publish();
            } else if (what == MediaPlayer.MEDIA_INFO_BUFFERING_END && wantsPlay && focusHeld) {
                handler.removeCallbacks(timeout); state = PlaybackState.STATE_PLAYING; status = "正在直播"; publish();
            }
            return false;
        });
        candidate.setOnErrorListener((mp, what, extra) -> { if (player == mp) failStream(); return true; });
        candidate.setOnCompletionListener(mp -> { if (player == mp) stopPlayback(); });
        try {
            candidate.setDataSource(station.streams().get(streamIndex));
            candidate.prepareAsync(); handler.removeCallbacks(timeout); handler.postDelayed(timeout, 25000);
        } catch (Exception error) { failStream(); }
    }

    private void heard() {
        if (!recorded && station != null && wantsPlay && focusHeld) {
            recorded = true; store.listened(station); version++;
            sync.changed();
            notifyChildrenChanged("recent"); publish();
        }
    }

    private void failStream() {
        handler.removeCallbacks(timeout); releasePlayer();
        if (station != null && wantsPlay && focusHeld && ++streamIndex < station.streams().size()) { connect(); return; }
        wantsPlay = false; abandonFocus();
        state = PlaybackState.STATE_ERROR; status = "直播暂不可用，请重试或换一台";
        publish(); stopForeground(false);
    }

    void resume() {
        if (station == null) { next(1); return; }
        if (state == PlaybackState.STATE_PLAYING) return;
        if (prepared && player != null) {
            startForeground(1, notification());
            focusHeld = audio.requestAudioFocus(focus) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED;
            if (!focusHeld) { status = "其他音源正在使用音频，请稍后播放"; publish(); stopForeground(false); return; }
            wantsPlay = true;
            try { player.start(); state = PlaybackState.STATE_PLAYING; status = "正在直播"; handler.postDelayed(playbackCheck, 1000); publish(); }
            catch (IllegalStateException error) { play(station); }
        } else { play(station); }
    }

    void pause() {
        wantsPlay = false; handler.removeCallbacks(timeout);
        // A live HLS window can expire while paused. Reconnect on explicit resume
        // so playback rejoins the live edge instead of waiting on stale segments.
        releasePlayer();
        abandonFocus(); state = PlaybackState.STATE_PAUSED; status = "已暂停";
        publish(); stopForeground(false);
    }

    void stopPlayback() {
        wantsPlay = false; handler.removeCallbacks(timeout); releasePlayer(); abandonFocus();
        setSleep(0); state = PlaybackState.STATE_STOPPED; status = "已停止";
        publish(); session.setActive(false); stopForeground(true);
    }

    void next(int direction) {
        if (queue.tab == StationQueue.DISCOVER && direction > 0) { shuffle(); return; }
        refreshQueue();
        Station selected = queue.adjacent(station, direction);
        if (selected == null) { status = "当前列表没有电台，请切换列表或调整搜索"; publish(); return; }
        play(selected);
    }

    void shuffle() {
        Station selected = StationQueue.random(directory, station, new java.util.Random());
        if (selected == null) { status = "当前发现列表没有电台，请刷新或调整筛选"; publish(); return; }
        play(selected);
    }

    void setBrowseContext(int tab, String query, String country, List<Station> visible) {
        if (queue.tab != tab || !browseQuery.equals(query) || !browseCountry.equals(country)) {
            browsing.edit().putInt("tab", tab).putString("query", query).putString("country", country).apply();
        }
        browseQuery = query; browseCountry = country;
        if (tab == StationQueue.DISCOVER) { directory.clear(); directory.addAll(visible); }
        queue.update(tab, query, visible);
    }

    private void refreshQueue() {
        List<Station> source = queue.tab == StationQueue.FAVORITES ? store.favorites
            : queue.tab == StationQueue.RECENT ? store.recent : directory;
        List<Station> visible = new ArrayList<>();
        for (Station item : source) {
            if (queue.tab == StationQueue.DISCOVER || item.name.toLowerCase(java.util.Locale.ROOT).contains(browseQuery.toLowerCase(java.util.Locale.ROOT))) visible.add(item);
        }
        queue.update(queue.tab, browseQuery, visible);
    }

    void toggleFavorite(Station item) { store.favorite(item); sync.changed(); version++; notifyChildrenChanged("favorites"); publish(); }
    void setSleep(int minutes) {
        handler.removeCallbacks(sleep); sleepUntil = minutes > 0 ? System.currentTimeMillis() + minutes * 60000L : 0;
        if (minutes > 0) handler.postDelayed(sleep, minutes * 60000L);
        version++;
    }

    private void focusChanged(int change) {
        if (change == AudioManager.AUDIOFOCUS_GAIN) {
            focusHeld = true;
            if (player != null) player.setVolume(1f, 1f);
            if (wantsPlay && prepared && player != null) {
                try { player.start(); state = PlaybackState.STATE_PLAYING; status = "正在直播"; handler.postDelayed(playbackCheck, 1000); publish(); }
                catch (IllegalStateException error) { failStream(); }
            } else if (wantsPlay && player != null) {
                state = PlaybackState.STATE_BUFFERING; status = "正在连接直播…";
                handler.removeCallbacks(timeout); handler.postDelayed(timeout, 25000); publish();
            }
        } else if (change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK) {
            if (player != null) player.setVolume(0.2f, 0.2f);
        } else if (change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
            focusHeld = false;
            handler.removeCallbacks(timeout);
            if (player != null && prepared) { try { player.pause(); } catch (IllegalStateException ignored) { } }
            state = PlaybackState.STATE_PAUSED; status = "音频被临时打断"; publish();
        } else if (change == AudioManager.AUDIOFOCUS_LOSS) { pause(); }
    }

    private void abandonFocus() { focusHeld = false; audio.abandonAudioFocusRequest(focus); }
    private void releasePlayer() {
        handler.removeCallbacks(playbackCheck);
        prepared = false;
        if (player != null) { player.release(); player = null; }
    }

    private void publish() {
        long actions = PlaybackState.ACTION_PLAY | PlaybackState.ACTION_PAUSE | PlaybackState.ACTION_STOP
            | PlaybackState.ACTION_PLAY_PAUSE | PlaybackState.ACTION_SKIP_TO_NEXT | PlaybackState.ACTION_SKIP_TO_PREVIOUS
            | PlaybackState.ACTION_PLAY_FROM_MEDIA_ID | PlaybackState.ACTION_PLAY_FROM_SEARCH;
        PlaybackState.Builder playback = new PlaybackState.Builder().setActions(actions)
            .setState(state, PlaybackState.PLAYBACK_POSITION_UNKNOWN, state == PlaybackState.STATE_PLAYING ? 1f : 0f);
        if (state == PlaybackState.STATE_ERROR) playback.setErrorMessage(status);
        if (station != null) {
            playback.addCustomAction("favorite", store.isFavorite(station) ? "取消收藏" : "收藏", android.R.drawable.btn_star);
            session.setMetadata(new MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_MEDIA_ID, station.id)
                .putString(MediaMetadata.METADATA_KEY_TITLE, station.name).putString(MediaMetadata.METADATA_KEY_ARTIST, station.detail())
                .putString(MediaMetadata.METADATA_KEY_ALBUM, "Mini Radio · 直播电台").putLong(MediaMetadata.METADATA_KEY_DURATION, -1).build());
        }
        session.setPlaybackState(playback.build()); version++;
        if (session.isActive()) ((NotificationManager) getSystemService(NOTIFICATION_SERVICE)).notify(1, notification());
    }

    private PendingIntent openApp() {
        return PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
    private PendingIntent command(String action) {
        return PendingIntent.getService(this, action.hashCode(), new Intent(this, RadioService.class).setAction(action), PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }
    private Notification notification() {
        return new Notification.Builder(this, "playback").setSmallIcon(com.miniradio.car.R.drawable.ic_radio)
            .setContentTitle(station == null ? "Mini Radio" : station.name).setContentText(status)
            .setContentIntent(openApp()).setVisibility(Notification.VISIBILITY_PUBLIC).setOnlyAlertOnce(true)
            .setOngoing(active()).setDeleteIntent(command("stop"))
            .addAction(android.R.drawable.ic_media_previous, "上一站", command("previous"))
            .addAction(active() ? android.R.drawable.ic_media_pause : android.R.drawable.ic_media_play, active() ? "暂停" : "播放", command(active() ? "pause" : "play"))
            .addAction(android.R.drawable.ic_media_next, "下一站", command("next"))
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "停止", command("stop"))
            .setStyle(new Notification.MediaStyle().setMediaSession(session.getSessionToken()).setShowActionsInCompactView(0, 1, 2)).build();
    }

    private List<Station> allStations() {
        List<Station> all = new ArrayList<>(directory); all.addAll(store.favorites); all.addAll(store.recent); return all;
    }
    private void voiceSearch(String query) {
        if (query == null || query.trim().isEmpty()) { resume(); return; }
        for (Station item : allStations()) {
            if (item.name.toLowerCase(java.util.Locale.ROOT).contains(query.toLowerCase(java.util.Locale.ROOT))) { play(item); return; }
        }
        status = "正在搜索电台…"; publish();
        network.execute(() -> {
            try {
                List<Station> found = new RadioDirectory().search(query, "", 0).stations;
                handler.post(() -> { if (!closed && !found.isEmpty()) { directory.clear(); directory.addAll(found); play(found.get(0)); } });
            } catch (Exception error) { handler.post(() -> { if (!closed) { status = "未能找到电台，请在应用中选择"; publish(); } }); }
        });
    }

    @Override public BrowserRoot onGetRoot(String clientPackage, int clientUid, Bundle rootHints) { return new BrowserRoot("root", null); }
    @Override public void onLoadChildren(String parent, Result<List<MediaBrowser.MediaItem>> result) {
        List<MediaBrowser.MediaItem> items = new ArrayList<>();
        if ("root".equals(parent)) {
            String[] ids = {"favorites", "recent", "discover"}, names = {"收藏", "最近收听", "发现电台"};
            for (int i = 0; i < ids.length; i++) items.add(new MediaBrowser.MediaItem(new MediaDescription.Builder()
                .setMediaId(ids[i]).setTitle(names[i]).build(), MediaBrowser.MediaItem.FLAG_BROWSABLE));
        } else {
            List<Station> list = "favorites".equals(parent) ? store.favorites : "recent".equals(parent) ? store.recent : "discover".equals(parent) ? directory : new ArrayList<>();
            for (Station item : list) items.add(new MediaBrowser.MediaItem(new MediaDescription.Builder().setMediaId(item.id)
                .setTitle(item.name).setSubtitle(item.detail()).build(), MediaBrowser.MediaItem.FLAG_PLAYABLE));
        }
        result.sendResult(items);
    }

    @Override public void onDestroy() {
        closed = true; wantsPlay = false; handler.removeCallbacksAndMessages(null); network.shutdownNow();
        if (sync != null) sync.close();
        releasePlayer(); abandonFocus(); session.release(); unregisterReceiver(noisy); stopForeground(true);
        if (current == this) current = null;
        super.onDestroy();
    }
}
