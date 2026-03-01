# Android AGENTS Instructions

- When the user asks for an Android release build or Play publish, increment `versionCode` in `android/app/build.gradle.kts` before creating the release artifact.
- Keep `versionName` unchanged unless the user explicitly asks to change it.
- Apply the versionCode bump once per requested release build so every uploaded AAB/APK has a new Play-acceptable version code.
