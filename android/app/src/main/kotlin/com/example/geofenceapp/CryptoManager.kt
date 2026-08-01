package com.example.geofenceapp

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.security.SecureRandom
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

object CryptoManager {
    private const val TAG = "CryptoManager"
    private const val KEYSTORE_ALIAS = "GeofenceAppMasterKey"
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val KEY_SIZE = 256
    private const val IV_SIZE = 12
    private const val GCM_TAG_BITS = 128
    private const val TRANSFORMATION = "AES/GCM/NoPadding"

    private val keyStore: KeyStore by lazy {
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
    }

    private fun getOrCreateKey(): SecretKey {
        if (!keyStore.containsAlias(KEYSTORE_ALIAS)) {
            val keyGenerator = javax.crypto.KeyGenerator.getInstance(
                KeyProperties.KEY_ALGORITHM_AES,
                ANDROID_KEYSTORE
            )
            val spec = KeyGenParameterSpec.Builder(
                KEYSTORE_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(KEY_SIZE)
                .setRandomizedEncryptionRequired(true)
                .setUserAuthenticationRequired(false)
                .build()
            keyGenerator.init(spec)
            keyGenerator.generateKey()
            if (BuildConfig.DEBUG) Log.d(TAG, "Master key generated in Android KeyStore")
        }
        return (keyStore.getEntry(KEYSTORE_ALIAS, null) as KeyStore.SecretKeyEntry).secretKey
    }

    fun encrypt(plainText: String): String {
        try {
            val secretKey = getOrCreateKey()
            val iv = ByteArray(IV_SIZE)
            SecureRandom().nextBytes(iv)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey, GCMParameterSpec(GCM_TAG_BITS, iv))
            val cipherOutput = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
            val combined = ByteArray(IV_SIZE + cipherOutput.size)
            System.arraycopy(iv, 0, combined, 0, IV_SIZE)
            System.arraycopy(cipherOutput, 0, combined, IV_SIZE, cipherOutput.size)
            return Base64.getEncoder().encodeToString(combined)
        } catch (e: GeneralSecurityException) {
            DebugLogger.e("CRYPTO", "Encryption failed: ${e.message}", throwable = e)
            throw CryptoException("Encryption failed", e)
        }
    }

    fun decrypt(cipherText: String): String {
        try {
            val secretKey = getOrCreateKey()
            val combined = Base64.getDecoder().decode(cipherText)
            if (combined.size < IV_SIZE + 1) {
                throw CryptoException("Ciphertext too short", null)
            }
            val iv = combined.copyOfRange(0, IV_SIZE)
            val cipherOutput = combined.copyOfRange(IV_SIZE, combined.size)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, secretKey, GCMParameterSpec(GCM_TAG_BITS, iv))
            val plainBytes = cipher.doFinal(cipherOutput)
            return String(plainBytes, Charsets.UTF_8)
        } catch (e: GeneralSecurityException) {
            DebugLogger.e("CRYPTO", "Decryption failed: ${e.message}", throwable = e)
            throw CryptoException("Decryption failed", e)
        }
    }
}

class CryptoException(message: String, cause: Throwable?) : RuntimeException(message, cause)
