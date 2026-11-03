package com.miniradio.car;

import android.app.Instrumentation;
import android.content.ComponentName;
import android.content.Context;
import android.media.browse.MediaBrowser;
import android.os.Bundle;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;

/** Device tests use separate named preferences; the user's library is never modified. */
public final class RadioInstrumentation extends Instrumentation {
    private int checks;
    private Context isolated() {
        return new android.content.ContextWrapper(getTargetContext()) {
            @Override public android.content.SharedPreferences getSharedPreferences(String name, int mode) {
                return super.getSharedPreferences("instrumentation-" + name, mode);
            }
        };
    }
    @Override public void onCreate(Bundle arguments) { super.onCreate(arguments); start(); }
    private void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
        checks++;
    }
    @Override public void onStart() {
        Bundle result = new Bundle();
        try {
            stationValidation(); libraryPersistence(); syncMerging(); secureCredentials(); mediaButtons(); mediaBrowser();
            result.putString("stream", "PASS: " + checks + " Android assertions\n"); finish(-1, result);
        } catch (Throwable error) {
            result.putString("stream", "FAIL: " + error.getClass().getSimpleName() + ": " + error.getMessage() + "\n"); finish(0, result);
        }
    }
    private void stationValidation() throws Exception {
        check(Station.validURL(" https://example.com/live "), "HTTPS accepted");
        check(Station.validURL("HTTP://example.com/live"), "Case-insensitive scheme");
        for (String invalid : new String[]{"file:///radio", "javascript:alert(1)", "https://user:secret@example.com/live", "https:///live", "not a url"})
            check(!Station.validURL(invalid), "Reject unsafe or malformed URL");
        check(Station.manual("test", "file:///radio") == null, "Manual URL validation");
        Station station = new Station(new JSONObject("{\"stationuuid\":\"x\",\"name\":\"Test\",\"url\":\"https://example.com/a\",\"url_resolved\":\"https://example.com/b\",\"bitrate\":\"128\"}"));
        check(station.streams().size() == 2 && station.streams().get(0).endsWith("/b"), "Resolved URL first, original fallback");
        check(station.bitrate == 128, "String bitrate accepted");
        check(Station.parse(new JSONArray().put(station.json()).put(station.json()).put(new JSONObject())).size() == 1, "Deduplicate and reject invalid stations");
        check(new Station(station.json()).name.equals(station.name), "Station JSON round-trip");
        check(RadioDirectory.starters("", "CN").size() == 3, "Preset country filter");
        check(RadioDirectory.starters("paradise", "US").size() == 1, "Preset name filter");
    }
    private void libraryPersistence() throws Exception {
        Context isolated = isolated();
        isolated.getSharedPreferences("radio-library", Context.MODE_PRIVATE).edit().clear().commit();
        RadioStore store = new RadioStore(isolated);
        check(store.favorites.isEmpty() && store.recent.isEmpty() && store.last == null, "Fresh library");
        Station first = Station.manual("First", "https://example.com/first");
        store.favorite(first);
        check(new RadioStore(isolated).isFavorite(first), "Favorite persists");
        store.favorite(first);
        check(new RadioStore(isolated).favorites.isEmpty(), "Unfavorite persists");
        check(store.recent.isEmpty(), "Selection/favorite must not record listening");
        for (int i = 0; i < 55; i++) store.listened(Station.manual("Station " + i, "https://example.com/" + i));
        RadioStore restored = new RadioStore(isolated);
        check(restored.recent.size() == 50, "History limit");
        check(restored.recent.get(0).name.equals("Station 54") && restored.last.name.equals("Station 54"), "History newest first and last station");
        restored.listened(restored.recent.get(10));
        check(restored.recent.size() == 50 && restored.recent.get(0).name.equals("Station 44"), "History deduplication");
        restored.cache("first", java.util.Collections.singletonList(first)); restored.cache("second", restored.recent);
        check(restored.cache("first").isEmpty() && restored.cache("second").size() == 50, "Query cache is bounded");
        check(new RadioStore(isolated).cache("second").size() == 50, "Cache persists");
        isolated.getSharedPreferences("radio-library", Context.MODE_PRIVATE).edit().clear().commit();
    }
    private void mediaBrowser() throws Exception {
        CountDownLatch ready = new CountDownLatch(1), children = new CountDownLatch(1);
        AtomicReference<String> error = new AtomicReference<>();
        AtomicReference<MediaBrowser> holder = new AtomicReference<>();
        runOnMainSync(() -> {
            MediaBrowser browser = new MediaBrowser(getTargetContext(), new ComponentName(getTargetContext(), RadioService.class), new MediaBrowser.ConnectionCallback() {
                @Override public void onConnected() { ready.countDown(); }
                @Override public void onConnectionFailed() { error.set("Browser connection failed"); ready.countDown(); }
            }, null);
            holder.set(browser); browser.connect();
        });
        try {
            check(ready.await(10, TimeUnit.SECONDS) && error.get() == null, "Media browser connection");
            runOnMainSync(() -> {
                MediaBrowser browser = holder.get();
                if (browser.getSessionToken() == null) error.set("Missing session token");
                browser.subscribe(browser.getRoot(), new MediaBrowser.SubscriptionCallback() {
                    @Override public void onChildrenLoaded(String id, List<MediaBrowser.MediaItem> items) {
                        if (items.size() != 3 || !items.get(0).isBrowsable()) error.set("Missing media categories");
                        children.countDown();
                    }
                    @Override public void onError(String id) { error.set("Browse failed"); children.countDown(); }
                });
            });
            check(children.await(10, TimeUnit.SECONDS) && error.get() == null, "Media categories and session token");
        } finally { runOnMainSync(() -> holder.get().disconnect()); }
    }
    private void syncMerging() throws Exception {
        Station station = Station.manual("Sync fixture", "https://example.com/live");
        JSONObject original = LibrarySync.empty(), incoming = LibrarySync.empty();
        JSONObject added = LibrarySync.record(station, true, false, 100);
        JSONObject removed = LibrarySync.record(station, true, true, 100);
        added.put("revision", "z"); removed.put("revision", "a");
        original.getJSONObject("favorites").put(station.id, added);
        incoming.getJSONObject("favorites").put(station.id, removed);
        JSONObject merged = LibrarySync.merge(original, incoming);
        check(merged.getJSONObject("favorites").getJSONObject(station.id).getBoolean("removed"), "Deletion wins equal timestamp even with smaller revision");
        check(LibrarySync.equivalent(merged, LibrarySync.merge(incoming, original)), "Merge is order-independent");
        check(LibrarySync.equivalent(merged, LibrarySync.merge(merged, merged)), "Merge is idempotent");
        added.put("modifiedAt", 101);
        check(!LibrarySync.merge(merged, original).getJSONObject("favorites").getJSONObject(station.id).getBoolean("removed"), "Newer favorite restores deleted item");
        added.put("modifiedAt", 100).put("revision", "b"); removed.put("removed", false).put("revision", "c");
        check(LibrarySync.merge(original, incoming).getJSONObject("favorites").getJSONObject(station.id).getString("revision").equals("c"), "Revision breaks timestamp ties");
        for (int i = 0; i < 55; i++) {
            Station item = Station.manual("History " + i, "https://example.com/" + i);
            original.getJSONObject("history").put(item.id, LibrarySync.record(item, false, false, i));
        }
        check(LibrarySync.merge(original, incoming).getJSONObject("history").length() == 50, "Sync retains latest 50 listening records");
        check(LibrarySync.validate(LibrarySync.document(merged)).getJSONObject("favorites").length() == 1, "Protocol document round-trip");
        JSONObject invalid = LibrarySync.document(LibrarySync.empty()); invalid.put("version", 2);
        boolean rejected = false;
        try { LibrarySync.validate(invalid); } catch (Exception expected) { rejected = true; }
        check(rejected, "Reject unsupported protocol version");
        invalid = LibrarySync.document(LibrarySync.empty()); invalid.getJSONObject("state").getJSONObject("favorites").put("wrong-id", added);
        rejected = false;
        try { LibrarySync.validate(invalid); } catch (Exception expected) { rejected = true; }
        check(rejected, "Reject mismatched station ID");
        RadioStore local = new RadioStore(isolated()); local.merge(merged);
        check(local.favorites.isEmpty() && local.syncState.getJSONObject("favorites").length() == 1, "Persist deletion tombstone without visible favorite");
        local.merge(original);
        check(local.recent.size() == 50 && local.last.name.equals("History 54"), "Sync materializes sorted recent history and last station");
        isolated().getSharedPreferences("radio-library", Context.MODE_PRIVATE).edit().clear().commit();
    }
    private void secureCredentials() throws Exception {
        SyncCredentials credentials = new SyncCredentials(isolated());
        String fixture = "MR1_" + String.join("", java.util.Collections.nCopies(43, "A"));
        credentials.save("https://example.com", fixture);
        check(credentials.enabled() && credentials.read().getString("key").equals(fixture), "Keystore credential round-trip");
        String stored = isolated().getSharedPreferences("sync-credentials", Context.MODE_PRIVATE).getAll().toString();
        check(!stored.contains(fixture) && !stored.contains("https://example.com"), "Preferences contain no plaintext credentials");
        credentials.enabled(false); check(!credentials.enabled(), "Sync can be disabled independently of saved key");
        check(!SyncCredentials.validServer("http://example.com") && !SyncCredentials.validServer("https://example.com?key=x")
            && !SyncCredentials.validServer("https://user:secret@example.com"), "Sync endpoint validation");
        isolated().getSharedPreferences("sync-credentials", Context.MODE_PRIVATE).edit().clear().commit();
    }
    private void mediaButtons() {
        java.util.List<Integer> skips = new java.util.ArrayList<>();
        MediaButtons.Navigation navigation = skips::add;
        long time = android.os.SystemClock.uptimeMillis();
        check(MediaButtons.handle(new android.view.KeyEvent(time, time, android.view.KeyEvent.ACTION_DOWN,
            android.view.KeyEvent.KEYCODE_MEDIA_NEXT, 0), navigation), "Next key handled");
        MediaButtons.handle(new android.view.KeyEvent(time, time + 10, android.view.KeyEvent.ACTION_DOWN,
            android.view.KeyEvent.KEYCODE_MEDIA_NEXT, 1), navigation);
        MediaButtons.handle(new android.view.KeyEvent(time, time + 20, android.view.KeyEvent.ACTION_UP,
            android.view.KeyEvent.KEYCODE_MEDIA_NEXT, 0), navigation);
        check(skips.size() == 1 && skips.get(0) == 1, "Key repeat and release do not skip again");
        check(MediaButtons.handle(new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN,
            android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS), navigation) && skips.get(1) == -1, "Previous key handled");
        check(!MediaButtons.handle(new android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN,
            android.view.KeyEvent.KEYCODE_VOLUME_UP), navigation), "Volume remains with the system");
        check(!MediaButtons.handle(null, navigation), "Missing event ignored");
        check(MediaButtons.adjacentIndex(0, 3, -1) == 2 && MediaButtons.adjacentIndex(2, 3, 1) == 0, "Station queue wraps in both directions");
        check(MediaButtons.adjacentIndex(-1, 3, -1) == 2 && MediaButtons.adjacentIndex(-1, 3, 1) == 0, "Unlisted current station starts at correct queue edge");
        check(MediaButtons.adjacentIndex(0, 1, -1) == 0 && MediaButtons.adjacentIndex(-1, 0, 1) == -1, "Single and empty queues");
    }
}
