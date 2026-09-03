> **Not (2026-09-02):** Bu belge `~/Downloads/macos-dynamic-notch-plani.md` dosyasının repo kopyasıdır. Uygulama adı **MyNotch** olarak kararlaştırıldı; metindeki "Ada" ifadelerini MyNotch olarak oku. Alınan kararlar sondaki §15'te.

# Dynamic Notch — macOS "Dinamik Ada" Uygulaması · Geliştirme Planı

> Hedef: MacBook notch'unu, iPhone'daki Dynamic Island gibi uygulamaya özgü, adaptif ve animasyonlu bir arayüze dönüştüren native macOS uygulaması. Claude Code ile faz faz geliştirilecek.
> Çalışma adı önerisi: **Ada** (Dynamic Island → Ada). İstersen değiştir.

---

## 1. Vizyon ve Ürün Tanımı

- Notch normalde "ölü" siyah bir alan; uygulama bu alanın üzerine şeffaf, her zaman üstte duran bir pencere çizerek notch'u canlı bir yüzeye çevirir.
- Üç temel deneyim:
  1. **Compact (canlı durum):** Notch'un sağına/soluna küçük canlı bilgiler eklenir (albüm kapağı + equalizer, Claude token sayacı vb.).
  2. **Expanded (etkileşim):** Fareyle üzerine gelince notch aşağı doğru "büyüyerek" modülün tam arayüzünü açar (müzik kontrolleri, usage dashboard).
  3. **Popup (olay bildirimi):** Parça değişti, şarj takıldı, Claude bloğu %80 doldu gibi olaylarda notch kısa süreliğine büyüyüp küçülür.
- Her entegrasyon bir **modül**: kendi compact/expanded/popup görünümü, kendi animasyon kimliği. MVP modülleri: **Medya (Spotify + Apple Music)** ve **Claude Code Usage**.

## 2. Açık Kaynak Ekosistemi ve Kod Devşirme (Harvesting) Stratejisi

Bu projede sıfırdan icat edilecek çok az şey var: notch motoru, medya erişimi ve Claude usage verisi için olgun açık kaynak örnekler mevcut. Strateji: **kendi motorumuzu ve modül sistemimizi biz yazıyoruz; izin veren lisanslı repolardan hedefli parçaları Claude Code'a adapte ettiriyoruz; kısıtlı lisanslılardan yalnızca davranış öğreniyoruz.**

### 2.1 Devşirme haritası — hangi repodan ne alınacak

| Repo | Lisans | Bizim için değeri | Devşirme modu |
|---|---|---|---|
| `MrKai77/DynamicNotchKit` | MIT | Notch penceresi + shape + expand mekaniği; notch'suz Mac'te floating fallback; `DynamicNotchInfo/Progress` desenleri | **Kod adapte et** (Faz 1) |
| `ericjypark/codex-island` | MIT | Claude Code için ALTIN MADENİ: salt-okunur kimlik çözümü (`CLAUDE_CODE_OAUTH_TOKEN` → `~/.claude/.credentials.json` → Keychain `Claude Code-credentials`), resmi usage endpoint'inden 5 saatlik + haftalık pencereler (`Sources/Usage/UsageFetcher.swift`), yerel JSONL maliyet okuyucuları (`Sources/Cost/`), silüet dışını tıklamaya kapatma (click-through), squircle köşeler, notch'suz ekran fallback'i, ≥5 dk polling disiplini | **Kod adapte et** (Faz 4 + Faz 1'de click-through) |
| `ungive/mediaremote-adapter` | BSD-3-Clause | Tüm uygulamalar için now-playing (perl + framework bundle); `test` komutu kırılmayı tespit edip AppleScript'e otomatik düşüş sağlar; bakımlı Swift package fork'u: `ejbills/mediaremote-adapter` | **Bundle + adapte et** (Faz 6) |
| `ryoppippi/ccusage` | MIT (kök `LICENSE` → `apps/ccusage/LICENSE` symlink) | JSONL → maliyet/blok hesabı; `--json` çıktısı (`@ccusage/mcp` 2026-09-03 itibarıyla repoda yok) | **Araç olarak çağır** (Faz 4), hesap mantığını v2'de adapte et |
| `TheBoredTeam/boring.notch` | GPL-3.0 (ana repodaki LICENSE; bazı eski README'lerde CC BY-NC-ND ifadesi var) | En olgun ürün: fullscreen davranışı, ayarlar yapısı, HUD replacement, MediaRemoteAdapter + NotchDrop'u nasıl bağladığı | **Sadece davranış incele — KOD KOPYALAMA YOK** |
| `spitfiresb/notch` | Lisans belirtilmemiş | Sıfırdan yazılmış tekil örnek: `matchedGeometryEffect` ile compact↔expanded morph, CoreAudio process tap → 6 bantlı gerçek ses-reaktif çubuklar, ~%0 boşta CPU hedefi, temiz `Services/` ayrımı | **Sadece davranış/mimari incele** |
| `farouqaldori/vibe-notch` (eski adı Claude Island) | Apache-2.0 (`LICENSE.md`) | Claude Code CLI oturumlarını notch'tan canlı izleme, araç izinlerini notch'tan onaylama, konuşma geçmişi — Claude modülümüzün gelecek sürümü için fikir kaynağı | **Kod adapte et** — Apache-2.0 yükümlülükleri: lisans metni + NOTICE korunur, değişiklikler belirtilir (Claude modülü v2) |
| `stevemcqueenz/claude-notch-tracker` | MIT | Claude usage'ı (5 saat / 7 gün / kredi) Keychain veya tarayıcı oturumundan okuyan alternatif yaklaşım | **Kod adapte et** (alternatif yaklaşım; codex-island ile karşılaştır, Faz 4) |
| `Lakr233/NotchDrop` | MIT | Notch'a sürükle-bırak dosya rafı + AirDrop (boring.notch'un Shelf'inin temeli) | **Kod adapte et** — Backlog (Faz 6+) |
| `fayazara/macos-app-skills` | LICENSE dosyası yok; README "MIT" diyor | Claude Code için hazır skill seti: macOS AppKit/SwiftUI desenleri (NSPanel, pencere seviyeleri, çoklu ekran) + `notch-ui` skill'i (CGShieldingWindowLevel'da borderless panel, içbükey "kulaklı" NotchShape Bezier'i) | **Skill olarak kuruldu** (Faz 0.5; `~/.claude/skills/macos-*`, kişisel kullanım) — referans Swift dosyaları davranış-only |
| NotchNook, Alcove, Seam (ticari, kapalı) | — | UX/animasyon kalite çıtası | Sadece gözlemle |

> **Lisans denetimi (2026-09-02):** `references/` klonları üzerinde yapıldı; kanıtlar ve klon sürümleri `docs/harvest/README.md`'de. Sapmalar: vibe-notch Apache-2.0, claude-notch-tracker MIT, NotchDrop MIT → kod adapte edilebilir; macos-app-skills LICENSE dosyasız → davranış-only; ccusage kök `LICENSE` dosyası `apps/ccusage/LICENSE`'a symlink.

### 2.2 Lisans kuralları (Claude Code için bağlayıcı)

1. **MIT / BSD / Apache** → kod adapte edilebilir. Her adapte edilen dosyanın başına `// Adapted from <repo> (<lisans>)` yorumu; repo köküne `THIRD_PARTY_LICENSES.md` açılır ve ilgili lisans metni eklenir.
2. **GPL-3.0 (boring.notch)** → tek satır bile kopyalanmaz; kopyalanırsa tüm projeyi GPL yapma yükümlülüğü doğar. Yalnızca davranış, UX ve yaklaşım incelenir; implementasyon sıfırdan yazılır.
3. **LICENSE dosyası olmayan repo** → "tüm hakları saklı" varsay: kod kopyalama yok, davranış incelemesi serbest.
4. `references/` altındaki hiçbir dosya `Ada/` kaynak ağacına doğrudan kopyalanmaz; her aktarım bizim sözleşmelere (`NotchModule`, `Anim`, `NotchShape`) uyarlanarak **yeniden yazılır**.

### 2.3 Faz 0.5 — Referans Madenciliği İş Akışı (ayrı bir Claude Code oturumu)

1. **Klonla (shallow):**
```bash
mkdir -p references && cd references
for r in MrKai77/DynamicNotchKit ericjypark/codex-island ungive/mediaremote-adapter \
         TheBoredTeam/boring.notch spitfiresb/notch farouqaldori/vibe-notch \
         stevemcqueenz/claude-notch-tracker Lakr233/NotchDrop ryoppippi/ccusage \
         fayazara/macos-app-skills; do
  git clone --depth 1 "https://github.com/$r.git"
done
```
`references/` klasörünü `.gitignore`'a ekle (repoya girmesin).
2. **Lisans denetimi:** Claude Code her klonun LICENSE dosyasını okur, §2.1 tablosundaki "devşirme modu"nu doğrular; fark varsa tabloyu ve bu dokümanı günceller. Belirsiz olanlar davranış-only'ye düşer.
3. **Skill kurulumu:** `macos-app-skills` içindeki macOS ve `notch-ui` skill'lerini Claude Code'a ekle (§12/6).
4. **Desen çıkarımı:** her repo için `docs/harvest/<repo>.md` notu yaz — hedef dosyalar, deseni bizim mimaride nereye oturtacağımız, dikkat edilecek farklar. Bu fazda **kod taşınmaz**; taşıma ilgili fazda (1, 4, 6) yapılır.
5. **Prompt şablonu** (her devşirme isteğinde kullan):
```text
references/<repo>/<dosya-veya-klasör> içindeki <desen>'i incele.
Lisansı <MIT/BSD> → bizim mimariye adapte et / <GPL veya lisanssız> → SADECE yaklaşımı özetle, kod kopyalama.
Hedef: <Ada içindeki dosya>. NotchModule / Anim / NotchShape sözleşmelerine uy.
Adapte edilen her dosyanın başına "// Adapted from <repo> (<lisans>)" ekle ve THIRD_PARTY_LICENSES.md'yi güncelle.
Bitince neyi aynen aldığını, neyi bilinçli değiştirdiğini 5 maddede özetle.
```

**Karar (güncel):** Kendi motor + hedefli devşirme. Pencere/shape/hover mekaniği DynamicNotchKit'ten (MIT), click-through ve Claude usage veri katmanı codex-island'dan (MIT) adapte edilir; boring.notch yalnızca davranış referansıdır.

## 3. Teknik Kararlar

| Konu | Karar | Not |
|---|---|---|
| Dil / UI | Swift + SwiftUI (pencere yönetimi AppKit) | Animasyonlar SwiftUI spring + `matchedGeometryEffect` |
| Min. macOS | 14 (Sonoma) | SMAppService, ScreenCaptureKit audio, modern SwiftUI için yeterli; en güncel sürümde test et |
| Proje tipi | Menü bar uygulaması (`LSUIElement = YES`) | Dock'ta görünmez, menü barda ikon + ayarlar |
| Sandbox | **Kapalı** | AppleScript otomasyonu ve dosya izleme için gerekli → App Store hedefleme, Developer ID + notarization ile dağıt |
| Mimari desen | MVVM + modül (plugin) protokolü | Her modül bağımsız test edilebilir |
| Bağımlılık | Mümkün olduğunca sıfır SPM bağımlılığı | Sadece gerekirse ekle |

## 4. Mimari Genel Bakış

```
┌─────────────────────────────────────────────────────┐
│ AppDelegate (menü bar, yaşam döngüsü)               │
│  └─ NotchWindowController (AppKit)                  │
│      └─ NSPanel (şeffaf, her zaman üstte)           │
│          └─ NotchRootView (SwiftUI)                 │
│              ├─ NotchShape (morfolojik şekil)       │
│              └─ ModuleManager.activeModule'ün view'ı│
│                                                     │
│ ModuleManager ── öncelik/aktivite çözümü            │
│  ├─ MediaModule (Spotify/Music sağlayıcıları)       │
│  ├─ ClaudeUsageModule (JSONL izleme / ccusage)      │
│  └─ (ileride) Battery, Shelf, HUD, Calendar...      │
│                                                     │
│ EventBus (Combine) ── popup olayları                │
│ SettingsStore (UserDefaults + @AppStorage)          │
└─────────────────────────────────────────────────────┘
```

### 4.1 Notch Penceresi (AppKit katmanı)

- `NSPanel`, `borderless + nonactivatingPanel`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow` sadece expanded'da.
- `level = .screenSaver` (menü barın üstünde kalsın), `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` → **tam ekran uygulamalarda da görünür.** *Doğrulandı 2026-09-03 (macOS 26.6.2, 16" M4 Pro):* TextEdit tam ekrandayken panel `CGWindowListCopyWindowInfo`'da `onscreen=true`, layer 1000 ve ekran görüntüsünde tam ekran uygulamanın üzerinde görünüyor — özel CGS/SkyLight API'sine gerek yok.
- Konumlama: notch'lu ekranın üst-ortası. Pencere her zaman "expanded" boyutunda dursun; içerik SwiftUI ile küçülüp büyüsün (pencere resize animasyonu titrek olur, içerik animasyonu akıcıdır).
- **Notch tespiti (runtime, hardcode yok):**

```swift
extension NSScreen {
    var hasNotch: Bool { safeAreaInsets.top > 0 }
    var notchFrame: CGRect? {
        guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        let width = frame.width - left.width - right.width
        return CGRect(x: left.maxX, y: frame.maxY - safeAreaInsets.top,
                      width: width, height: safeAreaInsets.top)
    }
}
```

- Notch'suz Mac / harici ekran: üst-ortada yüzen "hap" (floating capsule) moduna düş — aynı modüller, farklı closed şekli.
- Hover: `NSTrackingArea` (mouseEntered/Exited) → küçük gecikmeyle (ayarlanabilir, ~0.15 sn) expand; dışarı tıklama / ESC → collapse. *Güncelleme 2026-09-03 (bkz. `docs/harvest/claude-notch-tracker.md`, `DynamicNotchKit.md`):* panelde `ignoresMouseEvents` hiç set edilmemeli (true da false da); set edilince pencere sunucusunun piksel-alfa tabanlı tıklama geçirgenliği kapanır ve menü bar panelin altında ölür. Tıklama geçirgenliği çizilen şeklin alfa'sına bırakılır, hover SwiftUI `.onHover` + `contentShape(NotchShape)` ile şekle sadık alınır (`.mask` hit-test'i kırpmaz). Faz 0'daki geçici `ignoresMouseEvents = true` Faz 1'de silinir. DynamicNotchKit hover için gecikme kullanmaz; ~0.15 sn bizim kararımız. `onGeometryChange` macOS 15+ olduğundan macOS 14 için `GeometryReader` + `PreferenceKey`.
- Çoklu ekran: varsayılan dahili ekran; ayarlardan "tüm ekranlarda göster" opsiyonu (her ekrana bir panel).

### 4.2 Durum Makinesi

```swift
enum NotchState: Equatable {
    case closed                       // fiziksel notch ile birebir, görünmez
    case compact                      // notch + iki yanda canlı bilgi şeridi
    case expanded(moduleID: String)   // tam modül arayüzü
    case popup(event: NotchEvent)     // 2–4 sn'lik geçici büyüme
}
```

- Geçiş kuralları: `popup` her durumda araya girebilir, bitince önceki duruma döner. `expanded` iken gelen popup, expanded içinde banner olarak gösterilir (üst üste büyüme olmasın).
- Tüm geçişler tek bir `NotchViewModel` üzerinden (`@Published var state`).

### 4.3 Modül (Plugin) Sistemi — projenin kalbi

```swift
protocol NotchModule: AnyObject, Identifiable {
    var id: String { get }
    var displayName: String { get }
    var priority: Int { get }                 // çakışmada yüksek olan notch'u kazanır
    var isEnabled: Bool { get set }           // ayarlardan aç/kapa
    var activity: AnyPublisher<ModuleActivity, Never> { get }

    func compactLeading() -> AnyView          // notch'un SOLU (ör. albüm kapağı)
    func compactTrailing() -> AnyView         // notch'un SAĞI (ör. equalizer)
    func expandedView() -> AnyView
    func popupView(for event: NotchEvent) -> AnyView?
}

enum ModuleActivity { case idle, live, urgent }   // live: compact'ta görün; urgent: popup tetikle
```

- `ModuleManager`: kayıtlı modülleri tutar, `activity` yayınlarını birleştirir, **öncelik çözümü** yapar: `urgent > live(priority) > idle`. Örn. müzik çalarken medya modülü compact'ı alır; Claude bloğu %90'a gelirse popup ile araya girer.
- Yeni modül eklemek = tek dosyada protokolü implemente edip `ModuleManager.register()` çağırmak. "Her uygulamanın kendine özgü arayüzü" hedefini bu protokol karşılar.

### 4.4 Animasyon Sistemi

- **Morfoloji:** Tek bir `NotchShape` (parametrik `Shape`): `bottomCornerRadius`, `topOuterCurve` (expanded'da dış kenarlarda içbükey "kulak" kıvrımı), genişlik/yükseklik. Closed→compact→expanded arasında shape parametreleri anime edilir → iPhone'daki gibi "akışkan büyüme".
- **Spring standardı:** tek yerde tanımla, her yerde kullan:

```swift
enum Anim {
    static let morph  = Animation.spring(response: 0.42, dampingFraction: 0.72)
    static let popIn  = Animation.spring(response: 0.30, dampingFraction: 0.60)  // hafif overshoot
    static let subtle = Animation.easeInOut(duration: 0.18)
}
```

- Compact→expanded geçişinde albüm kapağı gibi ortak öğeler için `matchedGeometryEffect`.
- Sürekli animasyonlar (equalizer, pulsing) için `TimelineView(.animation)` — ama **görünürken çalışsın**, closed durumda timer'ları durdur (CPU hedefi: boşta < %1, animasyonda < %5; boring.notch'un CPU şikâyetlerinden ders al).
- Popup koreografisi: `scaleEffect(0.9→1)` + genişlik büyümesi + içerik `opacity/blur` geçişi; kapanışta ters.

## 5. Modül 1 — Medya / Spotify

### 5.1 Veri kaynağı stratejisi (önemli kısıt!)

macOS 15.4'ten itibaren Apple, `MediaRemote` framework'ünü (sistem geneli "now playing" verisi) entitlement'sız uygulamalara **kapattı**. Bu yüzden:

| Sağlayıcı | Yöntem | Kapsam | Risk |
|---|---|---|---|
| `SpotifyProvider` (MVP) | AppleScript + `DistributedNotificationCenter` (`com.spotify.client.PlaybackStateChanged`) | Spotify | Düşük — resmi scripting arayüzü |
| `AppleMusicProvider` (MVP) | AppleScript (`Music.app`) + `com.apple.Music.playerInfo` bildirimi | Apple Music | Düşük |
| `GenericNowPlayingProvider` (Faz 6) | `mediaremote-adapter` (BSD-3; perl script + framework bundle; Swift package fork'u: `ejbills/mediaremote-adapter`) | Safari/YouTube/Chrome dahil her şey | Orta — private API; ama `test` komutu kırılmayı tespit eder → otomatik AppleScript'e düşüş kurgula |

- Mimari: `MediaController` tek arayüz sunar; sağlayıcılar `MediaProvider` protokolünü implemente eder. Aktif sağlayıcı = son event gönderen.
- Spotify AppleScript örnekleri (Claude Code'a not):

```applescript
tell application "Spotify"
    player state                     -- playing / paused / stopped
    name of current track
    artist of current track
    artwork url of current track     -- URL'den indir, cache'le
    player position                  -- saniye
    duration of current track        -- DİKKAT: milisaniye!
    playpause / next track / previous track
    set player position to 42
end tell
```

- Bildirim geldiğinde AppleScript ile tam durumu çek (bildirim payload'ına güvenme); çalarken 1 sn'de bir sadece `player position` polle (progress bar için).
- `NSAppleEventsUsageDescription` Info.plist'e eklenecek; ilk kontrolde macOS otomasyon izni soracak — onboarding'de kullanıcıya anlat.

### 5.2 UI durumları

- **Compact:** solda 20×20 yuvarlatılmış albüm kapağı, sağda 4–5 çubuklu equalizer animasyonu (çalarken dalgalanır, pause'da düz çizgiye iner).
- **Expanded:** büyük artwork (köşe 12), başlık/sanatçı, sürüklenebilir progress bar (seek), önceki/oynat-duraklat/sonraki, ses kaydırıcısı, kaynak ikonu (Spotify/Music). Arka plan: artwork'ten çıkarılan baskın renkle (basit `CIAreaAverage`) hafif tint + `ultraThinMaterial`.
- **Popup (parça değişimi):** notch genişler, eski artwork sola kayıp küçülürken yeni artwork + parça adı sağdan gelir; 2.5 sn sonra compact'a küçülür. (İstediğin "büyüme–küçülme" animasyonu burası.)
- **Şarkı sözleri (2026-09-03 eklendi):** expanded'da başlık ile progress bar arasındaki boşlukta senkron sözler akar — aktif satır kapak vurgu renginde, sonraki satır soluk, `.easeOut(0.32)` ile yukarı kayar; yalnızca expanded'dayken ve çalarken 4 Hz'de günceller. Kaynak **LRCLIB** (`lrclib.net`, ücretsiz, anahtarsız): önce `/api/get` (tam eşleşme), senkron söz yoksa `/api/search`, o da olmazsa sadeleştirilmiş başlıkla ikinci arama; sonuç parça başına önbelleklenir (bulunamayanlar dahil). **Gizlilik:** sanatçı/parça/albüm/süre lrclib.net'e gider; `lyricsEnabled` bayrağıyla kapatılabilir, Faz 5'te Ayarlar'a anahtar olarak çıkacak.
- **Visualizer kararı:** MVP'de "sahte ama şık" — çalma durumuna bağlı animasyonlu çubuklar (gerçek FFT değil). Faz 6'da opsiyonel gerçek visualizer: ScreenCaptureKit sistem sesi yakalama (Ekran Kaydı izni ister!) + `Accelerate/vDSP` FFT, 8–16 bant. Varsayılan kapalı; izin maliyeti yüzünden ayardan açılır.

### 5.3 Kabul kriterleri (Faz 3 çıkışı)

- [ ] Spotify'da parça değişince ≤1 sn içinde compact güncellenir, popup animasyonu oynar.
- [ ] Expanded'dan play/pause/next/prev ve seek çalışır.
- [ ] Spotify kapalıyken modül `idle`'a düşer, notch closed görünür.
- [ ] Apple Music ile aynı senaryolar geçer.
- [ ] Tam ekran bir uygulamada (ör. video) kontroller çalışmaya devam eder.

## 6. Modül 2 — Claude Code Usage

### 6.1 Veri kaynağı

Claude Code her oturumu yerel JSONL olarak yazar: `~/.claude/projects/<proje>/<session>.jsonl` (kullanıcı `CLAUDE_CONFIG_DIR` değiştirmiş olabilir — ayarlardan path override sun). Topluluk aracı **ccusage** bu dosyalardan günlük/oturum/5 saatlik blok raporu üretir.

Üç veri yolu (harmanlanacak):

- **Resmi limitler (Faz 4'ün ana yolu — codex-island'dan MIT adapte):** Claude Code'un yerelde bıraktığı kimliği **salt-okunur** çöz (`CLAUDE_CODE_OAUTH_TOKEN` → `$CLAUDE_CONFIG_DIR/.credentials.json`, normalde `~/.claude/.credentials.json` → Keychain'deki `Claude Code-credentials` öğesi) ve Anthropic'in kendi usage endpoint'inden 5 saatlik + haftalık pencerelerin **resmi doluluk yüzdesini ve sıfırlanma zamanını** çek. Bu bilgi JSONL'den türetilemez. Dikkat: endpoint belgesiz (kırılabilir) ve agresif rate-limit'li → polling ≥5 dk; hata durumunda son iyi değeri koru. Kaynak: `codex-island/Sources/Usage/UsageFetcher.swift`. *Güncelleme 2026-09-03 (bkz. `docs/harvest/codex-island.md`, `claude-notch-tracker.md`):* Claude Code 2.x kimliği **önce Keychain'de** tutar, `.credentials.json` eski kalıntı olabilir → sıra `CLAUDE_CODE_OAUTH_TOKEN` → Keychain (`Claude Code-credentials` ve `-<hash>` varyantları; ACL uyarısı vermeyen tek yol `/usr/bin/security find-generic-password -s … -a … -w`) → dosya. Token `claudeAiOauth.accessToken`, `expiresAt` epoch **milisaniye**. Endpoint `GET https://api.anthropic.com/api/oauth/usage`, `Authorization: Bearer`, `anthropic-beta: oauth-2025-04-20`; codex-island `User-Agent: claude-code/<sürüm>` olmadan 401 aldığını söylüyor, claude-notch-tracker UA göndermiyor → Faz 4'te `curl` ile doğrula. Yanıt `five_hour` / `seven_day` `{utilization: 0–100, resets_at}`; `seven_day` model bazlı (`seven_day_opus`, `seven_day_sonnet`) bölünebilir. 429 hesap düzeyinde yapışkan (~900 sn) → ≥5 dk polling şart; token'ı asla loglama; refresh endpoint'ine ve Keychain'e asla yazma.
- **Maliyet/token (MVP'de araç, hızlı):** `Process` ile `npx ccusage@latest blocks --json` ve `daily --json` çağır (30–60 sn'de bir + dosya değişiminde). *Güncelleme 2026-09-03 (bkz. `docs/harvest/ccusage.md`):* ccusage v20 Rust binary + Node launcher; `daily` çoklu-ajan birleşik rapor oldu → Claude için `ccusage claude daily --json`; `blocks` Claude'a özel kaldı; ağ erişimini kapatmak için `--offline`; `CLAUDE_CONFIG_DIR` virgülle ayrılmış çoklu yol kabul eder, ayarlıysa varsayılan dizinler taranmaz. Maliyet hesabını sıfırdan yazma — battle-tested. (codex-island'ın `Sources/Cost/` okuyucuları da MIT alternatif.)
- **v2 (Faz 6):** Node bağımlılığını kaldırmak için native Swift JSONL parser: `DispatchSource`/FSEvents ile `projects/` klasörünü izle, dosyaları offset'ten itibaren artımlı oku, `usage` alanlarını (input/output/cache token, model) topla; fiyat tablosunu bundle'la.
- **"Claude çalışıyor" tespiti:** son ~10 sn içinde herhangi bir `.jsonl` değiştiyse → `activity = .live` + notch'ta nabız gibi atan turuncu ✳ animasyonu (Claude'un "düşünüyor" hissi).

### 6.2 UI durumları

- **Compact:** solda ✳ ikonu (aktif oturumda pulsing, boşta soluk), sağda bugünkü maliyet mini etiketi (ör. `$4.20`) veya aktif oturumda akan token sayacı.
- **Expanded (mini dashboard):**
  - 5 saatlik ve haftalık pencereler için **progress ring** (resmi endpoint verisi; erişilemezse ccusage blok tahminine zarifçe düş),
  - bugün: toplam maliyet, input/output token,
  - model kırılımı (Opus/Sonnet payı, yatay mini bar),
  - burn rate ($/saat) ve "bu hızla blok şu saatte dolar" tahmini,
  - son aktif proje adı.
- **Popup:** blok %80'e ulaştı ("yavaşla ⛽"), blok sıfırlandı, oturum bitti (oturum özeti: süre + maliyet). Eşikler ayarlanabilir.

### 6.3 Kabul kriterleri (Faz 4 çıkışı)

- [ ] Claude Code'da mesaj atınca ≤5 sn içinde notch'taki sayaç/animasyon tepki verir.
- [ ] Expanded'daki bugün-maliyeti, `npx ccusage daily` çıktısıyla tutarlıdır.
- [ ] Progress ring'deki 5 saatlik doluluk, Claude Code içindeki `/usage` görünümüyle tutarlıdır.
- [ ] Kimlik bulunamadığında modül "auth gerekli — `claude` çalıştır" durumunu gösterir, token'a asla yazmaz.
- [ ] %80 blok eşiğinde popup bir kez tetiklenir (spam yok).
- [ ] ccusage/Node yoksa modül zarifçe "kurulum gerekli" durumuna düşer, uygulama çökmez.

## 7. Backlog Modüller (MVP sonrası fikir havuzu)

Şarj/pil popup'ı · AirPods bağlantı animasyonu · ses/parlaklık HUD replacement · dosya rafı (notch'a sürükle-bırak → AirDrop) · takvim "sıradaki toplantı" · indirme ilerlemesi · Pomodoro · Xcode/CI build durumu. Hepsi aynı `NotchModule` protokolüyle eklenir — mimariyi değiştirmez.

## 8. İzinler, Dağıtım, Güvenlik

- **Automation (Apple Events):** Spotify/Music kontrolü için; ilk kullanımda sistem diyaloğu.
- **Ekran Kaydı:** sadece gerçek visualizer açılırsa (Faz 6).
- **Dosya erişimi:** `~/.claude` — sandbox kapalı olduğundan doğrudan; yine de onboarding'de şeffaf anlat.
- Dağıtım: Developer ID imza + notarization → dmg/Homebrew cask. App Store hedefleme (otomasyon + private API nedeniyle uygun değil).
- Launch at login: `SMAppService.mainApp.register()`.

## 9. Proje Yapısı

```
Ada/
├── CLAUDE.md
├── Ada.xcodeproj
├── App/            AdaApp.swift, AppDelegate.swift, MenuBar.swift
├── Core/
│   ├── Window/     NotchPanel.swift, NotchWindowController.swift, NotchShape.swift, ScreenObserver.swift
│   ├── State/      NotchViewModel.swift, NotchState.swift, Anim.swift
│   └── Modules/    NotchModule.swift, ModuleManager.swift, NotchEvent.swift, EventBus.swift
├── Modules/
│   ├── Media/      MediaController.swift, MediaProvider.swift, SpotifyProvider.swift,
│   │               AppleMusicProvider.swift, ArtworkCache.swift, Views/ (Compact, Expanded, TrackPopup, EqualizerBars)
│   └── ClaudeUsage/ UsageService.swift, CCUsageRunner.swift, ProjectsWatcher.swift, Views/ (Compact, Dashboard, BlockRing)
├── Settings/       SettingsView.swift, SettingsStore.swift, Onboarding.swift
├── DebugPreview/   PreviewWindow.swift   ← geliştirme hızlandırıcı (aşağıda)
└── Resources/
```

## 10. Yol Haritası — Her Faz ≈ Bir Claude Code Oturumu

| Faz | Kapsam | "Bitti" tanımı |
|---|---|---|
| **0 — İskelet** | Xcode projesi, menü bar app (LSUIElement), CLAUDE.md, boş NotchPanel notch üstünde konumlanır, DebugPreview penceresi | Uygulama açılır, menü bar ikonundan Quit/Settings/Debug Preview |
| **0.5 — Referans madenciliği** | §2.3 iş akışı: repoları `references/` altına klonla (gitignore'lu), lisans denetimi, skill kurulumu, her repo için `docs/harvest/` notu | Devşirme haritası doğrulandı; kod taşınmadı, notlar hazır |
| **1 — Notch motoru** | NotchShape, closed/compact/expanded state machine, hover ile aç/kapa animasyonu, tam ekran + çoklu ekran davranışı, notch'suz Mac fallback | Sahte içerikle akışkan morph animasyonu; fullscreen'de görünür |
| **2 — Modül sistemi** | NotchModule protokolü, ModuleManager, öncelik çözümü, EventBus, DemoModule ile popup akışı | Demo modül compact/expanded/popup üçlüsünü gösterir |
| **3 — Medya modülü** | SpotifyProvider + AppleMusicProvider, compact (kapak+equalizer), expanded kontroller, parça değişim popup'ı, artwork rengi | §5.3 kabul kriterleri |
| **4 — Claude Usage** | UsageFetcher (codex-island'dan adapte: kimlik çözümü + resmi 5h/7g pencereleri), CCUsageRunner (json, maliyet), ProjectsWatcher, compact sayaç + pulsing, dashboard, eşik popup'ları | §6.3 kabul kriterleri |
| **5 — Ayarlar & cila** | Settings penceresi (modül aç/kapa, hover gecikmesi, eşikler, ekran seçimi), launch at login, onboarding izin akışı, CPU/enerji ölçümü | Instruments'ta boşta <%1 CPU; temiz Mac'te kurulum akışı sorunsuz |
| **6 — Gelişmiş** | Gerçek visualizer (CoreAudio process tap — spitfiresb/notch'un yaklaşımı — veya ScreenCaptureKit + vDSP, opsiyonel), mediaremote-adapter generic provider (`test` komutlu AppleScript fallback ile), native JSONL parser, ilk backlog modülü | Ayarlardan açılabilir, kapalıyken sıfır maliyet |

## 11. CLAUDE.md Başlangıç İçeriği (repoya koy)

```markdown
# Ada — macOS Dynamic Notch App

## Build & Run
- Build: `xcodebuild -project Ada.xcodeproj -scheme Ada -configuration Debug build`
- Her değişiklikten sonra build al; derleme hatası bırakma.
- UI değişikliklerini önce DebugPreview penceresinde doğrula (aşağıda).

## Mimari kurallar
- UI = SwiftUI, pencere yönetimi = AppKit (NotchPanel). Bu sınırı koru.
- Yeni özellik = yeni NotchModule; Core/ dosyalarına modül-özel kod sızdırma.
- Animasyon parametreleri yalnızca Core/State/Anim.swift içinde tanımlanır.
- Private API yok (mediaremote-adapter hariç — sadece Modules/Media/Generic altında, feature flag arkasında).
- references/ altından Ada/ içine dosya KOPYALAMA. MIT/BSD kaynaklardan adapte et,
  başına "// Adapted from <repo> (<lisans>)" ekle, THIRD_PARTY_LICENSES.md'yi güncelle.
  boring.notch (GPL) ve lisanssız repolardan kod alma — sadece davranış incele.
- Ana thread'de AppleScript/Process çalıştırma; hepsi async.

## Debug Preview
- Menü bar → "Debug Preview": notch içeriğini normal, yeniden boyutlanabilir bir pencerede render eder.
- State override butonları (closed/compact/expanded/popup) ve sahte medya/usage verisi içerir.
- Gerçek notch'a deploy etmeden animasyon iterasyonu burada yapılır.

## Test
- Mantık katmanları (ModuleManager önceliği, UsageParser, MediaController) için XCTest yaz.
- UI değişikliğinde: DebugPreview screenshot'ı + gerçek notch'ta manuel senaryo listesi.
```

## 12. Claude Code Çalışma Taktikleri

1. **DebugPreview'u Faz 0'da yap.** Notch penceresi ekran görüntüsü almaya ve hızlı iterasyona uygun değil; normal pencerede render eden bir preview, Claude Code'la görsel iterasyon döngünü 10 kata kadar hızlandırır (screenshot verip "çubukları yumuşat" diyebilirsin).
2. Her fazı ayrı branch/PR gibi ele al; faz sonunda kabul kriterlerini Claude Code'a checklist olarak koştur.
3. Referans repo davranışını sorarken repo URL'sini ver ("boring.notch'un fullscreen davranışına bak, bizde X farklı olsun").
4. AppleScript ve ccusage entegrasyonlarını önce terminalde tek satırlık deneylerle doğrulat (`osascript -e '...'`, `npx ccusage blocks --json`), sonra Swift'e taşıt.
5. Animasyon ince ayarı için Debug Preview'a "Anim playground" slider'ları ekletmek (response/damping canlı ayarı) çok işe yarar.
6. **Skill kur (Faz 0.5'te):** `fayazara/macos-app-skills` reposundaki macOS ve `notch-ui` skill'lerini Claude Code'a ekle — NSPanel, pencere seviyeleri, çoklu ekran geometrisi ve notch shape gibi konularda Claude'un web alışkanlıklarına kaymasını engeller.
7. **Devşirme disiplini:** referans koddan her aktarım isteğinde §2.3'teki prompt şablonunu kullan ve lisans modunu (adapte / davranış-only) açıkça belirt; PR/commit mesajında kaynağı an.

## 13. Riskler ve Önlemler

| Risk | Etki | Önlem |
|---|---|---|
| macOS güncellemesi MediaRemote workaround'unu kırar | Generic provider ölür | MVP'yi AppleScript'e kur (resmi arayüz); adapter'ı feature flag arkasında tut |
| Spotify AppleScript izni reddedilir | Medya modülü çalışmaz | Onboarding'de izin akışı + "System Settings > Privacy > Automation" yönlendirmesi |
| Sürekli animasyon CPU/pil yakar | Kötü itibar (boring.notch şikâyetleri) | Closed'da tüm timer'ları durdur; TimelineView'ı görünürlüğe bağla; Faz 5'te Instruments ölçümü |
| ccusage/Node kullanıcıda yok | Usage modülü boş | Zarif düşüş + kurulum yönergesi; v2'de native parser |
| Resmi usage endpoint'i belgesiz — değişebilir veya rate-limit'e takılır | Ring verisi kaybolur | ≥5 dk polling, hata anında son iyi değeri koru, ccusage blok tahminine düş (codex-island deseni) |
| GPL veya lisanssız koddan yanlışlıkla kopya | Lisans ihlali ya da tüm projenin GPL'e dönüşmesi | `references/` gitignore'da; adapte dosyalarda kaynak yorumu zorunlu; PR'da provenance kontrolü; §2.2 kuralları CLAUDE.md'ye de eklenecek |
| Notch ölçüleri modele göre değişir | Yanlış hizalama | Ölçüleri her zaman `safeAreaInsets`/`auxiliaryTop*Area`dan hesapla, sabit değer yok |
| Claude Code log formatı değişebilir | Parser kırılır | MVP'de ccusage'a yaslan (topluluk hızlı günceller); parser'ı toleranslı yaz |

## 14. Başlamadan Netleştirilecek Küçük Kararlar

- Uygulama adı: **Ada** mı, başka bir şey mi? (Bundle ID: `com.emre.ada` gibi)
- Min. macOS 14 mü 15 mi? (Kendi makinen + hedef kitle; 14 daha kapsayıcı)
- MVP'de Apple Music dahil mi, sadece Spotify mı? (Öneri: ikisi de — maliyeti düşük, aynı desen)
- Visualizer MVP'de sahte-animasyon olarak yeterli mi? (Öneri: evet)

---

## 15. Kararlar (2026-09-02, Faz 0)

| Karar | Değer |
|---|---|
| Uygulama adı | **MyNotch** (dokümandaki "Ada" → MyNotch) |
| Bundle ID | `com.emre.mynotch` (`project.yml`, tek satır) |
| Min. macOS | 14 Sonoma |
| Proje üretimi | XcodeGen: `project.yml` → `MyNotch.xcodeproj`; üretilen `.xcodeproj` ve `Resources/Info.plist` git dışı |
| Dil modu | Swift 6, Approachable Concurrency; uygulama hedefinde varsayılan `MainActor` izolasyonu, saf yardımcılar `nonisolated` |
| İmza | Debug: ad-hoc (`CODE_SIGN_IDENTITY = "-"`, makinede identity yok); dağıtım için Developer ID + notarization sonra |
| Menü bar | SwiftUI `MenuBarExtra` (.menu) + `SettingsLink`; notch paneli ve Debug Preview AppKit pencereleri |
| MVP medya | Spotify + Apple Music (ikisi de) |
| Visualizer | MVP'de sahte animasyon; gerçek FFT Faz 6 opsiyonel |
| Test | XCTest (`MyNotchTests/`) |
| Faz durumu | Faz 0 iskelet 2026-09-02; Faz 0.5, Faz 1 (notch motoru) ve Faz 2 (modül sistemi) 2026-09-03; Faz 3 medya modülü 2026-09-03 (Spotify + Apple Music sağlayıcıları, AppleScriptRunner, MediaController, artwork + accent, scrubber/transport, parça değişimi popup'ı; 78 test). Sıradaki: Faz 4 (Claude usage). Elle yapılacak doğrulamalar: `docs/manual-tests.md` |
| Şarkı sözleri | LRCLIB (`/api/get` → `/api/search` → sadeleştirilmiş başlıkla arama), parça başına önbellek, `lyricsEnabled` bayrağı. AppleScript sayıları locale'e göre virgüllü döndürdüğü için tüm süre/konum alanları tam sayı **milisaniye** olarak alınır |
| EventBus | Combine yerine main-actor callback kaydı (`Core/Modules/EventBus.swift`): Swift 6'da `Sendable` gereksinimleri modül sözleşmesini kirletmesin diye. Abonelik token'ı bırakılınca bir sonraki main-actor turunda iptal olur, `invalidate()` anında iptal eder |
