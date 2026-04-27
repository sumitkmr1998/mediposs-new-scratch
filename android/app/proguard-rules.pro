# ObjectBox ProGuard Rules
-keep class com.medipos.medipos.shared.models.** { *; }
-keep class io.objectbox.relation.ToOne { *; }
-keep class io.objectbox.relation.ToMany { *; }
-keep class io.objectbox.relation.RelationInfo { *; }
-keep class * extends io.objectbox.relation.RelationInfo { *; }
-keep class io.objectbox.** { *; }
-keep class io.objectbox.InternalAccess { *; }

# Keep Flutter classes
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Shelf and other dependencies that might use reflection
-keep class com.google.gson.** { *; }
-keep class shelf.** { *; }
