package com.miniradio.car;

import android.os.Handler;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class SyncController {
    private final RadioService service;
    final SyncCredentials credentials;
    private final Handler handler = new Handler();
    private final ExecutorService network = Executors.newSingleThreadExecutor();
    private boolean busy, stopped, changedWhileBusy;
    private int configuration;
    String status = "同步未启用", server = "https://radio.myaichatbox.com";
    private final Runnable debounce = this::sync;
    private final Runnable periodic = new Runnable() {
        @Override public void run() { sync(); handler.postDelayed(this, 60000); }
    };
    SyncController(RadioService service) {
        this.service = service; credentials = new SyncCredentials(service);
        try {
            credentials.provision(service);
            JSONObject config = credentials.read(); if (config != null) server = config.getString("server");
            status = credentials.enabled() ? "等待同步" : "同步未启用";
        } catch (Exception error) { status = "同步配置无法读取，请重新设置"; }
        handler.post(periodic);
    }
    void configure(String address, String token) throws Exception {
        if (token.isEmpty()) {
            JSONObject existing = credentials.read();
            if (existing == null || !address.equals(existing.getString("server"))) throw new IllegalArgumentException("请输入同步密钥");
            token = existing.getString("key");
        }
        credentials.save(address, token); server = address; configuration++; status = "等待同步"; changed();
    }
    void disable() { credentials.enabled(false); configuration++; status = "同步已停用，本机数据保留"; service.version++; }
    void changed() {
        handler.removeCallbacks(debounce); handler.postDelayed(debounce, 1000);
    }
    void sync() {
        if (stopped || !credentials.enabled()) return;
        if (!service.store.storageHealthy) { status = "本机保存失败，已暂停同步"; service.version++; return; }
        if (busy) { changedWhileBusy = true; return; }
        final JSONObject config, snapshot;
        try {
            config = credentials.read(); snapshot = new JSONObject(service.store.syncState.toString());
            if (config == null) throw new IllegalStateException();
        } catch (Exception error) { status = "同步配置无法读取，请重新设置"; service.version++; return; }
        int requested = configuration;
        busy = true; changedWhileBusy = false; status = "正在同步…"; service.version++;
        network.execute(() -> {
            try {
                JSONObject response = exchange(config, snapshot);
                handler.post(() -> {
                    busy = false;
                    if (stopped || requested != configuration) { if (!stopped) changed(); return; }
                    service.store.merge(response);
                    status = service.store.storageHealthy ? "已同步 · 收藏 " + service.store.favorites.size() + " · 最近 " + service.store.recent.size() : "本机保存失败，已暂停同步";
                    service.notifyChildrenChanged("favorites"); service.notifyChildrenChanged("recent"); service.version++;
                    if (changedWhileBusy) changed();
                });
            } catch (Exception error) {
                final String message = error instanceof SyncError ? error.getMessage() : "暂时无法连接同步服务，将自动重试";
                handler.post(() -> {
                    busy = false;
                    if (!stopped && requested == configuration) { status = message; service.version++; }
                    else if (!stopped) changed();
                });
            }
        });
    }
    private static JSONObject exchange(JSONObject config, JSONObject snapshot) throws Exception {
        String address = config.getString("server");
        if (!SyncCredentials.validServer(address)) throw new SyncError("同步服务地址无效");
        byte[] body = LibrarySync.document(snapshot).toString().getBytes(StandardCharsets.UTF_8);
        if (body.length > LibrarySync.MAX_BYTES) throw new SyncError("同步数据超过 8 MB，本机数据已保留");
        HttpURLConnection connection = (HttpURLConnection)new URL(address.replaceAll("/+$", "") + "/v1/library/sync").openConnection();
        connection.setInstanceFollowRedirects(false); connection.setConnectTimeout(15000); connection.setReadTimeout(30000);
        connection.setRequestMethod("POST"); connection.setDoOutput(true); connection.setFixedLengthStreamingMode(body.length);
        connection.setRequestProperty("Authorization", "Bearer " + config.getString("key"));
        connection.setRequestProperty("Content-Type", "application/json"); connection.setRequestProperty("Cache-Control", "no-store");
        try {
            try (java.io.OutputStream output = connection.getOutputStream()) { output.write(body); }
            int code = connection.getResponseCode();
            if (code == 401 || code == 403) throw new SyncError("同步密钥无效或已失效，请重新设置");
            if (code == 429) throw new SyncError("同步请求过于频繁，稍后重试");
            if (code != 200) throw new SyncError("同步服务暂不可用，本机数据已保留");
            byte[] bytes;
            try (InputStream input = connection.getInputStream(); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[8192]; int count;
                while ((count = input.read(buffer)) != -1) {
                    if (output.size() + count > LibrarySync.MAX_BYTES) throw new SyncError("同步数据超过 8 MB，本机数据已保留");
                    output.write(buffer, 0, count);
                }
                bytes = output.toByteArray();
            }
            JSONObject received;
            try { received = LibrarySync.validate(new JSONObject(new String(bytes, StandardCharsets.UTF_8))); }
            catch (Exception invalid) { throw new SyncError("同步数据格式无效，本机数据未被替换"); }
            if (!LibrarySync.equivalent(LibrarySync.merge(snapshot, received), received)) throw new SyncError("服务未完整合并数据，本机数据未被替换");
            return received;
        } finally { connection.disconnect(); }
    }
    void close() { stopped = true; handler.removeCallbacksAndMessages(null); network.shutdownNow(); }
    private static final class SyncError extends Exception { SyncError(String message) { super(message); } }
}
