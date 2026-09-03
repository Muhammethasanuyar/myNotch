# vibe-notch — Harvest Notu

| | |
|---|---|
| Repo | https://github.com/farouqaldori/vibe-notch (eski adı "Claude Island"; Xcode proje klasörü hâlâ `ClaudeIsland/`) |
| Klon | `references/vibe-notch` @ `10f1d24` (2026-04-20) |
| Lisans | Apache-2.0 (`LICENSE.md`; repo kökünde **NOTICE dosyası yok**) |
| Devşirme modu | **Kod adapte et** + Apache-2.0 yükümlülükleri: lisans metni `THIRD_PARTY_LICENSES.md`'ye eklenir, adapte edilen her dosyada `// Adapted from farouqaldori/vibe-notch (Apache-2.0) — modified` benzeri **değişiklik beyanı** bulunur; NOTICE dosyası olmadığı için taşınacak NOTICE içeriği yok (durum bu notta kayıt altına alındı) |
| İlgili fazlar | Claude modülü **v2** (canlı oturum izleme, notch'tan izin onayı) — Faz 6+; Faz 1'de NotchShape/hover deseni referansı |

## 1. Bizim için değeri

Bu repo **fikir kaynağı**: usage/maliyet değil, **canlı oturum durumu**. Plan §6'daki Claude modülünün bir sonraki sürümünün ne olabileceğini gösteriyor:

- **Claude Code lifecycle hook'ları** ile oturumu gerçek zamanlı izlemek — dosya değişikliğinden tahmin etmeye gerek yok, Claude Code'un kendisi "şu an tool çalıştırıyorum / izin bekliyorum / durdum" diye **haber veriyor**. Bizim §6.1'deki "son 10 sn'de `.jsonl` değişti mi" heuristiğinden kat kat kesin.
- **Notch'tan araç izni onaylama**: `PermissionRequest` hook'u Unix socket üzerinden **senkron** çalışıyor — hook cevabı bekliyor, kullanıcı notch'tan Allow/Deny'a basıyor, karar hook'un stdout'una JSON olarak yazılıyor. Dynamic Island'ın "etkileşimli canlı aktivite" vaadinin en güçlü örneği.
- **Açık durum makinesi** (`SessionPhase` + `canTransition`) ve **tek giriş noktalı event akışı** (`SessionEvent` → `SessionStore.process`) — bizim `NotchModule` / `EventBus` mimarimizle çok uyumlu bir desen.
- Çoklu oturum yönetimi, oturum başına faz, terminal/tmux'a geri dönme, süreç ağacı ile pid/tty eşleme.
- `ClaudePaths` (`CLAUDE_CONFIG_DIR` → kullanıcı override → `~/.config/claude` → `~/.claude`) — üç repo içindeki **en eksiksiz** dizin çözümü.

Ama aynı zamanda **en çok "almayacağımız" barındıran** repo: kullanıcının `~/.claude/settings.json` dosyasına yazıyor, `/tmp`'de socket açıyor, `CGEvent` post ediyor, tmux'a tuş gönderiyor, Mixpanel telemetrisi topluyor. Her biri ayrı bir güvenlik/gizlilik kararı gerektiriyor (§5).

## 2. Hedef dosyalar

| Kaynak dosya (path:line) | Ne yapıyor | Bizde hedef dosya (per docs/PLAN.md §9) | Faz |
|---|---|---|---|
| `ClaudeIsland/Services/Hooks/HookInstaller.swift:34-97` | `settings.json`'a hook kaydı ekleme/temizleme (idempotent) | `Modules/ClaudeUsage/HookInstaller.swift` (v2, **opt-in**) | 6+ |
| `ClaudeIsland/Services/Hooks/HookInstaller.swift:116-216` | `claude --version` ile sürüm tespiti → sürüme göre desteklenen hook seti | `Modules/ClaudeUsage/HookInstaller.swift` | 6+ |
| `ClaudeIsland/Resources/claude-island-state.py:52-71, 74-233` | Hook script: stdin'den JSON, Unix socket'e gönder, `PermissionRequest`'te cevabı **bekle** | `Resources/mynotch-hook.py` (veya küçük bir Swift CLI) | 6+ |
| `ClaudeIsland/Services/Hooks/HookSocketServer.swift:137-197` | `AF_UNIX`/`SOCK_STREAM` sunucu, `O_NONBLOCK`, `chmod 0600`, `DispatchSource` accept | `Modules/ClaudeUsage/HookSocketServer.swift` | 6+ |
| `ClaudeIsland/Services/Hooks/HookSocketServer.swift:16-104` | `HookEvent` Codable (snake_case → camelCase), `HookResponse`, `PendingPermission` | `Modules/ClaudeUsage/HookModels.swift` | 6+ |
| `ClaudeIsland/Services/Hooks/HookSocketServer.swift:425-470` | İzin isteğinde socket'i **açık tutma**, `toolUseId` ile eşleme | `Modules/ClaudeUsage/HookSocketServer.swift` | 6+ |
| `ClaudeIsland/Services/Hooks/HookSocketServer.swift:118-126, 505-520` | `PreToolUse`'dan `tool_use_id` cache'i (FIFO) — `PermissionRequest` bunu taşımıyor | `Modules/ClaudeUsage/HookSocketServer.swift` | 6+ |
| `ClaudeIsland/Models/SessionPhase.swift:66-95+` | `SessionPhase` durum makinesi + `canTransition(to:)` doğrulaması | `Modules/ClaudeUsage/SessionModels.swift` | 6+ |
| `ClaudeIsland/Models/SessionPhase.swift:12-53` | `PermissionContext.formattedInput` — araç girdisini insan okunur özete indirgeme | `Modules/ClaudeUsage/Views/PermissionPopup.swift` | 6+ |
| `ClaudeIsland/Models/SessionEvent.swift:13-78` | Tüm durum değişikliklerinin tek `enum` girişi | `Core/Modules/NotchEvent.swift` deseni | 2, 6+ |
| `ClaudeIsland/Services/State/SessionStore.swift:16-52, 124-176` | `actor` içinde oturum sözlüğü + `CurrentValueSubject` ile UI'a yayın | `Modules/ClaudeUsage/SessionStore.swift` | 6+ |
| `ClaudeIsland/Services/State/SessionStore.swift:1050-1116` | 3 sn'lik periyodik sağlık kontrolü: `kill(pid, 0)` ile ölü oturum temizliği | `Modules/ClaudeUsage/SessionStore.swift` | 6+ |
| `ClaudeIsland/Services/Session/JSONLInterruptWatcher.swift:20-70` | `DispatchSourceFileSystemObject` ile tek dosyayı izleyip yeni satırları okuma | `Modules/ClaudeUsage/ProjectsWatcher.swift` (alternatif teknik) | 4 |
| `ClaudeIsland/Services/Session/ConversationParser.swift:13-58` | Artımlı JSONL parse + `UsageInfo` (input/output/cache token) + cache | `Modules/ClaudeUsage/ProjectsWatcher.swift` | 6 |
| `ClaudeIsland/Core/ClaudePaths.swift:29-112` | 4 kademeli Claude dizini çözümü + `NSLock`'lu cache + `invalidateCache()` | `Modules/ClaudeUsage/ClaudePaths.swift` | 4 |
| `ClaudeIsland/UI/Components/NotchShape.swift:10-60+` | İçbükey üst köşe + yuvarlak alt köşe, `animatableData` | `Core/Window/NotchShape.swift` | 1 |
| `ClaudeIsland/Core/NotchViewModel.swift:12-30, 158-203` | `NotchStatus` (closed/opened/popping) + `NotchOpenReason` + hover/click akışı | `Core/State/NotchState.swift`, `NotchViewModel.swift` | 1 |
| `ClaudeIsland/Core/NotchActivityCoordinator.swift:14-112` | Yanlara genişleyen "live activity" + otomatik gizleme task'ı | `Core/Modules/ModuleManager.swift`, `Core/State/NotchViewModel.swift` | 2 |
| `ClaudeIsland/Services/Shared/ProcessExecutor.swift` | `Process` çağrılarını `actor` arkasında async çalıştırma | `Modules/ClaudeUsage/CCUsageRunner.swift` | 4 |
| `scripts/create-release.sh:48-132` | `notarytool submit` + `stapler staple` (zip ve dmg) | `scripts/release.sh` | 5 |

## 3. Desenler

### 3.1 Claude Code hook'ları ile canlı oturum izleme

**Nasıl çalışıyor:** Uygulama açılışında `HookInstaller.installIfNeeded()` (`ClaudeIsland/Services/Hooks/HookInstaller.swift:13-32`) iki iş yapıyor:

1. Bundle'daki `claude-island-state.py`'yi `<claudeDir>/hooks/` altına kopyalıyor, `0o755` veriyor.
2. `<claudeDir>/settings.json`'a hook kayıtlarını yazıyor (`updateSettings`, a.g.e. 34-97).

Kayıt biçimi (a.g.e. 41-51): komut `"<python> '<mutlak yol>/hooks/claude-island-state.py'"`; üç şablon var — `matcher: "*"` ile, `matcher` + `timeout: 86400` ile, ve matcher'sız. `PreCompact` için `matcher: "auto"` ve `"manual"` ayrı ayrı.

Kaydedilen olaylar (`supportedHookEvents`, a.g.e. 169-216) — **taban set** (her hook destekleyen sürümde var): `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest` (timeout'lu), `Notification`, `Stop`, `SubagentStop`, `SessionStart`, `SessionEnd`, `PreCompact`. Sürüme bağlı ekler: `PostToolUseFailure` (≥2.0.0), `SubagentStart` (≥2.0.43), `PostCompact` (≥2.1.76), `StopFailure` (≥2.1.78), `PermissionDenied` (≥2.1.88).

Sürüm tespiti (`detectClaudeCodeVersion`, a.g.e. 116-147): bilinen yollarda `claude` aranıp `--version` çalıştırılıyor, çıktıdan ilk `X.Y.Z` regex ile alınıyor. Tespit başarısızsa **sadece taban set** kaydediliyor — yorumdaki gerekçe: "Claude Code bilinmeyen hook anahtarlarını reddediyor", eski sürümde yeni anahtar `settings.json`'ı bozuyor (issue #85).

Yazmadan önce **tüm** eski Claude Island hook'ları her olay tipinden temizleniyor (a.g.e. 55-70, `isClaudeIslandHook`: komut `claude-island-state.py` içeriyor mu) → idempotent kurulum, eskimiş anahtarlar (ör. artık desteklenmeyen `PermissionDenied`) temizleniyor. `uninstall()` (a.g.e. 246-283) script'i siliyor ve girdileri geri alıyor; hiç girdi kalmazsa `hooks` anahtarı komple kaldırılıyor.

Python script'i (`ClaudeIsland/Resources/claude-island-state.py:74-233`) stdin'den Claude Code'un verdiği JSON'u okuyor. **Payload alanları:** `session_id`, `hook_event_name`, `cwd`, `tool_name`, `tool_input`, `tool_use_id`, `notification_type`, `message`, `reason`, `error`. Script bunlara kendi bilgisini ekliyor: `pid` (= `os.getppid()`, yani Claude process'i) ve `tty` (`ps -p <ppid> -o tty=` ile, fallback `os.ttyname(stdin/stdout)`, a.g.e. 16-49). Sonra olayı bir **status**'a eşliyor: `UserPromptSubmit`/`PostToolUse`/`SubagentStart`/`SubagentStop`/`PostCompact` → `processing`; `PreToolUse` → `running_tool`; `PermissionRequest` → `waiting_for_approval`; `Stop`/`StopFailure`/`SessionStart`/`Notification(idle_prompt)` → `waiting_for_input`; `SessionEnd` → `ended`; `PreCompact` → `compacting`.

**Bize uyarlama:** Bu, Claude modülü v2'nin çekirdeği. `activity` eşlemesi çok temiz:
- `processing` / `running_tool` → `ModuleActivity.live` + compact'ta pulsing ✳ (plan §6.1'in dosya-mtime heuristiği yerine **kesin sinyal**),
- `waiting_for_approval` → `.urgent` → `EventBus` → `NotchState.popup` (izin popup'ı),
- `waiting_for_input` → kısa "oturum bitti" popup'ı (plan §6.2'deki "oturum özeti"),
- `ended` / hiçbir oturum yok → `.idle`.

Sürüm-kapılı hook kaydı **aynen alınmalı**: bizim de `claude --version` okuyup taban sete düşmemiz gerekir, yoksa eski kurulumları bozarız.

**Dikkat (kritik):** Bu desen **kullanıcının `~/.claude/settings.json` dosyasına YAZIYOR.** Bu, bizim şu ana kadarki "salt-okunur" doktrinimizin dışına çıkan tek şey. Kurallarımız:
1. **Asla otomatik kurma.** vibe-notch açılışta sessizce kuruyor (`AppDelegate.swift:70`) — biz **açık onay** isteyeceğiz (onboarding'de "Canlı oturum izleme için Claude Code'a bir hook kurulacak; ne yaptığını göster / şimdi kurma").
2. Yazmadan önce `settings.json`'ın **yedeğini** al.
3. Atomik yaz (temp + `replaceItemAt`), `JSONSerialization` ile round-trip'te kullanıcının diğer ayarlarını koruyarak (vibe-notch `sortedKeys` + `prettyPrinted` ile tüm dosyayı yeniden yazıyor → kullanıcının formatı/yorumları kayboluyor).
4. Ayarlardan **tek tıkla kaldır** (uninstall) sun.
5. Hook script'i Python yerine **bundle'daki küçük bir Swift/shell binary** olabilir — `detectPython()` (a.g.e. 285-301) `which python3` ile arıyor, yoksa `"python"` diyor; Python 3 olmayan makinede hook sessizce ölür.

### 3.2 Unix socket üzerinden senkron izin onayı

**Nasıl çalışıyor:** Hook script'i olayları `/tmp/claude-island.sock`'a yazıyor (`claude-island-state.py:12`). Normal olaylar "fire and forget"; `PermissionRequest` ise **cevap bekliyor** (a.g.e. 52-71: `sock.settimeout(300)`, `status == "waiting_for_approval"` ise `sock.recv(4096)`).

Uygulama tarafı `HookSocketServer` (`ClaudeIsland/Services/Hooks/HookSocketServer.swift:108-197`): `socket(AF_UNIX, SOCK_STREAM, 0)`, `O_NONBLOCK`, `bind` + `chmod(path, 0o600)` + `listen(fd, 10)`, `DispatchSource.makeReadSource` ile accept döngüsü, hepsi `com.claudeisland.socket` serial queue'sunda.

Kritik kısım (a.g.e. 425-470): olay `expectsResponse` ise (`event == "PermissionRequest" && status == "waiting_for_approval"`, a.g.e. 80-82) **client socket kapatılmıyor**; `PendingPermission` olarak `toolUseId` anahtarıyla saklanıyor ve UI'a iletiliyor. Kullanıcı karar verince `sendPermissionResponse` (a.g.e. 470-505) `HookResponse(decision:reason:)` JSON'unu socket'e yazıp kapatıyor.

Script cevabı alınca Claude Code'un beklediği çıktıyı stdout'a basıyor (`claude-island-state.py:145-176`):
```python
output = {
    "hookSpecificOutput": {
        "hookEventName": "PermissionRequest",
        "decision": {"behavior": "allow"},
    }
}
print(json.dumps(output))
sys.exit(0)
```
Kaynak: `references/vibe-notch/ClaudeIsland/Resources/claude-island-state.py:153-162` (Apache-2.0)

`deny` durumunda `{"behavior": "deny", "message": reason}`. Cevap gelmezse veya `"ask"` ise script sadece `exit(0)` yapıyor → Claude Code kendi normal izin UI'ını gösteriyor. **Zarif düşüş**: uygulama kapalıysa socket bağlanamaz, `send_event` `None` döner, Claude Code hiçbir şey olmamış gibi devam eder.

`tool_use_id` sorunu (a.g.e. 118-126, 505-520): `PermissionRequest` olayları `tool_use_id` taşımıyor, o yüzden `PreToolUse`'dan gelen id'ler `"sessionId:toolName:sortedJSON(input)"` anahtarıyla FIFO kuyruğa cache'leniyor ve `PermissionRequest` geldiğinde pop ediliyor. Cache hit yoksa socket kapatılıyor (Claude Code kendi UI'ını gösteriyor). `SessionEnd`'de cache temizleniyor.

Yaşam döngüsü temizliği: `cancelPendingPermissions(sessionId:)`, `cancelPendingPermission(toolUseId:)` (araç terminalden onaylandıysa) ve `stop()`'ta tüm bekleyen socket'lerin kapatılması.

**Bize uyarlama:** `Modules/ClaudeUsage/HookSocketServer.swift` (v2). Bizim mimaride:
- Socket sunucusu `actor` (Swift 6; vibe-notch `NSLock`'lu `class` kullanıyor, `nonisolated(unsafe)` ile `CurrentValueSubject` taşıyor — bizde `actor` + `AsyncStream` daha temiz),
- Gelen olay → `EventBus` → `ModuleManager` `.urgent` → `NotchState.popup(event:)` → `Modules/ClaudeUsage/Views/PermissionPopup.swift` (Allow / Allow always / Deny),
- Karar → `HookResponse` → socket → hook stdout.

**Dikkat:**
- **Socket yolu `/tmp`'de olmamalı.** `/tmp` tüm kullanıcılar için ortak; `chmod 0600` yardımcı olsa da doğru yer `~/Library/Application Support/MyNotch/hook.sock` veya `NSTemporaryDirectory()` (kullanıcıya özel). Ayrıca sabit isim = iki kullanıcı/iki instance çakışması.
- **Uygulama Claude Code'un çalışmasını bloke ediyor**: hook 300 sn timeout ile bekliyor. Uygulama donarsa/çökerse kullanıcının Claude oturumu 5 dakika asılı kalır. Bizde: timeout'u kısa tutmak (30-60 sn), uygulama kapanırken **tüm bekleyen socket'leri kapatmak** (vibe-notch `stop()`'ta yapıyor — şart), ve panic durumunda socket dosyasını silmek.
- **Bu bir güvenlik yüzeyi**: socket'e yazabilen herkes izin kararı tetikleyebilir. Kullanıcıya özel dizin + `0600` + gelen payload'ın **doğrulanması** gerekiyor.
- İzin onayı UI'ı **yanıltıcı olmamalı**: kullanıcı notch'ta gördüğü komutun tamamını görebilmeli. `PermissionContext.formattedInput` (`Models/SessionPhase.swift:19-53`) 100 karakterde kesiyor — Bash komutu kesilirse kullanıcı ne onayladığını bilmez. Bizde kesme yerine kaydırılabilir tam metin.

### 3.3 Açık durum makinesi + tek giriş noktalı event akışı

**Nasıl çalışıyor:** İki katman:

1. **`SessionPhase`** (`ClaudeIsland/Models/SessionPhase.swift:66-83`): `idle`, `processing`, `waitingForInput`, `waitingForApproval(PermissionContext)`, `compacting`, `ended`. `canTransition(to:)` (a.g.e. 88+) geçişleri **doğruluyor**: `.ended` terminal (hiçbir yere geçmiyor), her durumdan `.ended`'e geçilebiliyor vb. `SessionStore` geçersiz geçişi **sessizce yok saymıyor**, log'luyor (`Services/State/SessionStore.swift:150-154`).
2. **`SessionEvent`** (`ClaudeIsland/Models/SessionEvent.swift:13-78`): durumu değiştirebilecek **her şey** tek bir enum — `hookReceived`, `permissionApproved/Denied/SocketFailed`, `fileUpdated`, `toolCompleted`, `interruptDetected`, `subagentStarted/Stopped/...`, `clearDetected`, `sessionEnded`, `loadHistory`, `historyLoaded`. `SessionStore.process(_:)` (`Services/State/SessionStore.swift:56`) yorumda "**the ONLY way to mutate state**" diyor.

`SessionStore` bir `actor` (a.g.e. 16), oturumları `[String: SessionState]` sözlüğünde tutuyor, UI'a `nonisolated(unsafe) CurrentValueSubject` üzerinden yayın yapıyor (a.g.e. 42-49).

Sağlık kontrolü (a.g.e. 1050-1110): 3 saniyede bir `recheckAllSessions()` — `phase == .ended` olanları siliyor, `kill(pid, 0)` ile process ölmüşse oturumu düşürüyor (`isProcessRunning`, a.g.e. 1112-1116), `processing`/`waitingForApproval` olanlar için dosya senkronizasyonu planlıyor. Yani hook'lar kaçsa bile (Claude Code çökerse `SessionEnd` gelmez) hayalet oturum kalmıyor.

Dosya senkronizasyonu 100 ms debounce'lu `Task` ile (a.g.e. 1005-1042), oturum başına iptal edilebilir.

**Bize uyarlama:** Bu desen bizim `Core/Modules/` sözleşmelerine çok yakın:
- `SessionEvent` ≈ bizim `NotchEvent` + `EventBus` (plan §4.3). "State'i değiştirmenin tek yolu event" kuralı `NotchViewModel` için de geçerli olmalı.
- `SessionPhase.canTransition` ≈ plan §4.2'deki `NotchState` geçiş kuralları ("popup her durumdan araya girebilir, bitince önceki duruma döner"). Bu geçiş tablosunu **saf, `nonisolated`, test edilebilir** bir fonksiyona koymalıyız — vibe-notch tam olarak öyle yapmış.
- `kill(pid, 0)` ile ölü oturum temizliği — v2'de bizde de olmalı.
- Swift 6 uyarlaması: `nonisolated(unsafe) CurrentValueSubject` yerine `AsyncStream` veya `@MainActor` bir observable store; `actor` + Combine karışımı Swift 6'da hep sürtünme yaratıyor.

**Dikkat:** `SessionState` başına `toolTracker`, `subagentState`, `chatItems` gibi çok fazla şey birikiyor (`SessionStore.swift` 1143 satır) — bizim modülümüz bu kadar büyümemeli. MVP+v2 kapsamımız: faz + proje adı + bekleyen izin. Konuşma geçmişi/markdown render (`UI/Views/ChatView.swift` 1230 satır, `ToolResultViews.swift` 1123 satır) **kapsam dışı**.

### 3.4 Claude dizini çözümü (`ClaudePaths`) — üç repodaki en iyisi

**Nasıl çalışıyor:** `ClaudeIsland/Core/ClaudePaths.swift:80-112` dört kademe:

1. `CLAUDE_CONFIG_DIR` env değişkeni (tilde genişletilip **var olup olmadığı kontrol edilerek**),
2. Kullanıcı ayarı `AppSettings.claudeDirectoryName` — mutlak yol (`/` ile başlıyorsa) veya `~` altında dizin adı,
3. `~/.config/claude/` — **"Claude Code v2.1.30+ ile yeni varsayılan"**, ama sadece altında `projects/` varsa,
4. `~/.claude/` (legacy fallback).

Sonuç `NSLock` korumalı olarak cache'leniyor (a.g.e. 29-51); kullanıcı ayarı değiştirince `invalidateCache()` (a.g.e. 74-78). Türetilenler: `hooksDir`, `settingsFile`, `projectsDir`, ve `hookScriptShellPath` — shell'e gömülecek yol **tek tırnakla quote'lanıyor** (`shellQuote`, a.g.e. 114-116: içindeki `'` → `'\''`) çünkü boşluklu yollar komutu bölerdi.

**Bize uyarlama:** `Modules/ClaudeUsage/ClaudePaths.swift` bunu temel alacak. Üç repoyu birleştirince tam resim:
- **vibe-notch**: dört kademe + kullanıcı override + cache invalidation (en iyi yapı),
- **codex-island**: `CLAUDE_CONFIG_DIR` **virgülle ayrılmış çoklu dizin** olabilir + `~/.claude/projects` **ve** `~/.config/claude/projects` **birlikte** taranır,
- **claude-notch-tracker**: yok (sabit `~/.claude/projects`).

Bizim çözümümüz: env (virgüllü liste destekli) → `SettingsStore` override → var olan tüm varsayılan kökler (`~/.config/claude`, `~/.claude`). Tek bir dizin seçmek yerine **birden fazla kökü birden taramak** daha doğru (kullanıcı sürüm geçişi ortasında olabilir).

**Dikkat:** GUI app LaunchServices'ten açıldığında shell env'ini miras almaz → `CLAUDE_CONFIG_DIR` çoğu zaman görünmez (codex-island bunu açıkça not ediyor). Ayarlardan override **şart**. Ayrıca `AppSettings.claudeDirectoryName` gibi bir string yerine bizde `URL` + güvenlik kapsamlı bookmark düşünülebilir (sandbox kapalı olduğu için zorunlu değil).

### 3.5 Notch penceresi ve tıklama: `CGEvent` re-post yaklaşımı (ALMAYACAĞIZ)

**Nasıl çalışıyor:** `NotchPanel` (`ClaudeIsland/UI/Window/NotchWindow.swift:13-65`): `NSPanel`, `[.borderless, .nonactivatingPanel]`, `isFloatingPanel = true`, `becomesKeyOnlyIfNeeded = true`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `isMovable = false`, `collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`, `level = .mainMenu + 3`, `allowsToolTipsWhenApplicationIsInactive = true`, **`ignoresMouseEvents = true`** ve `acceptsMouseMovedEvents = false`.

Yani pencere tüm fare olaylarını yok sayıyor; hover ve tıklama **global `NSEvent` monitor**'larıyla algılanıyor (`Core/NotchViewModel.swift:158-203`), notch geometrisiyle karşılaştırılıyor: `isPointInNotch`, `isPointInOpenedPanel`, `isPointOutsidePanel`. Hover 1 saniye sürerse `notchOpen(reason: .hover)`.

Panel açıkken dışarı tıklanırsa panel kapanıyor **ve tıklama yeniden post ediliyor** (`repostClickAt`, a.g.e. 205-235 ve `NotchWindow.swift:95-120`): ekran koordinatı CGEvent koordinatına çevrilip `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` ile `.cghidEventTap`'e post ediliyor (mouseDown + mouseUp, 0.05 sn gecikmeli).

Yorumda "NotchDrop'un yaklaşımını izliyor" deniyor (`NotchWindow.swift:6-7`).

**Bize uyarlama:** **Bu yaklaşımı almayacağız.** Üç repo üç farklı yol tutuyor:
- codex-island: `hitTest` + global monitor ile `ignoresMouseEvents` toggle,
- claude-notch-tracker: sadece `hitTest`, `ignoresMouseEvents`'e **asla dokunma**,
- vibe-notch: `ignoresMouseEvents = true` sabit + global monitor + kaybedilen tıklamayı `CGEvent` ile yeniden post etme.

vibe-notch'unki en kırılganı: `CGEvent.post(tap: .cghidEventTap)` sentetik olay üretiyor; bu **Accessibility izni** gerektirebilir, olay sırasını bozabilir, ve sürükleme/çift tıklama gibi durumlarda yanlış davranır. Bizim tercihimiz claude-notch-tracker'ın yolu (§ claude-notch-tracker.md 3.5).

Buradan alacağımız iki şey:
- `collectionBehavior` + `level` kombinasyonu (`.mainMenu + 3`; plan §4.1 `.screenSaver` diyor, claude-notch-tracker `.statusBar + 2` — Faz 1'de üçü de denenecek),
- `NotchStatus` (`closed`/`opened`/`popping`) + `NotchOpenReason` (`click`/`hover`/`notification`/`boot`) ayrımı: **neden açıldığını** bilmek kapanma politikası için değerli (bildirimle açılan otomatik kapanır, tıklamayla açılan kapanmaz). Bizim `NotchState`'e (plan §4.2) `openReason` eklemek iyi fikir.

**Dikkat:** `hover 1 saniye` bizim plan §4.1'deki ~0.15 sn'den çok daha yavaş — vibe-notch'ta hover paneli **tamamen açıyor** (bizde compact→expanded). Bizim gecikmemiz ayarlanabilir olacak (plan §5).

### 3.6 Yanlara genişleyen "live activity" koordinatörü

**Nasıl çalışıyor:** `NotchActivityCoordinator` (`ClaudeIsland/Core/NotchActivityCoordinator.swift:33-112`) `@MainActor ObservableObject` singleton. `ExpandingActivity` struct'ı (`show`, `type`, `value`) `@Published`; `didSet` içinde `show == true` ise otomatik gizleme planlıyor (`scheduleActivityHide`, a.g.e. 96-111): `activityDuration > 0` ise `Task.sleep` sonrası — ve **tip hâlâ aynıysa** — `hideActivity()`. `duration = 0` "manuel kontrol, otomatik kapanma yok" anlamına geliyor. Tüm geçişler `withAnimation(.smooth)` içinde.

`NotchActivityType` şu an sadece `.claude` ve `.none`.

**Bize uyarlama:** Bu, plan §4.3'teki `ModuleManager` + `ModuleActivity`'nin basit hâli. Bizde:
- `ModuleActivity { idle, live, urgent }` zaten var; `ExpandingActivity.value` bizim compact şeridimizin içeriğine karşılık geliyor,
- "aynı tip hâlâ gösteriliyorsa gizle" guard'ı **popup yarışlarını** önlüyor — plan §4.2'deki "popup bitince önceki duruma döner" davranışında aynı guard gerekli,
- `duration = 0` → manuel kontrol ayrımı bizde `NotchEvent` başına `autoDismissAfter: TimeInterval?` olarak modellenebilir (izin isteği manuel, parça değişimi 2.5 sn).

**Dikkat:** Tek bir global singleton koordinatör, çoklu modül önceliğini çözemez — bizde `ModuleManager` `urgent > live(priority) > idle` çözümü yapacak (plan §4.3). vibe-notch tek modüllü olduğu için bu sorunu yaşamıyor.

### 3.7 JSONL'i tek dosya bazında `DispatchSource` ile izleme

**Nasıl çalışıyor:** `JSONLInterruptWatcher` (`ClaudeIsland/Services/Session/JSONLInterruptWatcher.swift:20-70`) FSEvents yerine **tek dosya** izliyor: `FileHandle(forReadingAtPath:)` + `DispatchSourceFileSystemObject` (`.userInteractive` queue), `lastOffset = handle.seekToEnd()` ile **sondan** başlıyor, dosya büyüdükçe yeni satırları okuyor.

Dosya yolu türetme (a.g.e. 40-43): Claude Code proje dizin adı = `cwd` içindeki `/` ve `.` karakterlerinin `-` ile değiştirilmiş hâli; tam yol `<projectsDir>/<dönüştürülmüş cwd>/<sessionId>.jsonl`.

Aradığı şey (a.g.e. 32-37): `is_error: true` + şu metinlerden biri — `"Interrupted by user"`, `"interrupted by user"`, `"user doesn't want to proceed"`, `"[Request interrupted by user"`. Hook'lar kesintiyi bildirmediği için JSONL'den yakalanıyor.

`ConversationParser` (`Services/Session/ConversationParser.swift:43-58`) ise `actor`, dosya yolu anahtarlı cache tutuyor, artımlı parse yapıyor ve `UsageInfo` (input/output/cacheRead/cacheCreation token) topluyor (a.g.e. 13-31).

**Bize uyarlama:** İki teknik arasında seçim:
- **FSEvents dizin izleme** (claude-notch-tracker `LogWatcher`): tüm `projects/` ağacını izler, hangi oturumun aktif olduğunu bilmek gerekmez. **MVP için doğrusu bu.**
- **`DispatchSource` tek dosya** (vibe-notch): aktif oturumun dosyası biliniyorsa daha ucuz ve daha düşük gecikmeli.

`ProjectsWatcher` MVP'de FSEvents kullanacak; v2'de aktif oturum belirlendiğinde onun dosyasına `DispatchSource` takmak "Claude yazıyor" animasyonunun gecikmesini düşürür.

**`cwd` → proje dizin adı dönüşümü** (`/` ve `.` → `-`) bizim için de gerekli: JSONL dosyasından proje adını göstermek (plan §6.2 "son aktif proje adı") ya da tersine bir projenin dosyasını bulmak için.

**Dikkat:** Kesinti tespiti **İngilizce metin eşleştirmesi** — Claude Code mesajı değiştirirse sessizce kırılır. Bu tür heuristikleri "varsa iyi" seviyesinde tutmalı, temel işlevi buna bağlamamalıyız (plan §13 "parser'ı toleranslı yaz").

## 4. Plan ile çelişkiler / doğrulamalar

**Doğrulananlar:**

| Plan varsayımı | Bu repoda |
|---|---|
| Sandbox kapalı olmalı | `ClaudeIsland/Resources/ClaudeIsland.entitlements`: `com.apple.security.app-sandbox = false`. |
| Menü bar / accessory app | `AppDelegate.swift:71`: `setActivationPolicy(.accessory)`. |
| `NSPanel` borderless + nonactivating, tüm Space'lerde, fullscreen'de görünür | `NotchWindow.swift:22, 42-50` — plan §4.1 ile birebir. |
| NotchShape: içbükey üst kıvrım + yuvarlak alt köşe, parametrik/animatable | `UI/Components/NotchShape.swift:10-30` (`topCornerRadius: 6`, `bottomCornerRadius: 14`, `animatableData`). Plan §4.4'ün tarifi. |
| Popup'ın otomatik kapanması, araya girme | `NotchActivityCoordinator:96-111`. |
| Dağıtım: Developer ID + notarization | `scripts/create-release.sh:48-132` — `notarytool submit` + `stapler staple` (hem zip hem dmg). Plan §8 ile uyumlu. |
| Ana thread'de `Process` çalıştırma | `Services/Shared/ProcessExecutor.swift` bir `actor`; tüm CLI çağrıları `await`. |

**Çelişkiler / dikkat gerektirenler:**

1. **`~/.claude/settings.json`'a YAZMA.** Şimdiye kadarki tüm notlarımız "salt-okunur" diyordu; hook kurulumu bu sınırı aşıyor. Plan §6.3'teki "token'a asla yazmaz" kriteri **token** hakkında, `settings.json` hakkında değil — ama v2'ye geçerken planın açıkça güncellenmesi gerekiyor: hangi dosyaya, hangi onayla, hangi geri alma yoluyla yazıyoruz.
2. **min. macOS 15.6** (README "Requirements"). Bizim hedefimiz macOS 14. Hook/socket kodunda 15'e özel API görünmüyor; kısıt muhtemelen SwiftUI kullanımından. v2'ye geçerken kontrol edilecek.
3. **Mixpanel telemetrisi** (`AppDelegate.swift:44-68`), hardcoded token ile, `App Launched` ve `Session Started` olayları + makine kimliğinden türetilen `distinctId`. **Bizde telemetri yok.** Adapte edilen hiçbir dosyaya bu kod sızmamalı.
4. **`CGEvent.post(tap: .cghidEventTap)`** ile sentetik fare olayı — Accessibility izni riski ve kırılgan davranış. Almayacağız (§3.5).
5. **`/tmp/claude-island.sock`** sabit yol — çok kullanıcılı makinede çakışma ve güvenlik yüzeyi. Bizde kullanıcıya özel dizin (§3.2).
6. **tmux'a tuş gönderme** (`Services/Tmux/ToolApprovalHandler.swift:21-44`: `send-keys -t <target> -l "1"` + `Enter`) — hook yolu çalışmadığında terminal UI'ını klavye simülasyonuyla sürmek. Çok kırılgan (Claude Code'un izin menüsündeki tuş atamaları değişirse yanlış şey onaylanır — **güvenlik açısından kabul edilemez**). Almayacağız.
7. **`Services/Window/YabaiController.swift`** — üçüncü taraf pencere yöneticisi entegrasyonu; kapsam dışı.
8. **Apache-2.0 yükümlülükleri:** repoda `NOTICE` dosyası **yok** (kontrol edildi) → taşınacak NOTICE içeriği yok. Yine de: lisans metni `THIRD_PARTY_LICENSES.md`'ye eklenecek, adapte edilen her dosyada kaynak + **"modified"** beyanı olacak (Apache-2.0 §4(b)). Bu, MIT kaynaklardan farklı bir yükümlülük — CLAUDE.md'deki devşirme kuralı zaten bunu söylüyor.

## 5. Bilinçli almayacaklarımız

1. **Mixpanel/telemetri** (`App/AppDelegate.swift:44-68, 100-130`) — bizde analytics yok, hardcoded üçüncü taraf token hiç yok.
2. **tmux entegrasyonunun tamamı** (`Services/Tmux/*`: `TmuxController`, `ToolApprovalHandler`, `TmuxTargetFinder`, `TmuxSessionMatcher`) — klavye simülasyonuyla izin onaylamak güvenlik açısından kabul edilemez; hook yolu zaten doğru çözüm.
3. **`CGEvent` ile tıklama yeniden post etme** (`UI/Window/NotchWindow.swift:69-120`, `Core/NotchViewModel.swift:205-235`) — Accessibility izni + kırılgan davranış.
4. **`Services/Window/YabaiController.swift`, `WindowFinder.swift`** — pencere yöneticisi entegrasyonu, kapsam dışı.
5. **Konuşma geçmişi UI'ı**: `UI/Views/ChatView.swift` (1230 satır), `ToolResultViews.swift` (1123 satır), `UI/Components/MarkdownRenderer.swift`, `Services/Chat/ChatHistoryManager.swift` — notch bir sohbet istemcisi değil. Bizim v2 kapsamımız: faz göstergesi + izin popup'ı.
6. **Subagent takibi** (`SessionStore` içindeki `processSubagentTracking`, `AgentFileWatcher.swift`) — v2 için fazla ayrıntı.
7. **Otomatik, onaysız hook kurulumu** (`AppDelegate.swift:70`) — bizde açık kullanıcı onayı + yedek + tek tıkla kaldırma.
8. **`settings.json`'ı tümüyle yeniden yazma** (`HookInstaller.swift:91-96`, `prettyPrinted + sortedKeys`) — kullanıcının dosya düzenini bozar; bizde minimal, atomik ve yedekli güncelleme.
9. **Python bağımlılığı** (`detectPython()` → `which python3`, yoksa `"python"`) — Python 3 olmayan makinede hook sessizce ölür; biz bundle'lanmış bir binary tercih edeceğiz.
10. **`nonisolated(unsafe)` + `NSLock` karışımı eşzamanlılık** (`SessionStore.swift:42`, `HookSocketServer` içindeki iki ayrı lock) — Swift 6 dil modunda `actor` + `AsyncStream` ile yeniden yazılacak.

## 6. Açık sorular

1. **Hook kurulumu v2 için gerçekten gerekli mi, yoksa JSONL izleme yeter mi?** FSEvents ile "Claude çalışıyor"u zaten yakalıyoruz (§6.3 kriteri ≤5 sn). Hook'un getirdiği ek değer: kesin faz bilgisi ve **izin onayı**. İzin onayı olmadan hook kurmanın maliyeti (settings.json'a yazma riski) değer mi?
2. **Hook script'i hangi dilde?** Bundle'lanmış küçük bir Swift CLI mi (Python bağımlılığı yok, imzalı), yoksa `/bin/sh` + `nc` mi (bağımlılık yok ama socket protokolü kısıtlı)? Swift CLI'ın notarization içindeki yeri netleşmeli.
3. **`settings.json` yazımı için kullanıcı sözleşmesi nasıl olmalı?** Onboarding'de diff göstermek mi, yoksa "hook komutunu kopyala, kendin ekle" gibi tamamen manuel bir yol mu sunmalıyız? İkincisi en güvenlisi ama kullanım oranını düşürür.
4. **Hook cevabı beklerken uygulama çökerse ne olur?** Claude Code 300 sn (bizde 30-60 sn) asılı kalır. Hook script'inde daha kısa bir timeout + "uygulama yanıt vermedi → ask" davranışı yeterli mi? Uygulama kapanışında socket'i silmek + bekleyenleri kapatmak zorunlu.
5. **`PermissionRequest` payload'ında `tool_use_id` hâlâ eksik mi?** vibe-notch'un FIFO cache hilesi (`PreToolUse`'dan eşleme) Claude Code'un mevcut sürümünde gereksiz olabilir. v2'ye başlarken gerçek payload'la doğrulanmalı.
6. **`~/.config/claude` mi `~/.claude` mi?** vibe-notch "v2.1.30+ ile yeni varsayılan `~/.config/claude`" diyor, codex-island ikisini birden tarıyor, claude-notch-tracker sadece `~/.claude`. Kullanıcının makinesinde gerçek durum nedir? (Faz 4'ün ilk kontrolü — bu oturumda kullanıcının dosyalarına bakmıyoruz.)
7. **min. macOS 15.6 kısıtı nereden geliyor?** Hook/socket katmanında macOS 15 API'si göremedim; v2'ye geçerken macOS 14'te derlenip derlenmediği kontrol edilecek.
8. **`NotchOpenReason`'ı Faz 1'de mi ekleyelim?** Popup'ın neden açıldığını bilmek kapanma politikasını basitleştiriyor; `NotchState.popup(event:)` zaten event taşıyor ama hover/click ayrımı için `expanded` durumuna da bir sebep alanı gerekebilir.
