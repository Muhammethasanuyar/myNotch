# codex-island — Harvest Notu

| | |
|---|---|
| Repo | https://github.com/ericjypark/codex-island |
| Klon | `references/codex-island` @ `0931117` (2026-08-18) |
| Lisans | MIT (`LICENSE`, "Copyright (c) 2026 Eric Park") |
| Devşirme modu | **Kod adapte et** |
| İlgili fazlar | Faz 1 (click-through, notch geometrisi, squircle), Faz 4 (Claude Usage veri katmanı — ana kaynak), Faz 5 (ayarlar: refresh interval, low-power, eşikler) |

## 1. Bizim için değeri

Faz 4'ün **altın madeni**. Plan §6.1'de "resmi limitler" olarak tarif ettiğimiz yolun tamamı burada çalışır durumda: kimlik çözümü, endpoint, header'lar, JSON şekli, rate-limit disiplini, "son iyi değeri koru" davranışı ve auth-hatası UI durumu. Ayrıca:

- **Salt-okunur kimlik doktrini** açıkça yazılmış ve gerekçelendirilmiş (`ClaudeCredentials.swift:10-16`): Anthropic her refresh'te `refresh_token`'ı döndürüyor ve eski token yeniden kullanılırsa **tüm token ailesini iptal ediyor** → ikinci bir refresher kullanıcının CLI login'ini bozar. Bizim §6.3 kabul kriterindeki "token'a asla yazmaz" maddesinin teknik gerekçesi bu.
- **Keychain ACL prompt'unu tamamen atlatan** okuma tekniği (`/usr/bin/security` + attributes-only enumeration). Bu, planımızda hiç düşünülmemiş kritik bir UX/izin riskini çözüyor.
- Faz 1 için: silüet dışını tıklamaya kapatma (hitTest + global mouse monitor), notch ölçüsünün `visibleFrame` üzerinden hesabı (bizim `NotchGeometry.swift`'ten farklı ve daha savunmalı), squircle köşe, notch'suz ekran fallback'i, occlusion/lock'ta animasyonu durdurma.
- Codex (OpenAI) tarafı bizim için **gereksiz**: `Sources/Usage/UsageFetcher.swift:9-140` ve `Sources/Cost/CodexLogReader.swift` alınmayacak. Ama `routeCodexWindows` (a.g.e. 69-89) desenindeki "pencereyi `limit_window_seconds`'a göre etiketle, slot sırasına güvenme" dersi Claude tarafında da akılda tutulmalı.

## 2. Hedef dosyalar

| Kaynak dosya (path:line) | Ne yapıyor | Bizde hedef dosya (per docs/PLAN.md §9) | Faz |
|---|---|---|---|
| `Sources/Usage/UsageFetcher.swift:152-221` | Claude usage endpoint çağrısı + `five_hour`/`seven_day` parse | `Modules/ClaudeUsage/UsageFetcher.swift` | 4 |
| `Sources/Usage/ClaudeCredentials.swift:120-199` | env → keychain kimlik çözümü, probe sonucuna göre kaynak ilerletme | `Modules/ClaudeUsage/ClaudeCredentials.swift` (yeni dosya) | 4 |
| `Sources/Usage/ClaudeCredentials.swift:317-483` | Keychain item keşfi, `security` CLI ile prompt'suz okuma, hex decode, fingerprint | `Modules/ClaudeUsage/ClaudeCredentials.swift` | 4 |
| `Sources/Usage/ClaudeCredentials.swift:276-288` | `CLAUDE_CONFIG_DIR` → `.credentials.json` dosya store'u | `Modules/ClaudeUsage/ClaudeCredentials.swift` + `Settings/SettingsStore.swift` (path override) | 4, 5 |
| `Sources/Usage/UsageStore.swift:62-222` | Polling, cooldown, merge, history kaydı | `Modules/ClaudeUsage/UsageService.swift` | 4 |
| `Sources/Usage/UsageStore.swift:381-618` | Timer arm, sleep/wake, network monitor, credential watch | `Modules/ClaudeUsage/UsageService.swift` | 4 |
| `Sources/Usage/AppUsage.swift:22-126` | `WindowUsage`/`AppUsage` value tipleri + `merged`/`carryForward` | `Modules/ClaudeUsage/UsageModels.swift` (yeni, `nonisolated` saf katman) | 4 |
| `Sources/Usage/WakeScheduling.swift:11-40` | Saf uyku/uyanma karar fonksiyonları (test edilebilir) | `Modules/ClaudeUsage/UsageService.swift` yanına saf yardımcı + `MyNotchTests/` | 4 |
| `Sources/Model/RefreshIntervalStore.swift:11-19` | 300/900/1800 sn preset, 5 dk taban | `Settings/SettingsStore.swift` | 4, 5 |
| `Sources/Model/AlertEngine.swift:213-325` | Saf eşik-geçişi motoru (`resetAt`-anahtarlı crossing memory) | `Core/Modules/EventBus.swift` tetikleyicisi + `Modules/ClaudeUsage/UsageService.swift` | 4 |
| `Sources/Model/AlertThresholdStore.swift:26-45` | Eşik ayarları (varsayılan 80/95, aralık 50-98 / 51-99) | `Settings/SettingsStore.swift` | 4, 5 |
| `Sources/Cost/ClaudeLogReader.swift:18-140` | `~/.claude/projects/**/*.jsonl` → `TokenEvent` (dedupe, synthetic filtre) | `Modules/ClaudeUsage/ProjectsWatcher.swift` (v2 native parser; MVP'de referans) | 6 |
| `Sources/Cost/LogParseCache.swift:17-208` | Dosya keşfi (mtime cutoff), 64 KB chunk streaming, (path,mtime,size) cache | `Modules/ClaudeUsage/ProjectsWatcher.swift` | 6 |
| `Sources/Cost/Pricing.swift:24-269` | Model → USD/1M tablo, canonical model adı, bilinmeyen model = $0 | v2 native maliyet; MVP'de `CCUsageRunner.swift` bunu yapıyor | 6 |
| `Sources/Cost/CostSummary.swift:11-70` | Tek geçişte today/month/5h/7d + model kırılımı | `Modules/ClaudeUsage/UsageService.swift` (dashboard verisi) | 6 |
| `Sources/Window/IslandHostingView.swift:33-50` | Silüet dışında `hitTest → nil` + `acceptsFirstMouse` | `Core/Window/NotchPanel.swift` / `NotchWindowController.swift` | 1 |
| `Sources/Window/IslandWindowController.swift:86-147` | Global mouse monitor ile `ignoresMouseEvents` toggle | `Core/Window/NotchWindowController.swift` | 1 |
| `Sources/Window/IslandWindowController.swift:203-241` | Occlusion + ekran kilidi → animasyonu/pencereyi durdur | `Core/Window/NotchWindowController.swift` | 1, 5 |
| `Sources/Model/NotchInfo.swift:23-72` | `visibleFrame` tabanlı menü bar yüksekliği, notch genişliği, fallback | `Core/Window/NotchGeometry.swift` (mevcut hesapla karşılaştır) | 1 |
| `Sources/Views/IslandShape.swift:10-25` | `UnevenRoundedRectangle(style: .continuous)`, radius 14 | `Core/Window/NotchShape.swift` | 1 |
| `Sources/Views/IslandRootView.swift:134-232` | Hover → peek, click → expanded state machine ve zamanlamalar | `Core/State/NotchViewModel.swift` + `Core/State/Anim.swift` | 1 |
| `Sources/Views/UsageView.swift:78-185` | "auth gerekli" durumu: tile'ları prompt ile değiştirme + re-auth butonu | `Modules/ClaudeUsage/Views/Dashboard.swift` | 4 |
| `Sources/Views/NotchPeekPill.swift:15-55` | Compact/peek yüzde + kalan süre pill'i, loading/error durumları | `Modules/ClaudeUsage/Views/Compact.swift` | 4 |
| `Casks/codexisland.rb`, `release.sh:40-46` | Homebrew cask + ad-hoc imza + create-dmg | `scripts/` (Faz 5+); **bizde Developer ID + notarization** | 5 |

## 3. Desenler

### 3.1 Kimlik çözümü: `CLAUDE_CODE_OAUTH_TOKEN` → Keychain → dosya (salt-okunur)

**Nasıl çalışıyor:** `ClaudeCredentials.resolveUsage(probe:)` (`Sources/Usage/ClaudeCredentials.swift:120-199`) iki token kaynağını sırayla dener ve **her adayı gerçek usage isteğiyle test eder** (probe closure'ı `UsageFetcher` sağlar):

1. `ProcessInfo.processInfo.environment["CLAUDE_CODE_OAUTH_TOKEN"]` (a.g.e. 130-141) — Claude Desktop'ın çocuk process'lerine enjekte ettiği, her zaman taze token.
2. Kimlik store'u: `readClaudeCreds()` (a.g.e. 259-266) → **önce Keychain, sonra dosya**. Yorum (a.g.e. 243-250) bunun gerekçesini veriyor: Claude Code 2.x Keychain'i primary olarak okuyor ve Keychain yazımı başarılı olduğunda `.credentials.json`'ı siliyor/öksüz bırakıyor → yan yana duran dosya **bayat artık**, Keychain item'ı taze olan. (Bu, codex-island'ın kendi #56'sında shipped edilen pre-2.x varsayımının tersi.)
3. Dosya yolu: `claudeCredentialsFilePath()` (a.g.e. 276-280) = `$CLAUDE_CONFIG_DIR/.credentials.json`, yoksa `\(NSHomeDirectory())/.claude/.credentials.json`.

Blob içinden token seçimi `selectClaudeCreds` (a.g.e. 298-311): `blob["claudeAiOauth"]["accessToken"]` boş değilse kabul, `blob["claudeAiOauth"]["subscriptionType"]` plan tier'ı (free/pro/max) olarak alınır — **plan bilgisi endpoint'ten değil kimlikten geliyor** (a.g.e. 123-128).

Probe sonucuna göre kaynak ilerletme asimetrisi (tip dokümanında 18-26. satırlarda gerekçelendirilmiş):
- env token'da **403 (scope insufficient) kısa devre yapmaz** → Keychain token'ı da denenir.
- Keychain token'da 403 → `claude /login` gerekiyor (refresh aynı scope setini yeniden verir), ama önce bayat adayın **arkasındaki** taze aday denenir: en fazla 3 iterasyonlu bounded walk, 401/403 alan token `excluded` setine girer, cache temizlenir ve store yeniden okunur (a.g.e. 143-188).
- **429 her kaynaktan kısa devre yapar**: limiter hesap-bazlı, token-bazlı değil (anthropics/claude-code#30930) → ikinci token denemek sadece limiter'ı besler (a.g.e. 136, 166).

Hiçbir kaynak çalışmazsa `Resolution.failed(lastError)`; `lastError` hâlâ jenerik ve Keychain'de başka bir kullanıcının item'ı varsa mesaj `"multiple keychain logins"` olur (a.g.e. 193-196). Sabit hata mesajları: `"re-login: claude /login"` (32), `"rate limited"` (37), `"token expired — run claude"` (42), `"auth required — run claude"` (121).

**Bize uyarlama:** `Modules/ClaudeUsage/ClaudeCredentials.swift` olarak neredeyse aynen taşınabilir; `enum` + `static` yapı Swift 6'da `nonisolated` saf katman olarak durur (mutable cache hariç — §3.2). `UsageFetcher.swift` sadece HTTP+parse yapar, kimlik kararını `ClaudeCredentials` verir — bu ayrım bizim "thin controller / heavy service" kuralımıza da uyuyor. Hata mesajlarını **ham string yerine enum** yapacağız: `enum UsageAuthState { case ok, tokenExpired, reauthRequired, rateLimited, authMissing(String) }` — codex-island UI'da string eşitliği ile karar veriyor (`UsageView.swift:141`, `UsageStore.swift:274`), bu kırılgan ve bizim "statik dizi/string yerine enum" kuralımıza aykırı. `NotchModule.activity` eşlemesi: `authMissing/tokenExpired` → `.idle` (compact'ta soluk ✳ + expanded'da auth prompt), normal veri → `.live`, eşik aşımı → `.urgent`.

**Dikkat:**
- **Asla yazma.** Ne Keychain'e, ne `.credentials.json`'a, ne de OAuth refresh endpoint'ine. Kabul kriteri §6.3.
- `CLAUDE_CONFIG_DIR` LaunchServices'ten açılan GUI app'e **miras kalmaz** (a.g.e. 273-275) → shell'de set etmiş kullanıcı için env okuması boş döner. Bu yüzden ayarlardan manuel path override sunmamız (plan §6.1) doğru karar; ayrıca Keychain item'larını isimden **türetmek yerine keşfetmek** gerekiyor (§3.2).
- `subscriptionType` yoksa plan chip'i boş kalır; endpoint plan döndürmüyor.
- Aynı Keychain service'i altında **birden fazla item** olabilir (MCP token'ları ayrı item'da, acct=`unknown`) — tek kör lookup yanlış item'a düşer (a.g.e. 252-258).

### 3.2 Keychain'i prompt tetiklemeden okumak (`/usr/bin/security` + attributes-only)

**Nasıl çalışıyor:** Üç katmanlı bir hile:

1. **Keşif metadata ile:** `claudeKeychainItems()` (`ClaudeCredentials.swift:346-366`) `kSecClass: kSecClassGenericPassword` + `kSecMatchLimitAll` + `kSecReturnAttributes: true` ile **`kSecReturnData` OLMADAN** sorgu atar → ACL prompt'u hiç tetiklenmez. Sonra `isClaudeCredentialService` (a.g.e. 337-339) ile filtreler: service tam olarak `"Claude Code-credentials"` (325) **veya** `"Claude Code-credentials-"` ile başlıyorsa (CLI'ın custom config dir başına türettiği `-<sha256 hash>` varyantları). Hash formülünü yeniden hesaplamak yerine **var olanı eşlemek** tercih edilmiş; `"Claude Code-doctor-probe"` gibi kardeş service'ler eşleşmiyor. Bare service'ler önce sıralanır.
2. **Secret okuması `security` CLI ile:** `readClaudeKeychainBlobViaSecurityCLI` (a.g.e. 450-476) `/usr/bin/security find-generic-password -s <service> -a <account> -w` çalıştırır. Yorumdaki gerekçe (a.g.e. 387-400) çok önemli: Claude Code her ~8 saatlik token rotasyonunda item'ı `security add-generic-password -U` ile yeniden yazıyor ve bu yazım item'ın **partition list'ini `apple-tool:`'a resetliyor** → kullanıcının verdiği "Always Allow" izni saatler içinde siliniyor, Developer-ID imzalı app bile bunu aşamıyor. `security` binary'si `apple-tool:` partition'ında olduğu için onun okumaları **kalıcı olarak sessiz**. In-process `SecItemCopyMatching` + `kSecReturnData` sadece fallback (a.g.e. 409-421) ve **prompt tetikleyebilen yol** o.
3. **Hex decode:** `security -w` secret'te basılmayan byte varsa çıktıyı hex-dump ediyor; `decodeClaudeKeychainBlob` (a.g.e. 426-448) önce JSON dener, olmazsa "tamamı hex digit + çift uzunluk" kontrolüyle decode edip yeniden parse eder (JSON `{` ile başladığı için çakışma imkânsız).

Üstüne bir de **cache**: `cachedClaudeCreds` (a.g.e. 226-231) `NSLock` korumalı; sadece başarılı okuma cache'lenir, 401/403 probe'u cache'i temizler. `Process` spawn'ı ve olası prompt her poll'da değil, nadiren ödenir.

Pipe okuma sırası da doğru yapılmış: `readDataToEndOfFile()` **`waitUntilExit()`'ten önce** — tersi 64 KB pipe buffer'ı dolduran çocukta deadlock (a.g.e. 464-467).

**Bize uyarlama:** Bu deseni **olduğu gibi** almalıyız; kendi başımıza `SecItemCopyMatching(kSecReturnData:)` yazsak kullanıcı her 8 saatte bir keychain şifresi soran bir uygulamaya sahip olur. `Modules/ClaudeUsage/ClaudeCredentials.swift` içinde:
- `Process` çalıştırma **ana thread'de değil** (CLAUDE.md kuralı): keychain okuması `nonisolated` bir fonksiyon olarak `Task.detached`/`await` arkasında.
- Swift 6 için mutable static cache `NSLock`'lu bir `final class` veya `actor CredentialCache` içine alınacak (global mutable `static var` Swift 6'da concurrency hatası verir).
- Test edilebilirlik: codex-island `keychainCandidatesProvider` / `keychainModificationDatesProvider` closure'larını enjekte edilebilir bırakmış (a.g.e. 236-237) — testler gerçek keychain'e dokunmadan koşuyor. Bizde de `MyNotchTests/` için aynı şey gerekli.

**Dikkat:** `/usr/bin/security` çıktısı **token içerir** → asla log'lanmamalı, hata mesajına konmamalı, `NSLog`'a sızmamalı. codex-island sadece "read failed" breadcrumb'ı basıyor (a.g.e. 408, 419), içeriği basmıyor — aynı disiplin. Ayrıca sandbox kapalı olması şart (bizde kapalı, plan §3).

### 3.3 Resmi usage endpoint: URL, header'lar, JSON şekli

**Nasıl çalışıyor:** `UsageFetcher.fetchClaudeUsage` (`Sources/Usage/UsageFetcher.swift:163-201`):

```swift
var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
req.setValue("application/json", forHTTPHeaderField: "Accept")
req.setValue("application/json", forHTTPHeaderField: "Content-Type")
// Anthropic gates this endpoint on a CLI User-Agent. Without it the
// request 401s even with a valid token.
req.setValue("claude-code/2.1.121", forHTTPHeaderField: "User-Agent")
```
Kaynak: `references/codex-island/Sources/Usage/UsageFetcher.swift:164-171` (MIT)

GET (body yok, method set edilmiyor). Status eşlemesi (a.g.e. 178-183): 401 → `.unauthorized`, 403 → `.scopeInsufficient`, 429 → `.rateLimited`, 200 dışı → `.otherError("HTTP \(code)")`. **200 gövdesinde de rate-limit hatası gelebiliyor** (a.g.e. 184-190): `obj["error"]["type"] == "rate_limit_error"` → `.rateLimited`.

Yanıt şekli (a.g.e. 191-195, 203-221): üst seviyede `five_hour` ve `seven_day` nesneleri. Her pencere:
- `utilization`: **0-100 aralığında yüzde** (normalize edilmiş kesir DEĞİL) → her zaman `/100`, sonra `min(1, max(0, ...))` ile clamp. Yorum (a.g.e. 205-209) eski `raw > 1 ? raw/100 : raw` heuristiğinin 5 saatlik pencere resetlendiğinde nasıl kırıldığını anlatıyor: %0.5 kullanım `0.5` gelir ve "zaten normalize" sanılıp %50 gösterilir.
- Alternatif alan adı `used_percent` da denenir.
- `resets_at`: epoch `Double` **veya** ISO8601 string (fraksiyonlu/fraksiyonsuz iki formatter ile) (a.g.e. 212-219).
- Pencere yok/parse edilemezse `WindowUsage.unknown` = `usedPercent: 0, resetAt: nil, error: "no data"`.

Plan tier yanıtta **yok** → §3.1'deki `subscriptionType`'tan gelir.

**Bize uyarlama:** `Modules/ClaudeUsage/UsageFetcher.swift`: `URLSession` çağrısı `async` (ana thread'de network yok), sonuç `nonisolated` saf parse fonksiyonundan geçirilip `Sendable` bir value tipine dönüşür. `five_hour` → 5 saatlik ring, `seven_day` → haftalık ring (plan §6.2). `Codable` struct yazmak cazip ama codex-island `JSONSerialization` + `[String: Any]` kullanıyor; belgesiz endpoint için **toleranslı** olan bu (eksik/ekstra alan `Codable`'ı kırar). Bizde: `Codable` + tüm alanlar `Optional` + `decodeIfPresent`, ya da aynı sözlük yaklaşımı — kararı Faz 4'te verelim, ama `keyDecodingStrategy` ile snake_case'i map etmek şart (`five_hour`, `seven_day`, `resets_at`).

**Dikkat:**
- **User-Agent zorunlu.** `claude-code/<sürüm>` olmadan geçerli token'la bile 401. Bu bir **spoof** ve endpoint belgesiz — Anthropic bunu değiştirirse veya kısıtlarsa modül kör kalır. Sürüm string'ini sabitten okuyalım ki tek yerden güncellenebilsin. (Kaynak atfı: codex-island bunu `RchGrav/claudecodeusage`'a atfediyor, README:367.)
- `anthropic-beta: oauth-2025-04-20` header'ı da gate'in parçası.
- Mid-2026'da Anthropic bu endpoint'in gerektirdiği scope setine `user:profile` ekledi (CLAUDE.md:80) → eski token'lar 403 alıyor ve **sadece yeni `claude /login`** düzeltebiliyor.
- Endpoint hesap-bazlı ve agresif rate-limit'li → §3.4.
- Token ve yanıt içeriği log'lanmamalı.

### 3.4 Polling disiplini: 5 dakika tabanı + sticky 429 cooldown

**Nasıl çalışıyor:** `RefreshIntervalStore` (`Sources/Model/RefreshIntervalStore.swift:11`) sadece `[300, 900, 1800]` saniyeye izin verir; varsayılan 300. README:329-331 gerekçe: "Anthropic `/api/oauth/usage`'ı hesap seviyesinde agresif rate-limit'liyor."

429 sonrası: `UsageStore.rateLimitCooldown = 900` (`Sources/Usage/UsageStore.swift:59`). Rate-limit tespit edilirse (`isRateLimited`, a.g.e. 273-276: **iki pencere de** `"rate limited"` mesajını taşıyorsa) `claudeCooldownUntil = now + 900` set edilir ve sonraki 15 dakika Claude fetch'i **hiç yapılmaz** (a.g.e. 125-129). Yorumdaki neden (a.g.e. 54-58): limiter bir kez tetiklendi mi `retry-after: 0` ile 429 dönmeye devam ediyor, hesap sessizleşene kadar — yani içinden poll'lamak asla iyileşmiyor. Cooldown **sadece bellekte**: quit+relaunch hemen yeniden dener.

Cooldown bitiminde tek seferlik retry planlanır (`scheduleCooldownRetry`, a.g.e. 556-569; `cooldown + 10 sn`) — yoksa iyileşme bir sonraki timer tick'ine kalır (en kötü 30 dk + 15 dk ≈ 45 dk).

**Bize uyarlama:** `Modules/ClaudeUsage/UsageService.swift`: `SettingsStore`'da interval preset'i (300/900/1800; **5 dakikanın altı UI'da hiç sunulmayacak**), `rateLimitCooldown` sabiti ve tek-seferlik cooldown retry task'ı. `Timer` yerine `Task` + `Task.sleep` tercih edebiliriz ama §3.6'daki uyanma sorunu `Task.sleep`'te daha kötü (deadline sistem uykusunda akmaya devam ediyor) → codex-island `Timer` + explicit wake handling yolunu seçmiş, biz de öyle yapalım.

**Dikkat:** ccusage çağrısı (plan §6.1, `CCUsageRunner`) 30-60 sn'de bir yapılabilir — o **yerel dosya okuması**, network değil, farklı bir cadence'i var. İki cadence'i karıştırmayalım: resmi endpoint ≥5 dk, ccusage/JSONL 30-60 sn + dosya değişimi.

### 3.5 "Son iyi değeri koru" (merge/carry-forward) + kalıcı history seed

**Nasıl çalışıyor:** Başarısız bir poll ne paneli boşaltmalı ne de hatayı saklamalı. `AppUsage.merged(fetched:retaining:at:)` (`Sources/Usage/AppUsage.swift:102-126`) pencere bazında karar verir:

```swift
private static func carryForward(
    _ fetched: WindowUsage, prior: WindowUsage, at now: Date
) -> WindowUsage {
    guard !fetched.hasReading, prior.hasReading else { return fetched }
    if fetched.isUnreported { return fetched }
    if let reset = prior.resetAt, reset <= now { return fetched }
    return WindowUsage(
        usedPercent: prior.usedPercent, resetAt: prior.resetAt, error: fetched.error
    )
}
```
Kaynak: `references/codex-island/Sources/Usage/AppUsage.swift:112-126` (MIT)

Yani: eski **gerçek sayı** korunur, üstüne **yeni hata caption'ı** takılır. Üç istisna:
1. `prior.resetAt` geçmişse taşınan sayı artık var olmayan bir pencereyi tarif eder → bırakılır ("—" gösterilir).
2. `fetched.isUnreported` (a.g.e. 50): sunucu pencereyi **başarıyla parse edilen** yanıtta hiç döndürmediyse (tek pencereli planlar) eski değer yerini alır, üstü örtülmez.
3. **Terminal auth failure** (expired token / eksik scope) carry-forward YAPMAZ (`UsageStore.swift:173-183`): token o sayıları bir daha asla yenileyemez, ve UI re-auth prompt'unu tam bu "hata-only" şekle göre gösteriyor.

`hasReading` (a.g.e. 41) kritik ayrım: hatalı fetch `usedPercent: 0` üretir, bu "gerçekten boş pencere" ile aynı görünür → `!(error != nil && usedPercent == 0)`. Her yüzde gösteren/alarm veren tüketici önce buna bakmalı.

Üstüne **kalıcı seed**: `UsageHistoryStore` (`Sources/Usage/UsageHistory.swift:17-52`) her başarılı poll'da hatasız pencereleri UserDefaults'a yazar (7 gün / max 1000 örnek). `seedFromHistory()` (`UsageStore.swift:232-235`) ilk fetch inmeden paneli son gerçek sayılarla doldurur — sticky 429 app restart'ından da uzun sürdüğü için bu olmadan soğuk başlangıç 15 dk boyunca "—" gösterir.

**Bize uyarlama:** `Modules/ClaudeUsage/UsageModels.swift` içinde `nonisolated` saf value katmanı (`WindowUsage`, `AppUsage`, `merged`) + `MyNotchTests/UsageMergeTests.swift`. `hasReading == false` → dashboard'da "—", compact'ta rakam yok (plan §6.2'deki ring "erişilemezse ccusage blok tahminine zarifçe düş" davranışı bu kapının arkasına takılacak: önce carry-forward, o da yoksa ccusage tahmini, o da yoksa "—").

**Dikkat:** Bizim plan "erişilemezse ccusage blok tahminine düş" diyor; codex-island'da böyle bir çapraz-kaynak fallback **yok** (usage ve cost tamamen ayrı store'lar). Bu bizim kendi yazacağımız katman ve **kaynağı UI'da işaretlenmeli** — kullanıcı resmi %'yi tahminle karıştırmamalı (ör. ring kesikli çizgi + "tahmini" etiketi).

### 3.6 Uyku/uyanma ve ağ geçişi disiplini

**Nasıl çalışıyor:** Tekrarlayan `Timer` uyku boyunca kaçırdığı fire'ı **uyanınca tek seferde hemen** teslim eder — yani Wi-Fi henüz associate olurken, tüm uyuyan Claude Code oturumlarının reconnect trafiği paylaşılan limiter'a yüklenirken ve access token uyku sırasında expire olmuşken. `"rate limited"` ve `"token expired"` tam kapak açılırken böyle geliyor (`Sources/Usage/UsageStore.swift:427-434`).

Çözüm: `WakeScheduling` (`Sources/Usage/WakeScheduling.swift`) iki saf karar sunar — `isOverdueFire(now:expected:)` (fire beklenenden **120 sn**'den fazla geç geldiyse uyku catch-up'ıdır, 11+26-29) ve `shouldRefreshAfterWake(lastPoll:now:pollInterval:)` (kısa şekerlemede off-schedule refresh yapma, 35-40). `timerFired()` (`UsageStore.swift:435-449`) overdue fire'ı yakar ve `deferPostWakeRefresh()`'e yönlendirir: **60 sn grace** (`WakeScheduling.graceDelay`) sonra tek bir probe. Grace penceresi **her** uyanışta armlanır ki `NWPathMonitor`'ın "ağ geri geldi" refresh'i de burst'e dalmasın (`UsageStore.swift:493-513`, 605).

`NWPathMonitor` (a.g.e. 593-618) sadece `unsatisfied → satisfied` geçişinde refresh eder (launch-at-login'de Wi-Fi henüz yokken atılan ilk isteğin yarattığı yarışı kapatır); ilk callback bilinçli yutulur. Uçuş halindeki refresh iptal edilip **`await refreshTask?.value` ile bitmesi beklenir** — yoksa yeni `refresh()` `if loading { return }` guard'ına takılır. `willSleepNotification`'da uçuştaki task iptal edilir.

Tek-seferlik recovery task'ları (`Task.sleep`) sistem uykusunda deadline'ı akmaya devam ettiği için `waitOutWakeGrace()` (a.g.e. 577-583) ile grace bitene kadar bekletilir.

**Bize uyarlama:** `Modules/ClaudeUsage/UsageService.swift`. Saf `WakeScheduling` fonksiyonlarını `nonisolated` + XCTest'li alacağız (bizim CLAUDE.md "saf yardımcılar `nonisolated` ve birim testli" kuralına birebir uyuyor). `NSWorkspace.willSleep/didWake` observer'ları ve `NWPathMonitor` `UsageService`'in `start()/stop()` yaşam döngüsüne bağlanacak; modül `isEnabled == false` olduğunda **hepsi kapanacak** (plan §13 CPU/enerji riski).

**Dikkat:** Bizde `ProjectsWatcher` da uyandığında bir sürü değişiklik görecek — dosya izleyicinin debounce'u ayrı düşünülmeli. Ayrıca notch penceresi kapalıyken (closed state) timer'ları durdurma kuralımız var; ama usage polling **görünürlükten bağımsız** olmalı (yoksa hover ettiğinde hep bayat veri) — codex-island da öyle yapıyor, sadece animasyonu occlusion'a bağlıyor (§3.11).

### 3.7 Kimlik store'unu izlemek + "refresh ping" (yazmadan token yenileme)

**Nasıl çalışıyor:** "token expired" hatası sebebinden **poll aralığı kadar** uzun yaşıyor: kullanıcı `claude` çalıştırdığında token saniyeler içinde dönüyor ama bizim sonraki poll'umuz 5-30 dk sonra. İki mekanizma:

1. **Fingerprint watch.** `credentialStoreFingerprint()` (`ClaudeCredentials.swift:374-381`) = Keychain item'larının `kSecAttrModificationDate`'leri + `.credentials.json` mtime'ının **en yenisi**. Tamamen metadata → prompt yok, network yok. `watchCredentialStore()` (`UsageStore.swift:523-550`) terminal auth hatasında devreye girer, **5 saniyede bir** fingerprint'i karşılaştırır; değiştiği an cache'i temizler, wake grace'i bekler ve refresh eder. Secret okuması (ve olası prompt) sadece store gerçekten değiştiğinde ödenir.
2. **Refresh ping.** `spawnTokenRefreshPing()` (`ClaudeCredentials.swift:547-576`): `claude -p ok --model haiku --strict-mcp-config`, cwd `$HOME`, stdio `FileHandle.nullDevice`, env'den `ANTHROPIC_API_KEY` / `ANTHROPIC_AUTH_TOKEN` / `CLAUDE_CODE_OAUTH_TOKEN` **silinmiş**. Amaç yan etki: CLI cevap vermeden önce expired access token'ı yeniler ve rotated çifti kendi store'una **kendisi** yazar; fingerprint watch bunu yakalar. Yani "refresh eden tek meşru aktör CLI'dır" doktrini korunuyor. Gating saf bir fonksiyonda: `shouldSpawnRefreshPing(for:alreadyAttempted:reauthInProgress:)` (a.g.e. 78-82) → **expiry episode'u başına en fazla bir kez**; başarılı fetch flag'i sıfırlar (`UsageStore.swift:204-208`). Sadece `claudeAiOauth` kaynaklı expired-token hatasından tetiklendiği için console/API-key kullanıcısı asla faturalanamıyor.

Ek olarak in-app re-auth: `spawnReauth()` = `claude auth login` (a.g.e. 509-527) ve `reauthenticateClaude()` (`UsageStore.swift:324-379`) 5 sn × 24 tur (~2 dk) fingerprint bekler, store yazımını gördükten sonra cache temizleyip fetch dener; 429 görürse döngüden çıkar. `canPromptReauth()` (`ClaudeCredentials.swift:496-500`) butonu ancak (a) bir Claude login store'u varsa ve (b) `claude` binary'si bilinen yollardan birinde bulunuyorsa gösterir; `which` **bilinçli kullanılmıyor** çünkü LaunchServices app'e kırpılmış PATH veriyor (`/usr/bin:/bin:/usr/sbin:/sbin`) → Homebrew/nvm/Bun kurulumları görünmez. Aranan yollar (a.g.e. 582-606): `/opt/homebrew/bin`, `/usr/local/bin`, `~/.bun/bin`, `~/.npm-global/bin`, `~/.local/bin`, sonra `~/.nvm/versions/node/*/bin/claude` (sürümler azalan sırada).

**Bize uyarlama:** Fingerprint watch'ı **alalım** — bedava ve UX'i çok iyileştiriyor; `Modules/ClaudeUsage/UsageService.swift` içinde 5 sn'lik hafif task, sadece auth hatası durumunda açık. `locateClaudeBinary()` ve `canPromptReauth()` da alınmalı (bizim "auth gerekli — `claude` çalıştır" durumu için buton koşulu).

**Refresh ping'i MVP'de ALMAYALIM** (§5). Kullanıcı adına para harcayabilecek (haiku olsa da) bir CLI process'i sessizce spawn etmek, bizim "kullanıcıya şeffaf ol" onboarding'imizle çelişir. Faz 5'te **ayardan kapalı** gelen bir opsiyon olarak düşünülebilir; o zaman da codex-island'ın env-temizleme + tek-seferlik gating disiplini aynen kopyalanmalı.

**Dikkat:** `claude auth login` spawn etmek bir tarayıcı sekmesi ve localhost listener açar — kullanıcıyı bilgilendirmeden yapılmamalı (buton = açık kullanıcı niyeti, otomatik = hayır).

### 3.8 Eşik alarmları: `resetAt`-anahtarlı crossing memory + warmup

**Nasıl çalışıyor:** Bizim §6.3 kabul kriterimiz "%80 eşiğinde popup **bir kez** tetiklenir (spam yok)". codex-island'ın çözümü `AlertDecision` (`Sources/Model/AlertEngine.swift:213-325`) — Combine ve mutable state'ten arındırılmış **saf** bir namespace:

- Anahtar: `CrossingKey(provider, threshold, resetAt)` (a.g.e. 62-66). `resetAt`'in anahtarın parçası olması, "pencere resetlendi → geçmiş geçişleri unut" davranışını bedava veriyor: her recompute'ta mevcut `resetAt`'e uymayan key'ler prune edilir (a.g.e. 285-293).
- Her tick'te iki eşik (`warning`, `critical`) kontrol edilir; yeni eklenen key varsa **tek** `PulseEvent` üretilir (birden fazla provider/eşik aynı tick'te geçerse tek event'te coalesce).
- `warmedUp` guard'ı (a.g.e. 172-175): ilk gerçek veri gelen recompute pulse üretmez — app'i %96'da açan kullanıcıya retroaktif popup atılmaz (ama **severity/tint hemen** hesaplanır, a.g.e. 130-139).
- `usage.lastUpdated != nil` guard'ı (a.g.e. 162): ilk fetch inmeden crossing memory oluşmaz.
- Alarmlar kapalıyken crossing memory ve warmup sıfırlanır (a.g.e. 149-155) → tekrar açılınca eski geçişler için geriye dönük pulse atılmaz.
- `hasReading == false` pencereler "sinyal yok" sayılır (a.g.e. 232, 314).
- Eşikler: varsayılan warning **80**, critical **95**; aralık 50-98 / 51-99; `warning < critical` geçersizse motor "eşik yok" gibi davranır (`AlertThresholdStore.swift:26-45`, `AlertEngine.swift:109-111`). Alarmlar **varsayılan kapalı** (mevcut kullanıcıya sürpriz görsel değişiklik olmasın).
- Pulse tüketimi one-shot: `@Published var pulseEvent` UI tarafından `nil`'e çekilir (`IslandRootView.swift:292-301`), `pulseToken` ile aynı event iki kez işlenmez. Panel expanded iken bastırma **view katmanında** yapılır, motor view state'ine bağlı değil (`AlertEngine.swift:193-202`).

**Bize uyarlama:** Bu tam olarak `Core/Modules/NotchEvent.swift` + `EventBus.swift` + `ModuleManager` önceliğine oturuyor:
- `AlertDecision` eşdeğerini `nonisolated` saf fonksiyon olarak `Modules/ClaudeUsage/` altına + `MyNotchTests/ThresholdCrossingTests.swift`.
- Yeni crossing → `EventBus`'a `NotchEvent.claudeThreshold(...)` publish → `ModuleManager` `activity = .urgent` görür → `NotchState.popup(event:)` (plan §4.2: popup her durumdan araya girebilir, expanded iken **banner** olarak gösterilir — codex-island'ın "expanded iken bastır" davranışından daha iyi).
- Popup'ı `Anim.popIn` ile, süre 2-4 sn (plan §4.4). codex-island peek'i ~4 sn tutuyor (`IslandRootView.swift:306-341`).
- Eşikler `SettingsStore`'da; varsayılanları 80/95 alalım ama bizde alarmlar **varsayılan açık** olabilir (yeni ürün, sürpriz sorunu yok) — bu bir ürün kararı.

**Dikkat:** `resetAt` `nil` ise crossing değerlendirilemiyor (a.g.e. 309) — endpoint `resets_at` döndürmezse popup hiç atılmaz. ccusage blok tahminine düştüğümüzde kendi `resetAt`'imizi (blok başlangıcı + 5 saat) üretmemiz gerekecek; bunu **tahmin** olarak işaretlemeyi unutmayalım.

### 3.9 Yerel JSONL okuma: dosya keşfi, artımlı cache, dedupe

**Nasıl çalışıyor:** `ClaudeLogReader.scan(lookbackDays:)` (`Sources/Cost/ClaudeLogReader.swift:18-47`) ccusage'ın veri yolunu birebir taklit ediyor:

- **Kökler** (`projectRoots()`, a.g.e. 49-61): `CLAUDE_CONFIG_DIR` set ise **virgülle ayrılmış** birden fazla dizin, her birine `projects/` eklenir. Değilse `~/.claude/projects` **ve** `~/.config/claude/projects` (var olanlar).
- **Dosya keşfi** (`LogParseCache.jsonlFiles`, `Sources/Cost/LogParseCache.swift:17-40`): recursive enumerator, `pathExtension == "jsonl"`, `contentModificationDate < cutoff` olanlar atlanır.
- **Satır ayrıştırma** (`parseLine`, `ClaudeLogReader.swift:87-140`): sadece `raw["type"] == "assistant"` satırları; `message.usage`, `message.model`, `message.id`, top-level `requestId`, top-level `timestamp` (ISO8601, fraksiyonlu + fraksiyonsuz iki formatter).
  ```swift
  let input = (usage["input_tokens"] as? Int) ?? 0
  let output = (usage["output_tokens"] as? Int) ?? 0
  let cacheCreate = (usage["cache_creation_input_tokens"] as? Int) ?? 0
  let cacheRead = (usage["cache_read_input_tokens"] as? Int) ?? 0

  // Skip noop entries — ccusage filters these so totals match exactly.
  if input == 0 && output == 0 && cacheCreate == 0 && cacheRead == 0 { return nil }
  ```
  Kaynak: `references/codex-island/Sources/Cost/ClaudeLogReader.swift:123-129` (MIT)
- **Dedupe**: `"\(messageId):\(requestId)"`; **ikisi de** varsa dedupe edilir, biri eksikse dedupe edilmeden geçirilir (ccusage paritesi, a.g.e. 111-116). `<synthetic>` / `synthetic*` modelleri atlanır (a.g.e. 106).
- **Artımlı okuma**: dosya-başına parse sonucu `~/Library/Caches/<bundle>/claude-parse-cache.v1.json`'da `(path, mtime, size)` anahtarıyla memoize edilir (`LogParseCache.swift:171-208`, `CachedFile.matches` a.g.e. 129-132 — JSON Double round-trip'i için 1 ms tolerans). İki poll arasında neredeyse hiçbir dosya değişmediğinden steady-state refresh JSONL taramasını **tamamen** atlıyor. Kaybolan/cutoff'tan çıkan dosyaların cache girdileri budanıyor. `cacheVersion` bump'ı temiz re-parse zorluyor.
- **Streaming**: `streamLines` (a.g.e. 62-119) 64 KB chunk + `memchr` ile newline arama; sadece yarım satır `pending`'de taşınır. Yorum, önceki O(N²) implementasyonunun base64 gömülü ~50 MB'lık tek satırlarda bir çekirdeği dakikalarca yaktığını anlatıyor. `maxLineBytes` ile satır başına cap (Claude yolunda cap yok, Codex opt-in).

**Bize uyarlama:** MVP'de `CCUsageRunner.swift` (`npx ccusage@latest blocks --json` / `daily --json`) ile gidiyoruz — plan §6.1 kararı doğru, maliyet hesabını yeniden yazmıyoruz. Bu desen **Faz 6 native parser'ın** hazır şablonu: `Modules/ClaudeUsage/ProjectsWatcher.swift` içinde kök keşfi + `(path,mtime,size)` cache + chunked streaming + dedupe. `Data(contentsOf:)` **kullanmayacağız**.

MVP'de bu dosyadan **hemen** alacağımız iki şey:
1. **Kök keşfi mantığı** — `ProjectsWatcher` neyi izleyecek? `CLAUDE_CONFIG_DIR` (virgüllü!) + `~/.claude/projects` + `~/.config/claude/projects`.
2. **"Claude çalışıyor" tespiti** için mtime taraması: plan §6.1 "son ~10 sn içinde herhangi bir `.jsonl` değiştiyse `.live`" — `jsonlFiles(under:modifiedAfter:)` tam bunu veriyor (ama bizde FSEvents/`DispatchSource` ile push, polling değil).

**Dikkat:** JSONL format drift (plan §13). codex-island'ın toleransı iyi: eksik alan → 0, parse hatası → `nil`, bilinmeyen model → $0. Aynı toleransı koruyalım ve **sessizce yutma** kuralımızla dengeleyelim: parse başarısızlığı sayacı tutup dashboard'da "N satır okunamadı" göstermek doğru orta yol. Ayrıca cache dosyası `~/Library/Caches` altında — kullanıcı verisi (proje adları, token sayıları) içerir, hassas değil ama token/mesaj içeriği **asla** yazılmamalı (codex-island da yazmıyor, sadece sayılar).

### 3.10 Fiyat tablosu: gömülü seed + uzaktan katalog + canonical model adı

**Nasıl çalışıyor:** `Pricing` (`Sources/Cost/Pricing.swift`) modelden USD/1M-token dört oranı çözer: `inputPerMillion`, `outputPerMillion`, `cacheCreationPerMillion`, `cacheReadPerMillion` (a.g.e. 17-22). Çözüm sırası (a.g.e. 205-217): **uzaktan katalog önce, gömülü seed sonra** — katalogda olmayan modelin sessizce $0'a düşmesini engelleyen şey seed. Bilinmeyen model $0 (ccusage paritesi) ama `isKnown()` ile UI kullanıcıyı uyarabiliyor.

`canonicalModel` (a.g.e. 261-269) Anthropic'in tarih suffix'ini soyuyor: son 9 karakter `-` + 8 rakam ise atılır (`claude-haiku-4-5-20251001` → `claude-haiku-4-5`) → pinned release başına ayrı satır gerekmiyor. `prettyModelName` (a.g.e. 229-259) `claude-opus-4-7` → `Opus 4.7` çevirisi yapıyor (bizim model kırılımı barı için birebir işe yarar).

Katalog: `PricingCatalog.endpoint = https://ericjypark.github.io/codex-island-model-catalog/v1/models.json` (`Sources/Cost/PricingCatalog.swift:33-35`), `schemaVersion` kontrollü, `NSLock`'lu, günlük yenilenen, diske cache'lenen. `App.swift:25` her şeyden önce `PricingCatalog.loadFromDisk()` çağırıyor — ilk cost taraması seed'e düşüp sonra sessizce sayı değiştirmesin diye.

Seed tablosundaki 1M-context tier (200k üstü 2x) **bilinçli atlanmış** (a.g.e. 182-186).

**Bize uyarlama:** MVP'de gerek yok (ccusage fiyatlıyor). Faz 6'da native parser'a geçerken: fiyat tablosunu **bundle'layalım** (plan §6.1 zaten böyle diyor) + `canonicalModel` suffix soyma + `prettyModelName`. **Başka birinin GitHub Pages katalogunu kullanmayacağız** (üçüncü taraf bağımlılığı + gizlilik); gerekirse kendi tablomuzu app güncellemesiyle taşırız veya LiteLLM'in `model_prices_and_context_window.json`'ını doğrudan çekeriz.

**Dikkat:** Fiyatlar hızla eskiyor (seed'de Opus 5 / Sonnet 5 / gpt-5.6 satırları var, yorumlarda "introductory pricing" notları). Gömülü tablo + "son güncelleme tarihi" göstermek dürüst; hiç göstermemek yanıltıcı.

### 3.11 Click-through: `hitTest` + global mouse monitor + `ignoresMouseEvents`

**Nasıl çalışıyor:** Pencere notch'tan çok daha büyük (900×360, `IslandWindowController.swift:22`) ama sadece görünen silüet tıklanabilir olmalı. **İki mekanizma birlikte** gerekiyor (`IslandHostingView.swift:4-11` yorumu bunu açıkça söylüyor):

1. `hitTest` override (`Sources/Window/IslandHostingView.swift:33-43`) — silüet dikdörtgeni dışındaki noktalar için `nil`:
   ```swift
   override func hitTest(_ point: NSPoint) -> NSView? {
       let b = bounds
       let size = islandModel.size
       let rect = NSRect(
           x: b.midX - size.width / 2,
           y: b.maxY - size.height,
           width: size.width,
           height: size.height
       )
       return rect.contains(point) ? super.hitTest(point) : nil
   }
   ```
   Kaynak: `references/codex-island/Sources/Window/IslandHostingView.swift:33-43` (MIT)
2. Global + local `NSEvent.mouseMoved` monitor'ları (`IslandWindowController.swift:86-110`) cursor pozisyonuna göre `window.ignoresMouseEvents`'i flip eder (a.g.e. 118-133). `hitTest` tıklama **sırasında** focus çalmayı engelliyor; global monitor tıklama **daha ulaşmadan** engelliyor.
3. Launch anında cursor zaten silüetin içindeyse hiç `mouseMoved` gelmez → 0.1 sn'lik güvenlik timer'ı, ilk gerçek `mouseMoved`'da kendini invalidate ediyor (a.g.e. 103-116) — steady-state'te 10 Hz timer maliyeti ödenmiyor.
4. `acceptsFirstMouse(for:) -> true` (`IslandHostingView.swift:50`): overlay modelinde kullanıcı başka bir app'e focus'luyken notch'a geliyor, **ilk tıklama** paneli açmalı; macOS varsayılanı ilk tıklamayı pencere aktivasyonuna yutuyor.
5. Silüete girildiğinde `NSApp.activate` + `window.makeKey()` ve **sadece o sırada** bir `keyDown` monitor'ı takılır (Cmd+Q, Cmd+1/2/3, ok tuşları); çıkışta kaldırılır (a.g.e. 134-146, 149-181).

Pencere konfigürasyonu (a.g.e. 28-46): `styleMask [.borderless, .fullSizeContentView]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `level = .popUpMenu`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`, `isMovable = false`, `canBecomeKey = true` / `canBecomeMain = false` (`BorderlessFloatingWindow.swift:3-6`).

**Bize uyarlama:** `Core/Window/NotchPanel.swift` + `NotchWindowController.swift` (Faz 1). Bizim mevcut kod `NSHostingView.sizingOptions = []` ile AppKit'e geometri sahipliği veriyor — aynı felsefe. Eklenecekler: `hitTest` override'ı (silüet dikdörtgeni `NotchLayout`'tan gelecek, `NotchShape`'in gerçek path'i ile de yapılabilir — daha doğru ama daha pahalı), global/local mouse monitor + `ignoresMouseEvents`, `acceptsFirstMouse`, launch-time polling emniyet supabı.

**Farklarımız:** plan §4.1 `level = .screenSaver` ve `collectionBehavior`'a `.fullScreenAuxiliary` diyor (tam ekranda görünürlük hedefimiz var; codex-island `.popUpMenu` + `.fullScreenAuxiliary` yok). Ayrıca bizde hover **expand ediyor** (plan §4.1, ~0.15 sn gecikme), codex-island'da hover sadece "peek", expand için click gerekiyor. İkisi de savunulabilir; Faz 1'de Debug Preview'da denenmeli.

**Dikkat:** `NSEvent.addGlobalMonitorForEvents` **Accessibility izni gerektirmez** (`.mouseMoved` için) ama sürekli çalışan bir monitor'dır — enerji maliyeti düşük ama sıfır değil. Silüet küçükken 10 Hz timer'ı asla açık bırakmayalım. `NSApp.activate(ignoringOtherApps:)` her hover'da çağrılırsa kullanıcının aktif app'ini çalar — codex-island bunu sadece "içeri girildi" geçişinde bir kez yapıyor (a.g.e. 134-138), aynısını yapalım.

### 3.12 Notch geometrisi, squircle ve görünmezlik durumları

**Nasıl çalışıyor:** `NotchInfo.detect(from:)` (`Sources/Model/NotchInfo.swift:23-39`):
- Genişlik: `screen.frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width`; ikisinden biri yoksa **200 pt** fallback.
- Yükseklik: `safeAreaInsets.top` **değil**, `screen.frame.maxY - screen.visibleFrame.maxY - 1` (`menuBarHeight`, a.g.e. 59-72). Gerekçe (a.g.e. 8-19, 50-58): kullanıcı "Scaled to avoid the notch" modundayken menü barı fiziksel notch'un altına iniyor (≈24 pt) ve `safeAreaInsets.top` (≈37 pt) görünen menü barla **çelişiyor**; ayrıca `visibleFrame.maxY` menü barın 1 pt altında (AppKit o şeridi rezerve ediyor) → ölçüm 1 pt fazla çıkıyor. Sonuç fiziksel notch yüksekliğine **clamp** ediliyor ki bayat `visibleFrame` (login, display wake) silüeti menü barın altına sarkıtmasın. Auto-hide menü barda (`visibleFrame == frame`) `safeAreaInsets.top`, o da yoksa `NSStatusBar.system.thickness`, o da yoksa 24.
- Notch'suz ekran: `hasNotch = false` + kullanıcı ayarından gelen `compactWidth` → aynı modüller, farklı closed genişlik (`IslandModel.applyOverride`, `Sources/Model/IslandModel.swift:136-139`).

Şekil: `IslandShape` (`Sources/Views/IslandShape.swift:10-25`) = `UnevenRoundedRectangle(topLeading: 0, bottomLeading: 14, bottomTrailing: 14, topTrailing: 0, style: .continuous)`. `.continuous` (squircle) seçimi gerekçelendirilmiş: dairesel yay bu ölçekte tanjant noktasında görünür kırık yapıyor.

Görünmezlik: `NSWindow.didChangeOcclusionStateNotification` (`IslandWindowController.swift:203-219`) → `WindowOcclusionStore` → 30 Hz `TimelineView` duruyor (idle CPU ≈ %0). Ekran kilidi: `DistributedNotificationCenter` `"com.apple.screenIsLocked"` / `"com.apple.screenIsUnlocked"` (a.g.e. 225-241) → pencere `orderOut` / 0.4 sn fade-in; yoksa ada lock-screen slide animasyonuna binip "notch düşüyor" gibi görünüyor.

**Bize uyarlama:** `Core/Window/NotchGeometry.swift`'i bu ölçüm kuralıyla **karşılaştırmalıyız** — bizim mevcut kodumuz `safeAreaInsets.top` kullanıyor (`NotchGeometry.swift`, CLAUDE.md kuralı da öyle diyor). codex-island'ın `visibleFrame` yaklaşımı "Scaled to avoid the notch" senaryosunda daha doğru; ama plan §13'teki "ölçüleri her zaman `safeAreaInsets`/`auxiliaryTop*Area`dan hesapla" kuralıyla çelişmiyor — sadece **hangisinin** hangi durumda kullanılacağını netleştiriyor. `menuBarHeight(safeTop:visibleFrameDelta:statusBarThickness:)` saf fonksiyonu birebir alınıp `MyNotchTests/`e test yazılabilir (codex-island'da da `Tests/NotchHeightTests.swift` var).
`NotchShape.swift` (Faz 1) `.continuous` kullanacak; plan §4.4'teki içbükey "kulak" kıvrımı codex-island'da **yok** (o sadece alt köşeleri yuvarlıyor) → oradan alacağımız tek şey `.continuous` kararı ve radius 14.
Occlusion + screen lock observer'ları `NotchWindowController`'a eklenecek (plan §13 CPU riski, §4.4 "closed durumda timer'ları durdur").

**Dikkat:** `com.apple.screenIsLocked` belgesiz bir distributed notification (private ama yaygın kullanılan); kırılırsa sadece kilit ekranı kozmetiği bozulur, kritik değil. Notch genişliği fallback'i (200 pt) sabit sayı — plan §13 "sabit değer yok" der; biz fallback'i ayrıca işaretleyelim (`isMeasured: Bool`) ki Debug Preview'da görülsün.

## 4. Plan ile çelişkiler / doğrulamalar

**Doğrulananlar (plan §6.1 / §13 birebir tutuyor):**

| Plan varsayımı | codex-island'daki gerçek |
|---|---|
| Kimlik sırası `CLAUDE_CODE_OAUTH_TOKEN` → `.credentials.json` → Keychain | Sıra **doğru başlıyor** ama store içinde **Keychain önce, dosya sonra** (`ClaudeCredentials.swift:259-266`) — 2.x CLI Keychain'i primary tutuyor, yan yana duran dosya bayat artık. **Planı düzeltmeliyiz.** |
| Keychain öğesi adı `Claude Code-credentials` | Doğru (`ClaudeCredentials.swift:325`) — ek olarak `Claude Code-credentials-<hash>` varyantları var (custom config dir) ve aynı service altında MCP token'ları için ayrı item bulunuyor. |
| Endpoint 5 saatlik + haftalık pencere veriyor | `https://api.anthropic.com/api/oauth/usage` → `five_hour` + `seven_day`, her biri `utilization` (0-100) + `resets_at`. |
| Polling ≥ 5 dk | `[300, 900, 1800]`, 5 dk taban (`RefreshIntervalStore.swift:11`). Üstüne 429'da 900 sn cooldown. |
| Hata durumunda son iyi değeri koru | `AppUsage.merged` + kalıcı `UsageHistoryStore` seed'i. **Bir istisna:** terminal auth hatasında değer korunmuyor, yerine re-auth prompt'u geliyor. |
| Kimlik yoksa "auth gerekli — `claude` çalıştır", token'a asla yazma | Birebir: `"auth required — run claude"` (121) ve tip dokümanında yazma yasağının gerekçesi (10-16). |
| %80 eşiğinde popup bir kez | `CrossingKey(provider, threshold, resetAt)` + `warmedUp` guard'ı; varsayılan eşikler 80/95. |
| Endpoint belgesiz, kırılabilir | README:344-347 ve `CONTRIBUTING.md:14` bunu açıkça kabul ediyor. |

**Çelişkiler / planı güncellemesi gerekenler:**

1. **Kimlik sırası:** plan §6.1 "`$CLAUDE_CONFIG_DIR/.credentials.json` → Keychain" diyor; doğrusu **env → Keychain → dosya**. Dosya sadece Keychain erişilemezken (SSH, kilitli keychain, Linux) CLI'ın düştüğü yol.
2. **Keychain prompt riski planda yok.** `SecItemCopyMatching(kSecReturnData:)` ile okumak her token rotasyonundan sonra kullanıcıya şifre sordurur (partition list reset'i, `ClaudeCredentials.swift:387-400`). Çözüm: metadata-only keşif + `/usr/bin/security` ile secret okuma. Bu **plana eklenmeli** ve §8 "İzinler" bölümünde onboarding'de anlatılmalı.
3. **`User-Agent` spoof'u planda yok.** `claude-code/2.1.121` olmadan endpoint geçerli token'la bile 401 veriyor. Bu, "belgesiz endpoint" riskinin en kırılgan parçası — plan §13'e ayrı satır olarak girmeli.
4. **403 / eksik scope durumu planda yok.** Mid-2026'da `user:profile` scope'u eklendi; eski token'lar 403 alıyor ve **sadece yeni `claude /login`** düzeltiyor. §6.2'deki UI durumlarına "re-login gerekli" (expired'dan **ayrı**) durumu eklenmeli.
5. **"ccusage blok tahminine zarifçe düş" codex-island'da yok.** Usage ve cost tamamen ayrı store'lar; çapraz fallback bizim kendi yazacağımız katman. Tasarım kararı: fallback verisi UI'da **tahmin** olarak işaretlenmeli.
6. **"Claude çalışıyor" (≤5 sn tepki) codex-island'da yok.** Repoda `FSEvents`/`DispatchSource` **hiç kullanılmıyor**; her şey 5-30 dk'lık poll. §6.3'ün "≤5 sn içinde sayaç/animasyon tepki verir" kriteri tamamen bizim `ProjectsWatcher`'ımıza kalıyor — burada devşirilecek kod yok, sadece `jsonlFiles(modifiedAfter:)` mtime deseni.
7. **Dağıtım farkı:** codex-island **imzasız** (ad-hoc `codesign --force --deep --sign -`, `release.sh:40`), Sparkle ile kendi güncelleme doğrulamasını yapıyor ve Homebrew cask'ı `postflight`'ta `xattr -dr com.apple.quarantine` çalıştırıyor (`Casks/codexisland.rb`). Bizim plan §8 **Developer ID + notarization** diyor — bu daha doğru; cask'tan sadece iskeleti (livecheck, `zap trash`, `app` stanza) alalım, quarantine hack'ini **almayalım**.
8. **`swiftc` build** (`build.sh:60`) — SwiftPM/Xcode projesi yok, XCTest yok (`AlertEngine.swift:11-13` "bugün test target'ı yok" diyor; sonradan `Tests/` + `scripts/run-tests.sh` eklenmiş). Bizde XcodeGen + XCTest var; saf katmanları (`WakeScheduling`, `AlertDecision`, `NotchInfo.menuBarHeight`, `AppUsage.merged`) test etmek için hazır adaylar.

## 5. Bilinçli almayacaklarımız

1. **Codex/OpenAI tarafının tamamı:** `UsageFetcher.fetchCodex` + `fetchCodexResetCredits` (`Sources/Usage/UsageFetcher.swift:9-140`), `Sources/Cost/CodexLogReader.swift`, `Sources/Cost/OpenCodeLogReader.swift`, `Sources/Usage/CodexResetCredits.swift`, `Sources/Views/CodexResetStatus.swift`, `ProviderVisibilityStore`. Bizde tek sağlayıcı var.
2. **`spawnTokenRefreshPing()`** (`ClaudeCredentials.swift:547-576`) — MVP'de yok. Kullanıcı adına sessizce `claude -p` çalıştırmak (haiku ile bile) şeffaflık ve maliyet açısından bizim onboarding sözleşmemize aykırı. Faz 5'te "kapalı gelen ayar" olarak yeniden değerlendirilebilir.
3. **`in-process SecItem` secret okuma fallback'i** (a.g.e. 409-421) — prompt tetikleyen tek yol. Bizde `security` CLI başarısız olursa doğrudan "auth okunamadı" durumuna düşelim; kullanıcıya sürpriz keychain diyaloğu göstermeyelim.
4. **Sparkle + imzasız dağıtım + `xattr` quarantine hack'i** — plan §8'e aykırı (Developer ID + notarization).
5. **Uzaktan fiyat kataloğu** (`PricingCatalog`, GitHub Pages endpoint'i) — üçüncü taraf servise bağımlılık; gömülü tablo + app güncellemesi yeterli.
6. **String tabanlı hata sözleşmesi** (`"rate limited"` vb. sabit string'lerin UI ve store tarafında eşitlik kontrolüyle karar vermesi) — bizde `enum`. (Global kural: statik string/dizi yerine Enum.)
7. **Demo mode enjeksiyonları** (`UsageStore.refresh`'in ilk 50 satırı, `CostStore.loadDemoData`) — bizde bu işi `DebugPreview/` yapıyor; production kod yoluna sahte veri kaçağı sokmayalım.
8. **Cmd-click ile görselleştirme stili döndürme, çoklu chart stili (Ring/Bar/Stepped/Numeric/Spark), yıllık contribution grid, sayfa carousel'i (3 sayfa + swipe + Cmd+1/2/3)** — MVP kapsamı dışı. Yatay swipe deseni (`IslandHostingView.swift:59-120`) Faz 6'da modüller arası geçiş için akılda tutulabilir.
9. **`NSHapticFeedbackManager` hover tick'i** (`IslandRootView.swift:174-176`) — hoş bir detay ama hover her geçişte tetiklenirse rahatsız edici; Faz 5'te ayara bağlı düşünülür.

## 6. Açık sorular

1. **`User-Agent` sürümü:** `claude-code/2.1.121` sabiti ne kadar dayanıyor? Anthropic minimum sürüm zorlarsa? Sürümü `SettingsStore`'dan override edilebilir mi yapsak (kullanıcı kendi kurulu CLI sürümünü girer), yoksa kurulu `claude --version`'dan mı okusak (ek `Process` maliyeti)?
2. **Hangi yükseklik ölçümü?** `safeAreaInsets.top` (bizim mevcut `NotchGeometry`) vs. `visibleFrame` deltası (codex-island). "Scaled to avoid the notch" ve auto-hide menü bar senaryolarında gerçek makinede ölçüm yapmalıyız — Faz 1 görevi.
3. **Fallback etiketleme:** resmi endpoint erişilemezken ccusage blok tahminine düştüğümüzde ring'i nasıl işaretleyeceğiz (kesikli çizgi? soluk renk? "~" prefix?) — plan §6.2 "zarifçe düş" diyor ama görsel sözleşme tanımlı değil.
4. **Eşik popup'ı varsayılan açık mı?** codex-island varsayılan **kapalı** (mevcut kullanıcı sürprizi). Bizde yeni ürün → açık mı gelsin? Ve eşikler 80/95 mi, yoksa plan §6.2'deki tek %80 mi?
5. **Keychain okumasının ilk çalıştırmadaki davranışı:** `security find-generic-password` gerçekten hiç prompt vermiyor mu, yoksa app'in ilk kez keychain'e erişmesinde bir kerelik diyalog çıkıyor mu? Gerçek makinede doğrulanmalı (bu oturumda kullanıcının keychain'ine dokunmuyoruz).
6. **`CLAUDE_CONFIG_DIR` virgüllü liste** desteği: `ClaudeLogReader` (JSONL) virgülle ayrılmış çoklu dizini destekliyor ama `ClaudeCredentials` (`.credentials.json`) **desteklemiyor** (tek path). Bu codex-island'da bir tutarsızlık mı, yoksa CLI'ın gerçek davranışı mı? Bizim ayar override'ımızı hangi şekilde tasarlayacağımızı belirler.
7. **Sticky 429'a hiç düşmeden yaşayabilir miyiz?** 5 dk taban + wake grace + cooldown ile codex-island bile 429 görüyor (tüm bu makine onun için var). Kullanıcının aynı anda hem Claude Code hem bizim uygulamayı çalıştırdığı normal senaryoda pratik 429 sıklığı ne? Faz 4'te gerçek kullanımda ölçelim; gerekirse varsayılanı 15 dk'ya çekelim.
