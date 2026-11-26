# AmkyawDev TTS Studio

**Repository:** `amkyawdev-tts-app`

AmkyawDev TTS Studio - hybrid offline/online text to speech

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

---

## Mobile Interface Preview

<p align="center">
  <img src="assets/readme/tts-studio-mobile.svg" alt="Concept preview of the AmkyawDev TTS Studio home screen: Burmese script input, Piper, Gemini, VieNeu and GGUF Hub engine choices, a voice profile, a Generate Speech action and recent audio" width="360" />
  <img src="assets/readme/gguf-model-hub-mobile.svg" alt="Concept preview of the Hugging Face GGUF Model Hub: repository URL and search, GGUF file discovery with quantization and sizes, compatibility states, local GGUF import and a safety note" width="360" />
</p>

<p align="center"><sub><strong>Left:</strong> TTS Studio home concept &nbsp;·&nbsp; <strong>Right:</strong> Hugging Face GGUF Model Hub concept</sub></p>

> **These are original concept previews, not screenshots of a completed app.**
> They show design intent only. Labels, colors, engine states and features may
> change, and nothing in these images should be read as a claim that a feature
> is implemented or that a particular model can synthesize speech on-device.
> GGUF is a model container, not a universal TTS runtime; only verified
> architectures with the required codec / projector are marked runnable.
> Refer to the repository documentation for the current implementation status.

---

## Android builds and CI

The workflow [`.github/workflows/android-building.yml`](.github/workflows/android-building.yml)
builds the Flutter Android app on every push to `main`, every pull request, and
on manual dispatch.

### What it does

1. Sets up Java 21, Flutter `3.50.1` and the Gradle cache.
2. Runs `dart format --set-exit-if-changed`, `flutter analyze` and `flutter test`.
3. Builds a release APK and a release AAB.
4. Uploads both files as the `amkyawdev-tts-studio-android` artifact for 14 days.

### Download the artifacts

1. Open the repository's **Actions** tab.
2. Select **Android Build** → the latest successful run.
3. Download `amkyawdev-tts-studio-android` from the **Artifacts** section.
4. The ZIP contains:
   - `app-release.apk` — installable on Android devices.
   - `app-release.aab` — upload bundle for Google Play.

Workflow page:
<https://github.com/amkyawdev/amkyawdev-tts-app/actions/workflows/android-building.yml>

### Signing

No keystore or password is committed. If the four repository secrets below are
absent, the release APK/AAB is signed with the Android debug key so CI still
produces installable test artifacts. That is **not** suitable for Play Store
distribution.

| Secret | Purpose |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded JKS/PKCS12 keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Release key alias |
| `ANDROID_KEY_PASSWORD` | Key password |

When all four are configured, the workflow decodes the keystore into
`$RUNNER_TEMP`, exports `ANDROID_KEYSTORE_FILE` and the matching variables, and
`android/app/build.gradle.kts` uses the release signing config. The decoded
keystore exists only for the job.

### Local commands

```bash
flutter pub get
dart format lib test integration_test
flutter analyze
flutter test
flutter build apk --release
flutter build appbundle --release
```

Artifacts are written to:

- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab`

