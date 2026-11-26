# AmkyawDev TTS Studio

**A dark, mobile-first Flutter app for speech generation and offline subtitle translation.**
Speech comes from Piper (on-device), Gemini (your own key), VieNeu (your own
server, online only) or the device voice. GGUF models are used **only for text
and subtitle translation**, never for speech.

![Brand icon](assets/branding/icon_256.png)

[![Android Build](https://github.com/amkyawdev/amkyawdev-tts-app/actions/workflows/android-building.yml/badge.svg?branch=main)](https://github.com/amkyawdev/amkyawdev-tts-app/actions/workflows/android-building.yml)
![Flutter](https://img.shields.io/badge/Flutter-3.50.1-02569B?logo=flutter)
![Version](https://img.shields.io/badge/app-0.2.0%2B2-orange)

---

## What changed in 0.2.0

| Area | Status |
| --- | --- |
| Searchable language picker (English, native script, locale, aliases) | **Implemented** |
| SVG brand source + generated Android/iOS launcher icons | **Implemented** |
| Offline subtitle/text translation (SRT, VTT, TXT) | **Implemented; device runtime unverified** |
| GGUF model manager (verified metadata, resumable downloads, SHA-256) | **Implemented** |
| GGUF as a speech engine | **Removed by design — GGUF is translation-only** |
| Piper offline speech | **Implemented; device inference still unverified** |
| VieNeu speech | **Online-only adapter (server required)** |
| Physical-device verification | **NOT VERIFIED in this environment (no KVM, no phone)** |

The previous APK looked broken on a phone. The concrete defects fixed in this
release are listed in [Fixes in 0.2.0](#fixes-in-020).

---

## Features

### Studio (speech)

- Engine chips with real status: Piper, Gemini, VieNeu, System.
- **Searchable language picker**: tap the language row to open a bottom sheet
  with instant filtering over English names, native names (မြန်မာ, 中文, 日本語),
  locale codes (`my-MM`, `zh-CN`) and aliases (Burmese / Myanmar / myanmar).
  Recently used languages are grouped on top, the current language is marked,
  and the empty state offers a clear-search action.
- Selecting a language filters the voice list to that language and keeps a valid
  voice selected. Languages are derived from the voice metadata each engine
  actually reports — no language is advertised without a voice behind it.
  Unknown or missing locales fall back to an "Unknown language" group instead of
  crashing or hiding the voice.
- Language **and** voice selections persist in settings.
- Progress, cancellation, history logging and playback.

### Translate (new, GGUF)

- Import `.srt`, `.vtt` or `.txt` (max 4 MB) or paste text.
- Encoding detection: UTF-8 (with/without BOM), UTF-16 LE/BE, Latin-1 fallback
  with a visible warning, so Burmese Unicode survives.
- Source language (including auto-detect) and target language, default
  **မြန်မာ (Burmese)**; source/target swap.
- SRT parsing is structural: cue indices, timestamps, ordering, blank lines and
  multi-line cues are preserved; HTML tags such as `<i>`, speaker labels and
  numbers are passed to the model with instructions to keep them, and never
  altered by the parser.
- Chunks are derived from the model's real context window; progress shows real
  completed/total chunks, the current stage (Loading model → Preparing text →
  Translating → Saving), the file name and the model name, with cancel and
  retry. Text is never silently truncated.
- Editable result preview, export as `<name>.my.srt|vtt|txt` in app storage with
  a share/save action.
- **Offline only.** No online translation backend is configured in this build,
  so nothing is uploaded. The privacy note is shown on the screen.

### Translation models (GGUF manager)

Curated, openly licensed GGUF text models with metadata read from the real
upstream repositories:

| Model | File | Size | Context | License | Source |
| --- | --- | --- | --- | --- | --- |
| Qwen3 0.6B Q4_K_M | `Qwen3-0.6B-Q4_K_M.gguf` | 396,705,472 B | 40,960 | Apache-2.0 | [unsloth/Qwen3-0.6B-GGUF](https://huggingface.co/unsloth/Qwen3-0.6B-GGUF) |
| Qwen2.5 0.5B Instruct Q4_K_M | `qwen2.5-0.5b-instruct-q4_k_m.gguf` | 491,400,032 B | 32,768 | Apache-2.0 | [Qwen/Qwen2.5-0.5B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF) |
| SmolLM2 360M Instruct Q4_K_M | `SmolLM2-360M-Instruct-Q4_K_M.gguf` | 270,590,560 B | 8,192 | Apache-2.0 | [unsloth/SmolLM2-360M-Instruct-GGUF](https://huggingface.co/unsloth/SmolLM2-360M-Instruct-GGUF) |

Each file also carries the published SHA-256 (Hugging Face LFS object id).
Architectures and context lengths were read from the first kilobytes of the real
GGUF files, not from marketing text. Burmese quality of these small models is
**not verified**; the catalogue says so.

Downloads:

- streaming with real byte/percentage progress, pause/resume/cancel/retry;
- resumable via HTTP `Range` only when the server answers `206`; a `200` answer
  restarts the file instead of appending to a partial download; `Content-Range`
  start offsets are validated;
- SHA-256 verification (when published), size verification, temp `.part` file,
  atomic rename, partial cleanup on failure;
- free-space check with headroom, safe filenames, one download at a time;
- download state persisted across restarts and reconciled with disk on launch;
- delete with confirmation, "Use for translation", "Verify" (re-reads the GGUF
  header, size and hash).

Storage: `Android/data/dev.amkyaw.amkyaw_tts_studio/files/gguf/models/…`
(app-specific; no broad storage permission is requested).

### Speech engines

| Engine | Mode | Status |
| --- | --- | --- |
| **Piper ONNX** | Offline after model download | English `en_US-lessac` catalogue, checksum-verified download, sherpa-onnx + piper-phonemize inference in an isolate. Device inference unverified. **Not Burmese.** |
| **Gemini TTS** | Online, your key | `gemini-3.8-flash-tts` via the Interactions API; key in platform secure storage. Burmese listed by the model; quality unverified here. |
| **VieNeu** | **Online-only** | Adapter for a separately deployed VieNeu server. No on-device VieNeu runtime exists in this project, so it is labelled online in the UI. |
| **System TTS** | Device | Uses installed Android/iOS voices. Android 11+ package visibility (`TTS_SERVICE` query) is declared so voices can be enumerated. |
| **GGUF** | — | **Not a speech engine.** Translation only. |

---

## Fixes in 0.2.0

- **Startup could show a black screen.** `main()` awaited preferences and SQLite
  before `runApp` with no error path. Bootstrap is now a widget with a splash, a
  readable failure screen and retry; the database and app data are untouched.
- **Android 11+ voice enumeration.** Added the `android.intent.action.TTS_SERVICE`
  `<queries>` entry that `flutter_tts` needs to see the system speech engine.
- **Voice/language races.** Switching engines quickly could apply the previous
  engine's voice list to the new engine. Requests are now validated against the
  current engine id, and switching engines cancels an in-flight generation.
- **Generation could attribute audio to the wrong engine.** Engine id, voice id
  and speed are captured when generation starts; empty/zero-length audio files
  are rejected instead of being logged as success.
- **Voice errors were swallowed** (`catch (_) => []`), showing an empty list
  instead of the reason. Failures now surface as an error banner with the real
  message, and the loading state is shown correctly on first open.
- **Engine recreation churn.** The engine registry no longer rebuilds on every
  settings write (voices, languages, theme) and disposes engines it owned.
- **Piper phonemizer language.** The phonemizer voice is derived from the model
  manifest and non-English manifests are refused instead of being phonemised as
  English.
- **System TTS voice cache** is rebuilt per enumeration instead of growing.
- **Player stream leaks/disposal** are guarded against state writes after
  disposal.

---

## Build and test

Requirements: Flutter 3.50.1 (Dart 3.14), JDK 21, Android SDK 36.

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test integration_test
flutter analyze
flutter test
flutter build apk --release
```

Regenerate launcher icons from the canonical SVG:

```bash
pip install cairosvg
python3 tool/generate_icons.py
```

The script rasterises `assets/branding/icon.svg` into:

- `android/app/src/main/res/mipmap-{mdpi..xxxhdpi}/ic_launcher.png` (legacy, API 24–25)
- `android/app/src/main/res/mipmap-{mdpi..xxxhdpi}/ic_launcher_foreground.png`
  (adaptive foreground inside a 108 dp canvas so masking cannot clip it)
- `mipmap-anydpi-v26/ic_launcher.xml` + `values/colors.xml` (adaptive icon)
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` (opaque, App Store safe)
- `assets/branding/icon_256.png` and `icon_512.png` for the in-app brand mark

CI: `.github/workflows/android-building.yml` runs format, analyze, tests and a
release APK/AAB build on Flutter **3.50.1**, which matches the pubspec SDK
constraint `^3.14.0`; Java 21 and Android 36 match `compileSdk`/`targetSdk`. The
workflow does not pin `packages: tools`, so it is not affected by the removal of
the legacy `tools` SDK package.

The APK built for this commit is
`amkyawdev-tts-studio-0.2.0-test-signed.apk` (335,453,049 bytes, SHA-256
`f771d75278413aec296af1f49798d2f3d4a6134c8ef36ed7c5382c7eac3cc49d`,
`CN=Android Debug` — test-signed, not production-signed).

Signing: release builds use the four `ANDROID_KEYSTORE_*` secrets when present
and otherwise fall back to the debug key (test-signed). No keystore or key is
committed.

---

## Verification matrix (this environment, 2026-11-26)

| Check | Result |
| --- | --- |
| `dart format` | PASS |
| `flutter analyze` | PASS (0 errors/warnings) |
| `flutter test` | PASS (unit + widget tests, local HTTP download server) |
| `flutter build apk --release` | PASS — 335,453,049 bytes, test-signed |
| APK install on a phone | **NOT VERIFIED — no device or emulator available** |
| Piper on-device inference | **NOT VERIFIED on a phone** |
| GGUF translation on-device | **NOT VERIFIED on a phone** |
| Launcher icon rendering on a device | **NOT VERIFIED on a phone** |

No claim in this README is based on an emulator or phone run in this
environment: it has no `/dev/kvm` and no attached Android device.

### Manual phone checklist

1. Install the APK, open the app. You should see the dark Studio screen with the
   brand mark in the header (no black screen, no launcher icon placeholder).
2. **Studio → language row** → search `မြန်မာ`, `Burmese`, `my-MM`; pick a
   language; confirm the voice list changes.
3. **Settings → Gemini**: paste your key, tap *Validate*. Then generate speech
   and play it. If the key is missing the app must show an actionable error.
4. **Models**: download the English Piper model, then generate with Piper. Piper
   does not speak Burmese; English text only.
5. **Translate**: install a translation model, import an `.srt`, translate to
   Burmese, edit the preview, share/save. Then enable airplane mode and repeat —
   translation must still work.
6. **Translate** with no model installed: the app must guide you to the model
   manager and refuse to translate (no fake output).
7. Restart the app: engine, language, voice and translation model selections
   must be remembered.

Useful commands while testing:

```bash
adb install -r app-release.apk
adb shell dumpsys package dev.amkyaw.amkyaw_tts_studio | grep -E "versionName|versionCode"
adb logcat -s flutter:V AndroidRuntime:E
adb shell am start -n dev.amkyaw.amkyaw_tts_studio/.MainActivity
```

---

## Project structure

```text
lib/
  app.dart                     Shell, navigation, PageHeader, BrandMark
  main.dart                    Resilient bootstrap + error screen
  core/                        Theme, errors, logging, formatters
  services/                    Settings, SQLite history, secure keys, storage
  providers/                   Studio, history, models, player, translation
  tts/                         Speech engines (Piper, Gemini, VieNeu, System)
    models/tts_language.dart   Language names, native names, aliases
    voices/voice_catalog.dart  Pure language grouping/search/selection
  gguf/                        Translation model catalogue, download manager,
                               GGUF header reader, compatibility gate
  translate/                   SRT/VTT/TXT parsing, chunking, translation
                               pipeline, llama.cpp backend (llamadart)
  features/
    studio/                    Speech UI + searchable language picker
    translate/                 Translation workflow + waiting animation
    models/                    Piper models + translation model manager
    history/ player/ settings/ about/
assets/branding/               icon.svg (canonical) + generated PNGs
tool/generate_icons.py         Reproducible icon generation
test/                          Unit, widget and local-HTTP tests
```

---

## Known limitations

- **No on-device verification** of Piper, GGUF translation, playback, sharing or
  the launcher icon in this build environment.
- Small GGUF models produce weak Burmese. The catalogue exposes real metadata,
  but translation quality is not verified.
- GGUF translation loads the whole model into RAM (llama.cpp requirement);
  the models listed need roughly 1–2 GB. Low-RAM phones may fail to load them —
  the UI warns but cannot measure free RAM precisely.
- Piper's catalogue is English-only, and the downloader decompresses the archive
  in memory (≈21–67 MB), which is heavy on very low-RAM devices.
- VieNeu has no offline runtime here; it remains an online adapter.
- MP3 export is not implemented; exported audio is WAV (or CAF on iOS).
- iOS was not built in this environment.
- No GitHub Release or tag was published for 0.2.0: releasing is a separate,
  explicit decision. The commit is on `main` and CI builds the APK.

---

## Privacy

- Gemini key: platform secure storage; never in history, logs or the repo.
- VieNeu token: secure storage; text goes to the server you configure.
- Translation: fully local; nothing is uploaded.
- History: local SQLite with text, engine, voice, timestamps and audio paths.
- No analytics, ads or crash reporters.

---

## License and third-party components

No `LICENSE` file is provided, so the app source is not granted an open-source
license. Third-party components keep their own licenses: sherpa-onnx
(Apache-2.0), piper-phonemize/espeak-ng (GPL-3.0 — review obligations before
redistributing), llamadart (see its pub.dev page), Piper voice models (follow
each model card), and the GGUF translation models listed above
(Apache-2.0; each repository's model card governs use).

---

## Admin / Developer

[![TikTok](https://img.shields.io/badge/TikTok-@amkyaw.dev1-000000?logo=tiktok&logoColor=white)](https://www.tiktok.com/@amkyaw.dev1)
