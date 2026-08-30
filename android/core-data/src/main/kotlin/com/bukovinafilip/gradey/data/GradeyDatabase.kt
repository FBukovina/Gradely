package com.bukovinafilip.gradey.data

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.RoomDatabase

@Entity(tableName = "cache_entries")
data class CacheEntryEntity(
    @PrimaryKey val key: String,
    val payload: String,
    val cachedAtEpochMillis: Long,
)

@Dao
interface CacheEntryDao {
    @Query("select * from cache_entries where key = :key")
    suspend fun load(key: String): CacheEntryEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun save(entity: CacheEntryEntity)

    @Query("delete from cache_entries where key = :key")
    suspend fun clear(key: String)

    @Query("delete from cache_entries where key like :prefix || '%'")
    suspend fun clearPrefix(prefix: String)

    @Query("delete from cache_entries")
    suspend fun clearAll()
}

@Database(
    entities = [CacheEntryEntity::class],
    version = 1,
    exportSchema = false,
)
abstract class GradeyDatabase : RoomDatabase() {
    abstract fun cacheEntries(): CacheEntryDao
}
