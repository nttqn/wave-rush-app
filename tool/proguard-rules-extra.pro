# Appended onto the freshly-generated android/app/proguard-rules.pro by
# the CI workflow's "Enable release code shrinking" step.
#
# WorkManager's Room-backed WorkDatabase_Impl is only referenced via
# reflection, so R8 (especially on recent AGP versions) strips it as
# "unused", which crashes the app on launch with "Unable to get provider
# androidx.startup.InitializationProvider" / "Failed to create an
# instance of androidx.work.impl.WorkDatabase". WorkManager itself is
# pulled in transitively by google_mobile_ads, not used directly by this
# app. See CLAUDE.md for the full story.
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.work.ListenableWorker {
    <init>(android.content.Context, androidx.work.WorkerParameters);
}
