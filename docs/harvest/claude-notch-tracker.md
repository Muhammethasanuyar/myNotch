# claude-notch-tracker — Harvest Notu

| | |
|---|---|
| Repo | https://github.com/stevemcqueenz/claude-notch-tracker |
| Klon | `references/claude-notch-tracker` @ `77e0a09` (2026-08-18) |
| Lisans | MIT (`LICENSE`, "Copyright (c) 2026 Stanislav Kulik") |
| Devşirme modu | **Kod adapte et** (alternatif yaklaşım; codex-island ile karşılaştırmalı) |
| İlgili fazlar | Faz 1 (NotchShape içbükey kulak, passthrough panel), Faz 4 (Claude usage — fallback zinciri, FSEvents, blok hesabı), Faz 5 (test altyapısı, notarization) |

## 1. Bizim için değeri

codex-island ile **aynı problemi farklı çözen** ikinci uygulama. Değeri karşılaştırmadan geliyor:

- **Kimlik için tamamen farklı bir birincil yol:** claude.ai oturum çerezini tarayıcı/Claude Desktop cookie store'undan okuyup `https://claude.ai/api/organizations/<org>/usage`'a gidiyor. Claude Code CLI'ın Keychain token'ı burada sadece **son çare fallback**. Biz bunun tersini yapacağız (CLI token birincil, cookie yolu **hiç yok**) ama endpoint/JSON bilgisi paha biçilmez.
- **`/api/oauth/usage`'ın modele göre bölünmüş haftalık pencere döndürebildiğini** gösteriyor (`seven_day_opus` / `seven_day_sonnet`) — codex-island'da bu yok, bizim parser'ımızda **olmalı**.
- **Üç kademeli fallback zinciri** (canlı limit → terminal statusline feed → yerel bloktan tahmin) plan §6.2'deki "erişilemezse ccusage blok tahminine zarifçe düş" gereksiniminin çalışan hâli.
- **FSEvents + tail-parse (byte offset)** ile gerçek zamanlı yerel okuma — codex-island'da tamamen yok, bizim `ProjectsWatcher.swift` için birebir şablon. §6.3'teki "≤5 sn içinde tepki" kriterinin cevabı burada.
- **ccusage'ın 5 saatlik blok algoritması Swift'te** (`BlockCalculator`) + testleri — resmi endpoint erişilemezken ring'i besleyecek şey bu.
- Swift 6 dil modu, macOS 14, **swift-testing** (`@Suite`/`@Test`/`#expect`) ve `.jsonl` fixture'ları — bizim `MyNotchTests/` yapımıza doğrudan örnek.
- Notch penceresinde **codex-island'la çelişen** kritik bir uyarı: `ignoresMouseEvents`'e asla dokunma (§3.5).

Ayrıca çok-sağlayıcılı (Claude/Codex/Antigravity): `Core/CodexUsageProvider.swift`, `Core/Antigravity*.swift`, `Core/ProtobufMessage.swift`, `Core/ProviderAvailability.swift` bizim için gereksiz.

## 2. Hedef dosyalar

| Kaynak dosya (path:line) | Ne yapıyor | Bizde hedef dosya (per docs/PLAN.md §9) | Faz |
|---|---|---|---|
| `Sources/ClaudeNotch/Core/ClaudeAPIService.swift:278-310` | CLI OAuth token ile `/api/oauth/usage` + Keychain okuma + `expiresAt` kontrolü | `Modules/ClaudeUsage/UsageFetcher.swift`, `ClaudeCredentials.swift` | 4 |
| `Sources/ClaudeNotch/Core/ClaudeAPIService.swift:192-256` | Yanıt parse: `five_hour`, `seven_day`, `seven_day_opus/sonnet`, `spend`, `limits[]` | `Modules/ClaudeUsage/UsageFetcher.swift` | 4 |
| `Sources/ClaudeNotch/Core/ClaudeAPIService.swift:142-171` | `Outcome` üçlemesi: `ok` / `rejected` / `offline` — ağ kesintisini ölü oturumla karıştırmama | `Modules/ClaudeUsage/UsageService.swift` | 4 |
| `Sources/ClaudeNotch/Core/LogWatcher.swift:16-55` | FSEvents ile `~/.claude/projects` izleme + 0.25 sn debounce | `Modules/ClaudeUsage/ProjectsWatcher.swift` | 4 |
| `Sources/ClaudeNotch/Core/LogParser.swift:72-91` | Byte offset'ten tail-parse, yarım satır koruması, truncation → reset | `Modules/ClaudeUsage/ProjectsWatcher.swift` | 4/6 |
| `Sources/ClaudeNotch/Core/LogParser.swift:4-46, 115-135` | `Codable` satır modeli + iki formatlı ISO8601 tarih stratejisi | `Modules/ClaudeUsage/UsageModels.swift` | 6 |
| `Sources/ClaudeNotch/Core/LogLoader.swift:5-22` | Parse'ı `actor` içinde ana thread dışında çalıştırma, `Sendable` sonuç | `Modules/ClaudeUsage/ProjectsWatcher.swift` | 4 |
| `Sources/ClaudeNotch/Core/BlockCalculator.swift:4-42` | ccusage 5 saatlik blok algoritması (saate yuvarlama, 5h boşluk → yeni blok) | `Modules/ClaudeUsage/UsageService.swift` (fallback ring) | 4 |
| `Sources/ClaudeNotch/Model/Block.swift:3-18` | Blok değer tipi: `remaining`, `fractionElapsed`, `contains` | `Modules/ClaudeUsage/UsageModels.swift` | 4 |
| `Sources/ClaudeNotch/Core/UsageStore.swift:25-96` | Dosya-başına event'leri birleştir, dedupe, günlük/oturum/blok özeti | `Modules/ClaudeUsage/UsageService.swift` | 4/6 |
| `Sources/ClaudeNotch/UI/AppModel.swift:67-70, 78-88` | Fallback zinciri + `isStale` (bayat veriyi soluklaştır) | `Modules/ClaudeUsage/UsageService.swift`, `Views/Dashboard.swift` | 4 |
| `Sources/ClaudeNotch/UI/AppModel.swift:406-431` | 5 sn tick + 10 sn mtime kapılı yeniden okuma (FSEvents emniyet supabı) | `Modules/ClaudeUsage/ProjectsWatcher.swift` | 4 |
| `Sources/ClaudeNotch/UI/AppModel.swift:91-102` | Burn-rate ETA: yüzde eğiminden "limite kalan süre" | `Modules/ClaudeUsage/Views/Dashboard.swift` | 4 |
| `Sources/ClaudeNotch/UI/AppModel.swift:481-495` | `~/.claude.json`'dan plan adı + haftalık reset tarihi fallback'i | `Modules/ClaudeUsage/UsageService.swift` | 4 |
| `Sources/ClaudeNotch/System/IslandWindow.swift:5-40` | `NSPanel` config + `PassthroughHostingView.hitTest` (ignoresMouseEvents YASAK notu) | `Core/Window/NotchPanel.swift`, `NotchWindowController.swift` | 1 |
| `Sources/ClaudeNotch/System/IslandWindow.swift:42-89` | Sabit boyutlu strip pencere; içerik kendi yüksekliğini anime eder, pencere resize edilmez | `Core/Window/NotchWindowController.swift` | 1 |
| `Sources/ClaudeNotch/UI/NotchShape.swift:9-40` | İçbükey üst "kulak" + yuvarlak alt köşe, `animatableData` ile morph | `Core/Window/NotchShape.swift` | 1 |
| `Sources/ClaudeNotch/UI/IslandView.swift:74-97` | Tek shape, `closedH + dropHeight`, tek spring ile açılma | `Core/State/NotchViewModel.swift`, `Anim.swift` | 1 |
| `Sources/ClaudeNotch/UI/IslandView.swift:223-262` | İki sayfalı pager + `DragGesture` swipe + page dots | `Modules/ClaudeUsage/Views/Dashboard.swift` (opsiyonel) | 4/6 |
| `Sources/ClaudeNotch/UI/Ring.swift:3-25` | Progress ring: trim + `-90°` rotasyon + eşiğe göre renk | `Modules/ClaudeUsage/Views/BlockRing.swift` | 4 |
| `Sources/ClaudeNotch/System/AppMonitor.swift:3-8, 48-57` | `NSScreen.island` (notch'lu ekran seçimi) + notch ölçüsü | `Core/Window/NotchGeometry.swift` (mevcut kodla aynı) | 1 |
| `Tests/ClaudeNotchTests/*.swift` + `Fixtures/*.jsonl` | swift-testing + JSONL fixture düzeni | `MyNotchTests/` | 4 |

## 3. Desenler

### 3.1 Kimlik: tarayıcı çerezi birincil, CLI token fallback (bizde TERS olacak)

**Nasıl çalışıyor:** `ClaudeAPIService` (`Sources/ClaudeNotch/Core/ClaudeAPIService.swift:27`) bir `actor` — bloklayan Keychain/SQLite/crypto işi ana thread'den uzak tutuluyor. `fetch(force:)` (a.g.e. 56-96) sırası:

1. **Bellekteki oturum cache'i** (30 dk TTL, a.g.e. 46-47, 64-70): Keychain'e de SQLite'a da hiç dokunmaz, prompt çıkmaz.
2. **Cookie store'ları** (a.g.e. 109-140), en son çalışan başa alınmış (`orderedSources`, a.g.e. 99-106; `lastGoodCookieSource` UserDefaults'ta):
   - Chromium ailesi (`Cookies` SQLite + Keychain "Safe Storage" anahtarı): `Claude Desktop` → `Library/Application Support/Claude/Cookies` / service `"Claude Safe Storage"`; `Chrome` / `"Chrome Safe Storage"`; `Brave` / `"Brave Safe Storage"`; `Edge` / `"Microsoft Edge Safe Storage"`; `Arc` / `"Arc Safe Storage"`.
   - Firefox/Zen: `cookies.sqlite`, **düz metin** (`moz_cookies`).
   - Gereken çerezler: `sessionKey` ve `lastActiveOrg` (a.g.e. 75-77).
3. **Son çare — Claude Code CLI OAuth token'ı** (`fetchFromCLIToken`, a.g.e. 263-276).

Cookie okuma tekniği (a.g.e. 314-346): DB'yi **ve** `-wal`/`-shm` yan dosyalarını temp'e kopyalar (çalışan tarayıcının henüz checkpoint edilmemiş çerezleri WAL'de), kopyaya `0o600` verir, read-write açar ki SQLite WAL'i uygulasın, sonra siler. Chromium çözümü: `PBKDF2(SHA1, "<App> Safe Storage" şifresi, salt "saltysalt", 1003 tur, 16 byte)` → AES-128-CBC, IV = 16 × `0x20`, `v10` prefix'i atılır; yeni build'ler plaintext'in başına 32 byte domain hash koyduğu için hem düz hem `dropFirst(32)` denenir (a.g.e. 381-442).

Prompt yönetimi: Safe Storage anahtarı **process ömrü boyunca** cache'lenir, **reddedilme de cache'lenir** (a.g.e. 388, 398) — yoksa 60 saniyede bir prompt. Başarısız kaynak 900 sn backoff'a alınır (a.g.e. 43-44, 78).

**Bize uyarlama:** **Cookie/çerez yolunu hiç almayacağız.** Başka uygulamaların şifreli çerez veritabanını açmak, Keychain'den Safe Storage anahtarı çekip AES çözmek — teknik olarak zarif ama bizim ürün sözleşmemiz için fazla saldırgan: kullanıcının tüm claude.ai oturumunu ele geçiren bir kod yolu, üstelik her tarayıcı için ayrı prompt. Bizim yolumuz codex-island'ınki (CLI OAuth token, salt-okunur).

Buradan alacaklarımız:
- `cliOAuthToken()` (a.g.e. 294-310) — Keychain item'ından `claudeAiOauth.accessToken` **ve** `claudeAiOauth.expiresAt` (**epoch milisaniye**, `/1000`). codex-island `expiresAt`'i hiç okumuyor; biz okuyup **istek atmadan önce** "expired" durumuna düşebiliriz → gereksiz 401 ve rate-limit baskısı yok. Eksik değer "zaten expired" sayılıyor (a.g.e. 307-309).
- Token cache + backoff deseni (a.g.e. 50-51, 264-274): geçerli token bellekte tutulur, expired ise 900 sn backoff.
- `orderedSources()` "son çalışanı başa al" fikri, bizde env/keychain/dosya sırası için uygulanabilir.

**Dikkat:** Bu implementasyon `SecItemCopyMatching(kSecReturnData:)` kullanıyor (a.g.e. 295-302) → **prompt tetikleyen yol**. README bunu kabul edip kullanıcıya "ilk çalıştırmada Always Allow deyin" diyor. codex-island'ın notu (`security` CLI + partition list reset'i) bu "Always Allow"un token rotasyonunda **silineceğini** gösteriyor — yani bu repo muhtemelen periyodik prompt sorunu yaşıyor. Biz codex-island'ın `/usr/bin/security` yolunu kullanacağız.

### 3.2 Endpoint ve yanıt şekli: `/api/oauth/usage` vs `claude.ai/api/organizations/<org>/usage`

**Nasıl çalışıyor:** İki farklı endpoint, **aynı parse fonksiyonu** (`parse(_:source:)`, a.g.e. 192-256) — yani ikisi de aynı JSON şeklini döndürüyor:

- Web/Desktop yolu: `https://claude.ai/api/organizations/<org>/usage` (a.g.e. 151), header'lar: `Cookie: k=v; …`, `Accept: application/json`, tarayıcı taklidi `User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)` (a.g.e. 153-158), timeout 15 sn.
- CLI yolu (`usageWithCLIToken`, a.g.e. 278-290):
  ```swift
  guard
        let url = URL(string: "https://api.anthropic.com/api/oauth/usage") else { return nil }
  var req = URLRequest(url: url, timeoutInterval: 15)
  req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
  req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
  req.setValue("application/json", forHTTPHeaderField: "Accept")
  ```
  Kaynak: `references/claude-notch-tracker/Sources/ClaudeNotch/Core/ClaudeAPIService.swift:279-284` (MIT)

  **Dikkat: `User-Agent` YOK.** codex-island bunun zorunlu olduğunu, olmadan 401 alındığını söylüyor (`UsageFetcher.swift:169-171`). İki repo çelişiyor — Faz 4'te gerçek denemeyle çözülecek (§6).
- Ek endpoint: `https://claude.ai/api/organizations/<org>/prepaid/credits` → `{"amount": 4251, "currency": "EUR"}` (a.g.e. 176-190). Sadece cookie yolunda; satın alınmış kredi bakiyesi. Bizim kapsamımız dışında.

Yanıt alanları (a.g.e. 192-256):
- `five_hour` → `{ utilization: 0-100, resets_at: ISO8601 }`. `resetsAt` camelCase varyantı da deneniyor (a.g.e. 196).
- `seven_day` → aynı şekil. **Yoksa** `seven_day_opus` ve `seven_day_sonnet` okunur, **ikisinin max'ı** haftalık olarak gösterilir, reset opus'unki (a.g.e. 208-213). Yorum: "`/api/oauth/usage` splits the 7-day limit by model".
- `extra_usage` → `utilization` (harcanana kadar `null`).
- `spend` → `{ enabled: Bool, percent: 0-100, used: { amount_minor, currency }, cap: { money: { amount_minor, currency } } }` (a.g.e. 221-230). `extra_usage` null iken `spend.percent` tercih ediliyor.
- `limits: [ { scope: { model: { display_name } }, percent: 0-100, resets_at } ]` — model bazlı ek pencereler; burada `display_name == "Fable"` aranıyor (a.g.e. 236-247).

Tüm yüzdeler `min(1, max(0, x/100))` ile normalize ediliyor — codex-island ile aynı sonuç.

**Bize uyarlama:** `Modules/ClaudeUsage/UsageFetcher.swift` parser'ı **hem** `seven_day` **hem de** `seven_day_*` varyantlarını desteklemeli; codex-island'ın parser'ı sadece `seven_day` okuyor ve bazı planlarda haftalık ring boş kalacak. Model-bazlı `limits[]` dizisini de okuyalım ama MVP'de göstermeyelim (dashboard'da "model bazlı limitler" v2). `spend` bloğu bizim kapsamda değil (abonelik dışı ekstra harcama).

**Dikkat:** İki repo `resets_at`'i farklı okuyor: codex-island epoch `Double` **veya** string; bu repo sadece string (iki ISO8601 formatı). Bizim parser ikisini de kaldırmalı. Ayrıca `utilization` `NSNumber` üzerinden okunuyor (a.g.e. 195) — JSON'da int gelirse `as? Double` cast'i başarısız olabilir, `NSNumber` yolu daha toleranslı; bunu akılda tutalım.

### 3.3 Üç kademeli fallback: canlı limit → statusline feed → yerel blok tahmini

**Nasıl çalışıyor:** `AppModel.claudeSessionUsage` (`Sources/ClaudeNotch/UI/AppModel.swift:68-70`) tek satırda zinciri kuruyor: `limits?.sessionPct ?? statuslineUsage ?? (snapshot.isEmpty ? nil : snapshot.blockUsageEstimate)`. Kaynak etiketi ayrı bir hesaplanan değer (a.g.e. 78-82): `"claude.ai"` / kaynak adı → `"terminal"` → `"estimate"` — **kullanıcı hangi veriye baktığını görüyor.**

Kademeler:
1. **Canlı limitler** — §3.2'deki endpoint.
2. **Terminal statusline feed** (`readStatusFeed`, a.g.e. 469-479): `~/.claude/notch-usage.json` dosyasından `rate_remaining` (yüzde kalan → `(100-rem)/100` kullanılan) ve `ctx_remaining` (context kalan). Kullanıcının Claude Code statusline script'inin yazdığı dosya.
3. **Yerel blok tahmini** (`UsageStore.snapshot`, `Sources/ClaudeNotch/Core/UsageStore.swift:78-83`): tüm 5 saatlik blokların **en yüksek token'lısı** referans alınıp aktif bloğun oranı hesaplanıyor — `min(1, aktifBlokToken / maxBlokToken)`. Yani "senin en yoğun bloğuna göre şu an neredesin". Gerçek limit bilinmediği için pratik bir proxy.

Ayrıca `weeklyResetsAt` için ikinci fallback: `limits?.weeklyResetsAt ?? weeklyResetFromConfig` (a.g.e. 76), ki `weeklyResetFromConfig` `~/.claude.json` içindeki `cachedGrowthBookFeatures.tengu_saffron_lattice.planLimitsEndDate`'ten okunuyor (a.g.e. 481-495). Aynı dosyadan plan adı: `oauthAccount.organizationRateLimitTier`.

**Bayat veri işareti:** `isStale` (a.g.e. 84-88) — son başarılı fetch 150 sn'den eskiyse (≈2-3 kaçırılmış 60 sn'lik fetch) sayılar **%50 opaklıkta** çiziliyor (`IslandView.swift:184`). Donmuş bir değer asla güncelmiş gibi gösterilmiyor.

**Bize uyarlama:** Plan §6.2'nin "resmi endpoint verisi; erişilemezse ccusage blok tahminine zarifçe düş" maddesinin **tam karşılığı** bu. `Modules/ClaudeUsage/UsageService.swift`:
```
usedFraction = officialFiveHour ?? ccusageBlockEstimate ?? nil   // nil → "—"
```
+ `source: UsageSource` enum'u (`.official`, `.estimated`, `.none`) ve `Views/BlockRing.swift`'te görsel ayrım (kesikli halka / soluk renk). `isStale` fikrini de alalım: bizim polling'imiz 5 dk olduğu için eşik ~12-15 dk olmalı.

`~/.claude.json`'dan plan adı + haftalık reset okuma **ucuz ve faydalı** — endpoint'e hiç ulaşamayan kullanıcıya bile "Max planı, haftalık limit 3 gün sonra sıfırlanıyor" diyebiliriz.

**Dikkat:** `~/.claude/notch-usage.json` **bu uygulamaya özgü** bir sözleşme (kullanıcının kurduğu statusline script'i yazıyor), Claude Code'un standart çıktısı değil — biz almayacağız. `cachedGrowthBookFeatures.tengu_saffron_lattice` ise tamamen belgesiz bir iç alan; okunabilir ama **kırılırsa sessizce yok sayılmalı** (kod da öyle yapıyor: `guard let … else { return }`).

### 3.4 FSEvents + byte-offset tail parse: "Claude çalışıyor" tespitinin omurgası

**Nasıl çalışıyor:** Üç parça:

1. **`LogWatcher`** (`Sources/ClaudeNotch/Core/LogWatcher.swift:16-55`): `~/.claude/projects` üzerinde `FSEventStreamCreate`, latency **0.3 sn**, flag'ler `kFSEventStreamCreateFlagFileEvents | NoDefer | UseCFTypes`. Callback'te `.jsonl` filtresi, değişen path'ler `pending` set'inde toplanır ve **0.25 sn debounce** ile tek batch olarak `@MainActor` closure'a verilir. `pending` ve `debounce` yalnızca tek bir serial queue'dan dokunuluyor (yorum, önceki race'i anlatıyor: stream'in concurrent global queue'su ile debounce'un thread'i çakışıyormuş).
2. **`LogParser.parseIncremental(fileURL:from:)`** (`Core/LogParser.swift:72-91`): dosyayı offset'ten sonuna kadar okur ama **son tam satıra kadar** tüketir (`data.lastIndex(of: 0x0A)`) — yazılmakta olan yarım satır bir sonraki turda alınır. Dosya küçüldüyse (rotate/truncate) baştan okur ve `reset: true` döner → çağıran, append yerine **replace** eder.
3. **`LogLoader`** (`Core/LogLoader.swift:5-22`): `actor`, parse'ı ana thread dışında yapar, `Sendable` sonuç döner. `AppModel.ingest` (`UI/AppModel.swift:390-403`) `parsedOffsets[url]`'i günceller, `reset` bayrağına göre `store.ingest` (replace) veya `store.append` çağırır.

**Emniyet supabı:** FSEvents kaçırırsa diye 5 saniyelik `ticker` (a.g.e. 259-261) → `tick()` → `reingestChangedFiles()` (a.g.e. 414-427): en fazla **10 saniyede bir** çalışır, `Task.detached(priority: .utility)` içinde son 2 günün dosyalarını gezip `mtime > parsedMTimes[url]` olanları yeniden okur. Recursive dizin gezme ve `stat`'lar ana aktörün dışında; sadece ingest geri hoplar.

Başlangıçta (a.g.e. 273-276) `ClaudePaths.recentLogFiles(within: 2)` (`Core/ClaudePaths.swift:18-27` — mtime filtresi, hiç yoksa hepsine düşer) `Task.detached` ile okunuyor.

**Bize uyarlama:** `Modules/ClaudeUsage/ProjectsWatcher.swift` bunun neredeyse birebir adaptasyonu olacak. Plan §6.1: "son ~10 sn içinde herhangi bir `.jsonl` değiştiyse → `activity = .live`". FSEvents callback'i geldiğinde:
- `ProjectsWatcher` `lastChangeAt = Date()` günceller ve `EventBus`'a "aktivite" yayar;
- `UsageService` `activity`'yi `.live`'a çeker, 10 sn sonra `.idle`'a düşürür (tek `Task` + `Task.sleep`, her olayda yeniden kurulur);
- compact görünümdeki ✳ pulsing animasyonu bu bayrağa bağlanır.

Swift 6 uyarlaması: `LogWatcher`'daki `Unmanaged.passUnretained(self)` + C callback deseni Swift 6'da `@Sendable` sınırlarına takılır — callback içinde sadece `nonisolated` bir sınıfa dokunmalı, `@MainActor` closure'a `Task { @MainActor in }` ile hoplamalı (repo zaten öyle yapıyor, a.g.e. 51). Debounce için `DispatchWorkItem` yerine bir `Task` + iptal de olur.

**Dikkat:**
- FSEvents `~/.claude/projects` yoksa sessizce hiçbir şey yapmaz (`FSEventStreamCreate` nil dönerse `return`) — kullanıcı Claude Code kurmamışsa modül "kurulum gerekli" durumuna düşmeli, sessiz kalmamalı (§6.3 kabul kriteri).
- Sandbox kapalı olmalı (bizde kapalı).
- `CLAUDE_CONFIG_DIR` desteği bu repoda **yok** — `ClaudePaths.projectsDir` sabit `~/.claude/projects` (`Core/ClaudePaths.swift:4-7`). Bizde ayar override'ı olacak (plan §6.1); codex-island'ın çok köklü yaklaşımını (§3.9) buraya taşıyacağız.
- Uyanma sonrası FSEvents bir yığın olay basar → debounce ve 10 sn mtime kapısı bunu zaten yumuşatıyor; bizde de kalmalı.

### 3.5 Notch penceresi: passthrough hitTest ve `ignoresMouseEvents` YASAĞI

**Nasıl çalışıyor:** `NotchPanel` (`Sources/ClaudeNotch/System/IslandWindow.swift:5-22`): `NSPanel`, `styleMask: [.borderless, .nonactivatingPanel]`, `isFloatingPanel = true`, `level = statusBar.rawValue + 2`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, `backgroundColor = .clear`, `isOpaque = false`, `hasShadow = false`, `hidesOnDeactivate = false`, `isExcludedFromWindowsMenu = true`, `canBecomeKey = false`, `canBecomeMain = false`.

Tıklama geçirgenliği için `PassthroughHostingView` (a.g.e. 31-40) sadece `hitTest` override'ı kullanıyor — ve dosyadaki **en değerli yorum** bunun neden yettiğini ve `ignoresMouseEvents`'in neden zehirli olduğunu anlatıyor:

```swift
/// NOTE: that fall-through works because the window server click-throughs transparent pixels of a
/// borderless non-opaque window. NEVER set `panel.ignoresMouseEvents` explicitly (even to false):
/// doing so disables that per-pixel behavior for the whole frame, and every click in the top strip
/// gets routed to us and dies here — dead menu bar and title-bar buttons under the strip.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    var interactiveRect: CGRect = .zero
    var interactionEnabled = true
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard interactionEnabled, interactiveRect.contains(point) else { return nil }
        return super.hitTest(point)
    }
}
```
Kaynak: `references/claude-notch-tracker/Sources/ClaudeNotch/System/IslandWindow.swift:27-38` (MIT); aynı sınıfta `acceptsFirstMouse(for:) -> true` override'ı da var (a.g.e. 39).

`interactiveRect` pencere resize edilmeden güncelleniyor (`updateInteractiveZone`, a.g.e. 81-89): "görünmez tıklama yakalayıcı"nın boyutu pill'in mevcut ayak izine göre yeniden hesaplanıyor — ucuz, animasyon zıplaması yok.

Pencere **sabit boyutlu** (400×300 içerikte, tam ekran genişliğinde strip olarak konumlanıyor, a.g.e. 44-77): "pill kendi yüksekliğini içeride anime eder — pencere hiç resize edilmez, bu yüzden expand/collapse zıplayamaz". Bizim plan §4.1 ile **birebir aynı karar**.

Fullscreen'de gizleme (`hide()`, a.g.e. 128-140): pencere **`orderOut` EDİLMİYOR** — yorumun gerekçesi: fullscreen Space aktifken pencereyi listeden çıkarmak macOS'un `.canJoinAllSpaces` üyeliğini düşürmesine ve sonrasında tek Space'e çakılmasına yol açıyor. Bunun yerine 110 pt yukarı kaydırılıp `alphaValue = 0` yapılıyor ve `interactionEnabled = false` ile view seviyesinde tıklama kapatılıyor.

**Bize uyarlama:** `Core/Window/NotchPanel.swift` zaten `NSPanel` + borderless yolunda; eklenecekler:
- `PassthroughHostingView` eşdeğeri `hitTest` + `acceptsFirstMouse`,
- `interactiveRect`'i `NotchLayout` metriklerinden hesaplama (state'e göre closed/compact/expanded),
- `.fullScreenAuxiliary` + `.canJoinAllSpaces` (plan §4.1 zaten diyor),
- fullscreen/gizleme senaryosunda `orderOut` yerine alpha+offset.

**codex-island ile ÇELİŞKİ:** codex-island `window.ignoresMouseEvents`'i global mouse monitor ile sürekli toggle ediyor (`IslandWindowController.swift:87-133`); bu repo "asla dokunma, menü barı öldürürsün" diyor. İki yaklaşım da sahada çalışıyor gibi görünüyor ama farklı pencere konfigürasyonlarıyla: codex-island pencereyi `canBecomeKey = true` yapıp hover'da `NSApp.activate` ediyor (odak çalıyor), bu repo `canBecomeKey = false` (odağı asla çalmıyor). **Bizim tercihimiz bu repo olmalı**: menü bar altındaki tıklamaların ölmesi kabul edilemez bir regresyon ve `nonactivatingPanel` + `canBecomeKey = false` planımızdaki "notch bir HUD'dur, odak çalmaz" felsefesine uyuyor. Faz 1'de her ikisi de gerçek makinede menü bar tıklaması ile test edilmeli.

**Dikkat:** `level = statusBar + 2`; plan §4.1 `.screenSaver` diyor. `.screenSaver` daha yüksek — fullscreen video oynatıcılarının kendi HUD'unun üstüne çıkabilir. Faz 1'de deneyip karar verelim.

### 3.6 NotchShape: içbükey "kulak" + animatable morph

**Nasıl çalışıyor:** `NotchShape` (`Sources/ClaudeNotch/UI/NotchShape.swift:9-40`) iki parametre alıyor: `topRadius` (üst köşelerdeki **içbükey** flare — siyahın menü bara donanım notch'u gibi karışmasını sağlıyor) ve `bottomRadius` (alt yuvarlak köşeler). `animatableData: AnimatablePair<CGFloat, CGFloat>` sayesinde iki yarıçap da SwiftUI tarafından enterpolasyona giriyor → "notch'un kendisi büyüyor" hissi. Path dört `addQuadCurve` ile kuruluyor; üst köşelerde control point köşenin **kendisinde** olduğu için eğri dışa değil içe bükülüyor.

Kullanım (`Sources/ClaudeNotch/UI/IslandView.swift:74-97`): `topRadius: 8` sabit, `bottomRadius: expanded ? 22 : max(10, closedH * 0.40)`; tek bir `ZStack` içinde `shape.fill(.black)` + içerik, `.clipShape(shape)` + `.contentShape(shape)`, ve **tek** animasyon: `.animation(.spring(response: 0.6, dampingFraction: 1.0), value: expanded)`. Kaynak yorumda pookify'a (MIT) atıf var.

Yükseklik `expanded ? closedH + dropHeight : closedH`, genişlik sabit (`wing + notchWidth + wing + insets`) — yani bu uygulama **genişlik morph'u yapmıyor**, sadece yükseklik.

**Bize uyarlama:** `Core/Window/NotchShape.swift` (Faz 1). Plan §4.4 tam olarak bunu tarif ediyor: "`bottomCornerRadius`, `topOuterCurve` (expanded'da dış kenarlarda içbükey kulak kıvrımı), genişlik/yükseklik" — bu dosya `topOuterCurve`'ün çalışan hâli. Bizde ek olarak **genişlik** de anime olacak (compact'ta iki yana bilgi şeridi, plan §1), yani `animatableData` üçlü olmalı ya da genişliği `frame` üzerinden aynı spring ile sürmeliyiz.

Kıyas: codex-island `.continuous` squircle `UnevenRoundedRectangle` kullanıyor (kolay, kulak yok); bu repo elle Bezier ile içbükey kulak yapıyor (bizim istediğimiz). İkisini birleştirelim: alt köşeler squircle hissi verecek kadar yumuşak, üst köşeler içbükey flare.

**Dikkat:** `b = max(0, min(bottomRadius, r.width/2 - t, r.height - t))` clamp'i şart — dar/kısa geometride path bozulur. Notch yüksekliği 24 pt'a düştüğünde (scaled mod) `closedH * 0.40` = 9.6 → `max(10, …)` devreye giriyor.

### 3.7 Yerel toplama: dedupe, blok hesabı, oturum kırılımı ve burn-rate

**Nasıl çalışıyor:**

- **Dedupe** (`Core/UsageStore.swift:25-33`): tüm dosyaların event'leri zaman sırasına dizilir, `dedupeKey` ile `Set` üzerinden ilk görülen kalır. `UsageEvent.dedupeKey` `messageId`+`requestId` üzerinden kuruluyor (ccusage paritesi). Event'ler **dosya bazında** saklanıyor (`eventsByFile`), böylece bir dosya yeniden okunduğunda sadece o dosyanınki değişiyor.
- **Blok hesabı** (`Core/BlockCalculator.swift:4-42`): ccusage algoritması. Event'ler sıralanır; blok başlangıcı **saate yuvarlanır** (`floorToHour`); yeni event bloğun başlangıcından ≥5 saat sonraysa **veya** son event'ten ≥5 saat sonraysa yeni blok açılır. `Block` (`Model/Block.swift`) `duration = 5*3600`, `remaining(at:)`, `fractionElapsed(at:)`, `contains(_:)` sunuyor.
- **Blok kullanım tahmini** (`Core/UsageStore.swift:78-83`): `min(1, aktifBlokToken / tümBlokların max token'ı)`.
- **Günlük özet** (a.g.e. 40-64): bugünün event'lerinden toplam token + maliyet; `sessionId` bazında gruplama (alt-ajanlar üst oturuma katlanıyor, oturum ortasında `cd` yapılsa bile bölünmüyor), isim `custom-title` satırından gelen sidebar başlığı, yoksa `cwd`'nin son bileşeni. Model kırılımı ve en çok kullanılan model.
- **Aktif oturum** (a.g.e. 66-71): son event'in `sessionId`'si; onun **tüm yaşamı** boyunca token+maliyet (bugüne kısıtlı değil) — uzun bir sohbetin büyüyen maliyeti görünsün diye.
- **Burn-rate ETA** (`UI/AppModel.swift:91-102`): son 8 `(zaman, yüzde)` örneğinden eğim; `dt > 60` ve `dpct > 0.005` ise `eta = (1 - cur) / (dpct/dt)`. Reset ETA'dan önce geliyorsa `nil` (blok zaten sıfırlanacak), 0-6 saat aralığı dışındaysa `nil`. Yüzde geçmişi, reset zamanı ileri atladığında temizleniyor (`applyLimits`, a.g.e. 377-388).
- **Günlük maliyet projeksiyonu** (a.g.e. 124-131): `costToday / dayFraction`, günün ilk %10'unda (≈02:24'ten önce) `nil`.
- **Fiyat tablosu** (`Core/PricingTable.swift`): model adında `"opus"`/`"sonnet"`/`"haiku"` alt dizgisi aranıyor, bulunamazsa sonnet oranları fallback. **Çok kaba** — codex-island'ın tam model tablosuna göre belirgin şekilde zayıf ve fiyatlar eski (opus 15/75 — codex-island'da opus-5 için 5/25).

**Bize uyarlama:** `BlockCalculator` + `Block` **doğrudan adapte edilecek** (`Modules/ClaudeUsage/UsageModels.swift` + `UsageService.swift`): resmi endpoint erişilemezken 5 saatlik ring'i besleyecek, `blockEnd`/`remaining` ile "bu hızla blok şu saatte dolar" tahminini kuracak (plan §6.2). Burn-rate ETA formülünü de alalım — plan §6.2 "burn rate ($/saat) ve blok dolma tahmini" istiyor; buradaki yüzde-eğimi yaklaşımı **token cap'i bilmeye gerek bırakmıyor**, zarif.

Oturum gruplama + `custom-title` okuması plan §6.2'nin "son aktif proje adı" maddesi için hazır: `type == "custom-title"` satırından `sessionId` → `customTitle`.

**Fiyat tablosunu ALMAYACAĞIZ** — MVP'de ccusage fiyatlıyor, v2'de codex-island'ın tam tablosunu alacağız.

**Dikkat:** `blockUsageEstimate`'in "kendi maksimum bloğuna göre oran" tanımı **gerçek limit değil**; ilk kullanım gününde maksimum = aktif blok olduğu için hep %100 gösterir. Bizde bu tahmin ancak resmi veri yokken ve **açıkça "tahmini" etiketiyle** gösterilmeli; alarm eşiklerini bu değere bağlamamalıyız (yanlış popup üretir).

## 4. Plan ile çelişkiler / doğrulamalar

**Doğrulananlar:**

| Plan varsayımı | Bu repoda |
|---|---|
| Keychain öğesi `Claude Code-credentials`, içinde `claudeAiOauth.accessToken` | Doğrulandı (`ClaudeAPIService.swift:294-310`) — ayrıca `expiresAt` (epoch **ms**) alanı var. |
| Salt-okunur kimlik, token'a asla yazma | Doğrulandı ve README'de vaat ediliyor: "read-only and never refreshed, so your CLI session is left untouched" (a.g.e. 260-262, README:99-103). |
| 5 saatlik pencere + haftalık pencere | Doğrulandı; **ek olarak** haftalık pencere modele göre bölünebiliyor (`seven_day_opus`/`seven_day_sonnet`). |
| JSONL: `type == "assistant"`, `message.usage.*`, `<synthetic>` filtresi, `messageId`+`requestId` dedupe | Doğrulandı (`LogParser.swift:115-135`) — codex-island ile birebir aynı. |
| "Claude çalışıyor" dosya değişiminden anlaşılır | Doğrulandı: FSEvents + 0.25 sn debounce + 5 sn tick emniyet supabı. |
| ccusage blok mantığı (5 saat, saate yuvarlama) | Doğrulandı ve Swift'e çevrilmiş + testli (`BlockCalculator` + `BlockCalculatorTests`). |
| Min. macOS 14, Swift 6 dil modu | Doğrulandı (`Package.swift`: `platforms: [.macOS("14.0")]`, `.swiftLanguageMode(.v6)`). |

**Çelişkiler / dikkat gerektirenler:**

1. **Polling 60 saniye.** `limitsTimer` 60 sn (`AppModel.swift:262-266`), `providerTimer` 60 sn, `ticker` 5 sn, `lifetimeTimer` 600 sn. Plan §6.1 ve codex-island **≥5 dakika** diyor ve 429'un hesap bazlı + yapışkan olduğunu gösteriyor. **Bu repo yanlış tarafta** — ama farklı endpoint kullandığı için (cookie ile `claude.ai/api/organizations/.../usage`) farklı bir limiter'a çarpıyor olabilir. **Bizim kararımız değişmiyor: ≥5 dk.** 60 sn'lik cadence'ten alacağımız tek şey `isStale` fikri.
2. **`/api/oauth/usage` çağrısında `User-Agent` yok.** codex-island "olmadan 401" diyor. İki repo çelişiyor → Faz 4'te `curl` ile doğrulanacak. Güvenli taraf: User-Agent'ı gönder (fazladan header zarar vermez), ama 401 alırsak header'ı değil scope/expiry'yi suçlamadan önce ikisini de dene.
3. **Kimlik sırası tamamen farklı.** Bu repo tarayıcı çerezini birincil yapıyor, CLI token'ı son çare. Plan §6.1 ve codex-island CLI token'ı birincil yapıyor. **Planımız doğru** — çerez yolu gizlilik ve kırılganlık açısından bizim için uygun değil (§5).
4. **`ignoresMouseEvents` yasağı planda yok.** Plan §4.1 pencere konfigürasyonunu tarif ediyor ama bu tuzağı içermiyor. **CLAUDE.md/plan'a eklenmeli**: borderless + non-opaque pencerede window server zaten şeffaf piksellerden tıklamayı geçiriyor; `ignoresMouseEvents`'e dokunmak bu davranışı tüm frame için kapatıyor ve menü barı öldürüyor.
5. **`CLAUDE_CONFIG_DIR` desteği yok** (`ClaudePaths.swift:4-7` sabit `~/.claude/projects`). Plan §6.1 override öngörüyor — codex-island'ın çok-köklü yaklaşımı doğru olan.
6. **Fiyat tablosu eskimiş ve kaba** (`PricingTable.swift:7-12`: opus 15/75). Plan §6.1'in "maliyet hesabını sıfırdan yazma, ccusage'a yaslan" kararını doğruluyor.
7. **Blok tahmini "kendi max bloğuna göre"** — plan §6.2'nin "ccusage blok tahminine düş" ifadesi bundan daha iyi bir şey ima ediyor (ccusage'ın `blocks --json` çıktısı gerçek token limiti tahminini içeriyor). Fallback kaynağımız ccusage olmalı, bu naif oran değil.
8. **Dağıtım:** bu repo **imzalı ve notarized** (README:128-130) — plan §8 ile uyumlu, codex-island'ın imzasız yaklaşımının aksine. Sparkle ile güncelleme (`Package.swift` bağımlılığı, `docs/appcast.xml`).

## 5. Bilinçli almayacaklarımız

1. **Tarayıcı/Desktop çerez yolunun tamamı** (`ClaudeAPIService.swift:99-140, 314-442`): cookie SQLite kopyalama, Chromium Safe Storage anahtar türetme (PBKDF2 + AES-128-CBC), Firefox `moz_cookies` okuma. Gerekçe: başka uygulamaların şifreli kimlik deposunu açmak, kullanıcı beklentisinin ötesinde bir yetki; her tarayıcı için ayrı Keychain prompt'u; Chromium şifreleme şeması sürüm başına değişiyor (`v10` + 32 byte domain hash örneği). Bizim tek kimlik kaynağımız Claude Code CLI'ın kendi token'ı.
2. **`claude.ai/api/organizations/<org>/usage` ve `/prepaid/credits` endpoint'leri** — çerez yolu olmadan zaten çağrılamaz.
3. **Codex ve Antigravity sağlayıcıları:** `Core/CodexUsageProvider.swift` (575 satır, `codex app-server` JSON-RPC), `Core/AntigravityUsageProvider.swift`, `Core/AntigravityLocalStore.swift`, `Core/AntigravityPaths.swift`, `Core/ProtobufMessage.swift`, `Core/ProviderAvailability.swift`, `UI/ProviderMarkView.swift`.
4. **`~/.claude/notch-usage.json` statusline feed'i** — bu uygulamaya özgü bir sözleşme, Claude Code standardı değil.
5. **`PricingTable`** — kaba ve eski.
6. **`SecItemCopyMatching(kSecReturnData:)` ile doğrudan Keychain okuma** — prompt tetikler; codex-island'ın `/usr/bin/security` yolunu kullanacağız.
7. **`SpaceInfo.swift`'teki private SkyLight API'leri** (`CGSMainConnectionID`, `CGSCopyManagedDisplaySpaces`, `CGSCopySpacesForWindows`, `@_silgen_name`) — plan §11/CLAUDE.md "Private API yok" kuralı. Fullscreen tespitini `NSApplication.didChangeScreenParametersNotification` + `NSWorkspace.activeSpaceDidChangeNotification` + `collectionBehavior` ile çözeceğiz; gerekirse boring.notch'un (davranış-only) yaklaşımına bakılır.
8. **Clawd/Spark animasyon kareleri** (`Assets/ClaudeCrabFrames.swift`, `ClaudeSparkFrames.swift`, `UI/AvatarView.swift`) — kendi görsel kimliğimiz olacak; ayrıca telif açısından karakter varlıkları alınmaz.
9. **Sağ tık menüsünün menü bar öğesinin yerini alması** (`IslandView.swift:100-165`) — bizde `MenuBarExtra` var (Faz 0 kararı).

## 6. Açık sorular

1. **`/api/oauth/usage` gerçekten `User-Agent` istiyor mu?** codex-island "evet, yoksa 401" diyor; bu repo header'ı hiç göndermiyor ve çalışıyor gibi. Faz 4'ün ilk işi: `curl` ile iki varyantı da denemek (token redakte ederek).
2. **`seven_day_opus` / `seven_day_sonnet` hangi planlarda geliyor?** Bizim parser her iki şekli de desteklemeli ama dashboard'da tek haftalık ring mi göstereceğiz (max) yoksa model başına ayrı ring mi? Plan §6.2 tek ring diyor; `max` almak makul ama hangi modelin dolduğunu göstermek daha bilgilendirici.
3. **`expiresAt` ile ön-kontrol yapmalı mıyız?** Token expired ise hiç istek atmayıp doğrudan "token expired" göstermek rate-limit baskısını azaltır. Ama saat farkı/clock skew yanlış negatif üretebilir. Küçük bir tolerans (ör. 60 sn) ile alalım mı?
4. **`ignoresMouseEvents` çelişkisi:** hangi yaklaşım bizim panel konfigürasyonumuzda (nonactivating + `canBecomeKey = false`) menü barı bozmadan çalışıyor? Faz 1'de gerçek makinede test edilecek somut senaryo: notch'un solundaki menü bar öğelerine ve sağdaki durum çubuğu ikonlarına tıklama.
5. **`~/.claude.json`'dan plan/haftalık reset okuması ne kadar güvenilir?** `cachedGrowthBookFeatures.tengu_saffron_lattice.planLimitsEndDate` tamamen belgesiz bir feature-flag cache'i; sürüm başına değişebilir. Sadece "resmi veri yokken" göstermeye değer mi, yoksa hiç mi okumayalım?
6. **`Block.duration` sabit 5 saat** — Anthropic pencere uzunluğunu değiştirirse (veya plana göre farklıysa) fallback ring yanlış olur. Resmi `resets_at` geldiğinde pencere uzunluğunu **ondan** türetip blok hesabını kalibre edebilir miyiz?
7. **Test altyapısı:** bu repo `swift-testing` (`import Testing`, `@Suite`, `#expect`) kullanıyor; bizim Faz 0 kararımız XCTest. Faz 4'te JSONL fixture'ları için swift-testing'e geçmek mantıklı mı, yoksa XCTest'te kalıp fixture düzenini (`Fixtures/*.jsonl`, bundle resource) mi alalım?
