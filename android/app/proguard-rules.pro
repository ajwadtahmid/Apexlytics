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

# Don't rename the exception types whose names we key logging and crash
# grouping on.
-keep public class com.ajwadtahmid.apexlytics.** extends java.lang.Exception

# flutter_local_notifications resolves the notification icon by name at
# runtime via Resources.getIdentifier(); R8 cannot see that reference, and
# shrinkResources would otherwise be free to strip the drawable.
-keep class com.dexterous.** { *; }
