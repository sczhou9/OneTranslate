# OneTranslate

OneTranslate is a local macOS translation keyboard inspired by the workflow at [TranslateFlow](https://translate.sensebeing.cn/): hold `Fn`, release it, and the selected text is translated in place. If nothing is selected, it uses the value of the focused text field.

The app has no telemetry or built-in translation service. Its only model interface is the OpenAI-compatible `POST /chat/completions` API. It sends text only to the endpoint configured in Settings. The default endpoint is `http://localhost:11434/v1/chat/completions`; change the endpoint and model name for your own compatible server.

## Run

```sh
swift run
```

On first launch, add the exact `OneTranslate.app` you are running under **System Settings → Privacy & Security → Accessibility** and **Input Monitoring**. Accessibility enables reading/replacing focused text; Input Monitoring enables `Fn` detection. The app appears as `OT` in the menu bar. Open **Settings…** to configure the endpoint, optional API key, model, source/target language, mode, and tone. Hold and release `Fn` to translate.

Local builds use standard ad-hoc signing. Rebuilding can require granting macOS permissions again. For a stable developer identity, set ONETRANSLATE_SIGNING_IDENTITY to your own installed signing certificate when building. Never weaken the designated requirement to an identifier-only rule.

With no selection, Fn translates the focused field to **To**. With a selection, Fn reverse-translates only those words to **Reverse to**, preserving the surrounding text. **Source language** uses **From**, or your Mac’s preferred language when From is Auto. Choose an explicit Reverse to language when needed. An animated circular indicator stays visible until the request completes or fails.

**Launch at login:** enable the toggle under Startup & undo in Settings. This uses macOS Login Items, and may require approval in System Settings. It is off unless you enable it.

**Undo:** choose Undo last translation in the menu-bar menu. It restores the exact original wording without calling a model. Only the last successful edit is retained, in memory, until the app quits. Undo refuses to overwrite later edits. This restores text, not rich-text formatting.

**Replacement:** editable fields must expose their value and selection range through Accessibility. The app verifies the resulting text before reporting success. Read-only pages and editors that do not expose these attributes cannot be replaced in place. Keep the original field focused while translating.

**Privacy:** only the selected words (or the focused field if nothing is selected) are sent to the configured endpoint. Remote endpoints must use HTTPS; HTTP is allowed only on loopback for local models. Requests use an ephemeral session with no disk cache or cookies, and redirects are rejected. Your API key is stored in macOS Keychain; preferences stay in macOS UserDefaults. Original and translated text are not written to disk. Clipboard fallback restores the prior clipboard unless you copy something new in the meantime.

Source uploads must exclude build directories, app bundles, distributions, logs, credentials, and personal settings. Tests use synthetic text and do not read Keychain or contact a model.

## Build a launchable app

```sh
./scripts/build-app.sh
open build/OneTranslate.app
```

The generated bundle is universal for Apple Silicon and Intel Macs. The current implementation is macOS-only because the system-level text replacement and Fn event are platform APIs.

The same command also creates `dist/OneTranslate-macOS-universal-0.0.1.dmg` for distribution. Set `ONETRANSLATE_VERSION` when building another release version; the DMG volume name and filename follow that value.
