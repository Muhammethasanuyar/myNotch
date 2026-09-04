# Harvest Notları — Referans Madenciliği (Faz 0.5)

Amaç: `references/` altındaki açık kaynak repolardan **davranış ve desen** öğrenmek; lisansı izin verenlerden ilgili fazda **adapte** etmek. Bu klasördeki notlar kod taşımaz. Taşıma Faz 1 / 4 / 6'da, `docs/PLAN.md` §2.2 kurallarıyla ve aşağıdaki prompt şablonuyla yapılır.

`references/` git'e girmez (`.gitignore`). Klonları yenilemek için `docs/PLAN.md` §2.3'teki klonlama döngüsünü yeniden çalıştır.

## Lisans denetimi (2026-09-02)

| Repo | Klon | Lisans (kanıt) | Devşirme modu | Faz | Not |
|---|---|---|---|---|---|
| `MrKai77/DynamicNotchKit` | `cd0b3e5` (2026-02-18) | MIT (`LICENSE`) | **Kod adapte et** | 1 | [DynamicNotchKit.md](DynamicNotchKit.md) |
| `ericjypark/codex-island` | `0931117` (2026-08-18) | MIT (`LICENSE`) | **Kod adapte et** | 1 (click-through), 4 | [codex-island.md](codex-island.md) |
| `ungive/mediaremote-adapter` | `3ac3d4b` (2026-05-11) | BSD-3-Clause (`LICENSE`) | **Bundle + adapte et** (feature flag) | 6 | [mediaremote-adapter.md](mediaremote-adapter.md) |
| `ryoppippi/ccusage` | `21c7f68` (2026-09-01) | MIT (kökteki `LICENSE`, `apps/ccusage/LICENSE`'a symlink; `apps/ccusage/package.json`) | **Araç olarak çağır**; hesap mantığı v2'de adapte | 4 | [ccusage.md](ccusage.md) |
| `TheBoredTeam/boring.notch` | `99900bf` (2026-08-29) | GPL-3.0 (`LICENSE`) | **Sadece davranış — kod kopyalama yok** | 1, 3, 5 (referans) | [boring.notch.md](boring.notch.md) |
| `spitfiresb/notch` | `eb8f26a` (2026-08-31) | LICENSE dosyası yok → tüm hakları saklı | **Sadece davranış — kod kopyalama yok** | 1, 6 (referans) | [spitfiresb-notch.md](spitfiresb-notch.md) |
| `farouqaldori/vibe-notch` | `10f1d24` (2026-04-20) | Apache-2.0 (`LICENSE.md`) | **Kod adapte et** (+ lisans/NOTICE yükümlülükleri) | Claude modülü v2 | [vibe-notch.md](vibe-notch.md) |
| `stevemcqueenz/claude-notch-tracker` | `77e0a09` (2026-08-18) | MIT (`LICENSE`) | **Kod adapte et** (alternatif yaklaşım) | 4 | [claude-notch-tracker.md](claude-notch-tracker.md) |
| `Lakr233/NotchDrop` | `e70b3d7` (2026-05-19) | MIT (`LICENSE`) | **Kod adapte et** | Backlog (6+) | [NotchDrop.md](NotchDrop.md) |
| `fayazara/macos-app-skills` | `a60365a` (2026-05-28) | LICENSE dosyası yok; README "MIT" diyor | **Skill olarak kuruldu**; referans Swift dosyaları davranış-only | 0.5, 1, 5 | [macos-app-skills.md](macos-app-skills.md) |

Plandaki tablodan sapmalar: vibe-notch (Apache-2.0), claude-notch-tracker (MIT) ve NotchDrop (MIT) kod adapte edilebilir sınıfına yükseldi; macos-app-skills LICENSE dosyası olmadığı için davranış-only kaldı; ccusage'ın kök `LICENSE` dosyası monorepo içindeki `apps/ccusage/LICENSE`'a symlink (ilk taramada `find -type f` bu yüzden kaçırdı).

## Kurallar (özet, bağlayıcı olan `docs/PLAN.md` §2.2)

1. **MIT / BSD / Apache-2.0** → adapte edilebilir. Adapte edilen her dosyanın başına `// Adapted from <repo> (<lisans>)`; lisans metni `THIRD_PARTY_LICENSES.md`'ye eklenir. Apache-2.0 için ek olarak varsa `NOTICE` içeriği korunur ve değiştirilen dosyalarda değişiklik yapıldığı belirtilir.
2. **GPL-3.0 (boring.notch)** ve **LICENSE dosyası olmayan repolar (spitfiresb/notch, macos-app-skills'in referans Swift dosyaları)** → tek satır kod alınmaz; yalnızca davranış, UX ve mimari incelenir. Notlarında kod bloğu yoktur.
3. `references/` altındaki hiçbir dosya proje ağacına doğrudan kopyalanmaz; her aktarım `NotchModule` / `Anim` / `NotchShape` / `NotchPanel` sözleşmelerine uyarlanarak **yeniden yazılır**.
4. Notlardaki kısa alıntılar (yalnızca izinli lisanslılarda, her biri ≤ 12 satır) kaynak yolu ve lisansla etiketlidir; bunlar da aynen kopyalanmaz, uyarlanır.

## Devşirme prompt şablonu

```text
references/<repo>/<dosya-veya-klasör> içindeki <desen>'i incele (not: docs/harvest/<repo>.md §3.x).
Lisansı <MIT/BSD/Apache-2.0> → bizim mimariye adapte et / <GPL veya lisanssız> → SADECE yaklaşımı özetle, kod kopyalama.
Hedef: <MyNotch içindeki dosya>. NotchModule / Anim / NotchShape / NotchPanel sözleşmelerine uy; Swift 6, varsayılan MainActor izolasyonu, macOS 14+.
Adapte edilen her dosyanın başına "// Adapted from <repo> (<lisans>)" ekle ve THIRD_PARTY_LICENSES.md'yi güncelle.
Bitince neyi aynen aldığını, neyi bilinçli değiştirdiğini 5 maddede özetle.
```

## Kurulan Claude Code skill'leri

`references/macos-app-skills/` içindeki altı skill `~/.claude/skills/` altına, frontmatter adlarıyla kopyalandı (kişisel kullanım, repoya girmez): `macos-patterns`, `macos-notch-ui`, `macos-settings-ui`, `macos-build`, `macos-auto-update`, `macos-release`. Her klasörde kaynak ve lisans durumunu belirten `SOURCE.txt` var. Yeniden kurmak için README'deki resmi yol: `npx skills add fayazara/macos-app-skills`.

Bu repoda `CLAUDE.md` ve `scripts/*.sh` skill'lerden önceliklidir (örn. build için `scripts/build.sh`).

## Notların yapısı

Her not aynı iskeleti izler: künye tablosu (repo, klon, lisans, mod, fazlar) → bizim için değeri → hedef dosyalar tablosu (kaynak `path:line` → bizde hedef dosya → faz) → desenler/davranışlar (nasıl çalışıyor · bize uyarlama · dikkat) → plan ile çelişkiler → bilinçli almayacaklarımız → açık sorular.

## Öne çıkan bulgular (notlardan derlenen, faz bazlı)

### Faz 1 — Notch motoru
- Pencere seviyesi `.screenSaver` DynamicNotchKit ile doğrulandı. DNK `collectionBehavior`'da `.fullScreenAuxiliary` kullanmıyor; tam ekran görünürlük için Faz 0'daki setimiz doğru. Skill'lerin önerdiği `CGShieldingWindowLevel()` kilit ekranı ve sistem uyarılarının da üstüne çıktığı için alınmaz.
- **`ignoresMouseEvents` hiç set edilmemeli** (claude-notch-tracker, `IslandWindow.swift`): set edilince pencere sunucusunun piksel-alfa geçirgenliği kapanır, menü bar panelin altında ölür. Hover: SwiftUI `.onHover` + `contentShape(NotchShape)`; `.mask` hit-test'i kırpmaz (DNK'de `padding(-50)` siyah arka plan 50 pt çevrede tıklama yutuyor). Faz 0'daki geçici `ignoresMouseEvents = true` Faz 1'de silinir.
- DNK pencereyi yarım ekran genişliğinde sabit tutar ve yalnızca içeriği anime eder → "panel her zaman expanded boyutunda" kuralımız doğrulandı; 600×240 ile compositing maliyeti daha düşük.
- NotchShape: içbükey "kulak" quad-curve + dışbükey alt köşeler, `animatableData: AnimatablePair`; radii compact 6/14 → expanded 15/20 (DNK). macos-app-skills'teki `NotchShape` referans dosyası DNK'nin MIT dosyasının atıfsız birebir kopyası → oradan değil DNK'den adapte et.
- Geçiş koreografisi: `blur(10) + scale + opacity` üçlüsü; hover'da gölge 0.5→0.8 / 10→20. DNK'nin compact↔expanded arasındaki ara "hidden" adımı ve `Task.sleep` tabanlı imperatif API'si alınmaz; durum makinesi + `Anim` ile doğrudan morph. Faz 1 prototipinde `matchedGeometryEffect` + animasyonlu maskeli `NotchShape` birlikte takılıyor mu ölç.
- `onGeometryChange` macOS 15+ → macOS 14 için `GeometryReader` + `PreferenceKey`. DNK'deki hiç iptal edilmeyen `NotificationCenter` `Task`'ı (retain cycle, gizliyken pencere yaratma) alınmaz.
- Notch'suz ekran: DNK ve plan üst-orta kapsül; skill alt-orta "pill" öneriyor → plan geçerli. DNK'nin 300 pt sabit fallback genişliği ve `NSScreen.screens[0]` varsayımı alınmaz.
- Plan boşlukları: Reduce Motion (`NSWorkspace.accessibilityDisplayShouldReduceMotion` → `Anim`), LSUIElement uygulamada Settings / Debug Preview için activation policy yönetimi, `SMAppService` üç durumlu (`.requiresApproval`) ele alma.
- `NotchGeometry` 2026-09-03'te genişlik tabanlı hesaba geçirildi (aux alanların koordinat uzayından bağımsız; test eklendi).

### Faz 3 — Medya (ve Faz 6 generic provider)
- mediaremote-adapter: `stream` diff protokolü `{type, diff, payload}` (diff olmayan yayın = parça değişti tetikleyicisi, `null` = anahtar silindi); zorunlu anahtarlar kodda `processIdentifier, title, playing` (README `bundleIdentifier` der ama eksik olabilir → kaynak ikonu için fallback zinciri). `test` komutu ayrı test-client binary'si ister ve kısa süre sahte now-playing yayınlar (diğer uygulamalar görür) → sadece sürüm değişiminde ve elle tetiklenir. Tek uzun ömürlü `stream` süreci, `--no-diff` asla (artwork base64 yüzlerce KB). `/usr/bin/perl` bağımlılığı (kullanımdan kalkan scripting runtime); framework (332 KB) ve test client (128 KB) ad-hoc imzalı → Developer ID ile yeniden imzala. ejbills fork'unun Swift package olduğu doğrulanamadı.
- Konum matematiği `elapsed + (now − timestamp) × playbackRate` Faz 3 AppleScript sağlayıcılarında da kullanılabilir.

### Faz 4 — Claude usage
- Kimlik sırası **env → Keychain → dosya** (plan §6.1 düzeltildi): Claude Code 2.x kimliği Keychain'de tutar, `.credentials.json` eski kalıntı olabilir. Keychain'i `/usr/bin/security find-generic-password -s … -a … -w` ile oku (ACL uyarısı vermez); `SecItemCopyMatching` uyarı verir ve Claude Code'un ~8 saatlik `-U` yeniden yazması "Always Allow" iznini sıfırlar. Token'ı asla loglama.
- Endpoint `GET https://api.anthropic.com/api/oauth/usage`, `anthropic-beta: oauth-2025-04-20`; codex-island `User-Agent: claude-code/<sürüm>` şart der, claude-notch-tracker göndermez → **2026-09-04: UA ile 200 alındı** (uygulama içinden, Keychain kimliğiyle); UA'sız varyant denenmedi, UA gönderilmeye devam. `utilization` her zaman 0–100 (/100), `seven_day` model bazlı (`seven_day_opus`, `seven_day_sonnet`) bölünebilir, `expiresAt` epoch **ms**. 429 hesap düzeyinde yapışkan (~900 sn), 403 = yeniden giriş gerekli (UI durumu olarak ekle).
- codex-island'da dosya izleme yok → "≤5 sn tepki" kriteri tamamen bizim. v2 native parser için en iyi kaynak claude-notch-tracker: `LogWatcher` (FSEvents 0.3 sn latency + 0.25 sn debounce), byte-offset artımlı parse + truncation reset, `BlockCalculator` (ccusage 5 saat algoritması, testli), `.jsonl` fixture düzeni.
- codex-island'dan: `AlertDecision` eşik geçişi `resetAt`'e anahtarlı + warmup guard (popup spam önleme), `AppUsage.merged` son iyi değer taşıma, `WakeScheduling` uyku/ağ disiplini, `LogParseCache` parçalı JSONL okuma. Sıfırdan: string hata sentinel'leri yerine enum, global mutable cache yerine actor.
- ccusage v20: Rust binary + Node launcher (`npx` soğuk başlangıçta platform paketi indirir → PATH'teki `ccusage` tercih, npx kullanılırsa sürüm sabitle). **Ölçüm 2026-09-04 (~300 MB log, nvm node 24):** `npx --yes ccusage@20 claude blocks --json --active --offline` 2,8 sn, `claude daily --json --since … --offline` 0,9 sn; JSON şekli `docs/harvest/ccusage.md` §3.3 ile birebir. Komutlar: `ccusage claude blocks --json --active --offline`, `ccusage claude daily --json --since … --offline`. `blocks` JSON: `tokenCounts{inputTokens,outputTokens,cacheCreationInputTokens,cacheReadInputTokens}`, `burnRate{tokensPerMinute,costPerHour}`, `projection{totalTokens,totalCost,remainingMinutes}`; blok kuralı: başlangıç saate yuvarlanır, başlangıçtan veya son kayıttan >5 sa geçince bölünür, `isActive = now−last < 5h && now < end`. Her çağrı tüm geçmişi okur → büyük geçmişte süre ölçülmeli; `--jq` kullanma (sistem `jq` çağırır); `--token-limit max` gerçek limit değil kendi en yüksek bloğun. `@ccusage/mcp` repoda yok; docs sitesindeki blocks şeması eski → koda göre parse et.
- vibe-notch (Claude modülü v2 fikri): Claude Code lifecycle hook'ları + Unix socket ile canlı oturum ve `PermissionRequest` onayı, sürüm kapılı hook seti, `SessionPhase` durum makinesi, dört kademeli `ClaudePaths` çözümü. Ama `~/.claude/settings.json`'a **yazar** → salt-okunur doktrinimiz için açık opt-in + yedek + tek tıkla geri alma şartı; min macOS 15.6; Mixpanel telemetri, `CGEvent` tıklama ve tmux `send-keys` ile onay simülasyonu reddedilir. Apache-2.0: NOTICE dosyası yok, adapte edilen dosyalarda kaynak + "değiştirildi" ifadesi gerekir.

### Backlog — Shelf (NotchDrop)
- `onDrop` + 32 pt şişirilmiş algılayıcı, `isTargeted` ile açılma; depo `<uuid>/<dosya>` + süre bazlı temizleme; AirDrop `NSSharingService(named: .sendViaAirDrop)` + `canPerform` kontrolü; `Transferable` ile geri sürükleme. Riskler: SwiftUI `onDrop` nonactivating panelde çalışmayabilir (deney; fallback AppKit `registerForDraggedTypes`), global event monitor + 1 sn timer boşta CPU hedefiyle çelişir, 8 SPM bağımlılığı alınmaz. Plan §9'a `Modules/Shelf/` eklenecek.

### Davranış-only repolardan (boring.notch GPL-3.0, spitfiresb/notch lisanssız) — yalnızca davranış, kod yok
- **`ignoresMouseEvents` üçüncü veri noktası:** boring.notch hiç set etmez ve `.onHover` kullanır (claude-notch-tracker ile aynı); spitfiresb/notch duruma göre toggle eder ve hover'ı global `mouseMoved` monitörü + geometri ile hesaplar. Faz 1'de set etmemeyi seçtik; gerçek notch'ta doğrulandı (şeffaf piksele yapılan tıklama alttaki menü bara geçiyor).
- **Sabit boyutlu pencere üçüncü kez doğrulandı:** boring.notch 640×210, spitfiresb 300×256; ikisi de içeriği anime eder. spitfiresb'den `sizingOptions = []` ve `constrainFrameRect` override dersi alındı (Faz 1'de uygulandı).
- **Tam ekran:** boring.notch `.fullScreenAuxiliary` + özel CGS space; spitfiresb `.fullScreenAuxiliary`'yi jest anındaki gizlenme yüzünden reddedip özel CGS overlay space kullanır. Biz özel API almıyoruz. **Faz 1'de doğrulandı (2026-09-03, macOS 26.6.2):** tam ekran bir uygulamanın üzerinde panel görünür kalıyor (`CGWindowListCopyWindowInfo` → `onscreen=true`, layer 1000); yalnızca 3 parmak Space geçişi sırasındaki kısa gizlenme kabul edilen kısıt.
- **Hover zamanlaması:** boring.notch 0,3 s açılış (0–1 s ayar) + 100 ms kapanış gecikmesi; spitfiresb 0 gecikme + "grace rect". Bizde 0,15 s açılış + 100 ms kapanış gecikmesi uygulandı; 2026-09-04'te grace-rect eklendi: bölge içinde ≤0,8 s tolerans, bölge dışına çıkınca anında kapanış (`NotchLayout.graceRect`; tolerans penceresinde 40 ms'lik `NSEvent.mouseLocation` kontrolü — spitfiresb'nin global mouseMoved monitörü yerine).
- **Morph dersleri (spitfiresb):** peek/sekme arası `if/else` (opacity değil), `.animation(_:value:)` doğrudan o grupta, eşlenen kapakta `.id/.transition/.aspectRatio` yok, açılış 0,32 s / kapanış 0,22 s asimetrik, ayrı yönlü gölge, köşe öğeleri `.offset` ile, `clipShape` ile kırpma.
- **Şekil parametreleri:** boring.notch radii kapalı 6/14 → açık 19/24 (+4 pt genişlik bleed, 1 pt üst siyah şerit); spitfiresb 8 pt içbükey kıvrım, kapalı ≤10 / açık 20 alt yarıçap. Bizim `NotchLayout` closed 0/10, compact 6/14, popup 8/16, expanded 15/20 ile başladı.
- **Compact live activity formülü (boring.notch):** çene genişliği = kapalı genişlik + 2×(kapalı yükseklik − 12) + 20; solda 20×20 kapak, sağda 4 çubuk. Popup süreleri: sneak peek 1,5 s, batarya 3 s; spitfiresb toast'ları 2,7 / 5,6 / 4,6 s → `NotchEvent.duration` varsayılanı 2,5 s.
- **Boşta CPU (spitfiresb):** ses tap'i yalnızca çalarken (2 s stop debounce), 30 Hz yayın + 0,004 eşiği, wiggle 30 fps kapağı, Now Playing poll 15 s / 60 s ve olay-güdümlü, vnode `DispatchSource` + 1 s emniyet poll'u, `NSAppleScript` derleme önbelleği (XProtect ~25 ms/derleme), konum ekstrapolasyonu `elapsed + Δt × rate` → plan §5.1'deki 1 s poll kaldırılacak.
- **Gerçek visualizer yolu (Faz 6):** `CATapDescription` + `AudioHardwareCreateProcessTap` (macOS 14.2+) + özel aggregate device; 6 RBJ bandpass (80–7000 Hz, Q 2,4), bant başına dB penceresi ve asimetrik zarf; yalnızca ses yakalama izni (Ekran Kaydı değil) → plan §5.2'deki ScreenCaptureKit yoluna tercih edilir.
- **Medya denetleyici yüzeyi (boring.notch):** protokol shuffle/repeat/volume/favorite yetenek bayrakları içerir; MediaRemoteAdapter `stream` süreci + JSON-lines borusu; başlangıçta `test` (paketli test client, 10 s zaman aşımı, çıkış 1 = deprecated) → Apple Music'e düş + onboarding adımı.
- **AppleScript thread çelişkisi:** boring.notch detached task'ta, spitfiresb ana thread'de (`NSAppleScript` thread-safe değil; TCC uyarısı ana thread ister). Bizde tek seri aktör + ilk izin tetiklemesi onboarding'de ana thread'de; Faz 3'te doğrulanacak.
- **Claude oturumları v2 (spitfiresb):** hook script → spool JSONL (soket değil; offline biriktirme + açılışta sessiz replay + 4 MB kesme), 15 olay, `timeout 5` + `async` ile Claude Code bloklanmaz; interrupt tespiti transcript kuyruğundan. `~/.claude/settings.json` yazımı açık opt-in + geri alma şartına bağlı.
- **Alınmayacaklar (her iki repo):** özel CGS/SkyLight space'ler, MultitouchSupport jest monitörü, özel MediaRemote dlopen, CoreBrightness, HID event tap ile HUD değiştirme, Erişilebilirlik zorunluluğu, sürekli `CGWindowList` poll'u, `nettop` çocuk süreci, SPM bağımlılıkları, sandbox + geçici istisnalar, quarantine bypass talimatıyla dağıtım.
- **Test fikri (spitfiresb):** `ImageRenderer` ile ekran dışı PNG render harness'i → ileride `NotchRenderTests` (her `NotchState` için PNG).
