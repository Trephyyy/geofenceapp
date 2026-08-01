package com.example.geofenceapp

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.SecretKeySpec

object PrivacyConsentManager {
    private const val TAG = "PrivacyConsent"
    private const val PREFS_FILE = "privacy_consent_prefs"
    private const val KEY_CONSENT_GRANTED = "consent_granted"
    private const val KEY_CONSENT_VERSION = "consent_version"
    private const val KEY_WEBHOOK_ENDPOINT = "webhook_endpoint_url"
    private const val KEY_WEBHOOK_HEADERS = "webhook_headers_json"
    private const val KEYSTORE_ALIAS = "geofenceapp_db_key"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val DB_KEY_SIZE = 256

    private var encryptedPrefs: EncryptedSharedPreferences? = null
    private var cachedDbKey: ByteArray? = null

    private fun getEncryptedPrefs(context: Context): EncryptedSharedPreferences {
        if (encryptedPrefs == null) {
            val masterKey = MasterKey.Builder(context)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()

            encryptedPrefs = EncryptedSharedPreferences.create(
                context,
                PREFS_FILE,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            ) as EncryptedSharedPreferences
        }
        return encryptedPrefs!!
    }

    fun hasConsent(context: Context): Boolean {
        return getEncryptedPrefs(context).getBoolean(KEY_CONSENT_GRANTED, false)
    }

    fun grantConsent(context: Context) {
        getEncryptedPrefs(context).edit()
            .putBoolean(KEY_CONSENT_GRANTED, true)
            .putInt(KEY_CONSENT_VERSION, 1)
            .apply()
        DebugLogger.init(context)
        DebugLogger.i("CONSENT", "Privacy consent granted. Engine starting.")
    }

    fun revokeConsent(context: Context) {
        getEncryptedPrefs(context).edit()
            .putBoolean(KEY_CONSENT_GRANTED, false)
            .apply()
        DebugLogger.init(context)
        DebugLogger.i("CONSENT", "Privacy consent revoked. Unregistering geofences and clearing queue.")
    }

    fun getWebhookEndpoint(context: Context): String? {
        return getEncryptedPrefs(context).getString(KEY_WEBHOOK_ENDPOINT, null)
    }

    fun setWebhookEndpoint(context: Context, url: String) {
        getEncryptedPrefs(context).edit().putString(KEY_WEBHOOK_ENDPOINT, url).apply()
    }

    fun getWebhookHeaders(context: Context): String? {
        return getEncryptedPrefs(context).getString(KEY_WEBHOOK_HEADERS, null)
    }

    fun setWebhookHeaders(context: Context, headersJson: String) {
        getEncryptedPrefs(context).edit().putString(KEY_WEBHOOK_HEADERS, headersJson).apply()
    }

    fun clearWebhookConfig(context: Context) {
        getEncryptedPrefs(context).edit()
            .remove(KEY_WEBHOOK_ENDPOINT)
            .remove(KEY_WEBHOOK_HEADERS)
            .apply()
    }

    fun getDatabaseKey(context: Context): ByteArray {
        if (cachedDbKey != null) return cachedDbKey!!

        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE)
        keyStore.load(null)

        if (!keyStore.containsAlias(KEYSTORE_ALIAS)) {
            val keyGenerator = KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                ANDROID_KEYSTORE
            )
            val spec = KeyGenParameterSpec.Builder(
                KEYSTORE_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(DB_KEY_SIZE)
                .build()
            keyGenerator.init(spec)
            keyGenerator.generateKey()
        }

        val secretKey = keyStore.getEntry(KEYSTORE_ALIAS, null) as KeyStore.SecretKeyEntry
        cachedDbKey = secretKey.secretKey.encoded
        return cachedDbKey!!
    }

    fun getDatabaseKeyAsHex(context: Context): String {
        return getDatabaseKey(context).joinToString("") { "%02x".format(it) }
    }
}