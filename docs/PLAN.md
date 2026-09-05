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

- Geçiş kuralları: `popup` her durumda araya girebilir, bitince önceki duruma döner. `expanded` iken gelen popup, expanded içinde banner olarak gösterilir (üst üste büyüme olmasın). *Güncelleme 2026-09-04:* banner kartın **üstünde ayrı bir şerit** alır ve yüzey `NotchLayout.bannerHeight` kadar büyür — eskiden içeriğin üzerine biniyordu. Ayrıca **açık olan modülün kendi olayı banner üretmez**: parça değişimini zaten oynatıcının kendisi gösteriyor.
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
- **Ekran değiştirici (2026-09-04):** expanded kartın altında ince bir şerit, notch'un gösterebileceği her ekran için bir hap: aktif olanın adı yazılı, diğerleri yalnızca ikon. Bir modül bir uygulamayı temsil ediyorsa (`ModuleScreen.appBundleIdentifier`) o uygulamanın **gerçek ikonu** çizilir, yani şerit aynı zamanda "şu an ne çalışıyor" listesidir. Kayıt sırası korunur (ikonlar yer değiştirmez); ekran yalnızca `isAvailable` iken listelenir, ama açık olan ekran sessizleşse bile kendi hapını kaybetmez. Tek ekran varsa şerit çizilmez.
- **Son seçilen ekran kalıcıdır (2026-09-05):** kullanıcı şeritten bir ekran seçince `ModuleManager.preferredModuleID` (UserDefaults `preferredModuleID`) yazılır ve hover artık o modüle açılır; compact şerit yine çözücünün kazananını (müzik) gösterir. Seçilen modülün gösterecek ekranı kalmadıysa (oynatıcı kapandı) kazanana, o da yoksa ilk etkin modüle düşülür; ekran geri gelince tercih geri döner (`ModuleResolver.expandedDestination`). Medya, çalışan oynatıcı kümesi değişince `activityChanged` göndererek çözücüyü tetikler.
- **Bir modül birden çok ekran sunabilir:** medya modülü **çalışan her oynatıcı için ayrı bir ekran** verir (`media.spotify`, `media.music`) — Spotify ve Music aynı anda açıksa ikisi de kendi ikonuyla şeritte durur, uygulama açıldığı anda (çalmaya başlamasını beklemeden) görünür. Bunun için `NSWorkspace` uygulama açılma/kapanma bildirimleri dinlenir; poll beklenmez. Bir oynatıcıya tıklamak onu **sabitler** (`MediaController.focus`): içinde parça olmasa bile kartı elinde tutar, yoksa bir sonraki yenileme kartı parçası olan öbür oynatıcıya geri verirdi. Sabitleme, uygulama kapanınca düşer.

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

- Bildirim geldiğinde AppleScript ile tam durumu çek (bildirim payload'ına güvenme). *Güncelleme 2026-09-04 (ölçüldü):* Spotify `PlaybackStateChanged`'i **play ve pause'da gönderiyor, seek'te göndermiyor** — bu yüzden konum için poll şart. Playhead yerel ekstrapolasyonla ilerler; yeniden örnekleme expanded oynatıcı ekrandayken 2 sn, sadece çalarken 15 sn, duraklatmada 60 sn. Örnek zaman damgası script'in **ortasına** basılır (gidiş-dönüş ~110 ms; sonuna basmak playhead'i o kadar geriye atıyordu).
- `NSAppleEventsUsageDescription` Info.plist'e eklenecek; ilk kontrolde macOS otomasyon izni soracak — onboarding'de kullanıcıya anlat.

### 5.2 UI durumları

- **Compact:** solda 20×20 yuvarlatılmış albüm kapağı, sağda 4–5 çubuklu equalizer animasyonu (çalarken dalgalanır, pause'da düz çizgiye iner).
- **Expanded:** büyük artwork (köşe 12), başlık/sanatçı, senkron sözler, sürüklenebilir progress bar (seek), kaynak ikonu (Spotify/Music) ve altta **kart genişliğince ortalanmış kontrol çubuğu**: shuffle · önceki · beyaz daire içinde oynat/duraklat · sonraki · repeat; solda favori (kalp) butonu. Vurgu rengi artwork'ten (`CIAreaAverage`) çıkarılır.
- **Kontrol yetenekleri (2026-09-04 ölçüldü, tahmin değil):** Apple Music `shuffle enabled`, `song repeat` (kapalı/tümü/tek) ve `favorited` yazımlarını kabul eder. Spotify sözlüğünde `shuffling`/`repeating` yazılabilir görünse de **yazmayı sessizce yok sayar**, `starred` ise -10000 ile hata verir. Bu yüzden Spotify'da bu üç kontrol yalnızca **durum göstergesi**: gerçek değeri gösterirler (shuffle açıksa vurgulu), tıklanamazlar ve nedenini tooltip'te yazarlar. Kalp Spotify'da **Web API** üzerinden çalışır (2026-09-04, `Modules/Media/Spotify/`): kullanıcı kendi client ID'sini `defaults write com.emre.mynotch spotifyClientID <id>` ile verir ve Spotify Dashboard'da `http://127.0.0.1:48219/callback` redirect URI'sini kaydeder; kalbe ilk tıklama PKCE yetkilendirmesi için tarayıcıyı açar, loopback sunucu kodu yakalar, token'lar `~/Library/Application Support/MyNotch/spotify-oauth.json` (0600) dosyasında durur (Keychain Faz 5'te, imza sabitlenince). Bağlıyken `GET /v1/me/library/contains?uris=spotify:track:…` kalbin gerçek durumunu getirir (URI başına 60 sn önbellek, hata sonrası 30 sn bekleme), `PUT`/`DELETE /v1/me/library?uris=…` ekler/çıkarır. **Dikkat:** eski `/v1/me/tracks` ve `/v1/me/tracks/contains` uçları kullanımdan kaldırıldı ve doğru scope'la bile çıplak 403 "Forbidden" döndürüyor (eksik scope'ta mesaj "Insufficient client scope" olur) — 2026-09-04'te canlı ölçüldü. Shuffle/repeat gösterge olarak kalır.
- **Popup (parça değişimi):** notch genişler, eski artwork sola kayıp küçülürken yeni artwork + parça adı sağdan gelir; 2.5 sn sonra compact'a küçülür. (İstediğin "büyüme–küçülme" animasyonu burası.)
- **Şarkı sözleri (2026-09-03 eklendi):** expanded'da başlık ile progress bar arasındaki boşlukta senkron sözler akar — aktif satır kapak vurgu renginde, sonraki satır soluk, `.easeOut(0.32)` ile yukarı kayar; yalnızca expanded'dayken ve çalarken 4 Hz'de günceller. Kaynak **LRCLIB** (`lrclib.net`, ücretsiz, anahtarsız): önce `/api/get` (tam eşleşme), senkron söz yoksa `/api/search`, o da olmazsa sadeleştirilmiş başlıkla ikinci arama; sonuç parça başına önbelleklenir (bulunamayanlar dahil). **Aday seçimi (2026-09-05, `LyricsMatch`):** arama sonuçları önce kimlikle süzülür — başlık ve sanatçı normalize edilip (Türkçe harfler katlanır, "- Topic"/"(Paused)" ekleri düşer) eşleşmeli; canlı/remix/akustik gibi sürüm sözcükleri tek tarafta varsa senkronlu kayıt reddedilir; süre farkı 8 sn'yi aşan ya da son satırı parçanın sonunu geçen dosya başka bir kayıt içindir, reddedilir; yarım kalmış dosya cezalandırılır, albümü eşleşen kazanır. Bu kural gerçek bir vakadan geldi: Vega — "Bu Sabahların Bir Anlamı Olmalı" için LRCLIB 9 kopya döndürüyor (230–289 sn), hepsi aynı zaman damgalarıyla. **Şarkı başına zamanlama düzeltmesi:** söz bandına hover → `−`/`+` (0,5 sn), `lyricsShifts` default'unda `sanatçı|başlık` anahtarıyla saklanır; topluluk zamanlaması kayıtla örtüşmediğinde kullanıcı iki tıkla düzeltir. **Gizlilik:** sanatçı/parça/albüm/süre lrclib.net'e gider; `lyricsEnabled` bayrağıyla kapatılabilir, Faz 5'te Ayarlar'a anahtar olarak çıkacak.
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
- **Expanded (mini dashboard) — 2026-09-05 görsel yeniden tasarım:** kullanıcı metin ağırlıklı ekranı reddetti ("yazı ile bilgilendirmeyi olabildiğince azalt, görsel ve animasyon odaklı"). Kart artık halkalar (kullanım yayı + pencere zamanı yayı, açılışta süpürme animasyonu), ikon+sayı çipleri, parçalı model çubuğu ve durum noktasından oluşur; metin yalnızca yapılacak iş varken (sign-in) görünür, açıklamalar tooltip'te. Ayrıca expanded içerik çentikten `expandedTopGap` (8 pt) aşağıda başlar — halka çizgisi çerçevesinden taşıp çentiğin altına giriyordu. Önceki plan maddeleri:
  - 5 saatlik ve haftalık pencereler için **progress ring** (resmi endpoint verisi; erişilemezse ccusage blok tahminine zarifçe düş),
  - bugün: toplam maliyet, input/output token,
  - model kırılımı (Opus/Sonnet payı, yatay mini bar),
  - burn rate ($/saat) ve "bu hızla blok şu saatte dolar" tahmini,
  - son aktif proje adı.
- **Popup:** blok %80'e ulaştı ("yavaşla ⛽"), blok sıfırlandı, oturum bitti (oturum özeti: süre + maliyet). Eşikler ayarlanabilir.

### 6.3 Kabul kriterleri (Faz 4 çıkışı)

- [x] Claude Code'da mesaj atınca ≤5 sn içinde notch'taki sayaç/animasyon tepki verir — FSEvents 0,3 sn + 0,25 sn debounce; gerçek dosya testi `ProjectsWatcherTests`. (Müzik çalarken şerit medya modülünde kalır: öncelik 10 > 5.)
- [x] Expanded'daki bugün-maliyeti `ccusage claude daily --json` çıktısıdır (aynı araç; 2026-09-04: 27,68 $).
- [x] Progress ring'deki 5 saatlik doluluk resmi `/api/oauth/usage` verisidir (2026-09-04 canlı: %6 / haftalık %52). Claude Code `/usage` ile elle karşılaştırma `docs/manual-tests.md`'de.
- [x] Kimlik bulunamadığında alt satır "Sign in with `claude`" der; kod yolu yalnızca okur (Keychain'e, dosyaya, refresh ucuna yazan tek satır yok).
- [x] %80 / %95 eşiklerinde popup pencere başına bir kez (`ThresholdMemory`, reset zamanına anahtarlı, ısınma korumalı; testli).
- [x] ccusage/Node yoksa `CCUsageState.notInstalled` → "Cost needs ccusage · brew install ccusage"; halkalar bağımsız çalışır.

## 7. Backlog Modüller (MVP sonrası fikir havuzu)

Şarj/pil popup'ı · AirPods bağlantı animasyonu · ses/parlaklık HUD replacement · dosya rafı (notch'a sürükle-bırak → AirDrop) · takvim "sıradaki toplantı" · indirme ilerlemesi · Pomodoro · Xcode/CI build durumu. Hepsi aynı `NotchModule` protokolüyle eklenir — mimariyi değiştirmez.

## 8. İzinler, Dağıtım, Güvenlik

- **Automation (Apple Events):** Spotify/Music kontrolü için; ilk kullanımda sistem diyaloğu.
- **Ekran Kaydı:** sadece gerçek visualizer açılırsa (Faz 6).
- **Spotify Web API (opsiyonel):** yalnızca kullanıcı kalbe tıklayıp bağlanırsa; scope `user-library-read` + `user-library-modify`, dışarı giden veri parça ID'si. Client secret yok (PKCE), client ID kullanıcının kendi Spotify uygulamasından.
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
| **4 — Claude Usage** ✅ 2026-09-04 | `Modules/ClaudeUsage/`: `ClaudeCredentials` (env → Keychain via `/usr/bin/security` → dosya, salt-okunur), `UsageFetcher` (resmi 5 sa / 7 gün), `CCUsageRunner` (`ccusage@20` npx/binary, `--offline`), `ProjectsWatcher` (FSEvents), `ClaudeUsageService` (5 dk poll, 429 cooldown, uyanma grace, sign-in izleme), dashboard (halkalar, maliyet, model kırılımı, blok), eşik popup'ları | §6.3 kabul kriterleri |
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
| Faz durumu | Faz 0 iskelet 2026-09-02; Faz 0.5, Faz 1 (notch motoru) ve Faz 2 (modül sistemi) 2026-09-03; Faz 3 medya modülü 2026-09-03 (Spotify + Apple Music sağlayıcıları, AppleScriptRunner, MediaController, artwork + accent, scrubber/transport, parça değişimi popup'ı; 78 test). Faz 4 Claude usage 2026-09-04 (194 test). Sıradaki: Faz 5 (ayarlar & cila). Elle yapılacak doğrulamalar: `docs/manual-tests.md` |
| Playhead çapası | 2026-09-05: rutin okuma oynatıcının kaba konum adımının rastgele bir fazına düşer; `PlayheadRules.merge` aynı parça çalıyorken ve fark <1,2 sn ise eski çapayı korur (seek ise alır). Expanded'da sözler ekrandayken `precisePosition()` (tek osascript içinde 20 ms'lik döngü, konum değiştiği an döner, `-1` = tık yok) ile açılışta ve 30 sn'de bir çapalanır; ayrı `AppleScriptRunner` kuyruğu kullanır ki komutları bloklamasın. `AudioOutputLatency` çıkış aygıtı gecikmesini CoreAudio'dan okur ve sözlerden düşülür |
| Şarkı sözleri | LRCLIB (`/api/get` → `/api/search` → sadeleştirilmiş başlıkla arama), parça başına önbellek, `lyricsEnabled` bayrağı. Satır değişimi poll ile değil, satır başlangıçlarından üretilen **kesin zaman çizelgesiyle** (`TimelineView(.explicit)`) yapılır; her uyanış sınırdan 30 ms sonraya kaydırılır (erken ateşleyen zamanlayıcı bir önceki satırı seçip her satırı bir satır geciktiriyordu). `lyricsLeadSeconds` (varsayılan 0,15 sn) sözleri sesin biraz önünde tutar; Bluetooth gecikmesi için negatif verilebilir. AppleScript sayıları locale'e göre virgüllü döndürdüğü için tüm süre/konum alanları tam sayı **milisaniye** olarak alınır |
| Spotify favori | AppleScript `starred` yazılamaz (-10000) → Spotify Web API + PKCE (`Modules/Media/Spotify/`): kullanıcı kendi client ID'sini getirir (`spotifyClientID` default'u), loopback port 48219 sabit, token dosyası 0600. `MediaFavoriteSupport` kalbin `available` / `needsConnection` / `needsSetup` / `unsupported` durumlarını taşır; kalp hiçbir durumda gizlenmez, tıklama eksik adımı başlatır |
| Yerelleştirme | 2026-09-05: `App/Localizable.xcstrings` (kaynak `en`, çeviri `tr`), kodda `String(localized:defaultValue:)`; kullanıcının Mac'i Türkçe olduğu için ekran Türkçe gelir. Yüzde işareti dile göre yer değiştirir (`%26` / `26%`), süreler `4s 26dk` / `4h 26m`. Şimdilik Claude modülü çevrildi; medya ve Debug Preview metinleri İngilizce (Faz 5) |
| Claude ekranı doluluğu | Boş alanlar veriyle dolduruldu: halkaların altında **bugünün 5 saatlik blokları** çubuk grafiği (`blocks --since <bugün>`, aktif blok vurgulu), çiplerin altında **token bileşimi** çubuğu (çıkış/giriş/önbellek). Her gösterge hover'da büyür ve kart içi balonda açıklanır (`DashboardFocus` + `Spotlight`) |
| Kalıcı ekran tercihi | Hover'ın açacağı modül = kullanıcının son seçimi (kalıcı), ekranı yoksa çözücünün kazananı, o da yoksa ilk etkin modül. Compact şerit tercihten bağımsız, kazananı gösterir. Kullanıcı 2026-09-05'te "en son hangi ekranda kaldıysam orada kalsın" dedi; öncesinde her hover Spotify'a açılıyordu |
| Ekran değiştirici | Modül protokolünde üç üye: `var screens: [ModuleScreen]`, `var activeScreenID: String`, `func selectScreen(_:)` (üçünün de varsayılanı extension'da, tek ekranlı modül hiçbirini yazmaz). Ekran id'si modül id'sinden ayrıdır (`media.music`), `ModuleScreen.moduleID` geri eşler; seçimi `ModuleManager` uygular (modüle bildirir + `model.expand`), böylece "view model'i tek yerden sürme" kuralı bozulmaz. Şerit motorun kendi parçası (`Core/Window/NotchScreenSwitcher.swift`), modül-özel kod içermez; liste `NotchContentProvider.screens(activeID)` üzerinden `ModuleManager`'dan gelir ve **body içinde** okunur ki modüllerin `@Observable` durumunu izlesin. Kart `switcherHeight` (26 pt) kadar büyür, panel 600×280'e çıktı. Uygulama ikonları `AppIconCache`'te bir kez çözülür (body morph sırasında defalarca çalışıyor) |
| Hover toleransı | Karttan çıkan imleç `NotchLayout.graceRect` bölgesindeyse (kart + 32/28 pt kenar payı, ekran üst kenarına kadar) kart en fazla `closeDelay` = 0,8 s daha açık kalır (Debug Preview'da 0–1 s slider); bölgeden çıkınca ya da süre dolunca anında kapanır, süre yenilenmez. İmleç 40 ms'de bir yalnızca bu pencere boyunca `NSEvent.mouseLocation` ile izlenir. Görünmez alan **çizilmez** (alfa tabanlı tıklama geçirgenliğini bozar ve tıklamaları yutar) |
| Claude usage kimliği | Salt-okunur: `CLAUDE_CODE_OAUTH_TOKEN` → Keychain (`Claude Code-credentials[-hash]`, keşif `kSecReturnAttributes` ile, sır `/usr/bin/security find-generic-password -w` ile — ACL uyarısı yok; 2026-09-04'te ilk çalıştırmada uyarı çıkmadı) → `.credentials.json`. Token asla loglanmaz, hiçbir yere yazılmaz, refresh yapılmaz (Anthropic eski refresh token'ı görünce tüm aileyi iptal eder). `expiresAt` ms; süresi dolmuşsa istek atılmaz |
| Claude usage `limits[]` | 2026-09-05'te ölçüldü: yanıtta `limits: [{group, is_active, kind, percent, resets_at, scope, severity}]` var — `kind: session` (5 sa), `weekly_all` (7 gün), `weekly_scoped` + `scope.model.display_name` ("Fable", %15). `scope: null` kayıtlar üst düzey `five_hour`/`seven_day` ile aynı, atlanır; adlı olanlar `UsageSnapshot.scopedLimits` → ekstra halka + eşik uyarısı (`UsageSubject.scoped`). `seven_day_opus/sonnet/cowork/oauth_apps` anahtarları bu hesapta `null`. `resets_at` 6 haneli kesir taşır (ISO8601 ayrıştırıcı kaldırıyor). Kart 480 pt'ye genişletildi ki üç halka sığsın |
| Claude usage endpoint | `GET https://api.anthropic.com/api/oauth/usage`, `anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-code/2.1.121` → 2026-09-04'te 200 (UA'sız varyant denenmedi; UA masrafsız, gönderiliyor). Poll 5 dk (`SuspendingClock`: uyku sayılmaz), 429 → 900 sn cooldown + tek retry, uyanmada 60 sn grace, `>15 dk` bayat = soluk. Başarısız poll son iyi değeri korur (reset geçmiş pencereler düşer) |
| ccusage | `ccusage` binary'si bulunursa o, yoksa `npx --yes ccusage@20` (nvm/Homebrew/bun/npm-global dizinleri taranır; GUI PATH'i kısıtlı). Ölçüm 2026-09-04: blocks 2,8 sn, daily 0,9 sn (~300 MB log). Her çağrı `--offline`; kadans: aktivite bittikten 20 sn sonra, çalışma sürerken en geç 2 dk'da bir. `Decodable` varsayılan değerleri kaçan anahtarları **kapsamaz** → DTO'lar elle `decodeIfPresent` |
| EventBus | Combine yerine main-actor callback kaydı (`Core/Modules/EventBus.swift`): Swift 6'da `Sendable` gereksinimleri modül sözleşmesini kirletmesin diye. Abonelik token'ı bırakılınca bir sonraki main-actor turunda iptal olur, `invalidate()` anında iptal eder |
