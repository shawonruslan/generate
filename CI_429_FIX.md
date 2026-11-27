# CI run #108: Android job failed with Maven Central HTTP 429 (v1.20.3+56)

## What the log actually says

Windows x64 job: SUCCESS. Android APK job: FAILURE - but not a
code error. Gradle never reached compilation:

    Could not GET 'https://repo.maven.apache.org/maven2/org/jetbrains/
    kotlin/kotlin-stdlib/2.0.21/kotlin-stdlib-2.0.21.pom'.
    Received status code 429 from server: Too Many Requests

Maven Central rate-limited the GitHub runner's shared IP while
Gradle downloaded the Kotlin plugin classpath (kotlin-stdlib,
kotlin-gradle-plugin, ...). Flutter's automatic single retry hit
the same 429 and the job died in ~40 s.

## Fix (build.yml, Android job only)

1. **Google's GCS mirror of Maven Central first**: the existing
   "Patch Android manifest + signing" step now also patches the
   generated `android/settings.gradle.kts`, inserting
   `maven { url = uri("https://maven-central.storage-download.googleapis.com/maven2") }`
   as the first repository in BOTH `pluginManagement` and
   `dependencyResolutionManagement`. Plugin + dependency downloads
   then come from Google's mirror instead of the rate-limited
   repo.maven.apache.org. (Patch logic simulation-tested against
   a stock flutter-create settings.gradle.kts: 2 insertions, in
   the right blocks.)
2. **Gradle download retries**: new step writes
   `~/.gradle/gradle.properties` with
   `org.gradle.internal.repository.max.retries=12` and
   `initial.backoff=4000`, so a transient 429 is retried with
   backoff instead of failing the job.

build.yml parses as valid YAML after the change.

## Note

A plain re-run of run #108 would probably pass too (429s are
transient) - this fix makes the Android job stop depending on
that luck. No app code changed in this version.
