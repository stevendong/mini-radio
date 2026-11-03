package com.miniradio.car;

import org.json.JSONArray;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

final class RadioDirectory {
    static final class Page {
        final List<Station> stations;
        final int count;
        Page(JSONArray array) { stations = Station.parse(array); count = array.length(); }
    }
    private final List<String> servers = new ArrayList<>();
    private long discovered;

    static List<Station> starters(String query, String country) {
        String[][] channels = {
            {"cnr-1", "中国之声", "https://ngcdn001.cnr.cn/live/zgzs/index.m3u8", "CN", "AAC"},
            {"cnr-2", "经济之声", "https://ngcdn002.cnr.cn/live/jjzs/index.m3u8", "CN", "AAC"},
            {"cnr-3", "音乐之声", "https://ngcdn003.cnr.cn/live/yyzs/index.m3u8", "CN", "AAC"},
            {"rp-main", "Radio Paradise", "https://stream.radioparadise.com/mp3-128", "US", "MP3"},
            {"soma-groove", "SomaFM · Groove Salad", "https://ice1.somafm.com/groovesalad-128-mp3", "US", "MP3"},
            {"soma-drone", "SomaFM · Drone Zone", "https://ice1.somafm.com/dronezone-128-mp3", "US", "MP3"}
        };
        List<Station> result = new ArrayList<>();
        for (String[] channel : channels) {
            if (!country.isEmpty() && !country.equals(channel[3])) continue;
            if (!channel[1].toLowerCase(java.util.Locale.ROOT).contains(query.toLowerCase(java.util.Locale.ROOT))) continue;
            org.json.JSONObject json = new org.json.JSONObject();
            try {
                json.put("stationuuid", "preset-" + channel[0]).put("name", channel[1]).put("url", channel[2])
                    .put("countrycode", channel[3]).put("codec", channel[4]);
            } catch (org.json.JSONException impossible) { throw new IllegalStateException(impossible); }
            result.add(new Station(json));
        }
        return result;
    }

    static String request(String address) throws Exception {
        HttpURLConnection connection = (HttpURLConnection) new URL(address).openConnection();
        connection.setConnectTimeout(7000); connection.setReadTimeout(9000);
        connection.setRequestProperty("User-Agent", "MiniRadio/0.4.0 (Android; github.com/stevendong/mini-radio)");
        connection.setRequestProperty("Accept", "application/json");
        try {
            if (connection.getResponseCode() != 200) throw new java.io.IOException("Directory unavailable");
            try (InputStream input = connection.getInputStream(); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8192]; int count;
                while ((count = input.read(buffer)) != -1) {
                    if (output.size() + count > 8_000_000) throw new java.io.IOException("Response too large");
                    output.write(buffer, 0, count);
                }
                return output.toString("UTF-8");
            }
        } finally { connection.disconnect(); }
    }

    private void discover() {
        if (!servers.isEmpty() && System.currentTimeMillis() - discovered < 3600000) return;
        servers.clear();
        try {
            JSONArray found = new JSONArray(request("https://all.api.radio-browser.info/json/servers"));
            for (int i = 0; i < found.length(); i++) {
                String host = found.getJSONObject(i).optString("name").toLowerCase(java.util.Locale.ROOT);
                if (host.matches("[a-z0-9-]+\\.api\\.radio-browser\\.info") && !servers.contains(host)) servers.add(host);
            }
            Collections.shuffle(servers);
        } catch (Exception ignored) { }
        // Keep independent seeds even when discovery only returns an unreachable peer.
        for (String seed : new String[]{"de2.api.radio-browser.info", "all.api.radio-browser.info", "de1.api.radio-browser.info"})
            if (!servers.contains(seed)) servers.add(seed);
        discovered = System.currentTimeMillis();
    }

    synchronized Page search(String query, String country, int offset) throws Exception {
        discover();
        String path = "/json/stations/search?hidebroken=true&order=clickcount&reverse=true&limit=60&offset=" + offset
            + "&name=" + URLEncoder.encode(query, "UTF-8") + "&countrycode=" + URLEncoder.encode(country, "UTF-8");
        for (String host : servers) {
            if (Thread.currentThread().isInterrupted()) throw new InterruptedException();
            try { return new Page(new JSONArray(request("https://" + host + path))); }
            catch (Exception ignored) { }
        }
        discovered = 0;
        throw new java.io.IOException("暂时无法连接目录，可收听收藏或手动添加直播地址。");
    }
}
