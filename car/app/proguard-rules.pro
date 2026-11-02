# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class ai.allo.car.**$$serializer { *; }
-keepclassmembers class ai.allo.car.** { *** Companion; }
-keepclasseswithmembers class ai.allo.car.** { kotlinx.serialization.KSerializer serializer(...); }

# Pleos SDK
-keep class ai.pleos.** { *; }
-dontwarn ai.pleos.**

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
