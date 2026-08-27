# ProGuard rules for Grocery ERP

# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Drift / SQLite
-keep class * extends androidx.sqlite.db.SupportSQLiteOpenHelper { *; }
-keep class drift.sqlite.** { *; }

# Keep model classes for serialization
-keep class com.grocery.grocery_erp.** { *; }
-keep class grocery_erp.** { *; }

# Kotlin
-dontwarn kotlinx.coroutines.**
-keep class kotlinx.coroutines.** { *; }

# Preserve annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes SourceFile,LineNumberTable

# Remove logs in release
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
}
