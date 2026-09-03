# boring.notch — Harvest Notu

| | |
|---|---|
| Repo | https://github.com/TheBoredTeam/boring.notch |
| Klon | `references/boring.notch` @ `99900bf` (2026-08-29) |
| Lisans | GPL-3.0 (`LICENSE`). Güncel README'de ayrı bir lisans bölümü yok, yalnızca `THIRD_PARTY_LICENSES` dosyasına bağlantı var (CC BY-NC-ND ifadesi bu sürümde yok). `THIRD_PARTY_LICENSES` MediaRemoteAdapter için BSD-3 metnini taşır; `private/CGSSpace.swift` Parrot projesinden MPL-2.0 ile alınmış. |
| Devşirme modu | **Sadece davranış — kod kopyalama yok** (tek satır bile alınmaz; alınırsa tüm proje GPL'e döner) |
| İlgili fazlar | 1 (pencere, hover, shape, çoklu ekran), 2 (live activity / popup kavramı), 3 (medya denetleyici mimarisi), 5 (ayarlar, onboarding, dağıtım), 6 (mediaremote-adapter kablolaması), backlog (HUD, shelf, takvim) |

Bu not kod içermez; dosya yolları, sayısal sabitler ve Apple API adları olgu olarak verilir. "Bizde nasıl yapacağız" bölümleri kendi sözleşmelerimize (NotchPanel / NotchState / NotchViewModel / Anim / NotchShape / NotchModule / ModuleManager) göre sıfırdan tasarım tarifidir.

## 1. Bizim için değeri

En olgun ve en çok kullanılan açık kaynak notch ürünü: çoklu ekran, tam ekran davranışı, ~70 ayar anahtarı, medya denetleyici soyutlaması, mediaremote-adapter'ın gerçek dünyadaki kablolaması, HUD değiştirme ve shelf gibi bizim backlog'umuzdaki her özelliğin çalışan bir örneği. Değeri iki yönlü: hangi davranışların kullanıcılar tarafından beklendiğini gösterir (ayar yüzeyi, popup süreleri, tam ekran tercihleri) ve hangi yolların bize kapalı olduğunu netleştirir (özel CGS/SkyLight/CoreBrightness API'leri, Erişilebilirlik gerektiren event tap, 11 SPM bağımlılığı). Ayrıca `ignoresMouseEvents`'i hiç set etmeyip `.onHover` ile çalışması, claude-notch-tracker bulgusunu ikinci bir üründe doğrular.

## 2. İncelenen dosyalar

| Kaynak dosya (path) | Hangi davranışı gösteriyor | Bizde ilgili bileşen | Faz |
|---|---|---|---|
| `boringNotch/boringNotchApp.swift` | Uygulama girişi, `MenuBarExtra`, ekran başına pencere, ekran/kilit değişimi, kısayollar, onboarding tetikleri | `App/MyNotchApp.swift`, `NotchWindowController` | 1, 5 |
| `boringNotch/components/Notch/BoringNotchWindow.swift`, `BoringNotchSkyLightWindow.swift` | Panel stili, seviye, collectionBehavior, ekran kaydından gizleme, kilit ekranı (SkyLight) | `Core/Window/NotchPanel.swift` | 1, 5 |
| `boringNotch/managers/NotchSpaceManager.swift`, `private/CGSSpace.swift` | Özel CGS space ile "her şeyin üstünde" | (alınmaz) | — |
| `boringNotch/observers/FullscreenMediaDetection.swift`, `models/BoringViewModel.swift` | Tam ekran tespiti (MacroVisionKit) ve kapalı notch'u gizleme kararı | `NotchViewModel`, Faz 5 ayarı | 1, 5 |
| `boringNotch/sizing/matters.swift`, `components/Notch/NotchShape.swift` | Ölçü modeli, köşe yarıçapları, yükseklik modları | `NotchLayout`, `NotchShape` | 1 |
| `boringNotch/ContentView.swift` | Hover gecikmesi, kapanış gecikmesi, jestler, live activity yerleşimi, sneak peek/HUD | `NotchRootView`, `NotchViewModel`, `Anim` | 1, 2 |
| `boringNotch/BoringViewCoordinator.swift` | Sneak peek türleri/süreleri, ekran tercihi (UUID), ilk açılış | `ModuleManager`, `NotchEvent`, `SettingsStore` | 2, 5 |
| `boringNotch/models/Constants.swift` | Tüm `Defaults` anahtarları (ayar yüzeyi) | `Settings/SettingsStore.swift` | 5 |
| `boringNotch/components/Live activities/*` | Live activity modifier, sistem olay göstergesi, batarya, inline HUD | `NotchModule.compactLeading/Trailing`, `popupView` | 2, backlog |
| `boringNotch/MediaControllers/*`, `managers/MusicManager.swift`, `helpers/MediaChecker.swift`, `helpers/AppleScriptHelper.swift` | Denetleyici protokolü, MediaRemoteAdapter süreç kablolaması, `test` ile deprecation kontrolü, Spotify/Apple Music bildirim + AppleScript | `Modules/Media/*` | 3, 6 |
| `boringNotch/observers/MediaKeyInterceptor.swift`, `managers/VolumeManager.swift`, `BrightnessManager.swift`, `BoringNotchXPCHelper/*` | HUD değiştirme: event tap, CoreAudio, XPC yardımcısı ile parlaklık | backlog | — |
| `boringNotch/observers/DragDetector.swift`, `components/Shelf/*` | Sürükleme algılama, shelf servisleri, QuickShare | backlog Shelf modülü | 6+ |
| `boringNotch/components/Settings/SettingsView.swift`, `components/Onboarding/*` | Ayar sekmeleri, onboarding akışı | `Settings/`, `Onboarding.swift` | 5 |
| `boringNotch.xcodeproj/project.pbxproj` (paket referansları), `boringNotch.entitlements`, `Configuration/dmg`, `updater/appcast.xml` | Bağımlılıklar, sandbox + istisnalar, DMG ve Sparkle dağıtımı | dağıtım | 5 |

## 3. Davranışlar ve yaklaşımlar

### 3.1 Pencere: NSPanel, seviye ve "her şeyin üstünde" yaklaşımı
**Ne yapıyor:** Borderless + nonactivating + utility + HUD stil maskeli `NSPanel`; `isFloatingPanel`, opak değil, gölge yok, taşınamaz, `canBecomeKey/Main` false; seviye `.mainMenu + 3`; collectionBehavior `[.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`; zorla koyu görünüm; "ekran kaydında gizle" ayarı `sharingType = .none` ile. Pencere ayrıca en yüksek mutlak seviyeli özel bir CGS space'e eklenir (Parrot'tan alınan MPL-2.0 sarmalayıcı), kilit ekranında görünmek istenirse SkyLightWindow paketi ile "delegate" edilir. Pencere boyutu sabit: 640×190 + 20 pt gölge payı; üst-ortaya `setFrameOrigin` ile yerleşir. `ignoresMouseEvents` hiçbir yerde set edilmez.
**Bizde nasıl yapacağız:** Faz 0 paneli zaten aynı ailede (`.screenSaver`, aynı collectionBehavior, `canBecomeKey` false). Alınacaklar: `.utilityWindow`/`.hudWindow` stil bitleri değerlendirilir (görsel etkisi yok, panel semantiği), zorla koyu görünüm (`NSAppearance` darkAqua) siyah şeklin sistem temasından etkilenmemesi için, `sharingType` ile ekran kaydından gizleme opsiyonu (Faz 5). Özel CGS space ve SkyLight **alınmaz**; `.fullScreenAuxiliary` yeterli.
**Dikkat:** İki farklı "üstte kalma" mekanizması (seviye + özel space) birlikte kullanılıyor; biz yalnızca pencere seviyesine güveniriz ve tam ekran jest anındaki kısa gizlenmeyi kabul ederiz (bkz. spitfiresb notu 3.7).

### 3.2 Çoklu ekran ve ekran tercihi
**Ne yapıyor:** İki mod: "tüm ekranlarda göster" (ekran başına bir pencere + bir view model, display UUID ile anahtarlanmış sözlükler) ya da tek pencere (tercih edilen ekran UUID'si `@AppStorage`'da; eski sürümdeki isim tabanlı tercih UUID'ye göç ettirilir; "otomatik ekran değiştir" açıksa `NSScreen.main` izlenir). `didChangeScreenParametersNotification`'da ekran sayısı, UUID kümesi ve frame kümesi karşılaştırılır; değişim varsa pencereler kapatılıp yeniden kurulur; kaybolan ekranların pencereleri silinir. Pencere pozisyonu her ekran için ayrı hesaplanır; alfa 0→1 ile yeniden konumlama sırasında titreme gizlenir. Notch'suz ekranlarda "simüle notch" 185 pt genişlik ve ayarlanabilir yükseklik.
**Bizde nasıl yapacağız:** Faz 1'de `ScreenObserver`: display UUID'yi `CGDisplayCreateUUIDFromDisplayID` (public) ile türeten `NSScreen` uzantısı; `NotchWindowController` ekran başına örneklenebilir (`[UUID: NotchWindowController]`), varsayılan tek ekran (notch'lu → yoksa main). Ayarlar (Faz 5): "ekran seç", "otomatik ana ekranı izle", "tüm ekranlarda göster". Yeniden konumlamada alfa gizleme numarası alınır.
**Dikkat:** Ekran adı yerine UUID kullanımı (aynı isimli iki monitör) doğru ders. Ekran başına ayrı `NotchViewModel` gerekir; `ModuleManager` tek kalır, görünüm durumları ekran başına ayrılır.

### 3.3 Tam ekran davranışı
**Ne yapıyor:** Pencere `.fullScreenAuxiliary` sayesinde tam ekran uygulamaların üstünde kalır; ayrıca `hideNotchOption` ayarı (never / always / nowPlayingOnly, varsayılan nowPlayingOnly) ile **kapalı** notch UI'si o ekranda tam ekran uygulama varken gizlenir: notch'suz ekranda etkin kapalı yükseklik 0'a iner, notch'lu ekranda fiziksel siyah zaten var. Tam ekran tespiti kendi SPM paketleri `MacroVisionKit`'in `FullScreenMonitor.spaceChanges()` akışıyla, ekran UUID'si başına durum ve o Space'teki çalışan uygulamalar (nowPlayingOnly: yalnızca müzik kaynağı tam ekransa gizle). Hover yine açar.
**Bizde nasıl yapacağız:** Faz 1 kabul kriteri "tam ekranda kontroller çalışır" `.fullScreenAuxiliary` ile karşılanır. "Tam ekranda gizle" Faz 5 ayarı olarak eklenir; tespit için public yol: `NSWorkspace.shared.frontmostApplication` + `CGWindowListCopyWindowInfo` ile o uygulamanın ekran boyutunda bir penceresi var mı (ya da menü bar gizliyken `visibleFrame == frame`). Üç seçenekli semantik (asla / her zaman / yalnızca medya kaynağı) iyi bir UX modeli.
**Dikkat:** MacroVisionKit'in içi incelenmedi (klonda yok); özel CGS Space API'lerine dayanıyorsa bizim için kapalıdır.

### 3.4 Hover, gecikmeler ve jestler
**Ne yapıyor:** SwiftUI hover ile çalışır: `minimumHoverDuration` varsayılan 0,3 s (ayarlarda 0–1 s kaydırıcı), `openNotchOnHover` kapatılabilir, `extendHoverArea` hover alanını 30 pt genişletir (sıfır yükseklikte 10 pt), hover başlangıcında haptik (`enableHaptics`); imleç çıkınca 100 ms sonra kapanır (batarya popover'ı ya da paylaşım paneli açıksa kapanmaz). İki parmak dikey kaydırma: aşağı → aç, yukarı → kapat, eşik `gestureSensitivity` 200, kaydırma sırasında notch `gestureProgress` ile hafifçe ölçeklenir (interactive spring response 0,38, damping 0,8). Klavye kısayolları: notch'u aç/kapat (açılınca 3 s sonra otomatik kapanır), sneak peek'i göster.
**Bizde nasıl yapacağız:** `NotchViewModel.hoverDelay` (varsayılan 0,15 s, Faz 5'te kaydırıcı), çıkışta ~100 ms kapanış gecikmesi (imleç sınırda titrerse flicker önler), `Anim.morph` yerine jest sırasında interaktif spring. Dikey iki parmak kaydırma Faz 5 opsiyonu: `NSEvent.scrollWheel` faz + deltaY eşiği (spitfiresb'nin yatay swipe tespiti ile aynı kalıp). Haptik: `NSHapticFeedbackManager` (public), açılma anında bir "tick".
**Dikkat:** 0,3 s varsayılan bize göre uzun; 0,15 s + kullanıcı ayarı planımız geçerli. `.onHover`'ın hızlı imleci kaçırma riski için spitfiresb notu 3.5'teki geometri yaklaşımı yedek.

### 3.5 Şekil ve ölçü modeli
**Ne yapıyor:** `NotchShape(topCornerRadius, bottomCornerRadius)` animatable; kapalı 6/14, açık 19/24 (`cornerRadiusScaling` kapalıysa açıkken de küçük radii). Kapalı genişlik = ekran genişliği − iki yan alan + **4 pt** (kenar antialiasing sızıntısını örtmek için) ya da 185 pt varsayılan; yükseklik modları: gerçek notch yüksekliği / menü bar yüksekliği / özel (32 pt varsayılan); notch'suz ekranlar için ayrı yükseklik ayarı. Şeklin üstüne 1 pt siyah şerit bindirilerek ekran kenarındaki dikiş kapatılır; `hideTitleBar` açıkken menü bar yüksekliği − notch yüksekliği kadar "çene" eklenir. Açık içerik yatay padding'i köşe yarıçapına bağlı.
**Bizde nasıl yapacağız:** `NotchLayout`: kapalı genişliğe 2–4 pt "bleed" (Faz 0'da 0; gerçek cihazda kenar sızıntısı görülürse eklenir), 1 pt üst şerit dersi `NotchRootView`'a, radii setleri DNK (6/14 → 15/20) ve buradaki (6/14 → 19/24) arasında Debug Preview'da seçilir. Yükseklik modları Faz 5 ayarı ("gerçek notch / menü bar / özel").
**Dikkat:** Sabit 185 pt varsayılanı alınmaz (biz aux alanlardan hesaplıyoruz); notch'suz ekranda simüle pill boyutu ayardan gelir.

### 3.6 Live activity (compact) kavramı
**Ne yapıyor:** Kapalı notch'un iki yanına içerik bindiren bir `liveActivity(for: mediaPlayback | charging | download, left:, right:)` modifier'ı: medya için solda 20×20 albüm kapağı (köşe 4), sağda 4 çubuklu sahte spektrum (albüm ortalama renginden gradyan ya da Lottie animasyonu), şarj için batarya göstergesi (yüzde, bolt/plug ikonu, düşük güç sarı, %20 altı kırmızı), indirme için ilerleme. "Çene" genişliği: kapalı genişlik + 2×(kapalı yükseklik − 12) + 20; batarya bildirimi geçici olarak 640 pt'ye genişler. Boştayken opsiyonel "yüz" animasyonu (göz kırpma zamanlayıcısı).
**Bizde nasıl yapacağız:** Bu bire bir `NotchModule.compactLeading()/compactTrailing()` sözleşmemiz; genişlik formülü `NotchLayout.compactWidth(contentHeight:)` olarak sıfırdan yazılır (yanlar ≈ yükseklik − 12, artı boşluk). Medya modülünde 20×20 kapak + 4–5 çubuk, Claude modülünde ✳ + etiket. Batarya popup'ı backlog `BatteryModule` (IOKit `IOPSCopyPowerSourcesInfo`, public).
**Dikkat:** Sahte spektrum: 4 çubuk, 0,3 s'de bir 0,35–1,0 arası rastgele hedef, `CABasicAnimation` autoreverse, 24 fps sınırı, duraklamada durur. Bizim `EqualizerBars` `TimelineView` ile aynı davranışı görünürlük kapılı yapar.

### 3.7 Sneak peek / popup sistemi
**Ne yapıyor:** `SneakContentType`: brightness, volume, backlight, music, mic, battery, download. İki stil: standart (notch içerik boyutunda genişler) ve inline (kapalı şeritte 380 pt'lik satır içi HUD). Varsayılan süre 1,5 s; batarya/indirme "expanding view" 3 s (indirme 2 s); müzik sneak peek'i için `waitInterval` 3 s; HUD açık notch içinde de gösterilebilir (`showOpenNotchHUD`, yüzde gösterimi ayrı anahtar). Parça değişimi/çalma başlangıcında müzik sneak peek'i tetiklenir; gecikmeli gizleme `DispatchWorkItem`/`Task.sleep` ile.
**Bizde nasıl yapacağız:** `NotchEvent` (tür + değer + ikon + süre) ve `NotchState.popup(event)`; `ModuleManager` `urgent` aktiviteyi popup'a çevirir; süre varsayılanları: bilgi 1,5–2,5 s, dikkat gerektiren 4–6 s (spitfiresb 2,7/5,6 ile uyumlu). Expanded'dayken popup banner olur (plan §4.2). Inline HUD stili Faz 5 seçeneği.
**Dikkat:** Popup süresi bitince "önceki duruma dön" kuralı (plan) burada da var; expanded içinde gösterim için `showOpenNotchHUD` benzeri anahtar.

### 3.8 HUD değiştirme (ses / parlaklık / klavye ışığı)
**Ne yapıyor:** Kapalı varsayılan `hudReplacement`. Açıkken HID seviyesinde bir `CGEvent` tap (head insert) sistem tanımlı olayları (tür 14, alt tür 8: ses ±, sessiz, parlaklık ±, klavye ışığı ±) yakalar, tuş-basımını **yutar** (sistem OSD'si çıkmaz) ve işlemi kendi yapar: ses CoreAudio ile varsayılan çıkış cihazının volume/mute özellikleri (1/16 adım, Option/Shift ince adım), ekran parlaklığı ve klavye ışığı bir XPC yardımcı servisinde DisplayServices/IOKit ve özel CoreBrightness (`KeyboardBrightnessClient`) ile. Yardımcı ayrıca Erişilebilirlik iznini sorar/ister (event tap için şart). Option tuşu eylemi ayarlanabilir (ilgili System Settings pane'ini aç ya da HUD göster). Mikrofon sessize alma göstergesi de sneak peek türü.
**Bizde nasıl yapacağız:** Backlog'da kalır ve plan §7'deki "HUD replacement" maddesine şu not düşülür: Erişilebilirlik izni + event tap + parlaklık için özel API gerektirir; ses HUD'u tek başına (CoreAudio property listener ile **yalnızca gösterme**, tuşu yutmadan) izin gerektirmeden yapılabilir ama sistem OSD'si de görünür. Parlaklık/klavye ışığı kısmı bizim "özel API yok" kuralıyla çelişir → yapılmaz.
**Dikkat:** Event tap ile tuş yutma, sistemin kendi ses geri bildirimini de devre dışı bırakır; ayrıca ad-hoc imzada Erişilebilirlik grant'ı her build'de sıfırlanır.

### 3.9 Medya denetleyici mimarisi ve MediaRemoteAdapter kablolaması
**Ne yapıyor:** `MediaControllerProtocol`: `playbackStatePublisher` (Combine), play/pause/togglePlay/next/previous/seek/toggleShuffle/toggleRepeat/setVolume/setFavorite, `isActive`, `updatePlaybackInfo`, `supportsVolumeControl`, `supportsFavorite`. Dört denetleyici: **NowPlaying** (MediaRemoteAdapter: `/usr/bin/perl <adapter.pl> <framework> stream` bir `Process` olarak çalışır, JSON-lines borusu okunur; komutlar özel MediaRemote fonksiyon işaretçileriyle — send command, set elapsed, shuffle, repeat — gönderilir; favori Music'e AppleScript), **Apple Music** (`com.apple.Music.playerInfo` dağıtık bildirimi + AppleScript), **Spotify** (`com.spotify.client.PlaybackStateChanged` + AppleScript; komut→güncelleme arası 25 ms; artwork URL'den indirilir), **YouTube Music** (masaüstü uygulamasının yerel HTTP API'si, kimlik doğrulama, zamanlayıcılar). `MediaChecker` başlangıçta adapter'ı `test` komutuyla ve paketlenmiş `MediaRemoteAdapterTestClient` ile çalıştırır, 10 s zaman aşımı, çıkış kodu 1 = "deprecated" → tercih NowPlaying ise Apple Music'e düşer ve onboarding'de `musicPermission` adımı gösterilir. `MusicManager` aktif denetleyiciyi tutar (kullanıcı tercihi `mediaController`), durum değişiminde idle debounce, albüm ortalama rengi, kapak "flip" animasyonu, web'den LRC sözleri, çalma başlangıcında sneak peek. AppleScript, `NSAppleScript` ile **ayrılmış bir görevde** (ana thread dışı) çalıştırılır.
**Bizde nasıl yapacağız:** Plan §5.1'deki `MediaProvider` protokolü bu yüzeye yakınsatılır: `playbackState` yayını + komut seti + `capabilities` (volume/favorite/seek). Faz 3: Spotify + Apple Music sağlayıcıları bildirim-güdümlü + toplu AppleScript (spitfiresb notu 3.10); Faz 6: `GenericNowPlayingProvider` = `stream` süreci + JSON-lines okuyucu + `test` ön kontrolü (bizim mediaremote-adapter notu). Komutlar için özel MediaRemote fonksiyon işaretçileri **alınmaz**; adapter'ın `send` komutu kullanılır. Sözler, YouTube Music, favori: kapsam dışı.
**Dikkat:** `NSAppleScript`'in ana thread dışında kullanımı iki repoda çelişiyor (spitfiresb ana thread'de ısrar eder, burada detached task). Bizim çözüm: tek seri aktör/kuyruk üzerinde çalıştırma ve ilk izin tetiklemesini ana thread'de onboarding'de yapma; Faz 3'te doğrulanır.

### 3.10 Shelf ve sürükleme algılama
**Ne yapıyor:** Global `leftMouseDown/Dragged/Up` monitörleri ve sürükleme pano (`NSPasteboard(name: .drag)`) `changeCount` değişimiyle "içerik sürükleniyor" tespit edilir; imleç açık-notch dikdörtgenine (üst-orta, 640×190) girerse notch shelf sekmesiyle açılır (`expandedDragDetection`). Kapalı notch üzerindeki şeffaf `onDrop` hedefi fileURL/url/text/data kabul eder. Shelf servisleri: kalıcılık, geçici dosya deposu, küçük resim, Quick Look, QuickShare (AirDrop ve diğer paylaşım sağlayıcıları), kopyala-sürükle, otomatik temizleme; 18 dosya.
**Bizde nasıl yapacağız:** Backlog `ShelfModule` NotchDrop notuna göre; buradaki ek fikir: sürükleme pano `changeCount` ile "gerçek içerik sürüklemesi" ayrımı (imleç hareketini sürüklemeden ayırır). Global monitörler yalnızca modül etkinken kurulur (boşta CPU).
**Dikkat:** Sürekli global mouse monitörü boşta maliyet; sadece `leftMouseDown` ile başlatıp `mouseUp`'ta kapatan kalıp mantıklı.

### 3.11 Ayar yüzeyi
**Ne yapıyor:** Sekmeler: General, Appearance, Media, Calendar, HUDs, Battery, Shelf, Shortcuts, Advanced, About. ~70 anahtar; öne çıkanlar: menü bar ikonu göster, tüm ekranlarda göster, otomatik ekran değiştir, hover süresi, haptik, hover ile aç, hover alanını genişlet, notch/notch'suz yükseklik modları ve değerleri, kilit ekranında göster, ekran kaydından gizle, ayna (webcam) ve şekli, ayarlar ikonu notch içinde, ışık efekti, gölge, köşe yarıçapı ölçekleme, takvim ve hatırlatıcılar, kaydırıcı rengi, oynatıcı renk tonu, visualizer ve özel visualizer'lar, jestler ve hassasiyet, sneak peek stili ve bekleme, shuffle/repeat gösterimi, sözler, medya kontrol slotları, güç durumu bildirimleri/batarya yüzdesi, indirme dinleyicisi ve stilleri, HUD değiştirme ve inline HUD, Option tuşu eylemi, shelf seçenekleri, tam ekranda gizleme seçeneği, medya denetleyici tercihi, özel vurgu rengi, "başlık çubuğunu gizle".
**Bizde nasıl yapacağız:** Faz 5 `SettingsStore` için başlangıç envanteri (plan §10 Faz 5 ile kesişim): General (ekran, hover süresi, haptik, launch at login, menü bar ikonu), Appearance (yükseklik modu, gölge, köşe ölçekleme, ekran kaydından gizle), Modüller (her `NotchModule` için aç/kapa + modül ayarları: eşikler, sağlayıcı tercihi), Davranış (tam ekranda gizle: asla/her zaman/medya kaynağı; popup süreleri), Kısayollar, Hakkında. Her anahtar `NotchModule` ya da `Core` ayarı olarak sınıflanır; modül ayarları modül dosyasında kalır (Core'a sızmaz).
**Dikkat:** Aşırı ayar yüzeyi bakım yükü; bizde her ayar bir kabul kriterine bağlanır.

### 3.12 Onboarding, izinler ve dağıtım
**Ne yapıyor:** Onboarding: karşılama (ses efekti) → izin istekleri (genel "Allow / Not now" kartı + gizlilik notu; takvim EventKit, kamera AVCapture, Erişilebilirlik XPC üzerinden, Automation) → medya denetleyici seçimi → Sparkle güncelleme onayı → bitiş; "neler yeni" penceresi. Uygulama **sandbox'lı** ama geçici istisnalarla (apple-events, mach-lookup global name) ve entitlements: apple-events, kamera, takvim, dosya bookmark'ları, ağ istemci/sunucu. Dağıtım: Developer ID **yok** (README kullanıcıya `xattr -dr com.apple.quarantine` ya da "Open Anyway" yaptırır), DMG `dmgbuild` ile, Sparkle appcast (min macOS 14.0), Homebrew cask, Crowdin yerelleştirme, CI/CD workflow.
**Bizde nasıl yapacağız:** Plan §8 geçerli: sandbox kapalı, Developer ID + notarization (quarantine bypass talimatı istemiyoruz). Onboarding kartı deseni (ikon, başlık, açıklama, gizlilik notu, Allow/Not now) Faz 5 `Onboarding.swift` için model. Sparkle sonraki sürüm (skill'lerde `macos-auto-update` var; bağımlılık kararı Faz 5 sonunda).
**Dikkat:** Sandbox + geçici istisna kombinasyonu App Store'a da uygun değil; bize gösterdiği tek şey Automation için hangi entitlement'ın gerektiği (sandbox açık olsaydı).

### 3.13 Performans gözlemleri
**Ne yapıyor:** Zamanlayıcılar: sahte visualizer 0,3 s + 24 fps CA animasyonu (yalnızca çalarken), boştaki "yüz" göz kırpma zamanlayıcısı (ayar kapalıysa yok), müzik kaydırıcısı için `TimelineView` (açıkken), YouTube Music denetleyicisinde poll zamanlayıcıları, tam ekran izleme akışı, sürükleme için global mouse monitörleri, ekran başına pencere + view model. 11 SPM bağımlılığı (Lottie, Pow, Defaults, KeyboardShortcuts, LaunchAtLogin-Modern, SwiftUIIntrospect, Sparkle, AsyncXPCConnection, SkyLightWindow, MacroVisionKit, swift-collections). Kullanıcı CPU şikâyetlerinin hangi kaynaktan geldiği koddan doğrulanamaz; adaylar: açıkken sürekli `TimelineView`, Lottie, global monitörler, ekran başına pencere.
**Bizde nasıl yapacağız:** Plan §13 önlemleri: closed'da tüm zamanlayıcılar durur, `TimelineView` yalnızca görünürken ve fps sınırlı, global monitörler yalnızca ilgili modül etkinken, sıfır SPM bağımlılığı. Faz 5'te Instruments ile boşta <%1 ölçümü; kıyas için boring.notch'u aynı makinede ölçmek faydalı olabilir (yalnızca çalıştırma, kod değil).

## 4. Plan ile çelişkiler / doğrulamalar

- **Pencere seviyesi:** `.mainMenu + 3` (+ özel CGS space) vs bizim `.screenSaver`. İkisi de menü barın üstünde; plan geçerli, Faz 1'de DNK ile birlikte karar netleşir. Özel space alınmaz.
- **`.fullScreenAuxiliary`:** kullanılıyor → planımızla uyumlu (spitfiresb'nin aksine).
- **`ignoresMouseEvents`:** hiç set edilmiyor, hover `.onHover` ile → claude-notch-tracker bulgusu ikinci üründe doğrulandı; Faz 1 varsayılanımız (set etmemek) güçlendi.
- **Hover gecikmesi:** 0,3 s varsayılan, 0–1 s ayarlanabilir; bizim 0,15 s + ayar planı geçerli. Çıkışta 100 ms kapanış gecikmesi eklenmeli (planda yok).
- **Panel sabit boyut:** 640×210 sabit → planımız üçüncü kez doğrulandı; 640 pt genişlik bizim 600 ile uyumlu.
- **Sahte vs gerçek visualizer:** burada sahte (4 çubuk, rastgele) → MVP kararımız sektör normu; gerçek visualizer için spitfiresb yolu.
- **Çoklu ekran:** plan §4.1 "varsayılan dahili ekran, tüm ekranlarda göster opsiyonu" birebir; UUID anahtarlama ve ekran değişiminde yeniden kurma dersi eklenir.
- **Tam ekranda gizleme:** planda yok; Faz 5 ayarı olarak (asla / her zaman / medya kaynağı) eklenmesi önerilir.
- **Medya sağlayıcı yüzeyi:** plan §5.1 `MediaProvider`'a shuffle/repeat/volume/favorite yetenek bayrakları eklenmeli; `test` → deprecated → fallback + onboarding adımı akışı plan §5.1 ve mediaremote-adapter notuyla uyumlu.
- **AppleScript thread'i:** planımız "ana thread'de yok" der; burada detached task, spitfiresb'de ana thread → tek seri aktör çözümü Faz 3'te doğrulanır.
- **HUD replacement (plan §7 backlog):** Erişilebilirlik + event tap + özel CoreBrightness gerektirir → yalnızca "ses HUD gösterimi" versiyonu bizim kurallara sığar.
- **Sıfır bağımlılık kuralı (plan §3):** boring.notch 11 paket kullanır; bizim için kural geçerli, Sparkle Faz 5 sonunda tek istisna adayı.
- **Sandbox:** onlarda açık + istisnalar, bizde kapalı (plan §3) → değişiklik yok.

## 5. Bilinçli almayacaklarımız

- Özel CGS space (`CGSSpace`, `NotchSpaceManager`), SkyLightWindow ile kilit ekranı, özel MediaRemote fonksiyon işaretçileri, özel CoreBrightness, `MacroVisionKit` (içi doğrulanmadan).
- HID event tap ile tuş yutma ve XPC yardımcı servisi (Erişilebilirlik gereksinimi).
- YouTube Music denetleyicisi, sözler, webcam aynası, takvim/hatırlatıcılar (backlog'da ayrı karar), Lottie/Pow efektleri, "yüz" animasyonu.
- Sandbox + geçici istisnalar; quarantine bypass talimatı; Developer ID'siz dağıtım.
- 0,3 s hover varsayılanı, 185 pt sabit genişlik, isim tabanlı ekran tercihi.
- Her ayar için ayrı `Notification.Name` yayınlama kalıbı (bizde `SettingsStore` yayınları / `@Observable`).

## 6. Açık sorular

1. `MacroVisionKit`'in tam ekran tespiti public API ile mi yapılıyor? Faz 5'te paket kaynağı ayrıca klonlanıp lisans/API denetimi yapılmalı; aksi halde kendi public heuristiğimiz.
2. `.mainMenu + 3` ile `.screenSaver` arasında macOS 26'da pratik fark var mı (sistem uyarıları, Spotlight, Notification Center üstünde davranış)? Faz 1 prototipinde her ikisi denenir.
3. Kapalı genişliğe 4 pt "bleed" gerçekten gerekli mi? 16" M4 Pro'da Faz 0 ekran görüntüsünde kenar sızıntısı görülmedi; farklı ölçeklerde test.
4. Spotify `PlaybackStateChanged` bildiriminden sonra 25 ms bekleme yeterli mi, yoksa spitfiresb gibi bildirim payload'ına güvenmeden tam durum çekmek mi? Faz 3'te ölçülür.
5. Tam ekranda "yalnızca medya kaynağı tam ekransa gizle" davranışı bizim için anlamlı mı (Claude modülü tam ekran terminalde ne yapmalı)? Faz 5 ayar tasarımında karar.
