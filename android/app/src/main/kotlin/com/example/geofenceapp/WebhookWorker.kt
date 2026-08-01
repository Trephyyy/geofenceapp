package com.example.geofenceapp

import android.content.Context
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.Constraints
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class WebhookWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "WebhookWorker"
        private const val WORK_NAME = "webhook_dispatch"
        private const val BATCH_SIZE = 10
        private const val MAX_RETRIES = 6
        private const val DEAD_LETTER_RETRY_COUNT = 99

        fun scheduleDispatch(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val workRequest = OneTimeWorkRequestBuilder<WebhookWorker>()
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.APPEND_OR_REPLACE,
                workRequest
            )
        }

        fun rescheduleOnBoot(context: Context) {
            val constraints = Constraints.Builder()
                .setRequiredNetworkType(NetworkType.CONNECTED)
                .build()

            val workRequest = OneTimeWorkRequestBuilder<WebhookWorker>()
                .setConstraints(constraints)
                .build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                workRequest
            )
        }
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    override suspend fun doWork(): Result {
        DebugLogger.init(applicationContext)

        val endpoint = PrivacyConsentManager.getWebhookEndpoint(applicationContext)
        if (endpoint.isNullOrBlank()) {
            return Result.success()
        }

        val dbHelper = DbHelper(applicationContext)
        try {
            val items = dbHelper.getPendingWebhookItems(BATCH_SIZE)
            if (items.isEmpty()) {
                return Result.success()
            }

            val endpointHost = try {
                java.net.URI(endpoint).host ?: "unknown"
            } catch (_: Exception) { "unknown" }

            DebugLogger.d("WEBHOOK", "Dispatching batch of ${items.size} items to $endpointHost",
                extra = mapOf("batch_size" to items.size, "host" to endpointHost))

            var allSucceeded = true
            var successCount = 0

            for (item in items) {
                val webhookId = item.id
                val payloadJson = item.payloadJson
                val endpointUrl = item.endpointUrl
                val headersJson = item.headersJson ?: ""
                val retryCount = item.retryCount

                if (endpointUrl.isBlank()) {
                    dbHelper.deleteWebhook(webhookId)
                    continue
                }

                val result = executeWebhook(endpointUrl, payloadJson, headersJson)

                when (result) {
                    is WebhookResult.Success -> {
                        dbHelper.deleteWebhook(webhookId)
                        successCount++
                    }
                    is WebhookResult.NonRetryableError -> {
                        if (BuildConfig.DEBUG) Log.w(TAG, "Webhook $webhookId non-retryable (HTTP ${result.statusCode}), marking dead letter")
                        DebugLogger.e("WEBHOOK", "Event dead-lettered. HTTP ${result.statusCode} or max retries exceeded.",
                            placeId = null, extra = mapOf("webhook_id" to webhookId, "status_code" to result.statusCode, "retry_count" to retryCount))
                        dbHelper.updateWebhookRetry(webhookId, DEAD_LETTER_RETRY_COUNT, 0L)
                    }
                    is WebhookResult.RetryableError -> {
                        val newRetryCount = retryCount + 1
                        if (newRetryCount >= MAX_RETRIES) {
                            if (BuildConfig.DEBUG) Log.e(TAG, "Webhook $webhookId exceeded max retries ($MAX_RETRIES), dropping")
                            DebugLogger.e("WEBHOOK", "Event dead-lettered. HTTP ${result.statusCode} or max retries exceeded.",
                                placeId = null, extra = mapOf("webhook_id" to webhookId, "status_code" to result.statusCode, "retry_count" to retryCount))
                            dbHelper.updateWebhookRetry(webhookId, DEAD_LETTER_RETRY_COUNT, 0L)
                        } else {
                            val delaySeconds = (1L shl newRetryCount) * 60L
                            val scheduledAt = System.currentTimeMillis() + (delaySeconds * 1000L)
                            val statusCode = when (result) { is WebhookResult.RetryableError -> result.statusCode; else -> 0 }
                            DebugLogger.w("WEBHOOK", "Dispatch failed (HTTP $statusCode). Retry $newRetryCount scheduled at $scheduledAt",
                                extra = mapOf("webhook_id" to webhookId, "status_code" to statusCode, "retry_count" to newRetryCount))
                            dbHelper.updateWebhookRetry(webhookId, newRetryCount, scheduledAt)
                        }
                        allSucceeded = false
                    }
                }
            }

            if (allSucceeded) {
                DebugLogger.i("WEBHOOK", "Batch dispatched successfully. Deleted $successCount items.",
                    extra = mapOf("success_count" to successCount))
                val remaining = dbHelper.getPendingWebhookItems(Int.MAX_VALUE)
                if (remaining.isNotEmpty()) {
                    scheduleDispatch(applicationContext)
                }
                return Result.success()
            } else {
                return Result.retry()
            }
        } catch (e: Exception) {
            if (BuildConfig.DEBUG) Log.e(TAG, "Webhook dispatch failed: ${e.javaClass.simpleName}")
            DebugLogger.e("WEBHOOK", "Webhook dispatch failed: ${e.javaClass.simpleName}", throwable = e)
            return Result.retry()
        } finally {
            dbHelper.close()
        }
    }

    private fun executeWebhook(endpointUrl: String, payloadJson: String, headersJson: String): WebhookResult {
        return try {
            val body = payloadJson.toRequestBody(jsonMediaType)
            val requestBuilder = Request.Builder()
                .url(endpointUrl)
                .post(body)

            if (headersJson.isNotBlank()) {
                val jsonObject = JSONObject(headersJson)
                for (key in jsonObject.keys()) {
                    requestBuilder.addHeader(key, jsonObject.getString(key))
                }
            }

            val response = client.newCall(requestBuilder.build()).execute()
            val statusCode = response.code

            response.close()

            when {
                statusCode in 200..299 -> WebhookResult.Success
                statusCode == 408 || statusCode == 429 -> WebhookResult.RetryableError(statusCode)
                statusCode in 400..499 -> WebhookResult.NonRetryableError(statusCode)
                statusCode >= 500 -> WebhookResult.RetryableError(statusCode)
                else -> WebhookResult.RetryableError(statusCode)
            }
        } catch (e: Exception) {
            val safeMessage = e.javaClass.simpleName
            if (BuildConfig.DEBUG) Log.e(TAG, "Webhook HTTP request failed: $safeMessage")
            WebhookResult.RetryableError(0)
        }
    }

    private sealed class WebhookResult {
        data object Success : WebhookResult()
        data class NonRetryableError(val statusCode: Int) : WebhookResult()
        data class RetryableError(val statusCode: Int) : WebhookResult()
    }
}