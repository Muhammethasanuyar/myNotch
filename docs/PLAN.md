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

Şarj/pil popup'ı **(Faz 6 ✓ `Modules/Battery`)** · AirPods bağlantı animasyonu · ses/parlaklık HUD replacement (bilinçli dışarıda: Erişilebilirlik + event tap) · dosya rafı (notch'a sürükle-bırak → AirDrop) **(Faz 6 ✓ `Modules/Shelf`)** · takvim "sıradaki toplantı" **(Faz 6 ✓ `Modules/Calendar`)** · indirme ilerlemesi · Pomodoro **(Faz 6 ✓ `Modules/Pomodoro`)** · Xcode/CI build durumu. Hepsi aynı `NotchModule` protokolüyle eklenir — mimariyi değiştirmez; raf için gereken tek motor dikişi (`acceptsDrops`) de modül-agnostiktir.

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

Faz 6 sonrası gerçek ağaç (adlar `MyNotch`; üretilen `MyNotch.xcodeproj` ve `Resources/Info.plist` git dışı):

```
MyNotch/
├── App/            AppDelegate (SIGTERM → NSApp.terminate, applicationWillTerminate → ModuleManager.stopAll), SettingsApplier, Localizable.xcstrings
├── Core/
│   ├── Window/     NotchPanel (NotchHostingView = drag hedefi), NotchRootView, NotchLayout, NotchShape, NotchDropDetector, NotchDragSessionMonitor,
│   │               NotchScreenSwitcher, NotchSpotlight, PulsingSymbol, EqualizerBars, NotchTap, ScreenPreference
│   ├── State/      NotchViewModel, NotchState, NotchTransition, Anim
│   └── Modules/    NotchModule (+ acceptsDrops / NotchDrop), ModuleManager, ModuleResolver, ModuleScreen, EventBus, NotchEvent
├── Modules/
│   ├── Media/      MediaController, providers (Spotify, AppleMusic), Spotify/ (PKCE kütüphane), Generic/ (mediaremote-adapter süreci), AudioTap/AudioMeter, LyricsService, Views/
│   ├── ClaudeUsage/ ClaudeUsageService, SessionLogParser, BlockCalculator, UsageLedger, UsageAggregator, CostAllocator, CCUsageRunner, Views/
│   ├── Battery/    BatteryService (IOKit.ps), BatteryRules, Views/
│   ├── Pomodoro/   PomodoroTimer, PomodoroStateStore, PomodoroRules, Views/ (CountdownArc)
│   ├── Calendar/   CalendarService (EventKit), CalendarRules, Views/
│   └── Shelf/      ShelfStore, ShelfStorage (actor), ShelfItem (Transferable), ShelfRules, ShelfShare (AirDrop), Views/
├── Settings/       SettingsStore, SettingsContext (sekmeler), SettingsWindowController, Panes/ (General, Modules, Media, Claude, Calendar, Battery, Pomodoro, Shelf, Setup, About)
├── DebugPreview/
├── Vendor/mediaremote-adapter/   scripts/vendor-mediaremote-adapter.sh üretir; git'e girer
├── scripts/        build/test/run, measure-idle, sync-settings-strings, vendor-mediaremote-adapter
└── docs/           PLAN.md, manual-tests.md, harvest/
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
| macOS güncellemesi MediaRemote workaround'unu kırar | Generic provider ölür | MVP'yi AppleScript'e kur (resmi arayüz); adapter'ı feature flag arkasında tut. *Faz 6:* `test` sağlık kontrolü OS build/uygulama sürümü başına bir kez; stream `exit ≠ 0` ile ölürse yeniden başlatma yok, `broken(code)` ayarlarda görünür, Spotify/Music sağlayıcıları devam eder |
| `/usr/bin/perl` bir macOS sürümünde kalkar ya da artefaktlar derlemeye girmez | Generic sağlayıcı hiç başlamaz | `MediaRemoteAdapterProcess.Paths.bundled()` → `artefactsMissing`; yalnızca bu sağlayıcı susar, medya modülü AppleScript'le çalışır |
| Gömülü `MediaRemoteAdapter.framework` + test client + `.pl` notarization'a girer (ek Mach-O'lar, ad-hoc imza) | Release reddi | Release'de Developer ID ile içten dışa imza (framework → test client → app); ret gelirse `.pl`'yi Resources dışına taşıma seçeneği (`docs/harvest/mediaremote-adapter.md` S6) |
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
| Menü bar | SwiftUI `MenuBarExtra` (.menu); notch paneli, Debug Preview **ve ayarlar penceresi** AppKit pencereleri (Faz 5'te `SettingsLink`/`Settings` sahnesi kaldırıldı: liquid glass için `.fullSizeContentView` pencere oluşturulurken verilmek zorunda, SwiftUI sahnesi bunu sunmuyor) |
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
| Ayar deposu (Faz 5) | `Settings/SettingsStore.swift`: tüm UserDefaults anahtarları `SettingsKey`'de (Faz 1–4 anahtarları aynı kaldı: `spotifyClientID`, `lyricsEnabled`, `lyricsLeadSeconds`, `lyricsShifts`, `ccusagePath`, `claudeConfigDir`); yeniler `hoverDelay`, `closeDelay`, `hapticsEnabled`, `disabledModules`, `displaySelection`, `usageWarningThreshold`, `usageCriticalThreshold`, `usagePollInterval`, `usageAlertsEnabled`, `onboardingCompleted`. Sınırlar `SettingsRules` (closeDelay ≤ 1 s, poll ∈ {300, 600, 900, 1800}, critical ≥ warning + 0,05). Depo motoru tanımaz; `App/SettingsApplier.swift` dağıtır. `preferredModuleID` kullanıcı tercihi olarak `ModuleManager`'da kaldı. |
| `@Observable` + `didSet` | 2026-09-06'da ölçüldü: `didSet` içinde kendi özelliğine atama (`x = clamp(x)`) macro'lu sınıfta sonsuz özyineleme (SIGSEGV). Sınırlanan değerler `@ObservationIgnored` depo + `access/withMutation` ile açık accessor kullanır; yalnızca kalıcılaştıran `didSet`'ler kalır. |
| Açılışta başlat | `SMAppService.mainApp` (`Settings/LaunchAtLogin.swift`); durum sistemden okunur, defaults'a yazılmaz. `build/` dizininden çalışan derlemede `status == .notFound` normaldir; UI bunu "Uygulamalar klasörüne taşı" olarak açıklar. |
| Ekran seçimi | `ScreenPreference` (`automatic` / ekran adı) saf çözüm: adı eşleşen ekran → çentikli → ana → ilk. Ekran çıkarılınca otomatiğe düşer, ad listede "(bağlı değil)" olarak kalır. `NotchWindowController.screenPreference` değişince `reposition()`. |
| Onboarding | Ayrı pencere yok: ayarlar penceresinin **Kurulum** sekmesi (Otomasyon, Spotify, Claude girişi, loglar, ccusage, açılışta başlat; her satır durum + tek eylem). `onboardingCompleted` false ve `-debugState` yokken açılışta bu sekme gelir; "Bitti" bayrağı yazar. `-onboardingCompleted YES` argümanı ölçüm/ekran görüntüsü çalıştırmalarında bastırır. |
| Ayar metinleri | `L("anahtar", "English default")` (`Core/Localization.swift`) + `scripts/sync-settings-strings.py` içindeki tr tablosu; script eksik çeviride hata verir. Medya modülünün kalan İngilizce metinleri de bu yolla Türkçeleştirildi. |
| Boşta CPU | `scripts/measure-idle.sh` (`top`, 2 sn örnek). 2026-09-06 Debug: kapalı %0,00 (25 MB), compact (demo canlı) %0,00; açık Claude kartı ilk ölçümde **%14–18 sürekli**. Bisect (`-mask` başlatma argümanıyla bölümleri/efektleri tek tek açıp `top` ile ölçmek) suçluyu buldu: **tekrarlayan `symbolEffect(.pulse/.variableColor, options: .repeating)`** SwiftUI'yi her karede tüm kartın display list'ini yeniden üretmeye zorluyor (blur/gölge ile ilgisi yok; `sample` yalnızca genel `renderDisplayList` kareleri gösterdi). Çözüm `Core/Window/PulsingSymbol.swift`: `NSImageView` + `CABasicAnimation(opacity)` — nefes render server'da koşar, uygulama %0. Kural: sürekli/ambient animasyon = `PulsingSymbol` (CA); tek seferlik `.bounce`/`.numericText` SwiftUI'de kalır. Ölçümler §16.4. |
| Popup yerleşimi | Popup = **compact satırı + altında 36 pt metin şeridi** (`popupExtraHeight`), iki stilde de. Compact ve popup `NotchRootView`'da aynı satırı paylaşır (kanatlar kimliğini korur, yüzey genişlerken dış kenarlara kayar: solda kapak, sağda seviye ölçer), şeritte `NotchPopupLine` tek satır ortalı (kalın başlık + soluk detay, `lineLimit(1)`). Önceki iki yerleşim de reddedildi: kanat hizasındaki satır uzun başlıkları kameranın arkasına sokuyordu; yalnızca şeritteki kapaklı satır kanatları boş bırakıyordu (2026-09-06 kullanıcı geri bildirimi: "solda resmi ve sağda müzik animasyonu devam etsin, boş alan gözükmesin"). Modül popup görünümleri (`MediaPopupView`, `NotchEventRow`, `DemoPopupView`) yalnızca metin verir; kapak/ikon kanatlardan gelir. Kanat içeriği boyutu motordan `EnvironmentValues.wingContentSize` ile gelir (`Core/Window/WingContentSize.swift`) ve **yüzeyin o anki yüksekliğini izler**: `yükseklik − 2·wingContentInset (8)` → compact'ta ≈ çentik yüksekliği − 16 (dahili ekranda 21 pt), popup'ta 73 − 16 = 57 pt; kapak yüzeyin solunda boydan boya, ölçer sağda, başlık şeridi ikisinin arasında (popup genişliği 300 pt ekstra). Kanatlar popup'ta doğal genişlik + 8 pt pay alır; morph animasyonlu; modüller sabit ölçü yazmaz. `-debugState popup -debugModule media` uzun başlıkla gösterir. |
| Hibrit maliyet (Faz 6) | Token/blok/hız/model `Modules/ClaudeUsage/{SessionLogParser,BlockCalculator,UsageLedger,UsageAggregator}.swift` ile yerel; ccusage yalnızca `claude daily --json --since bugün --offline` (0,9 sn) ile günün dolarını verir ve `CostAllocator` (göreli ağırlıklar input 1 / output 5 / cache-write 1,25 / cache-read 0,1) bunu bloklara dağıtır. `blocks` çağrısı (2,8 sn, 300 MB okuma) kaldırıldı. Dedupe agregasyon anında (S7 cevabı: kalıcılaştırılmaz). `todayBlocks` yerel güne göre, `activeBlock` tüm kümeden (dünden başlayan aktif blok kaybolmaz). 2026-09-06 paritesi birebir (§17.7). Ledger anahtarı `standardizedFileURL.resolvingSymlinksInPath()` — `/var` ile `/private/var` aynı dosya. |
| Generic sağlayıcı (Faz 6) | mediaremote-adapter **bundle edilir, adapte edilmez**: artefaktlar `scripts/vendor-mediaremote-adapter.sh` ile `references/` klonundan (SHA `3ac3d4b`) clang'la derlenir, `Vendor/mediaremote-adapter/` altında commit'lenir, XcodeGen gömer; framework'ü `/usr/bin/perl` yükler, uygulama link etmez. `Modules/Media/Generic/`: tek uzun ömürlü `stream --debounce=250` süreci, satırlar `AdapterEnvelope` → `AdapterPayload` (diff merge, aynı parçada artwork korunur) → `NowPlayingSnapshot`; playhead adaptörün `timestamp`'ine demirlenir. Değişiklikler `MediaProvider.changeTicks()` ile push edilir (dağıtık bildirim yok; `changeNotification` artık opsiyonel). Kaynak Spotify/Music'e aitse (`bundleIdentifier` ya da `parentApplicationBundleIdentifier`) generic **susar**. Sağlık: `test` yalnızca ilk etkinleştirme, OS build/uygulama sürümü değişimi ve "Yeniden test et" ile; sonuç `genericPlayerHealth` (kendi anahtarı, ayar değil). Stream `exit ≠ 0` → yeniden başlatma yok. Yaşam döngüsü: `applicationWillTerminate` → `ModuleManager.stopAll()` → `MediaController.stop()` alt süreci SIGTERM'le kapatır; **SIGTERM `NSApp.terminate`'e yönlendirilir** (AppKit SIGTERM'i kendiliğinden zarif kapanışa çevirmez — `pkill` ile öksüz perl kalıyordu); çökme sonrası öksüzler açılışta bir kez `pkill -f <script yolu>` ile süpürülür, stream bu süpürmeyi bekler. Komutlar `AdapterCommandQueue` actor'unda seri (aynı türden bekleyen komut son gelenle değişir); MediaRemote kimlikleri `MediaRemoteCommand` (0 play … 13). |
| Modül öncelikleri (Faz 6) | Kayıt sırası = şerit sırası: claude 5 → media 10 → calendar 7 → pomodoro 8 → battery 6 → shelf 4 (DEBUG demo 0). Pomodoro müziğin altında kalır (kullanıcı müzik şeridine yatırım yaptı); istenirse tek sayıyla yükseltilir. Hiçbir modül `activity` olarak `.urgent` döndürmez — kesintiler yalnızca `context.post(event)`; `ModuleResolver.acceptsPopup` yalnızca `isEnabled` ister, idle modül de popup atar. |
| Sürükleyerek açma dikişi (Faz 6) | `Core` modül-agnostik kalır: `NotchModule.acceptsDrops` (varsayılan false) + `dropTargetingChanged(unitPoint)` + `acceptDrop(NotchDrop)`; `NotchContentProvider.dropTargetModuleID/dropTargetingChanged/acceptDrop`; `ModuleManager.dropTargetModule` = ilk etkin kabul eden. Drop hedefi **AppKit**: `NotchHostingView` `registerForDraggedTypes([.fileURL])` + `NSDraggingDestination` (SwiftUI `onDrop` kullanılmadı — kapalı notch'ta view yok, `NSHostingView` destination değil). Sürükleme yüzeye değince `NotchViewModel.dragTargetingChanged` kartı **anında** açar (`NotchTransition.stateOnDragTarget`, hangi kart açık olsa da), çıkınca hover çıkışı gibi kapatır; bırakmadan sonra `dropLanded` kartı `closeDelay + dropLinger (2,5 s)` tutar, imleç üzerine gelirse hover devralır. Pencere sunucusu sürüklemeyi de piksel alfasıyla yönlendirir → housing kendi başına yakalar; 32 pt taşma için `NotchDropDetector` (alfa 0,001, NotchDrop'tan) yalnızca `isDragSessionActive` iken çizilir. Oturum tespiti `NotchDragSessionMonitor`: global `leftMouseDown/Dragged/Up` + `NSPasteboard(.drag).changeCount`; `mouseMoved` asla; boşta CPU %0,01. Bırakma noktası `NotchLayout.expandedContentUnitPoint` ile 0…1 kart koordinatına çevrilir, bölge kararı modülde (`ShelfRules.zone`). |
| Raf deposu (Faz 6) | Bırakma **kopyalar**: `~/Library/Application Support/MyNotch/Shelf/<uuid>/<dosya>` + `preview.png` (QLThumbnailGenerator, 128 pt @2x, arka planda) + kökte `index.json` (ISO-8601). Disk işi `actor ShelfStorage`, UI modeli `ShelfStore` (`@MainActor @Observable`). Saklama `shelfKeepInterval` (24 sa; 1 sa/12 sa/1 gün/2 gün/1 hafta/kaldırılana kadar = 0); süresi dolanlar yüklemede, her bırakmada ve ayar değişince gider — timer yok. Silme kopyayı da siler, özgün dosyaya dokunulmaz. `activity` bırakmadan sonra 120 s `live`, sonra idle; ekran raf boşken şeritten düşer. AirDrop `NSSharingService(.sendViaAirDrop)` doğrudan (picker yok: key pencere ister); dışarı sürükleme `ShelfItem: Transferable` (`FileRepresentation`, kopyanın kendisi). |
| Pomodoro durumu (Faz 6) | Çalışma durumu ayar değil: `PomodoroStateStore` kendi `pomodoroState` JSON anahtarında (`preferredModuleID` emsali); kapalıyken biten faz yeniden açılışta bir kez duyurulur, `autoStart`'a göre devam eder ya da bekler. Sayaç tek `Task.sleep(until:)`, halka `CountdownArc` (CAShapeLayer `strokeEnd`, süre = kalan; duraklatmada animasyon kaldırılır). |
| Visualizer (Faz 6) | CoreAudio process tap (`CATapDescription(stereoGlobalTapButExcludeProcesses:)` → özel aggregate device → `AudioDeviceCreateIOProcIDWithBlock`), 6 RBJ bandpass → 4 çubuk; yalnızca `visualizerEnabled ∧ çalıyor (2 s debounce) ∧ ekranda gözlemci` iken yaşar, aksi halde `EqualizerMode.dancing` (CA). Seviye yolu 30 Hz utility kuyruğu → eşik geçince main → `EqualizerBarsView.setLevels` (CATransaction); SwiftUI per-frame yok. İzin `NSAudioCaptureUsageDescription`; ret → `.silent` → dans. |

## 16. Faz 5 Planı — Ayarlar & Cila (2026-09-06)

Amaç: Faz 1–4'te `defaults write` ile ayarlanan her şeyin bir yüzü olsun, uygulama temiz bir Mac'te kendini kurdursun ve boşta neredeyse hiç kaynak yemesin. Bu faz **yeni bir modül eklemez**; motor, modüller ve Settings katmanı arasındaki bağı tamamlar.

### 16.1 Kapsam ve dosyalar

| İş parçası | Dosyalar | Not |
|---|---|---|
| **A. Ayar deposu** | `Settings/SettingsStore.swift` (+ `SettingsKey`) | `@MainActor @Observable`, enjekte edilebilir `UserDefaults`. Faz 1–4 anahtarları (`spotifyClientID`, `lyricsEnabled`, `lyricsLeadSeconds`, `lyricsShifts`, `ccusagePath`, `claudeConfigDir`) ve yeniler (`hoverDelay`, `closeDelay`, `hapticsEnabled`, `disabledModules`, `usageWarningThreshold`, `usageCriticalThreshold`, `usagePollInterval`, `usageAlertsEnabled`, `displaySelection`, `onboardingCompleted`) **tek yerde**. Değerler okunurken sınırlanır (ör. `closeDelay ≤ 1 s`, poll ≥ 300 s, `warning < critical`). `preferredModuleID` `ModuleManager`'da kalır (kullanıcı tercihi, ayar değil). |
| **B. Motora bağlama** | `App/SettingsApplier.swift`, `NotchViewModel`, `ModuleManager`, `ClaudeUsageService`, `ClaudeUsageModule`, `MediaController` | Depo değişince `SettingsApplier` ilgili nesneye yazar: `hoverDelay/closeDelay/hapticsEnabled → NotchViewModel`, modül aç/kapa → `ModuleManager.setEnabled`, eşikler/poll aralığı/uyarılar → `ClaudeUsageService`/`ClaudeUsageModule`, ccusage yolu → `service.relocateCCUsage()`, Spotify client ID → `library.refreshConfiguration()`, ekran → `NotchWindowController.screenPreference`. `LyricsService` ve `configDirectory` zaten her okumada defaults'a bakıyor; anahtar aynı kaldığı için ek bağ yok. Modüller `SettingsStore`'u tanımaz — değerler var olan servis özellikleri üzerinden gider. |
| **C. Ayarlar penceresi** | `Settings/SettingsWindowController.swift`, `Settings/SettingsView.swift`, `Settings/Panes/*.swift`, `App/MenuBar.swift`, `App/MyNotchApp.swift` | `macos-settings-ui` skill deseni: AppKit `NSWindowController` + `.fullSizeContentView` (liquid glass), `NavigationSplitView` kenar çubuğu, `Form.formStyle(.grouped).scrollContentBackground(.hidden)`, geri/ileri araç çubuğu. Sekmeler: **Genel** (açılışta başlat, hover/kapanma süresi, haptik, ekran), **Modüller** (aç/kapa), **Medya** (şarkı sözü, sözler kayması sıfırla, Spotify bağlantısı + client ID + redirect URI, Otomasyon izni), **Claude** (giriş durumu, eşikler, uyarılar, poll aralığı, ccusage yolu/durumu, config dizini), **Kurulum** (izin/kimlik kontrol listesi = onboarding), **Hakkında** (sürüm, dışarı ne gidiyor, üçüncü taraf kaynaklar). SwiftUI `Settings` sahnesi ve `SettingsLink` kalkar; menü bar "Settings…" (⌘,) `SettingsWindowController.show(tab:)` çağırır. Tüm metinler String Catalog'da (en kaynak, tr). |
| **D. Açılışta başlat** | `Settings/LaunchAtLogin.swift` | `SMAppService.mainApp` (macOS 13+): `register/unregister`, `status → LaunchAtLoginState` saf eşleme (`.enabled/.disabled/.requiresApproval/.notFound`); `requiresApproval`'da Sistem Ayarları → Giriş Öğeleri düğmesi. |
| **E. Ekran seçimi** | `Core/Window/ScreenPreference.swift`, `NotchWindowController` | `automatic` (çentikli ekran, yoksa ana ekran) ya da ekran adı; ad bulunamazsa otomatiğe düşer. Çözüm saf ve testli (`ScreenCandidate`), `NSScreen` yalnızca adaptör. Harici ekranda floating stil zaten `NotchLayout` tarafından üretiliyor. |
| **F. Onboarding** | `SetupPane`, `AppDelegate`, `LaunchOptions` | İlk açılışta (`onboardingCompleted == false`) ayarlar penceresi **Kurulum** sekmesiyle açılır: Otomasyon izni (`MediaController.permission`), Claude girişi (`service.auth`), ccusage (`service.costState`), oturum logları (`service.hasLogs`), Spotify (isteğe bağlı, `library.connection`), açılışta başlat. Her satırda durum simgesi + tek eylem. "Bitti" bayrağı kalıcı yapar. `-openSettings <sekme>` başlatma argümanı ekran görüntüsü için. |
| **G. Cila** | `Modules/Media/**`, `Core/Window/NotchScreenSwitcher.swift`, `App/Localizable.xcstrings` | Medya modülü ve değiştirici metinleri kataloğa (tr). `scripts/measure-idle.sh`: MyNotch PID'sini `top` ile 30 sn örnekler (kapalı / compact / expanded); sonuç `docs/PLAN.md` §16.4'e işlenir, %1'in üzerindeki her durum düzeltilir. |
| **H. Test & belge** | `MyNotchTests/SettingsStoreTests.swift`, `ScreenPreferenceTests.swift`, `LaunchAtLoginTests.swift`, `docs/manual-tests.md`, `CLAUDE.md`, §15 | Depo varsayılanları/kalıcılık/sınırlama, ekran çözümü, durum eşlemesi, `ModuleManager` kayıt sırasında `isEnabled`. Manuel senaryolar Faz 5 bölümü. |

### 16.2 Kabul kriterleri (Faz 5 çıkışı)

1. Ayarlar penceresindeki her denetim **anında** etki eder (yeniden başlatma yok) ve yeniden açılışta korunur.
2. `defaults write` ile daha önce ayarlanan hiçbir anahtar kırılmaz; aynı anahtarlar kullanılır.
3. "Açılışta başlat" açıkken oturum kapatıp açınca uygulama menü barda; onay bekleyen durumda pencere bunu söyler.
4. Harici ekran seçilince notch o ekranın üst orta noktasında floating stilde çıkar; ekran çıkarılınca otomatiğe döner.
5. Temiz kullanıcı hesabında ilk açılış Kurulum sekmesini gösterir; tüm satırlar yeşile döndükten sonra "Bitti" ile bir daha açılmaz.
6. Boşta CPU: kapalı < %0,5, compact (şarkı çalıyor) < %1,5, expanded ≤ %5 (animasyonlar); ölçüm `scripts/measure-idle.sh` ile.
7. Türkçe sistemde pencere tamamen Türkçe; İngilizce'de İngilizce. `scripts/test.sh` yeşil.

### 16.3 Bilinçli dışarıda bırakılanlar

- Keychain'e Spotify token taşıma (Faz 5'te planlanmıştı): 0600 dosya + tek kullanıcı hesabı için yeterli; Keychain girişi dağıtım imzasıyla anlamlı olur → Faz 6 / release.
- Sparkle/auto-update ve notarize: `macos-release` skill'iyle ayrı bir iş.
- Kısayol tuşları (notch'u klavyeyle aç/kapa): backlog.

### 16.4 Ölçümler (2026-09-06, Debug derlemesi, M-serisi MacBook, dahili ekran)

`scripts/measure-idle.sh 30` (`top -l`, 2 sn örnek, ilk örnek atılır; Türkçe yerelde ondalık virgül normalize edilir):

| Durum | Ortalama CPU | Not |
|---|---|---|
| Kapalı (Spotify duraklatılmış, Claude boşta) | %0,00 | 25 MB |
| Compact (demo modülü canlı) | %0,00 | 26 MB |
| Açık Claude kartı, yerleşmiş | %0,0–0,2 | 37 MB |
| Açık Claude kartı, Claude çalışıyor (nabızlar aktif) — **önce** | %14–18 sürekli, açılışta %25 | tekrarlayan `symbolEffect` her karede display list yeniliyordu |
| Açık Claude kartı, Claude çalışıyor — **sonra** (`PulsingSymbol`) | %0,0 (açılış animasyonu 2 sn %23) | 32 MB |
| Açık medya kartı / demo kartı | %0,0 | ölçüm açılıştan 2 sn sonra |
| Compact, **müzik çalıyor**, SwiftUI seviye ölçeri (`TimelineView(.animation(1/24))`) — **önce** | %5,4 | 24 fps display list yenilemesi |
| Compact, müzik çalıyor — **sonra** (`Core/Window/EqualizerBars.swift`, CA `transform.scale.y` döngüleri) | %0,01 | 26 MB |

Artık uygulamada per-frame `TimelineView(.animation)` ya da tekrarlayan `symbolEffect` yok; ambient animasyonların hepsi Core Animation'da (`PulsingSymbol`, `EqualizerBars`).

Yöntem notu: `sample` süreç içi render'ı gösterdi ama hangi görünüm olduğunu değil; `Self._logChanges()` gövde yeniden değerlendirmesi olmadığını kanıtladı (16 değerlendirme / 20 sn); sonucu **maske argümanıyla bisect** verdi. Başlatma argümanları `UserDefaults`'a *string* olarak gelir — `object(forKey:) as? Int` sessizce nil döner, `integer(forKey:)` kullan. zsh'ta `log` bir builtin'dir; `/usr/bin/log show|stream` yaz.

## 17. Faz 6 Planı — Gelişmiş (2026-09-06)

### 17.1 Bağlam ve kararlar

Faz 0–5 tamam (`docs/PLAN.md` §10, §15, §16; son commit `79a8688`). Faz 6 satırı (§10): gerçek visualizer, mediaremote-adapter generic sağlayıcı, native JSONL parser, backlog modülü; kabul kriteri "ayarlardan açılabilir, kapalıyken sıfır maliyet". Kullanıcının kararları (2026-09-06):

| Konu | Karar |
|---|---|
| Visualizer | **Evet**, ayarlardan açılır (varsayılan kapalı), CoreAudio process tap (ScreenCaptureKit değil) |
| Generic sağlayıcı | **Evet**, bayrak arkasında (varsayılan kapalı); `test` sağlık kontrolü, kırılırsa AppleScript'e sessiz düşüş |
| Backlog modülleri | **Hepsi**: Şarj/pil, Dosya rafı (Shelf → AirDrop), Takvim (sıradaki toplantı), Pomodoro |
| Maliyet | **Hibrit**: token/blok/hız/model yerel parser'dan; dolar yalnızca ccusage kuruluysa |

Faz 6 mimariyi değiştirmez: her yeni özellik ya `Modules/<Ad>/` altında bir `NotchModule` ya da medya/Claude modülünün içinde bayraklı bir parça. `Core/` modül-özel kod almaz; tek istisna Shelf için gereken **genel** "sürükleyerek aç" seam'i.

### 17.2 Bağlayıcı ilkeler

- Kapalıyken sıfır maliyet: bayrak kapalıysa süreç/tap/timer/monitör yok; açıkken bile olay güdümlü (FSEvents, IOKit bildirimi, EKEventStoreChanged, medya durum geçişleri).
- Ambient animasyon yalnızca Core Animation (`PulsingSymbol`, `EqualizerBars`); per-frame SwiftUI yasak; `TimelineView(.periodic(by: ≥1 s))` yalnızca kart görünürken.
- Ayar anahtarları yalnızca `SettingsStore` (`SettingsKey` + `SettingsRules`), dağıtım `SettingsApplier` (exhaustive switch); modül aç/kapa `ModuleCatalog`; izin/kurulum satırları `SetupPane`.
- Metinler `L("anahtar", "English")` + `scripts/sync-settings-strings.py` tablosu (Türkçe zorunlu).
- Private API yalnızca `Modules/Media/Generic/` altında ve bayrak arkasında; ağ/dış süreç kullanan parçalar dosya başlığında ne gönderdiğini yazar.
- `references/`'tan dosya kopyalanmaz; MIT/BSD adaptasyonlarında `// Adapted from …` başlığı + `THIRD_PARTY_LICENSES.md`.
- Doğrulama: `scripts/run.sh --args -debugState … -debugModule <id> -onboardingCompleted YES` + `screencapture -x -R …`; CPU `scripts/measure-idle.sh 30`; hiçbir zaman sentetik girdi yok. Build + 268 test yeşil olmadan checkpoint commit yok; her checkpoint `origin main`'e push (yetki var).

### 17.3 A. Gerçek ses visualizer'ı (`visualizerEnabled`, varsayılan kapalı)

**Yol:** CoreAudio process tap — `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` (`isPrivate`, `muteBehavior .unmuted`) → `AudioHardwareCreateProcessTap` (macOS 14.2+) → tap'i içeren özel aggregate device (`kAudioAggregateDeviceIsPrivateKey`, MainSubDevice = varsayılan çıkış, drift compensation, TapAutoStart) → `AudioDeviceCreateIOProcIDWithBlock` → 6 RBJ bandpass (80/200/500/1200/3000/7000 Hz, Q 2,4) → bant başına dB penceresi + asimetrik zarf → ≤30 Hz yayın → CA çubukları. Tap yalnızca **bayrak açık ∧ müzik çalıyor (2 s duraklama debounce) ∧ ekranda gözlemci var** iken yaşar; aksi halde bugünkü otonom CA dansı (`EqualizerMode.dancing`).

**Dosyalar**
- Yeni `Modules/Media/AudioMeterRules.swift` (saf, `nonisolated`): `BandSpec`, `Biquad` (`mutating process`), `BiquadDesign.bandpass(center:q:sampleRate:)`, `level(rms:band:)` (dBFS → 0,10…1,0), `envelope(previous:target:)` (atak 0,55 / bırakma 0,18), `barLevels(_:barCount:)` (6→4: [[0,1],[2],[3],[4,5]]), `changed(_:_:)` (eşik 0,004), `mode(state:isPlaying:)`, sabitler `publishInterval` 33 ms, `restingLevel` 0,14.
- Yeni `Modules/Media/AudioTap.swift`: `nonisolated final class AudioTapEngine: @unchecked Sendable` — `start() throws -> Double` (örnekleme hızı), `stop()`, `drainBands(into:) -> Bool`; RT thread'de ayırma/bloklayan kilit yok (`os_unfair_lock` trylock, önceden ayrılmış tamponlar); `kAudioHardwarePropertyDefaultOutputDevice` dinleyicisi cihaz değişince tap'i yeniden kurar; yıkım kurulumun tersi.
- Yeni `Modules/Media/AudioMeter.swift`: `@MainActor @Observable final class AudioMeter: EqualizerLevelFeed` — `state: AudioMeterState` (off/unsupported/starting/running/silent/failed(OSStatus)), `setEnabled`, `setPlaying` (2 s debounce), `addLevelObserver(_ owner:_ handler:)` / `removeLevelObserver`; 30 Hz `DispatchSourceTimer` utility kuyruğunda okur, eşik geçilirse `DispatchQueue.main.async { MainActor.assumeIsolated { … } }` ile gözlemcilere iletir (sessizlikte ana thread'de sıfır iş).
- Değişir `Core/Window/EqualizerBars.swift`: `EqualizerMode { resting, dancing, live }`, `EqualizerLevelFeed` protokolü (Core modül tanımaz), `EqualizerBarsView.setLevels(_:)` → her çubuk `CATransaction` (0,05 s linear) ile `transform.scale.y`; gözlemci kaydı `viewDidMoveToWindow`'da (pencereye girince ekle, çıkınca sil).
- Değişir `Modules/Media/MediaController.swift` (`let audioMeter = AudioMeter()`, `updateState` → `audioMeter.setPlaying`, `setVisualizer(enabled:)`), `Modules/Media/Views/MediaViews.swift` (`MediaCompactTrailing` feed + mode), `Settings/SettingsStore.swift` (`visualizerEnabled`), `App/SettingsApplier.swift` (+`appliedAtLaunch`), `Settings/Panes/MediaPane.swift` (bölüm: anahtar, izin durumu, "Gizlilik ayarlarını aç", macOS 14.2 notu), `Settings/Panes/SetupPane.swift` (satır), `project.yml` (`NSAudioCaptureUsageDescription` — **deneyle doğrula**), `scripts/sync-settings-strings.py`.
- Yeni test `MyNotchTests/AudioMeterTests.swift`: bandpass seçiciliği (merkezde ≥20 dB baskın, DC ~0), `level` sınırları ve monotonluk, zarf asimetrisi, 6→4 eşleme, `changed` eşiği, `mode` tablosu.

**Commit noktaları:** (1) `feat(media): add the audio meter rules` → (2) `feat(media): tap the system audio for the level meter` (+`-debugAudioMeter YES` seviyeleri log'a basar; Swift 6 izolasyonu burada kanıtlanır) → (3) `feat(engine): drive the level meter from real audio` → (4) `feat(settings): add the visualizer toggle` → (5) `docs(plan): record the visualizer decision`.

**Doğrulama:** `defaults write com.emre.mynotch visualizerEnabled -bool YES && scripts/run.sh --args -debugState compact -onboardingCompleted YES`; Spotify çalarken `screencapture -x -R 704,0,320,60` (iki kare, çubuklar ses seviyesini izlemeli); `scripts/measure-idle.sh 30` hedef ≤ %2 (tap dahil); `tccutil reset AudioCapture com.emre.mynotch` ile izin akışı; `/usr/bin/log stream --predicate 'subsystem == "com.apple.TCC"' --info` ile gerçek servis adı. Elle: ses kısılınca çubuklar tabana iner; izin reddinde dans devreye girer; duraklamada 2 s içinde tap kapanır.

**Riskler → fallback:** macOS 14.0–14.1 → `.unsupported` → dans; TCC reddi / ad-hoc imza grant'i düşürür → `.silent` → dans + pane'de derin link; aggregate kurulumu hatası → `.failed`, 30 s sonra tek yeniden deneme; 30 Hz yayın CPU yerse 20 Hz.
**Canlı deney gereken:** Info.plist anahtarı/TCC servis adı; Gizlilik derin linki (macOS 26 "Audio Recording" bölmesi); IO block'un Swift 6 `complete` altında derlenmesi. Karar: expanded kartta ek çubuk yok (yalnızca compact 4 çubuk).

### 17.3 B. Generic now-playing sağlayıcısı — mediaremote-adapter (`genericPlayerEnabled`, varsayılan kapalı)

**Yol:** BSD-3 artefaktlar (`MediaRemoteAdapter.framework`, `mediaremote-adapter.pl`, `MediaRemoteAdapterTestClient`) `references/` klonundan **clang** ile derlenir (cmake yok), `Vendor/mediaremote-adapter/` altında commit'lenir, `.app`'e gömülür; `/usr/bin/perl <pl> <framework> [testclient] <komut>` ile tek uzun ömürlü `stream` süreci (JSON satırları `{type, diff, payload}`), kısa ömürlü `get/send/seek/test`. Spotify/Music'e ait kaynaklarda generic **susar** (S4).

**Dosyalar**
- Yeni `scripts/vendor-mediaremote-adapter.sh`: klon SHA `3ac3d4b` kontrolü; framework için `src/adapter/*.m` + `src/private/MediaRemote.m` + `src/utility/{Debounce,helpers}.m` → `clang -arch arm64/x86_64 -dynamiclib -fobjc-arc -fvisibility=default -mmacosx-version-min=14.0 -Iinclude -Isrc -framework Foundation -framework AppKit -framework UniformTypeIdentifiers -install_name @rpath/…` → `lipo`; `Versions/A/{binary,Resources/Info.plist,Headers}` + symlink'ler; test client `src/test/{main,NowPlayingTest}.m -framework MediaPlayer`; `codesign --force --sign - --deep`; `.pl` olduğu gibi (0644); `MANIFEST.txt` (URL, SHA, sha256'lar, clang/sw_vers).
- Yeni `Vendor/mediaremote-adapter/…` (git'e girer) + `project.yml` (framework `embed: true, codeSign: true, link: false`; `.pl` ve test client `buildPhase: resources`) — **deney:** XcodeGen bu fazları doğru yerlere koyuyor mu; değilse `postBuildScript`.
- Yeni `Modules/Media/Generic/MediaRemoteAdapterProcess.swift`: `Paths.bundled()` (saf), `Command { get, stream(debounceMS:includeArtwork:), send(MediaRemoteCommand), seek(microseconds:), test }`, `static arguments(_:_:)` (saf; `FRAMEWORK [TEST_CLIENT] FUNCTION [OPTIONS]`, `--micros/--no-diff/--human-readable` asla), `run(_:timeout:) async throws`, `lines(debounceMS:includeArtwork:) -> AsyncStream<AdapterLine>` (`payload/diagnostic/exited`), `terminate()` (SIGTERM + waitUntilExit), `static killOrphans(scriptPath:)`; `LineAccumulator` (yarım/çoklu satır), `MediaRemoteCommand: Int` (0 play … 13), `adapterMicroseconds(_:)`.
- Yeni `Modules/Media/Generic/NowPlayingSnapshot.swift`: `AdapterValue`, `AdapterEnvelope.decode` (`"null"` satırı → nil = medya yok), `AdapterPayload.apply` (diff merge, `null` siler, kimlik değişimi → parça değişti, aynı parçada artwork korunur), `NowPlayingSnapshot(payload:)` (zorunlu `processIdentifier`, boş olmayan `title`, `playing`; `bundleIdentifier` → `parentApplicationBundleIdentifier` → jenerik ikon), `mediaState(providerID:providerName:now:)` (`elapsed + (now − timestamp) × playbackRate`).
- Yeni `Modules/Media/Generic/GenericNowPlayingProvider.swift` (`@MainActor final class`, `MediaProvider`): `fetch()` hafızadaki snapshot'ı verir (süreç açmaz), `changeTicks() -> AsyncStream<Void>` push seam'i, `prepareArtwork(destination:)` base64'ü dosyaya yazar (ArtworkCache accent'i çıkarır), `precisePosition()` `elapsed@timestamp`, komutlar `actor AdapterCommandQueue` (seri, aynı türden bekleyen komut son gelenle değişir), `isRunning()` = bayrak ∧ sağlık ok ∧ stream canlı ∧ kaynak AppleScript sağlayıcısına ait değil; `exit != 0` → **yeniden başlatma yok**, `broken(code)`; `GenericSourceRules.isOwnedByScriptProvider/sourceName` (saf).
- Yeni `Modules/Media/Generic/AdapterHealthCheck.swift`: `test` (10 s timeout) yalnızca ilk etkinleştirme + OS build/uygulama sürümü değişimi + elle "Yeniden dene"; `AdapterHealthRecord { status, osBuild, appVersion, checkedAt }` storedValue codec'i; `AdapterHealth { ok, noTestClientPath, testClientFailed, setupTimeout, noData, broken(exitCode:), artefactsMissing, timedOut }`.
- Değişir `Modules/Media/MediaProvider.swift` (`changeNotification: Notification.Name?` + `changeTicks()` varsayılan nil), `MediaController.swift` (`start()` push seam'i; generic sağlayıcı listede sona; `setGenericPlayer(enabled:)`, `recheckGenericPlayer()`, `genericHealth`; boş bundle id'li sağlayıcıları workspace gözleminden süz), `SpotifyProvider/AppleMusicProvider` (opsiyonel tip), `Settings` (anahtar `genericPlayerEnabled` + `genericPlayerHealth`; `MediaPane` bölümü: anahtar, durum, "Yeniden dene"; `SetupPane` satırı), `THIRD_PARTY_LICENSES.md` (BSD-3 tam metin, SHA, "bundle edildi, adapte edilmedi"), `CLAUDE.md` (Vendor kuralı), `docs/PLAN.md` §13 (+ `/usr/bin/perl` kalkabilir; ek Mach-O'lar notarization'a girer). `MediaModule.swift` değişmez (pill = `displayName` + bundle id ikonu).
- Yeni test `MyNotchTests/MediaRemoteAdapterTests.swift`: argüman sırası/bayraklar; `LineAccumulator` (yarım satır, 3 satır tek okumada, 400 KB base64); `AdapterEnvelope.decode` (`null`, boş payload, bozuk JSON throw); `AdapterPayload.apply` (merge/silme/kimlik/artwork koruma); `NowPlayingSnapshot` (bundle id fallback zinciri, boş title, ISO-8601 kesirli, `playbackRate <= 0`); `GenericSourceRules` (`com.spotify.client`/`com.apple.Music` sus, `com.apple.Safari` geç, parent id); `adapterMicroseconds`; `AdapterHealthRecord` codec + exit kodu eşlemesi.

**Commit noktaları:** (1) `chore(vendor): build the mediaremote-adapter artefacts` → (2) `feat(media): run the mediaremote adapter` (sarmalayıcı + decode + testler) → (3) `feat(media): add the generic now-playing provider` → (4) `feat(media): check the adapter's health before using it` → (5) `feat(settings): add the system-wide player toggle` → (6) `docs(plan): record the generic provider decision`.

**Doğrulama:** `scripts/vendor-mediaremote-adapter.sh`; duman testi `/usr/bin/perl "$PL" "$FW" get | head -c 400` (Safari'de YouTube çalarken), `… stream --debounce=250 | head -5`, `… "$TC" test; echo $?`; `scripts/build.sh && ls build/Build/Products/Debug/MyNotch.app/Contents/{Frameworks,Resources} | grep -i mediaremote`; `defaults write com.emre.mynotch genericPlayerEnabled -bool YES` + `scripts/run.sh --args -debugState expanded -debugModule media -onboardingCompleted YES` + `screencapture -x -R 384,0,960,300` (Safari ikonlu pill + kart); `scripts/measure-idle.sh 30` + `top -pid $(pgrep -f mediaremote-adapter.pl)` (perl CPU ayrı ölçülür). Elle: Spotify çalarken generic susar; bayrak kapatılınca `pgrep -f mediaremote-adapter.pl` boş; `kill -9` sonrası yeniden açılışta öksüz perl kalmaz.

**Riskler → fallback:** `test` başka uygulamalara sahte kayıt sızdırır → yalnızca ilk etkinleştirme/sürüm değişimi/elle; private API kesildi → yeniden başlatma yok, AppleScript devralır; `/usr/bin/perl` kalkar → `artefactsMissing`; hızlı komutlar → seri kuyruk; notarization → release'de inside-out Developer ID imzası.
**Canlı deney gereken:** XcodeGen embed/resources fazları; perl'in üçüncü taraf framework yüklemesinde library validation; gecikme/CPU/RSS ölçümleri (`--debounce` optimumu); `ejbills` fork'unun SPM olup olmadığı (plan buna bağımlı değil); yabancı `test` çalıştırmalarının stream'e düşürdüğü hata satırları.

**Sonuç (2026-09-06):** XcodeGen `embed: true, codeSign: true, link: false` framework'ü `Contents/Frameworks`'e, `buildPhase: resources` `.pl` ve test client'ı `Contents/Resources`'a koydu (exec biti korundu) — `postBuildScript` gerekmedi. Ad-hoc imzalı framework'ü `/usr/bin/perl` sorunsuz yükledi (`get`, `stream`, `test` çalıştı; sağlık `ok`, macOS 26.6.2). Boşta perl %0,0 CPU / 6,5 MB RSS (`--debounce=250`, artwork açık). Yaşam döngüsü testleri §17.7'de. Fork (`ejbills`) incelenmedi — plan bağımlı değil, harvest S1 açık kalır. Yabancı `test` hata satırı ilk çalıştırmalarda görülmedi; stderr satırları `mediaremote-adapter` kategorisinde info olarak loglanır.

### 17.3 C. Dört yeni modül — Battery · Shelf · Calendar · Pomodoro

Ortak: her modül `Modules/<Ad>/` altında (`<Ad>Module.swift`, servis/store, `<Ad>Rules.swift` saf + testli, `Views/`), `activity` **hiçbir modülde `.urgent` döndürmez** (kesintiler yalnızca `context.post(event)`; `ModuleResolver.acceptsPopup` yalnızca `isEnabled` ister → idle modül de popup atabilir), popup gövdeleri metin (`NotchPopupLine`), kompakt kanatlar `@Environment(\.wingContentSize)`, ambient animasyon CA, hover açıklamaları kart içinde.

**Önce ortak yardımcı (adım 1):** `Core/Window/NotchSpotlight.swift` — `Spotlight<Element: Hashable>`, `Reveal`, kart içi açıklama balonu, `Modules/ClaudeUsage/Views/ClaudeUsageViews.swift`'teki `private` kopyalardan genelleştirilir; Claude kartı bunu kullanır (davranış aynı). Dört kart "hover → öne çık + kart içinde cümle" desenini kopyalamadan alır.

**Kayıt sırası ve öncelikler** (`App/AppDelegate.swift`; sıra = şerit sırası + hiçbir şey canlı değilken hover hedefi): claude 5 (ilk kalır) → media 10 → calendar 7 → pomodoro **8** (müziğin altında: kullanıcı müzik şeridine çok yatırım yaptı; istenirse tek sayı ile 12'ye çekilir) → battery 6 → shelf 4 → DEBUG demo 0.

#### C1. Battery — `Modules/Battery/` (izin yok, motor değişikliği yok)
- **Veri:** `IOKit.ps` — `IOPSNotificationCreateRunLoopSource` (ana run loop), her bildirimde `IOPSCopyPowerSourcesInfo/List/GetPowerSourceDescription`; anahtarlar `kIOPSIsChargingKey`, `kIOPSCurrentCapacityKey`, `kIOPSMaxCapacityKey`, `kIOPSTimeToFullChargeKey`, `kIOPSTimeToEmptyKey` (−1 = hesaplanıyor → nil), `kIOPSPowerSourceStateKey`; düşük güç modu `ProcessInfo.isLowPowerModeEnabled` + `NSProcessInfoPowerStateDidChange`. Timer yok; iç pil yoksa `start()` hiçbir şey kaydetmez, `isAvailable false`.
- **Davranış:** compact yalnızca şarjda **veya** ≤ düşük eşik (`live`): sol `PulsingSymbol("bolt.fill", isActive: isCharging)`, sağ yüzde (`numericText`). Kart: solda büyük pil grafiği (yüzdeye göre dolgu, veri değişiminde tek seferlik spring; renk yeşil/sarı/kırmızı), sağda durum / tahmin (`1s 20dk dolar`, `4s 10dk kaldı`, yoksa —) / düşük güç modu; spotlight açıklamaları.
- **Popup'lar:** adaptör takıldı/çıktı 2,5 s; ≤%20 ve ≤%10 4 s (geçiş başına bir kez, `BatteryAlertMemory`: şarj başlayınca ya da eşik+%5 üstüne çıkınca yeniden silahlanır); tam doldu 2,5 s; düşük güç modu değişti 2 s.
- **Dosyalar:** `BatteryModule.swift` (`id "battery"`, `priority 6`, `alertsEnabled`), `BatteryService.swift` (`@MainActor @Observable`; IOKit C callback için `nonisolated final class PowerSourceObserver` + `MainActor.assumeIsolated`), `BatteryState.swift` (`BatterySnapshot`, `BatteryThresholds`), `BatteryRules.swift` (`parse(powerSource:lowPowerMode:)` sözlükten — testli; `activity`, `alerts(previous:current:thresholds:memory:)`, `formatTime`, `fillLevel/color`, `statusTitle`), `Views/BatteryViews.swift`.
- **Ayarlar:** `batteryLowThreshold` 0,20 (0,10…0,35), `batteryCriticalThreshold` 0,10 (0,05…0,25, `critical ≤ low − 0,05`), `batteryAlertsEnabled`; `BatteryPane`.

#### C2. Pomodoro — `Modules/Pomodoro/` (izin yok)
- **Davranış:** compact sol `CountdownArc` (CA) + faz glifi (`timer` / `cup.and.saucer.fill`), sağ kalan **dakika** (dakika sınırında uyanan tek `Task`); kart: büyük halka + `mm:ss` (`TimelineView(.periodic(by: 1))` yalnızca kart görünürken), `notchTap` denetimleri Başlat/Duraklat · Atla · Sıfırla, tamamlanan tur noktaları (4'te bir uzun mola), spotlight açıklamaları. Ekran her zaman `isAvailable: true` (notch tek kontrol yüzeyi).
- **Animasyon:** `Views/CountdownArc.swift` — `NSViewRepresentable` + `CAShapeLayer`, `CABasicAnimation(strokeEnd)` `duration = kalan süre`, linear, `isRemovedOnCompletion false`; duraklatmada animasyon kaldırılır ve oran sabitlenir → per-frame yok.
- **Dosyalar:** `PomodoroModule.swift` (`id "pomodoro"`, `priority 8`), `PomodoroTimer.swift` (`phase`, `endDate`, `isPaused`, `completedWorkCount`, `config`, `start/pause/resume/skip/reset`, tek `Task.sleep(until: endDate)`, `didWakeNotification`'da yeniden kurulum), `PomodoroState.swift` (`PomodoroPhase { idle, work, shortBreak, longBreak }`, `PomodoroConfig`, `PomodoroSnapshot: Codable`), `PomodoroStateStore.swift` (çalışma durumu ayar değil → kendi `pomodoroState` JSON anahtarı, `preferredModuleID` emsali), `PomodoroRules.swift` (`nextPhase`, `duration`, `remaining`, `progress`, `format` → `"12:34"`, `restore(snapshot:now:config:)` — kapalıyken biten faz bir kez duyurulur, `autoStart`'a göre devam/bekle; `phaseEndEvent`, `activity(phase:isPaused:)`), `Views/PomodoroViews.swift`.
- **Popup'lar:** faz sonu 4 s (`"Work done — take 5 minutes"` / `"Break over"`), `pomodoroSoundEnabled` ise `NSSound(named: "Glass")`.
- **Ayarlar:** `pomodoroWorkMinutes` 25 (5…90), `pomodoroBreakMinutes` 5 (1…30), `pomodoroLongBreakMinutes` 15 (5…60), `pomodoroLongBreakEvery` 4 (2…8), `pomodoroAutoStart` false, `pomodoroSoundEnabled` true; `PomodoroPane`.

#### C3. Calendar — `Modules/Calendar/` (EventKit, salt okuma, opt-in)
- **Veri:** `EKEventStore.authorizationStatus(for: .event)` istem çıkarmaz; `requestFullAccessToEvents()` **yalnızca** Setup/Calendar panesinde "Erişim ver"e basılınca. `project.yml` → `NSCalendarsFullAccessUsageDescription`. Yenileme: `.EKEventStoreChanged` + `NSWorkspace.didWakeNotification` + `NSCalendarDayChanged` + `CalendarRules.nextBoundary` ile **tek** sınır zamanlayıcısı (`Task.sleep(until:)`); periyodik poll yok. Sorgu `predicateForEvents(withStart: now, end: now+36h, calendars: seçilenler)`; tüm-gün ve reddedilenler süzülür; ilk 3.
- **Davranış:** compact yalnızca sıradaki toplantı `calendarLeadMinutes` (15) içindeyse: sol sağlayıcı glifi (`video.fill`/`calendar.badge.clock`), sağ geri sayım (`12dk`, `4dk`, `şimdi`) dakika sınırında güncellenir. Kart: yatay zaman şeridi (takvim renginde bloklar), ilkinin başlığı büyük, saat aralığı + takvim adı, `joinURL` varsa `notchTap` "Katıl" (`NSWorkspace.open`), spotlight; etkinlik yoksa "Bugün toplantı kalmadı". Popup'a hover → motor kuralıyla takvim kartı açılır.
- **Popup'lar:** 5 dk kaldı 4 s, başlangıç 6 s; etkinlik id + sınır anahtarlı hafıza (tekrar yok).
- **Dosyalar:** `CalendarModule.swift` (`id "calendar"`, `priority 7`, `screens` `appBundleIdentifier "com.apple.iCal"` → gerçek Takvim ikonu, `isAvailable: service.hasAccess`), `CalendarService.swift`, `CalendarEvent.swift` (`CalendarEvent`, `CalendarAccess { notDetermined, authorized, denied, restricted }`, `MeetingProvider { zoom, meet, teams, webex, other }`), `CalendarRules.swift` (`joinURL(url:location:notes:)` host beyaz listesi `zoom.us`, `meet.google.com`, `teams.microsoft.com`, `teams.live.com`, `webex.com`; `provider(for:)`, `activity`, `boundaries`, `nextBoundary`, `countdownText`, `popupEvent`, `visible(events:selectedIDs:now:)`), `Views/CalendarViews.swift`.
- **Ayarlar:** `calendarLeadMinutes` 15 (1…60), `calendarSelectedIDs` [] (= hepsi), `calendarAlertsEnabled`; `CalendarPane`; Setup satırı üç ton + `SystemSettingsLink.calendars` (`…?Privacy_Calendars`); izin sıfırlama `tccutil reset Calendar com.emre.mynotch`.

#### C4. Shelf — `Modules/Shelf/` + tek motor dikişi (en riskli; en sona)
- **Önce deney turu (kod commit'i yok, sonuç `docs/harvest/NotchDrop.md` §6'ya yazılır):** E-1 SwiftUI `onDrop` `.nonactivatingPanel` içinde `isTargeted/performDrop` veriyor mu; E-2 AppKit yolu `NotchHostingView.registerForDraggedTypes([.fileURL])` + `draggingEntered/Updated/performDragOperation` (600×280 panel masaüstüne giden sürüklemeyi kaçırmamalı → `NotchLayout.dropZoneRect` kapısı); E-3 0,001 alfalı 32 pt dedektör menü bar tıklamasını yiyor mu; E-4 `Transferable` + `.draggable` ile key olmayan panelden dışarı sürükleme; E-5 `NSSharingService(named: .sendViaAirDrop)?.perform` ve `NSSharingServicePicker` key pencere ihtiyacı (B planı 1×1 geçici key pencere `ShelfShareAnchorWindow`, en son menü bar yolu); E-6 `~/Desktop`/`~/Downloads`'tan bırakılan dosya kopyalanırken TCC istemi (gerekirse üç klasör usage description'ı); E-7 `NSSharingService(named:)` deprecated uyarısı (`@available(macOS, deprecated: 13.0)` sarmalayıcı).
- **Motor dikişi (Core modül-agnostik kalır):** `NotchModule.acceptsDrops: Bool` (extension'da false); `NotchContentProvider.dropTargetModuleID: () -> String?` + `beginDrop: () -> Void`; `ModuleManager.contentProvider()` doldurur (`modules.first { $0.isEnabled && $0.acceptsDrops }`, `beginDrop` → `model.expand`); yeni `Core/Window/NotchDropDetector.swift` (`// Adapted from Lakr233/NotchDrop (MIT)`: `Color.black.opacity(0.001)` + `.contentShape(Rectangle())` + `.onDrop(of: [.item], isTargeted:) { _ in false }` — yalnızca hedeflenme; `NotchRootView` `state.isResting` ∧ `dropTargetModuleID != nil` iken yüzeyin arkasına koyar). Aşamalı: (a) dedektör çizili yüzey kadar (notch'lu ekranda kapalı yüzey opak, menü bar etkilenmez); (b) 32 pt taşma (`NotchLayout.dropDetectorMargin`) yalnızca aktif sürükleme oturumunda — oturum tespiti `NSPasteboard(name: .drag).changeCount` + `leftMouseDown` monitörü **yalnızca Shelf etkinken** (`mouseMoved` asla). `NotchLayout.dropZoneRect(panelFrame:metrics:state:margin:)` saf + testli. Çentiksiz ekranda kapalı yüzey `.zero` → sürükleyerek açma yalnızca compact'ta (bilinen sınır).
- **Davranış:** bırakma dosyayı **kopyalar** (`~/Library/Application Support/MyNotch/Shelf/<uuid>/<dosya>` + `index.json`; önizleme `<uuid>/preview.png` `QLThumbnailGenerator` ile arka planda), popup "3 dosya rafta" 2 s; `activity` bırakmadan sonra **120 s `live`**, sonra idle (notch gün boyu şişkin kalmasın); ekran `isAvailable: !items.isEmpty`. Kart iki bölge: solda ~130 pt AirDrop hedefi (`dot.radiowaves.right`, `canPerform` false ise soluk + neden), sağda `LazyVGrid` raf; `ShelfItemView`: önizleme, ad, `.draggable(item)`, hover'da `×`, Option-tıklama (`NSEvent.modifierFlags` tıklama anında) siler (kopya da), `notchTap` → kart kapanır + `NSWorkspace.open`. Süre dolumu `shelfKeepInterval` (24 sa; seçenekler 1 sa/12 sa/24 sa/48 sa/1 hafta/sonsuz) — temizlik modül açıldığında ve her bırakmada, timer yok.
- **Dosyalar:** `ShelfModule.swift` (`id "shelf"`, `priority 4`, `acceptsDrops = true`), `ShelfStore.swift` (`@MainActor @Observable`: `items`, `keepInterval`, `load`, `accept(_ providers:)`, `accept(urls:)`, `remove`, `removeAll`, `purgeExpired(now:)`, `totalBytes`), `ShelfStorage.swift` (`actor`: `copy(from:id:)`, `makeThumbnail(for:)`, `delete`, `purge`, `size`, `readIndex/writeIndex`), `ShelfItem.swift` (`Codable`, `Transferable` `FileRepresentation`), `ItemProviderLoader.swift` (`withCheckedThrowingContinuation`; semafor yok), `ShelfShare.swift` (`canAirDrop`, `airDrop`, `showPicker`, gerekirse anchor pencere), `ShelfRules.swift` (`activity(itemCount:lastDropAt:now:)`, `shouldClean`, `uniqueFileName`, `formatBytes`, `badgeText`, `dropEvent`, `keepIntervalTitle`), `Views/ShelfViews.swift`; `THIRD_PARTY_LICENSES.md` NotchDrop bölümü.
- **Ayarlar:** `shelfKeepInterval` 86400 (`shelfKeepIntervalChoices`), `shelfDragToOpenEnabled` true; `ShelfPane`; Setup satırı (depo yolu, boyut, "Finder'da göster", "Rafı boşalt").
- **Düşüşler:** `onDrop` çalışmazsa AppKit yolu; o da olmazsa raf yalnızca Finder/menü barından beslenir ve özellik ertelenir; dedektör menü bar tıklamasını yerse taşma yalnızca sürükleme oturumunda; picker key pencere isterse anchor pencere → menü bar yolu.

#### C5. Ayarlar / kurulum / yerelleştirme (dört modül için)
- `SettingsKey` + `SettingsRules` (`batteryThresholds(low:critical:)`, `pomodoroConfig(...)`, `shelfKeepInterval(_:)`, aralıklar) + `SettingsApplier` dalları; `ModuleCatalog` (`battery` `"battery.100percent.bolt"`, `shelf` `"tray.full.fill"`, `calendar` `"calendar"`, `pomodoro` `"timer"` + özetler). Dördü varsayılan **açık** (hiçbiri kendiliğinden görünmez).
- `SettingsTab` + `SettingsView`: yeni sekmeler `calendar`, `battery`, `pomodoro`, `shelf` (Medya/Claude emsali: modül başına pane); sıra general, modules, media, claude, calendar, battery, pomodoro, shelf, setup, about.
- `SetupPane`: "Takvim" bölümü (izin satırı), "Raf" satırı. `project.yml`: `NSCalendarsFullAccessUsageDescription` (+ E-6 sonucuna göre klasör anahtarları).
- Metinler `L()` → `scripts/sync-settings-strings.py` tablosu; `*Rules` içindeki interpolasyonlu metinler Claude emsali gibi `String(localized:defaultValue:bundle:)` + `App/Localizable.xcstrings`'e elle.
- Testler: `BatteryRulesTests` (sözlükten parse: şarjda/AC/−1/eksik anahtar/masaüstü; activity; alert memory; süre biçimi), `PomodoroRulesTests` (4 iş → uzun mola, `restore` geçmiş endDate × autoStart, format, clamp), `CalendarRulesTests` (joinURL dört sağlayıcı + reddedilen, nextBoundary, activity, tüm-gün/reddedilen filtresi), `ShelfRulesTests` + `ShelfStoreTests` (geçici dizin, `addTeardownBlock`; kopyalama + index gidiş-dönüş + purge), `NotchLayoutTests.dropZoneRect`, `ModuleManagerTests` (`dropTargetModuleID`, `beginDrop`), `SettingsStoreTests` (yeni anahtarlar).
- Doğrulama: `scripts/run.sh --args -debugState expanded -debugModule battery|pomodoro|calendar|shelf -onboardingCompleted YES` + `-debugState popup -debugModule <id>`; `screencapture -x -R 384,0,960,300`; `scripts/measure-idle.sh 30` (kapalı/compact/kart); pil eşiği `defaults write com.emre.mynotch batteryLowThreshold 0.95`; `sudo pmset -a lowpowermode 1`; `pomodoroWorkMinutes 1`; Calendar.app'te 6 dk sonrasına Zoom linkli etkinlik; Finder'dan sürükleme; Debug Preview "Test popup".

### 17.3 D. Native JSONL parser — hibrit maliyet (`Modules/ClaudeUsage/`)

**Karar:** token / 5 saatlik blok / burn rate / model kırılımı **yerel** hesaplanır; dolar `ccusage claude daily --json --since <bugün> --offline` (0,9 sn) ile gelir ve yerel sayıların üzerine **merge** edilir. `blocks` çağrısı (2,8 sn, 300 MB okuma) kalkar. ccusage yoksa yalnızca `$` çipi "—" olur; kartın geri kalanı çalışır. Ölçülen zemin (bu Mac): 528 MB / 283 `.jsonl`; canlı oturum 61 MB, satır başı ~12,6 KB; `"usage":{` içeren satır %28 (byte ön-filtresi %72 decode'u siler); son 8 MB kuyruk yalnızca 3,5 saat geriye gidiyor (kademeli genişletme şart); `costUSD` hiç yok (native maliyet imkânsız → hibrit doğru); `usage.cache_creation {ephemeral_5m, ephemeral_1h}` var; `usage.iterations[]` toplanmaz (çift sayım); `subagents/agent-*.jsonl` = `isSidechain: true`, aynı `sessionId`, farklı `message.id` (gerçek kullanım, sayılır); dosya başındaki `file-history-snapshot` satırları iç `timestamp` taşır (byte ile ilk timestamp aramak yanlış).

**Dosyalar (yeni):** `SessionLogParser.swift` (`RawEntry` DTO'ları elle `CodingKeys` + `decodeIfPresent`; `usageMarker = "\"usage\":{"` ön-filtresi; `parse(_:fromStart:since:) -> LogChunk {entries, titles, tail}`; `entry(from:decoder:)`), `UsageLedger.swift` (`actor`: `FileState {size, offset, entries}`, `chunkBytes` 2 MB, `perFileCap` 64 MB, `maxEntries` 50 000; `warmStart(roots:now:)`, `ingest(_:now:)`, `resync(roots:now:)`, `snapshot(now:)` → `LedgerSnapshot {entries (dedupe edilmemiş, sıralı), titles, tail, isAnchored, bytesRead}`), `BlockCalculator.swift` (`floorToHour` **UTC**, `identifySessionBlocks(_:now:duration:)`, `burnRate`, `projection`), `UsageAggregator.swift` (`dedupe`, `report(_:now:calendar:cost:) -> CCUsageReport`), `CostAllocator.swift` (`CostTable {totalUSD, perModelUSD, asOf}`, göreli ağırlıklar input 1 / output 5 / cacheWrite 1,25 / cacheRead 0,1; `scales`, `cost`). Başlıklar: `// Adapted from https://github.com/ccusage/ccusage (MIT)` (parser/blok/aggregate) ve `// Adapted from https://github.com/stevemcqueenz/claude-notch-tracker (MIT)` (ledger).
**Değişen:** `CCUsageReport.swift` (+`costSource: CostSource { unavailable, ccusage(asOf:) }`, memberwise init'ler), `CCUsageRunner.swift` (`blocksCommand`/`report(using:)` gider, `daily(using:configDirectory:now:)` gelir), `ClaudeUsageService.swift` (ledger + kadans; `logsChanged` içindeki 64 KB tail okuması kalkar, `SessionTail` ledger'dan gelir), `Views/ClaudeUsageViews.swift` (`tokens`/`pace` çipleri her zaman; `spend` çipi `.ready` → tutar, `.notInstalled` → `"—"` + caption `ccusage`, `.failed` → uyarı), `Settings/Panes/ClaudePane.swift` + `SetupPane.swift` (metin: "Yalnızca dolar gizli kalır; token, blok ve hız yerel okunur"), `App/Localizable.xcstrings` + sync script, `THIRD_PARTY_LICENSES.md`, `docs/harvest/ccusage.md` S7 cevabı. `CCUsageState` aynen kalır.

**Parite kuralları:** geçerlilik `type == "assistant"` + `message.usage`; `version` semver değilse / `sessionId`, `requestId`, `message.id`, `message.model` boş string ise / timestamp parse edilemezse satır düşer (dosya durmaz); cache = `cache_creation` varsa `5m + 1h` yoksa `cache_creation_input_tokens`; `<synthetic>` model breakdown'a girmez; `usage.speed == "fast"` → `-fast` soneki; dedupe **agregasyon anında** (`messageID + requestID + sessionID`, ikinci "requestID'siz" anahtar replay'i yakalar; kazanan: sidechain olmayan → yüksek token → `speed`'li; `messageID` yoksa dedupe yok) → artımlı okuma dedupe'u bozamaz (S7 cevabı: **dedupe kalıcılaştırılmaz**); bloklar `sinceStart > 5 sa || sinceLast > 5 sa` → kapanır, `sinceLast > 5 sa` → `gap-<id>`; aktif `now − son < 5 sa && now < end`; burn/projection yalnız aktif blokta, süre ilk↔son entry dakikası, indicator = input+output; `todayBlocks` = `startTime` yerel günü bugün, gap'siz, sıralı; **bilinçli sapma:** `activeBlock` filtrelenmemiş kümeden (00:30'da dün 21:00'de başlayan aktif blok kaybolmaz — testle sabitlenir); günlük gruplama yerel takvim günü.

**Artımlı okuma ve bellek:** offset + size; `size < cachedSize` → truncation: o dosyanın entry'leri silinir, 0'dan okunur; daima son tam satıra kadar. Soğuk başlangıç: `projects/**` (subagents dahil) `mtime ≤ 36 sa` dosyalar; sondan 2 MB kademelerle geriye, en eski entry `< cutoff` (`min(startOfToday − 8 sa, now − 30 sa)`) ya da `perFileCap`'e kadar → hedef toplam ~20–60 MB, `Task.detached(.utility)` tek sefer. Anchor: en eski tutulan entry'den önce ≥5 sa boşluk kanıtlanmazsa `isAnchored = false` → bir kademe daha (en fazla 3 tur / 7 gün). Budama yalnızca blok sınırında; `timestamp < cutoff` atılır; 48 saattir görülmeyen `FileState` silinir. **Disk cache önerilmiyor** (bayat cache = yanlış rakam); `LedgerSnapshot`/`FileState` `Codable` yazılır, soğuk tarama > 2 sn ölçülürse ayrı commit'le `claude-usage-cache.json` eklenir.

**Kadans:** FSEvents batch → `ledger.ingest` → `rebuild()` (~1–5 ms, debounce yok); `start()` → `warmStart`; sınır zamanlayıcısı `min(activeBlock.endTime, sonraki yerel gece yarısı)` (tavan 15 dk, `SuspendingClock`); uyanma / 10 dk emniyet → `resync` (mtime karşılaştırması); ccusage `daily` eski kadans (aktivite bitiminden 20 sn, çalışırken en geç 120 sn) yalnız launcher varsa. Parsing `actor UsageLedger` içinde, `Sendable` sonuç main actor'a; agregasyon saf, µs.

**Testler (satır içi fixture, `MyNotchTests/ClaudeUsageTests.swift` + yeni dosyalar):** `SessionLogParserTests` (geçerli satır; `cache_creation` vs düz alan; `iterations` toplanmıyor; `<synthetic>`; `version: "dev"`/boş id'ler düşer; bozuk satır diğerlerini düşürmez; `custom-title`; `file-history-snapshot` entry üretmez; marker'sız satır decode edilmez), `BlockCalculatorTests` (09:37 → 09:00 UTC; 5 sa dolumu; gap; aktiflik sınırları; burn rate; süre 0 → nil; projection yalnız aktif), `UsageLedgerTests` (gerçek geçici dosyalar: artımlı append, yarım satır, truncation reset, kademeli tarama cutoff'ta durur, `perFileCap`, blok sınırında budama, iki kökte aynı dosya çift saymaz), `UsageAggregatorTests` (dedupe kazananı, `messageID` yoksa iki kayıt, subagent sayılır, gece yarısı Europe/Istanbul `Calendar` enjekte, `todayBlocks`, dünden başlayan `activeBlock`, breakdown sırası), `CostAllocatorTests` (iki modelli gün toplamı ±%0,5; fiyatsız model 0; `unknown` → `costPerHour nil`), **`UsageParityTests`** (~30 satır sentetik JSONL + geliştirme sırasında `CLAUDE_CONFIG_DIR=<tmp> npx --yes ccusage@20 claude blocks --json --offline` ile bir kez kaydedilmiş beklenen JSON → `id/startTime/endTime/tokenCounts/totalTokens/models` alan alan; testte ağ/Process yok).

**Commit noktaları:** (1) `feat(claude): parse Claude session logs natively` → (2) `feat(claude): compute five-hour blocks and burn rate in Swift` → (3) `feat(claude): keep a ledger of session log entries` → (4) `feat(claude): build the usage report without ccusage` (servis ledger'a geçer, runner `daily`'ye iner, `costSource`, çipler) → (5) `feat(claude): merge ccusage cost into the native report` → (6) `perf(claude): measure the cold scan and idle cost` → (7) `docs(claude): record the native parser decision`.

**Doğrulama:** `scripts/test.sh`; `scripts/run.sh --args -debugState expanded -debugModule claude -onboardingCompleted YES -debugUsageDump YES` (her `rebuild()` sonrası bugünün toplamları + blok listesi `Logger.info`; `warmStart` süresi ve okunan bayt — hedef **< 1,5 sn, < 60 MB**); `npx --yes ccusage@20 claude blocks --json --offline` ve `… daily --json --since $(date +%Y%m%d) --offline` ile blok id/token ve günlük dolar karşılaştırması; `scripts/measure-idle.sh 30` kapalı / Claude çalışırken / kart açık → ≈%0; `ccusagePath`'e geçersiz yol + PATH dışı ile hibrit düşüş (token/blok/hız durur, `$` "—").
**Riskler → fallback:** anchor'lanamayan blok zinciri → pencere 3 tura kadar, `isAnchored` log, son çare ayarda "blokları ccusage ile doğrula"; şema değişikliği → toleranslı decode + atlanan satır sayacı + parite testi + `daily` bağımsız doğrulama; soğuk tarama pahalı → satır dilimleme → disk cache; FSEvents kaçırır → uyanma + 10 dk resync; maliyet dağıtımı sapar (hedef <%5) → `costPerHour`/`projection.totalCost` nil.
**Canlı deney gereken:** S1 yoğun günde `todayBlocks` id paritesi; S2 blok başına maliyet sapması; S3 `warmStart` gerçek süre/MB; S4 JSONL'deki `quotaLimits {rateLimitType, resetsAt, status}` 5 sa halkasına yedek olabilir mi (ayrı iş parçası); S5 eski mtime + yeni entry mümkün mü (resync sayaçlarıyla bir gün izle).

### 17.4 Uygulama sırası (riski düşükten yükseğe; her madde build + test yeşil → commit + push)

| # | İş | Bağımlılık / not |
|---|---|---|
| 1 | `refactor(core): generic spotlight and reveal helpers` (`Core/Window/NotchSpotlight.swift`, Claude kartı adapte) | tüm yeni kartların temeli |
| 2 | **Battery** modülü (C1) + `BatteryPane` | motor değişikliği yok, izin yok |
| 3 | **Pomodoro** modülü (C2) + `CountdownArc` + `PomodoroPane` | `measure-idle` sonucu §17.7'ye |
| 4 | **Native parser** (D) 7 commit | Claude kartına en büyük kazanç; parite testi |
| 5 | **Calendar** modülü (C3) + `NSCalendarsFullAccessUsageDescription` + Setup satırı | izin akışı elle doğrulanır |
| 6 | **Visualizer** (A) 5 commit | TCC anahtarı + Swift 6 IO block deneyi ilk commit'te |
| 7 | **Generic sağlayıcı** (B) 6 commit | `scripts/vendor-mediaremote-adapter.sh` + XcodeGen kopya fazı deneyi ilk commit'te |
| 8 | **Shelf**: deney turu E-1…E-7 (`docs(harvest): resolve NotchDrop open questions`) → motor dikişi (`feat(core): drag-to-open seam`) → `feat(shelf): …` → `feat(shelf): airdrop and share` | en riskli; E-1/E-2 başarısızsa özellik ertelenir, diğer her şey tamamlanmış olur |
| 9 | `docs(plan): Faz 6 kararları` — `docs/PLAN.md` yeni **§17 Faz 6 planı** (bu bölüm + §17.7 ölçümler), §7 backlog işaretleri, §9 yeni klasörler, §13 yeni riskler (`/usr/bin/perl`, notarization Mach-O'ları), §15 karar satırları (öncelikler, `activity` asla `.urgent`, drop dikişi, raf deposu, pomodoro durum kalıcılığı, hibrit maliyet, tap/CA seviye yolu, Vendor kuralı); `docs/manual-tests.md` "Faz 6"; `CLAUDE.md` (intro "Faz 0–6", Vendor kuralı, drop dikişi, `activity` kuralı, `EqualizerBars.setLevels`); memory güncellemesi | Faz kapanışı |

**Durum (2026-09-06):** 1–8 tamam ve `origin main`'de (spotlight, Battery, Pomodoro, native parser, Calendar, Visualizer, Generic, Shelf); 9 bu commit. Ekran kilitli olduğundan alınamayan görsel doğrulamalar ve sürükleme/izin akışları `docs/manual-tests.md` Faz 6 listesinde.

Toplam ≈ 30 commit; her iş parçası kendi içinde bitmiş ve geri alınabilir. Faz 6 başlarken ilk commit `docs/PLAN.md`'ye §17 planını ekler (bu dosyadan).

### 17.5 Kabul kriterleri (Faz 6 çıkışı)

1. Visualizer ve generic sağlayıcı **kapalıyken** hiçbir ek süreç/tap/timer yok (`pgrep -f mediaremote-adapter.pl` boş; `scripts/measure-idle.sh` kapalı/compact ≈%0).
2. Visualizer açık + müzik çalıyor: çubuklar gerçek sese uyar, CPU ≤ %2 (tap dahil); izin reddinde CA dansına düşer.
3. Generic sağlayıcı açık: Safari/YouTube kaynağı şeritte kendi ikonuyla görünür, Spotify/Music çalarken susar; `test` başarısızsa AppleScript devralır; bayrak kapatılınca perl süreci biter.
4. Claude kartı ccusage **olmadan** token/blok/hız/model gösterir; bloklar `ccusage blocks` ile aynı id/token (parite testi + canlı karşılaştırma); dolar ccusage varsa gelir; `warmStart` < 1,5 sn / < 60 MB; idle ≈%0.
5. Dört modül: pil popup'ları ve eşikler (geçiş başına bir kez), pomodoro sayaç/faz/kalıcılık, takvim geri sayım + 5 dk/başlangıç popup'ı + Katıl, raf sürükle-bırak → kopya → önizleme → AirDrop; hepsi `-debugState expanded -debugModule <id>` görüntüleriyle ve `docs/manual-tests.md` Faz 6 listesiyle doğrulanmış.
6. Türkçe/İngilizce tam; `scripts/sync-settings-strings.py` sıfır eksik; tüm testler yeşil (268 + yeni suite'ler); `THIRD_PARTY_LICENSES.md` NotchDrop (MIT) ve mediaremote-adapter (BSD-3) girdileriyle güncel.

### 17.6 Bilinçli dışarıda bırakılanlar

- Expanded kartta ek visualizer çubukları (compact 4 çubuk yeter); HUD değiştirme (Erişilebilirlik + event tap); Claude hook/socket entegrasyonu (`~/.claude/settings.json` yazımı salt-okunur doktrine aykırı); Spotify token Keychain, Sparkle/notarize, Developer ID imzası → release işi (`macos-release`); mediaremote `shuffle/repeat/speed` komutları; JSONL `quotaLimits` yedeği (S4, ayrı iş parçası).

### 17.7 Ölçümler

| Tarih | Ne | Sonuç |
|---|---|---|
| 2026-09-06 | Native parser soğuk başlangıç (`-debugUsageDump YES`, 528 MB / 283 dosya arşiv) | 767 entry, **39,7 MB** okundu (hedef < 60 MB), zincir anchor'landı |
| 2026-09-06 | **Parite** — native vs `npx ccusage@20 claude blocks/daily --json --since bugün --offline` | Blok id'leri ve token sayıları **birebir**: `10:00 → 57 052 319`, `15:00 → 31 372 257 (aktif)`; günlük 88 424 576 token; dolar 16,09 $ (ccusage `daily`'den merge) |
| 2026-09-06 | Açık Claude kartı CPU, açılıştan sonraki 16 sn (ledger + ccusage + açılış animasyonu dahil) | ort. %3,0, tepe %23,6; yerleşmiş durumda ≈%0 (§16.4 ile aynı) |
| 2026-09-06 | Battery/Pomodoro kartları | render doğrulandı (pil); pomodoro görsel doğrulaması ekran kilitliyken alınamadı — manuel listede |
| 2026-09-06 | Generic sağlayıcı — gömme ve sağlık | Framework/`.pl`/test client doğru fazlarda gömüldü; `test` exit 0 → `genericPlayerHealth = ok\|26.6.2\|0.1.0/1\|…`; adaptör Edge/YouTube öğesini (`com.microsoft.edgemac`, duraklatılmış) 3 sn içinde bildirdi (`log … category == "mediaremote-adapter"` → "adapter item: …") |
| 2026-09-06 | Generic sağlayıcı — CPU/RSS | perl `stream` boşta **%0,0 / 6,5 MB**, MyNotch %0,0 / 90 MB (kart açık, `--debounce=250`, artwork açık). Parça değişiminden ilk satıra gecikme ölçülemedi (o an yalnızca duraklatılmış öğe vardı) → manuel liste |
| 2026-09-06 | Generic sağlayıcı — yaşam döngüsü | Bayrak kapalı → `pgrep -f mediaremote-adapter.pl` boş (açılış süpürmesi önceki öksüzü de temizledi); bayrak açık → tek perl; `pkill -x MyNotch` (SIGTERM) → çocuk uygulamayla bitti (ilk denemede hayatta kalmıştı: AppKit SIGTERM'i `applicationWillTerminate`'e çevirmiyor → `DispatchSource` ile `NSApp.terminate`); `kill -9` → öksüz kaldı → sonraki açılışta süpürüldü, yeni tek perl. Görsel doğrulama (şeritte tarayıcı ikonu, kart) ekran kilitli olduğundan alınamadı → manuel liste |
| 2026-09-06 | Raf — deney turu | E-5 `NSSharingService(.sendViaAirDrop)` var, `canPerform(dosya) == true` (UI'sız `swiftc` deneyi); E-7 `sendViaAirDrop` deprecated değil (yalnızca sosyal servisler); E-1 yerine E-2 (AppKit hedefi) seçildi — `NSHostingView` `NSDraggingDestination` değil, `NSView` resmen uyuyor, `override` derlendi; E-3 konu dışı (dedektör yalnızca sürükleme oturumunda). E-2/E-4/E-6 canlı sürükleme **kullanıcıda** (sentetik girdi yok) |
| 2026-09-06 | Raf — CPU | Kart açık, sürükleme monitörü kurulu: **%0,01** ort., tepe %0,10 (8 örnek, 79 MB). Depo klasörü ilk bırakmaya kadar oluşmaz |
| 2026-09-06 | Visualizer (process tap) | Swift 6 `complete` altında IO block derlendi; saf kurallar testli. Canlı tap **henüz çalıştırılmadı**: Spotify duraklatılmıştı (tap yalnızca çalarken açılır) ve TCC istemi kullanıcı onayı ister — `docs/manual-tests.md` Faz 6 visualizer maddeleri |
