package com.rocgrey.sleeptongshu.core.classroom

import android.content.Context
import com.rocgrey.sleeptongshu.core.api.ApiClient
import com.rocgrey.sleeptongshu.core.api.ClassroomItem
import com.rocgrey.sleeptongshu.core.api.ContentItemsResponse
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.MessageDigest

/** 与 iOS ContentStore 同口径：内置目录兜底 + 远端分页拉取 + 本地缓存。 */
class ContentStore(
    private val context: Context,
    private val clientProvider: () -> ApiClient,
) {
    private val json = Json { ignoreUnknownKeys = true }

    @Volatile
    private var items: List<ClassroomItem> = emptyList()

    @Volatile
    private var catalogInitialized: Boolean = true

    @Volatile
    private var lastRefreshAt: Long = 0

    private val refreshMutex = Any()

    /** 内置目录兜底（assets/catalog.json，与 iOS ClassroomCatalog.json 同文件）。 */
    private fun bundledCatalog(): List<ClassroomItem> = try {
        context.assets.open("catalog.json").bufferedReader().use { reader ->
            json.decodeFromString<List<ClassroomItem>>(reader.readText())
        }
    } catch (_: Exception) {
        emptyList()
    }

    private fun cacheFile(scope: String) =
        java.io.File(context.filesDir, "ContentCache/${sha256(scope)}.json").apply {
            parentFile?.mkdirs()
        }

    fun sha256(value: String): String =
        MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    suspend fun refresh(force: Boolean = false, userScope: String = "shared") {
        synchronized(refreshMutex) {
            if (!force && System.currentTimeMillis() - lastRefreshAt < 15 * 60 * 1000 && items.isNotEmpty()) return
        }
        val fetched = fetchRemote()
        synchronized(refreshMutex) {
            lastRefreshAt = System.currentTimeMillis()
            if (fetched == null) {
                // 网络失败：保留现有或读缓存
                if (items.isEmpty()) items = readCache(userScope) ?: bundledCatalog()
            } else if (fetched.items.isEmpty() && fetched.catalogInitialized == false) {
                // 服务器未初始化目录：与 iOS 一致回退内置
                items = bundledCatalog()
                catalogInitialized = false
                cacheFile(userScope).delete()
            } else {
                items = fetched.items
                catalogInitialized = fetched.catalogInitialized ?: true
                cacheFile(userScope).writeText(json.encodeToString(ContentItemsResponse.serializer(), fetched))
            }
        }
    }

    private suspend fun fetchRemote(): ContentItemsResponse? = try {
        val all = mutableListOf<ClassroomItem>()
        var total = Int.MAX_VALUE
        var page = 1
        while (all.size < total && page <= 100) {
            val response = clientProvider()
                .get<ContentItemsResponse>("content/items?page=$page&page_size=100")
            all += response.items
            total = response.total
            if (response.items.isEmpty()) break
            page++
        }
        ContentItemsResponse(items = all, total = all.size, catalogInitialized = catalogInitialized)
    } catch (_: Exception) {
        null
    }

    private fun readCache(scope: String): ContentItemsResponse? = try {
        val file = cacheFile(scope)
        if (file.exists()) json.decodeFromString(ContentItemsResponse.serializer(), file.readText()) else null
    } catch (_: Exception) {
        null
    }

    fun all(): List<ClassroomItem> = items

    fun isCatalogInitialized(): Boolean = catalogInitialized

    fun courses(): List<ClassroomItem> =
        items.filter { it.kind == "course" }.sortedBy { it.sortOrder }

    fun chaptersOf(courseId: String): List<ClassroomItem> =
        items.filter { it.kind == "chapter" && it.parentId == courseId }.sortedBy { it.sortOrder }

    fun articles(): List<ClassroomItem> =
        items.filter { it.kind == "article" }.sortedBy { it.sortOrder }

    /** 助眠栏：呼吸/白噪音/晚安卡 + 服务器同名 kind 条目。 */
    fun relaxItems(): List<ClassroomItem> =
        items.filter { it.kind in setOf("noise", "breathing", "goodnight") }.sortedBy { it.sortOrder }

    /** 产品栏：仅保留京东白名单外链。 */
    fun products(): List<ClassroomItem> =
        items.filter { it.kind == "product" && ApiClient.isJdUrl(it.externalUrl) }.sortedBy { it.sortOrder }

    fun byId(id: String): ClassroomItem? = items.firstOrNull { it.id == id }

    /** 今日阅读：按日期序数轮换（iOS daily() 语义）。 */
    fun dailyArticle(today: java.time.LocalDate): ClassroomItem? {
        val list = articles()
        if (list.isEmpty()) return null
        val epochDay = today.toEpochDay().toInt()
        return list[Math.floorMod(epochDay, list.size)]
    }

    fun featuredCourses(): List<ClassroomItem> =
        courses().filter { it.featured || it.featured.not() }.take(10)

    fun coverImage(cover: String?): String? = cover
}
