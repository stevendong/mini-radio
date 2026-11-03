package com.miniradio.car;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.UUID;

final class Station {
    final String id, name, url, resolved, country, state, language, tags, codec;
    final int bitrate;

    Station(JSONObject json) {
        id = json.optString("stationuuid"); name = json.optString("name", "未命名电台").trim();
        url = json.optString("url"); resolved = json.optString("url_resolved");
        country = json.optString("countrycode"); state = json.optString("state");
        language = json.optString("language"); tags = json.optString("tags");
        codec = json.optString("codec"); bitrate = json.optInt("bitrate");
    }

    static boolean validURL(String value) {
        try {
            URI uri = new URI(value.trim());
            return ("https".equalsIgnoreCase(uri.getScheme()) || "http".equalsIgnoreCase(uri.getScheme()))
                && uri.getHost() != null && uri.getUserInfo() == null;
        } catch (Exception ignored) { return false; }
    }

    List<String> streams() {
        List<String> result = new ArrayList<>();
        for (String value : new String[]{resolved, url}) {
            String clean = value.trim();
            if (validURL(clean) && !result.contains(clean)) result.add(clean);
        }
        return result;
    }

    String detail() {
        String place = country.isEmpty() ? "世界电台" : new Locale("", country).getDisplayCountry(Locale.SIMPLIFIED_CHINESE);
        String quality = codec + (bitrate > 0 ? " · " + bitrate + " kbps" : "");
        return place + (quality.isEmpty() ? "" : "   /   " + quality);
    }

    JSONObject json() {
        JSONObject j = new JSONObject();
        try {
            j.put("stationuuid", id).put("name", name).put("url", url).put("url_resolved", resolved)
                .put("countrycode", country).put("state", state).put("language", language)
                .put("tags", tags).put("codec", codec).put("bitrate", bitrate);
        } catch (JSONException impossible) { throw new IllegalStateException(impossible); }
        return j;
    }

    static Station manual(String name, String address) {
        if (!validURL(address)) return null;
        JSONObject j = new JSONObject();
        try {
            j.put("stationuuid", "manual-" + UUID.randomUUID()).put("name", name.trim().isEmpty() ? "自定义电台" : name.trim())
                .put("url", address.trim());
        } catch (JSONException impossible) { throw new IllegalStateException(impossible); }
        return new Station(j);
    }

    static List<Station> parse(JSONArray array) {
        List<Station> result = new ArrayList<>();
        java.util.Set<String> ids = new java.util.HashSet<>();
        for (int i = 0; i < array.length(); i++) {
            JSONObject item = array.optJSONObject(i);
            if (item == null) continue;
            Station station = new Station(item);
            if (!station.id.isEmpty() && !station.streams().isEmpty() && ids.add(station.id)) result.add(station);
        }
        return result;
    }

    static JSONArray array(List<Station> stations) {
        JSONArray array = new JSONArray();
        for (Station station : stations) array.put(station.json());
        return array;
    }
}
