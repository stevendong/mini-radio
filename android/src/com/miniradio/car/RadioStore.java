package com.miniradio.car;

import android.content.Context;
import android.content.SharedPreferences;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.List;

final class RadioStore {
    private final SharedPreferences preferences;
    final List<Station> favorites, recent;
    Station last;
    JSONObject syncState;
    boolean storageHealthy = true;

    RadioStore(Context context) {
        preferences = context.getSharedPreferences("radio-library", Context.MODE_PRIVATE);
        favorites = read("favorites"); recent = read("recent");
        try { last = new Station(new JSONObject(preferences.getString("last", "{}"))); }
        catch (Exception ignored) { last = null; }
        if (last != null && last.streams().isEmpty()) last = null;
        try {
            String stored = preferences.getString("sync-state", null);
            if (stored != null) syncState = LibrarySync.validate(LibrarySync.document(new JSONObject(stored)));
            else {
                syncState = LibrarySync.empty();
                for (int i = 0; i < favorites.size(); i++) syncState.getJSONObject("favorites").put(favorites.get(i).id,
                    LibrarySync.record(favorites.get(i), true, false, -978307200d - i));
                for (int i = 0; i < recent.size(); i++) syncState.getJSONObject("history").put(recent.get(i).id,
                    LibrarySync.record(recent.get(i), false, false, -978307201d - i));
                if (last != null) syncState.getJSONObject("history").put(last.id, LibrarySync.record(last, false, false, -978307200d));
            }
            materialize();
        } catch (Exception invalid) { syncState = LibrarySync.empty(); storageHealthy = false; }
    }

    private List<Station> read(String key) {
        try { return Station.parse(new JSONArray(preferences.getString(key, "[]"))); }
        catch (Exception ignored) { return new ArrayList<>(); }
    }

    boolean isFavorite(Station station) {
        for (Station item : favorites) if (item.id.equals(station.id)) return true;
        return false;
    }

    void favorite(Station station) {
        boolean exists = isFavorite(station);
        favorites.removeIf(item -> item.id.equals(station.id));
        if (!exists) favorites.add(0, station);
        try { syncState.getJSONObject("favorites").put(station.id, LibrarySync.record(station, true, exists, LibrarySync.now())); }
        catch (Exception invalid) { storageHealthy = false; }
        save();
    }

    void listened(Station station) {
        recent.removeIf(item -> item.id.equals(station.id));
        recent.add(0, station);
        while (recent.size() > 50) recent.remove(recent.size() - 1);
        last = station;
        try {
            syncState.getJSONObject("history").put(station.id, LibrarySync.record(station, false, false, LibrarySync.now()));
            syncState = LibrarySync.merge(syncState, LibrarySync.empty());
        } catch (Exception invalid) { storageHealthy = false; }
        save();
    }

    void merge(JSONObject incoming) {
        syncState = LibrarySync.merge(syncState, incoming); materialize(); save();
    }
    private void materialize() {
        JSONObject f = syncState.optJSONObject("favorites"), h = syncState.optJSONObject("history");
        favorites.clear(); recent.clear();
        for (String id : LibrarySync.sorted(f, "modifiedAt")) {
            JSONObject record = f.optJSONObject(id);
            if (!record.optBoolean("removed")) favorites.add(new Station(record.optJSONObject("station")));
        }
        for (String id : LibrarySync.sorted(h, "listenedAt")) recent.add(new Station(h.optJSONObject(id).optJSONObject("station")));
        if (!recent.isEmpty()) last = recent.get(0);
    }

    private void save() {
        if (!storageHealthy) return;
        SharedPreferences.Editor editor = preferences.edit()
            .putString("favorites", Station.array(favorites).toString()).putString("recent", Station.array(recent).toString());
        if (last != null) editor.putString("last", last.json().toString());
        editor.putString("sync-state", syncState.toString());
        storageHealthy = editor.commit();
    }

    List<Station> cache(String query) { return read("cache:" + query); }
    void cache(String query, List<Station> stations) {
        // Keep only the last result so repeated searches cannot grow storage without bounds.
        String old = preferences.getString("cache-query", "");
        preferences.edit().remove("cache:" + old).putString("cache-query", query)
            .putString("cache:" + query, Station.array(stations).toString()).apply();
    }
}
