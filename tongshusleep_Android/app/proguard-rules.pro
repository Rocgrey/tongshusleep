# kotlinx-serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class com.rocgrey.sleeptongshu.**$$serializer { *; }
-keepclassmembers class com.rocgrey.sleeptongshu.** { *** Companion; }
-keepclasseswithmembers class com.rocgrey.sleeptongshu.** { kotlinx.serialization.KSerializer serializer(...); }
# Room
-keep class * extends androidx.room.RoomDatabase { *; }
