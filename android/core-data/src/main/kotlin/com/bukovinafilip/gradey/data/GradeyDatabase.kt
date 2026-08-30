package com.bukovinafilip.gradey.data

import android.content.Context
import android.database.sqlite.SQLiteException
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.RoomDatabase
import androidx.room.Room
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Entity(
    tableName = "cache_entries",
    indices = [Index(value = ["cachedAtEpochMillis"], name = "index_cache_entries_cachedAtEpochMillis")],
)
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
    version = 2,
    exportSchema = true,
)
abstract class GradeyDatabase : RoomDatabase() {
    abstract fun cacheEntries(): CacheEntryDao
}

internal object GradeyDatabaseMigrations {
    val Migration1To2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL(
                "CREATE INDEX IF NOT EXISTS `index_cache_entries_cachedAtEpochMillis` " +
                    "ON `cache_entries` (`cachedAtEpochMillis`)",
            )
        }
    }

    val All: Array<Migration> = arrayOf(Migration1To2)
}

internal fun buildGradeyDatabase(
    context: Context,
    name: String = "gradey.db",
): GradeyDatabase {
    fun create(): GradeyDatabase = Room.databaseBuilder(context, GradeyDatabase::class.java, name)
        .addMigrations(*GradeyDatabaseMigrations.All)
        // This database contains reproducible cache only; unknown historical schemas may be rebuilt.
        .fallbackToDestructiveMigration(dropAllTables = true)
        .build()

    val initial = create()
    return try {
        // Force validation here so a corrupt disposable cache cannot crash a later user flow.
        initial.openHelper.writableDatabase
        initial
    } catch (error: SQLiteException) {
        initial.close()
        val databasePath = context.getDatabasePath(name)
        val removed = context.deleteDatabase(name)
        if (!removed && databasePath.exists()) throw error
        create().also { recovered -> recovered.openHelper.writableDatabase }
    }
}
