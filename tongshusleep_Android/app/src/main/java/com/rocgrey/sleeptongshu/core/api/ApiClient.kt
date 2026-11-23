package com.rocgrey.sleeptongshu.core.api

import com.rocgrey.sleeptongshu.BuildConfig
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.serializer
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit

/** 统一 API 业务错误：带 HTTP 状态码与后端 detail 文案。 */
class ApiException(val code: Int, message: String) : IOException(message)

object JsonCodec {
    val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = false
        explicitNulls = false
        coerceInputValues = true
    }
}

/**
 * 与 iOS APIClient.swift 同口径：
 * - sharecode 网关：请求前对根路径握手一次；所有请求自动追加 ?sharecode=
 * - 认证头：Authorization: Bearer <token>；配置了网关时额外带 X-Auth-Token（网关会改写 Authorization）
 * - 不跟随重定向，防止 token 泄漏
 * - 401 回调 onUnauthorized（仅当前会话 token 才生效，由 AccountStore 保证）
 */
class ApiClient(
    baseUrl: String = BuildConfig.SLEEP_API_BASE_URL,
    private val gatewayCode: String = BuildConfig.SLEEP_GATEWAY_SHARE_CODE,
    private var accessToken: String? = null,
    private val onUnauthorized: (token: String?, message: String) -> Unit = { _, _ -> },
) {
    var baseUrl: String = baseUrl.trimEnd('/')
        private set

    val json = JsonCodec.json
    private val jsonMedia = "application/json; charset=utf-8".toMediaType()

    @Volatile
    private var gatewayPrepared = false

    private val gatewayMutex = Mutex()

    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .cache(null)
        .build()

    fun updateToken(token: String?) {
        accessToken = token
        gatewayPrepared = false
    }

    fun newClient(baseUrl: String, gatewayCode: String, token: String?): ApiClient =
        ApiClient(baseUrl, gatewayCode, token, onUnauthorized)

    private fun addSharecode(url: String): String {
        if (gatewayCode.isBlank()) return url
        val sep = if (url.contains("?")) "&" else "?"
        return "$url${sep}sharecode=$gatewayCode"
    }

    private suspend fun prepareGateway() {
        if (gatewayCode.isBlank() || gatewayPrepared) return
        gatewayMutex.withLock {
            if (gatewayPrepared) return
            val request = Request.Builder()
                .url(addSharecode(baseUrl))
                .header("Accept", "application/json")
                .build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw ApiException(response.code, "链接不完整：需要有效的分享码（sharecode）。")
                }
            }
            gatewayPrepared = true
        }
    }

    private fun buildRequest(method: String, path: String, bodyJson: String?): Request {
        val url = addSharecode("$baseUrl/${path.trimStart('/')}")
        val builder = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
        accessToken?.let { token ->
            builder.header("Authorization", "Bearer $token")
            if (gatewayCode.isNotBlank()) builder.header("X-Auth-Token", "Bearer $token")
        }
        when (method.uppercase()) {
            "GET" -> builder.get()
            "DELETE" -> builder.delete()
            else -> builder.method(
                method.uppercase(),
                (bodyJson ?: "{}").toRequestBody(jsonMedia),
            )
        }
        return builder.build()
    }

    private fun errorMessage(response: Response, raw: String?): String {
        val text = raw ?: ""
        return try {
            val element = json.parseToJsonElement(text)
            val obj = element.jsonObjectOrNull()
            when {
                obj?.get("detail") != null -> {
                    val d = obj!!["detail"]!!
                    if (d.toString().startsWith("[")) {
                        d.toString().replace(Regex("[\\[\\]{}\"\\\\]|msg"), "").ifBlank { response.message }
                    } else d.toString().trim('"')
                }
                obj?.get("message") != null -> obj!!["message"].toString().trim('"')
                else -> response.message.ifBlank { "请求失败" }
            }
        } catch (_: Exception) {
            response.message.ifBlank { "请求失败" }
        }
    }

    private fun kotlinx.serialization.JsonElement.jsonObjectOrNull(): kotlinx.serialization.json.JsonObject? =
        this as? kotlinx.serialization.json.JsonObject

    /** 发起请求并返回原始文本；401 触发回调。 */
    suspend fun request(method: String, path: String, bodyJson: String? = null): String {
        prepareGateway()
        client.newCall(buildRequest(method, path, bodyJson)).execute().use { response ->
            val raw = response.body?.string()
            when {
                response.isSuccessful -> return raw ?: "{}"
                response.code == 401 -> {
                    val message = errorMessage(response, raw)
                    val token = accessToken
                    onUnauthorized(token, message)
                    throw ApiException(401, message)
                }
                else -> throw ApiException(response.code, errorMessage(response, raw))
            }
        }
    }

    suspend inline fun <reified T> decode(raw: String): T = json.decodeFromString(raw)

    suspend inline fun <reified T> get(path: String): T =
        json.decodeFromString(request("GET", path))

    suspend inline fun <reified T> post(path: String, body: Any? = null): T =
        json.decodeFromString(request("POST", path, body?.let { encodeBody(it) } ?: "{}"))

    suspend inline fun <reified T> put(path: String, body: Any): T =
        json.decodeFromString(request("PUT", path, encodeBody(body)))

    /** 运行时按类查序列化器（@Serializable 数据类无需额外依赖）。 */
    fun encodeBody(value: Any): String =
        json.encodeToString(value::class.serializer(), value)

    suspend fun postNoBody(path: String) {
        request("POST", path, "{}")
    }

    companion object {
        // 京东域名白名单，与 iOS ClassroomItem.purchaseURL 校验一致
        private val JD_HOSTS = setOf("3.cn", "jd.com", "www.jd.com", "item.jd.com", "item.m.jd.com")

        fun isJdUrl(url: String?): Boolean {
            if (url.isNullOrBlank()) return false
            val host = try {
                java.net.URI(url).host?.lowercase() ?: return false
            } catch (_: Exception) {
                return false
            }
            if (host in JD_HOSTS) return true
            // item.m.jd.com/goods/xxx.html 等子域形态按后缀匹配
            return JD_HOSTS.any { host == it || host.endsWith(".$it") }
        }
    }
}
