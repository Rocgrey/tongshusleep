package com.rocgrey.sleeptongshu.core.data

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import kotlinx.coroutines.flow.Flow

/** 睡眠记录：结构对齐 iOS SwiftData SleepRecord。 */
@Entity(tableName = "sleep_records")
data class SleepRecordEntity(
    @PrimaryKey val id: String,
    val startEpochMs: Long,
    val endEpochMs: Long,
    /** 原始时区 ID，day 标签按它计算 */
    val zoneId: String,
    val source: String,
    val segmentsJson: String,
    val heartSamplesJson: String,
    val averageHeartRate: Double? = null,
    val averageSpO2: Double? = null,
    val averageRespiratoryRate: Double? = null,
    val note: String? = null,
    val metadataJson: String,
    val aisScore: Int? = null,
)

/** 课程学习进度：对应 iOS lesson.{sha256}。 */
@Entity(tableName = "learning_progress")
data class LearningProgressEntity(
    @PrimaryKey val itemKey: String,
    val seconds: Double,
    val duration: Double,
    val updatedAt: Long,
)

/** 设备步数（蓝牙设备来源，本地合并）。 */
@Entity(tableName = "device_steps")
data class DeviceStepEntity(
    @PrimaryKey val mergeKey: String,
    val deviceId: String,
    val deviceName: String,
    val day: String,
    val steps: Int,
    val readAt: Long,
    val dayBasis: String,
)

/** 设备体征历史。 */
@Entity(tableName = "wearable_vitals")
data class WearableVitalEntity(
    @PrimaryKey val id: String,
    val deviceId: String,
    val kind: String,
    val value: Double,
    val recordAt: Long,
    val unit: String,
    val origin: String,
)

@Dao
interface SleepRecordDao {
    @Query("SELECT * FROM sleep_records ORDER BY endEpochMs DESC")
    fun observeAll(): Flow<List<SleepRecordEntity>>

    @Query("SELECT * FROM sleep_records ORDER BY endEpochMs DESC")
    suspend fun all(): List<SleepRecordEntity>

    @Query("SELECT * FROM sleep_records WHERE id = :id")
    suspend fun byId(id: String): SleepRecordEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(record: SleepRecordEntity)

    @Query("DELETE FROM sleep_records WHERE id = :id")
    suspend fun delete(id: String)

    @Query("DELETE FROM sleep_records")
    suspend fun deleteAll()
}

@Dao
interface LearningProgressDao {
    @Query("SELECT * FROM learning_progress WHERE itemKey = :key")
    suspend fun byKey(key: String): LearningProgressEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(progress: LearningProgressEntity)
}

@Dao
interface DeviceStepDao {
    @Query("SELECT * FROM device_steps ORDER BY day DESC")
    suspend fun all(): List<DeviceStepEntity>

    @Query("SELECT * FROM device_steps ORDER BY day DESC")
    fun observeAll(): Flow<List<DeviceStepEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertAll(records: List<DeviceStepEntity>)

    @Query("DELETE FROM device_steps")
    suspend fun deleteAll()
}

@Dao
interface WearableVitalDao {
    @Query("SELECT * FROM wearable_vitals ORDER BY recordAt DESC")
    suspend fun all(): List<WearableVitalEntity>

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(records: List<WearableVitalEntity>)

    @Query("DELETE FROM wearable_vitals")
    suspend fun deleteAll()
}

@Database(
    entities = [
        SleepRecordEntity::class,
        LearningProgressEntity::class,
        DeviceStepEntity::class,
        WearableVitalEntity::class,
    ],
    version = 1,
    exportSchema = false,
)
abstract class AppDatabase : RoomDatabase() {
    abstract fun sleepRecordDao(): SleepRecordDao
    abstract fun learningProgressDao(): LearningProgressDao
    abstract fun deviceStepDao(): DeviceStepDao
    abstract fun wearableVitalDao(): WearableVitalDao

    companion object {
        @Volatile
        private var instance: AppDatabase? = null

        fun get(context: Context): AppDatabase =
            instance ?: synchronized(this) {
                instance ?: Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "tongshusleep.db",
                ).build().also { instance = it }
            }
    }
}
