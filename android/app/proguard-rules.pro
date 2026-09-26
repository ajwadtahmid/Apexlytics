# R8 keep rules for the release build (isMinifyEnabled = true).
#
# Flutter's own engine classes and the plugins' registrant are covered by the
# consumer rules each dependency ships, so this file only needs the cases R8
# can't see through.

# Sentry resolves some classes reflectively and ships native/JNI glue; its own
# consumer rules cover most of it, but keep the line-number and source-file
# attributes so release stack traces stay symbolicatable.
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*

# Keeps the flutter_local_notifications classes (manifest receivers, Gson-
# serialized notifications). Doesn't protect the icon drawables — res/raw/
# keep.xml does.
-keep class com.dexterous.** { *; }
