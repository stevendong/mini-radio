package com.miniradio.car;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.security.MessageDigest;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

final class SyncCredentials {
    private static final String ALIAS = "mini-radio-sync-v1";
    private final SharedPreferences preferences;
    SyncCredentials(Context context) { preferences = context.getSharedPreferences("sync-credentials", Context.MODE_PRIVATE); }
    static boolean validServer(String value) {
        try {
            URI uri = new URI(value);
            return "https".equalsIgnoreCase(uri.getScheme()) && uri.getHost() != null && uri.getUserInfo() == null && uri.getQuery() == null && uri.getFragment() == null;
        } catch (Exception ignored) { return false; }
    }
    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (!store.containsAlias(ALIAS)) {
            KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
            generator.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
            generator.generateKey();
        }
        return (SecretKey)store.getKey(ALIAS, null);
    }
    JSONObject read() throws Exception {
        String encoded = preferences.getString("encrypted", null);
        if (encoded == null) return null;
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(preferences.getString("iv", ""), Base64.NO_WRAP)));
        return new JSONObject(new String(cipher.doFinal(Base64.decode(encoded, Base64.NO_WRAP)), StandardCharsets.UTF_8));
    }
    void save(String server, String token) throws Exception {
        if (!validServer(server) || !token.matches("MR1_[A-Za-z0-9_-]{43}")) throw new IllegalArgumentException("Invalid sync configuration");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        JSONObject value = LibrarySync.object().putValue("server", server).putValue("key", token).json;
        byte[] ciphertext = cipher.doFinal(value.toString().getBytes(StandardCharsets.UTF_8));
        if (!preferences.edit().putString("encrypted", Base64.encodeToString(ciphertext, Base64.NO_WRAP))
            .putString("iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP)).putBoolean("enabled", true).commit())
            throw new java.io.IOException("Secure storage unavailable");
    }
    boolean enabled() { return preferences.getBoolean("enabled", false); }
    void enabled(boolean value) { preferences.edit().putBoolean("enabled", value).apply(); }
    void provision(Context context) throws Exception {
        byte[] bytes;
        try (InputStream input = context.getAssets().open("sync-provisioning.json"); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[1024]; int count;
            while ((count = input.read(buffer)) != -1) {
                if (output.size() + count > 4096) throw new java.io.IOException("Invalid provisioning");
                output.write(buffer, 0, count);
            }
            bytes = output.toByteArray();
        } catch (java.io.FileNotFoundException noProvisioning) { return; }
        String digest = Base64.encodeToString(MessageDigest.getInstance("SHA-256").digest(bytes), Base64.NO_WRAP);
        if (digest.equals(preferences.getString("provisioned", ""))) return;
        JSONObject config = new JSONObject(new String(bytes, StandardCharsets.UTF_8));
        save(config.getString("server"), config.getString("key"));
        preferences.edit().putString("provisioned", digest).commit();
    }
}
