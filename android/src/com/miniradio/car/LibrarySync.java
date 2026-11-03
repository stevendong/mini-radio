package com.miniradio.car;

import org.json.JSONException;
import org.json.JSONObject;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Iterator;
import java.util.List;

final class LibrarySync {
    static final int MAX_BYTES = 8 * 1024 * 1024;
    static JSONObject empty() { return object().putValue("favorites", new JSONObject()).putValue("history", new JSONObject()).json; }
    static JSONObject document(JSONObject state) {
        return object().putValue("format", "mini-radio-library").putValue("version", 1).putValue("state", state).json;
    }
    static JSONObject record(Station station, boolean favorite, boolean removed, double time) {
        Builder builder = object().putValue("station", station.json()).putValue("revision", java.util.UUID.randomUUID().toString().toUpperCase(java.util.Locale.ROOT))
            .putValue(favorite ? "modifiedAt" : "listenedAt", time);
        if (favorite) builder.putValue("removed", removed);
        return builder.json;
    }
    static double now() { return System.currentTimeMillis() / 1000d - 978307200d; }
    static List<String> keys(JSONObject object) {
        List<String> keys = new ArrayList<>(); Iterator<String> iterator = object.keys();
        while (iterator.hasNext()) keys.add(iterator.next()); return keys;
    }
    static JSONObject validate(JSONObject document) throws JSONException {
        if (!"mini-radio-library".equals(document.getString("format")) || !(document.get("version") instanceof Number)
            || ((Number)document.get("version")).doubleValue() != 1d) throw new JSONException("Unsupported sync format");
        JSONObject state = document.getJSONObject("state");
        for (String kind : new String[]{"favorites", "history"}) {
            JSONObject records = state.getJSONObject(kind); boolean favorite = kind.equals("favorites");
            for (String id : keys(records)) {
                JSONObject record = records.getJSONObject(id), source = record.getJSONObject("station");
                Station station = new Station(source);
                if (id.isEmpty() || id.length() > 1024 || !id.equals(station.id) || station.streams().isEmpty()
                    || !(record.get("revision") instanceof String) || record.getString("revision").isEmpty()
                    || record.getString("revision").length() > 1024) throw new JSONException("Invalid sync record");
                Object time = record.get(favorite ? "modifiedAt" : "listenedAt");
                if (!(time instanceof Number) || !Double.isFinite(((Number)time).doubleValue())) throw new JSONException("Invalid sync time");
                if (favorite && !(record.get("removed") instanceof Boolean)) throw new JSONException("Invalid deletion");
                for (String field : new String[]{"name", "url", "url_resolved", "countrycode", "state", "language", "tags", "codec"})
                    if (!(source.get(field) instanceof String)) throw new JSONException("Invalid station field");
                Object bitrate = source.get("bitrate");
                if (!(bitrate instanceof Number)) throw new JSONException("Invalid bitrate");
                double value = ((Number)bitrate).doubleValue();
                if (!Double.isFinite(value) || value != Math.rint(value) || Math.abs(value) > 9007199254740991d) throw new JSONException("Invalid bitrate");
            }
        }
        return state;
    }
    static JSONObject merge(JSONObject current, JSONObject incoming) {
        JSONObject result = empty();
        try {
            for (String kind : new String[]{"favorites", "history"}) {
                boolean favorite = kind.equals("favorites"); String time = favorite ? "modifiedAt" : "listenedAt";
                JSONObject records = new JSONObject(current.getJSONObject(kind).toString());
                JSONObject changes = incoming.getJSONObject(kind);
                for (String id : keys(changes)) {
                    JSONObject next = changes.getJSONObject(id), old = records.optJSONObject(id);
                    if (old != null) {
                        int order = Double.compare(next.getDouble(time), old.getDouble(time));
                        if (order < 0) continue;
                        if (order == 0) {
                            if (favorite && old.getBoolean("removed") && !next.getBoolean("removed")) continue;
                            if ((!favorite || next.getBoolean("removed") == old.getBoolean("removed"))
                                && next.getString("revision").compareTo(old.getString("revision")) <= 0) continue;
                        }
                    }
                    records.put(id, new JSONObject(next.toString()));
                }
                if (!favorite) {
                    List<String> ids = sorted(records, time);
                    for (int i = 50; i < ids.size(); i++) records.remove(ids.get(i));
                }
                result.put(kind, records);
            }
        } catch (JSONException invalid) { throw new IllegalArgumentException("Invalid library state"); }
        return result;
    }
    static List<String> sorted(JSONObject records, String time) {
        List<String> ids = keys(records);
        Collections.sort(ids, (a, b) -> {
            int order = Double.compare(records.optJSONObject(b).optDouble(time), records.optJSONObject(a).optDouble(time));
            return order != 0 ? order : a.compareTo(b);
        });
        return ids;
    }
    static boolean equivalent(JSONObject a, JSONObject b) {
        if (a.length() != b.length()) return false;
        for (String key : keys(a)) {
            if (!b.has(key)) return false;
            Object x = a.opt(key), y = b.opt(key);
            if (x instanceof JSONObject && y instanceof JSONObject) { if (!equivalent((JSONObject)x, (JSONObject)y)) return false; }
            else if (x instanceof Number && y instanceof Number) { if (Double.compare(((Number)x).doubleValue(), ((Number)y).doubleValue()) != 0) return false; }
            else if (!x.equals(y)) return false;
        }
        return true;
    }
    static Builder object() { return new Builder(); }
    static final class Builder {
        final JSONObject json = new JSONObject();
        Builder putValue(String key, Object value) {
            try { json.put(key, value); } catch (JSONException error) { throw new IllegalArgumentException("Invalid JSON value"); }
            return this;
        }
    }
}
