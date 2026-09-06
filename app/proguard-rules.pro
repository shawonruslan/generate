-keep class com.github.junrar.** { *; }
-dontwarn com.github.junrar.**
-dontwarn okhttp3.**
-dontwarn okio.**
-keepattributes *Annotation*

# slf4j (pulled in by junrar) - no Android binding, safe to ignore
-dontwarn org.slf4j.**
-dontwarn org.slf4j.impl.StaticLoggerBinder
-dontwarn org.slf4j.impl.StaticMDCBinder
-dontwarn org.slf4j.impl.StaticMarkerBinder
-dontwarn java.lang.invoke.StringConcatFactory
