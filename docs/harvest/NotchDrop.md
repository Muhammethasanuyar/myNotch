# NotchDrop — Harvest Notu

| | |
|---|---|
| Repo | https://github.com/Lakr233/NotchDrop |
| Klon | `references/NotchDrop` @ `e70b3d7` (2026-05-19) |
| Lisans | **MIT** — `LICENSE:1` "MIT License", `LICENSE:3` "Copyright (c) 2024 Lakr Aream" |
| Devşirme modu | **Kod adapte et** (dosya başına `// Adapted from Lakr233/NotchDrop (MIT)` + `THIRD_PARTY_LICENSES.md`) |
| İlgili fazlar | Backlog — Faz 6+ (Shelf modülü); Faz 1'de pencere/geometri karşılaştırması için referans |

---

## 1. Bizim için değeri

`docs/PLAN.md` §7'deki "dosya rafı (notch'a sürükle-bırak → AirDrop)" backlog maddesinin **referans implementasyonu** ve boring.notch'un Shelf özelliğinin kökeni. 2065 satırlık küçük bir kod tabanı; okunması kolay, dört somut problemi çözülmüş halde gösteriyor:

1. **Sürükleme algılama:** SwiftUI `onDrop` bir notch penceresinde nasıl çalıştırılır (ve neden neredeyse-şeffaf bir dikdörtgen gerekir).
2. **Sürükleme ile açılma:** dosya notch'un üzerine geldiğinde paneli açma/kapatma koreografisi.
3. **Dosya rafı deposu:** kopyalama, süre dolumu, önizleme, dışarı sürükleme (`Transferable`).
4. **AirDrop:** `NSSharingService(named: .sendViaAirDrop)` ile tek tıkta paylaşım + genel paylaşım paneli fallback'i.

Ayrıca bizim Faz 1'de yazdığımız `NotchGeometry`/`NotchPanel` yaklaşımı için bağımsız bir **doğrulama**: aynı `safeAreaInsets` + `auxiliaryTopLeftArea/auxiliaryTopRightArea` hesabını kullanıyor.

Buna karşılık mimarisinin bize **uymayan** yanları da öğretici: tek amaçlı uygulama olduğu için modül sistemi yok, global singleton'lar ve global `let`'ler var, pencere odak çalıyor, sürekli çalışan global event monitörleri ve 1 sn'lik timer var, yedi SPM bağımlılığı var. Bunları bilinçli olarak almayacağız (§5).

---

## 2. Hedef dosyalar

| Kaynak dosya (path:line) | Ne yapıyor | Bizde hedef dosya (per docs/PLAN.md §9) | Faz |
|---|---|---|---|
| `NotchDrop/NotchWindow.swift:10-47` | Pencere yapılandırması: şeffaf, hareketsiz, `level = .statusBar + 8`, `collectionBehavior`, `canBecomeKey = true` | `Core/Window/NotchPanel.swift` (karşılaştırma / doğrulama) | 1 |
| `NotchDrop/NotchWindowController.swift:18-67` | Ekran seçimi, notch dikdörtgeni hesabı, ekranın üstünde 200 pt'lik tam genişlik şerit | `Core/Window/NotchWindowController.swift` | 1 |
| `NotchDrop/Ext+NSScreen.swift:10-33` | `notchSize` (safeArea + auxiliary alanlar), `isBuildinDisplay`/`buildin` | `Core/Window/NotchGeometry.swift` (doğrulama; bizde mevcut) | 1 |
| `NotchDrop/AppDelegate.swift:19-64` | Ekran parametresi değişiminde pencereleri yeniden kurma, `.accessory` aktivasyon politikası | `App/AppDelegate.swift`, `Core/Window/NotchWindowController.swift` | 1 |
| `NotchDrop/NotchView.swift:138-159` | `dragDetector`: neredeyse şeffaf drop hedefi, `dropDetectorRange`, hover ile açılma | `Modules/Shelf/Views/ShelfDropDetector.swift` (yeni) | 6+ |
| `NotchDrop/NotchView.swift:15-41` | Duruma göre boyut/köşe yarıçapı (`closed/opened/popping`) | `Core/Window/NotchShape.swift`, `Core/State/NotchState.swift` (karşılaştırma) | 1 |
| `NotchDrop/NotchViewModel+Events.swift:14-115` | Global event monitörleriyle hover/dışarı tıklama/Option tuşu; haptic | `Core/Window/` (bizde `NSTrackingArea`) | 1 (karşı örnek) |
| `NotchDrop/TrayDrop.swift:60-119` | Item deposu: yükleme (ana thread dışı), süresi dolanları temizleme, silme | `Modules/Shelf/ShelfStore.swift` (yeni) | 6+ |
| `NotchDrop/TrayDrop+DropItem.swift:24-88` | Dosyayı uygulama deposuna kopyalama, QuickLook önizleme, `storageURL`, `shouldClean` | `Modules/Shelf/ShelfItem.swift` (yeni) | 6+ |
| `NotchDrop/TrayDrop+DropItem.swift:43-64` | `Transferable` + `FileRepresentation` ile dışarı sürükleme | `Modules/Shelf/ShelfItem.swift` | 6+ |
| `NotchDrop/Ext+FileProvider.swift:12-60` | `NSItemProvider` → dosya URL'si dönüşümü | `Modules/Shelf/ItemProviderLoader.swift` (yeni, async/await ile) | 6+ |
| `NotchDrop/Share.swift:29-52` + `Share+View.swift:33-40` | AirDrop servisi / genel paylaşım paneli | `Modules/Shelf/ShelfShare.swift` (yeni) | 6+ |
| `NotchDrop/TrayDrop+DropItemView.swift:20-61` | Item hücresi: önizleme, `.draggable`, Option ile silme rozeti | `Modules/Shelf/Views/ShelfItemView.swift` (yeni) | 6+ |
| `NotchDrop/Localizable.xcstrings` | String Catalog: 53 anahtar × 6 dil (en, de, fr, ja, zh-Hans, zh-Hant) | `Resources/Localizable.xcstrings` | 5+ |

---

## 3. Desenler

### 3.1 Notch penceresi: konumlama, seviye ve tam ekran davranışı

**Nasıl çalışıyor:** Pencere `NSWindow` alt sınıfı (`NotchWindow.swift:10-47`); `.borderless + .fullSizeContentView`, `isOpaque = false`, `backgroundColor = .clear`, `isMovable = false`, `hasShadow = false`.

```swift
collectionBehavior = [
    .fullScreenAuxiliary,
    .stationary,
    .canJoinAllSpaces,
    .ignoresCycle,
]
level = .statusBar + 8 // kills ibar lol
```
Kaynak: `references/NotchDrop/NotchDrop/NotchWindow.swift:30-37` (MIT)

Geometri: ekran, dahili ekran + notch'u olan ekran tercih edilerek seçilir, yoksa `.main` (`AppDelegate.swift:48-51`). Pencere ekranın **tüm genişliğinde ve 200 pt yüksekliğinde** bir üst şerit kaplar (`NotchWindowController.swift:10`, `:59-67`); notch dikdörtgeni ekran koordinatlarında ayrıca hesaplanır (`:32-37`). Notch yoksa 150×28'lik sanal bir kutu kullanılır (`:29-31`) ve `inset` 0 olur (notch varken `-4`, yani hedef alan 4 pt büyütülür — `:25`). Ekran parametreleri değişince tüm pencere yıkılıp yeniden kuruluyor (`AppDelegate.swift:20-25`, `:53-64`).

**Bize uyarlama:** Bizim `NotchPanel`/`NotchLayout` yapımız aynı problemi çözüyor; buradan alınacak iki fikir: (a) `.ignoresCycle` — pencerenin Cmd+` döngüsüne girmemesi, bizim `collectionBehavior`'a eklenebilir; (b) ekran parametresi değişiminde **yeniden kurma** yerine bizim `NotchWindowController.reposition()` yaklaşımımız (mevcut pencereyi taşımak) daha ucuz ve daha az titrek — mevcut çözümümüzü koruyalım.

**Dikkat:** `level = .statusBar + 8` menü barının üstüne çıkar ama `docs/PLAN.md` §4.1 `.screenSaver` diyor; ikisi de menü barı geçer, `.screenSaver` daha yüksek. Sayısal aritmetik (`+ 8`) yerine adlandırılmış seviye kullanmak daha okunur. Ayrıca 200 pt'lik tam genişlik pencere, altındaki menü bar ögelerine tıklamayı **şeffaf piksellerde** engellemez ama SwiftUI hit-test alanlarını dikkatle sınırlamak gerekir (§3.2).

### 3.2 Sürükleme ile açılma: neredeyse-şeffaf drop hedefi

**Nasıl çalışıyor:** Notch görselinin arkasına, ondan `dropDetectorRange = 32` pt daha geniş/uzun görünmez bir dikdörtgen konur ve `onDrop` ile hedeflenme durumu izlenir (`NotchView.swift:138-159`, sabit `NotchViewModel.swift:27`).

```swift
RoundedRectangle(cornerRadius: notchCornerRadius)
    .foregroundStyle(Color.black.opacity(0.001)) // 0.001 is the smallest we can have
    .contentShape(Rectangle())
    .frame(width: notchSize.width + vm.dropDetectorRange, height: notchSize.height + vm.dropDetectorRange)
    .onDrop(of: [.data], isTargeted: $dropTargeting) { _ in true }
```
Kaynak: `references/NotchDrop/NotchDrop/NotchView.swift:140-144` (MIT)

`isTargeted` true olunca ve durum `.closed` ise notch açılır (`vm.notchOpen(.drag)`) ve haptic tetiklenir; hedefleme bitince fare açık panelin dışındaysa kapatılır (`:145-157`). Bu dedektörün kendisi hiçbir dosyayı kabul etmez (`{ _ in true }` sadece hover için); gerçek kabul, açılan panel içindeki `TrayView`'ın `onDrop`'unda olur (`TrayDrop+View.swift:38-41`).

**Bize uyarlama:** `docs/PLAN.md` §4.3'e uygun biçimde Shelf bir `NotchModule` olur. Ama sürükleme ile açılma **modüle özgü olamaz**: notch kapalıyken modülün view'ı render edilmiyorsa `onDrop` da yoktur. İki katmanlı çözüm: (1) `NotchRootView` seviyesinde, aktif modüllerden herhangi biri "drop kabul ediyorum" diyorsa gösterilen ince bir dedektör katmanı; (2) hedeflenme olayı `EventBus` üzerinden `NotchViewModel`'a `.expanded(moduleID: "shelf")` geçişi olarak iletilir. `Anim.morph` ile açılır, `Anim.subtle` ile kapanır. `0.001` opaklık hilesi ve `contentShape(Rectangle())` aynen gerekli — SwiftUI tamamen şeffaf bir view'ı hit-test etmez.

**Dikkat:** `docs/PLAN.md` §4.1 panelimizi `nonactivatingPanel` yapıyor. `onDrop`'un nonactivating bir `NSPanel` içinde çalışıp çalışmadığı **deneyle doğrulanmalı** (§6/S1); çalışmıyorsa AppKit tarafında `NSView.registerForDraggedTypes` ile kendi drop hedefimizi yazmamız gerekir. Ayrıca dedektör 32 pt taşma ile menü barının bir kısmını kaplar — normal tıklamaların geçtiğinden emin olmak için dedektör yalnızca **sürükleme sırasında** etkinleştirilmeli (`.allowsHitTesting(isDragSessionActive)`).

### 3.3 Dosya rafı deposu ve yaşam süresi

**Nasıl çalışıyor:** Sürüklenen dosya, uygulama deposuna **kopyalanır** (taşınmaz):

```swift
extension TrayDrop.DropItem {
    static let mainDir = "CopiedItems"

    var storageURL: URL {
        documentsDirectory
            .appendingPathComponent(Self.mainDir)
            .appendingPathComponent(id.uuidString)
            .appendingPathComponent(fileName)
    }
```
Kaynak: `references/NotchDrop/NotchDrop/TrayDrop+DropItem.swift:67-75` (MIT)

`documentsDirectory` = `~/Documents/NotchDrop`, geçici dizin = `NSTemporaryDirectory()/<bundleID>` ve **her açılışta silinip yeniden yaratılır** (`main.swift:16-33`). Item oluşturma ana thread dışında zorlanır (`TrayDrop+DropItem.swift:25`, `TrayDrop.swift:61`): dosya boyutu okunur, `copiedDate` damgalanır, QuickLook ile 128×128 önizleme üretilip **PNG verisi item'ın içine gömülür** (`:30-32`, `Ext+URL.swift:12-23`), sonra dosya kopyalanır (`:34-38`). Saklama süresi `keepInterval` (varsayılan `3600 * 24`, `TrayDrop.swift:11-12`), ayarlardan 1 saat/1 gün/2 gün/3 gün/1 hafta/sonsuz/özel olarak seçilir (`:121-169`). `shouldClean` üç durumu kontrol eder: dosya kayıp, `keepInterval <= 0` (kullanıcının dosyalarını silmemek için savunma), süre dolmuş (`:81-87`). Temizlik açılışta bir kez çalışır (`main.swift:56`). Silme, boş kalan ara dizinleri de yukarı doğru toplar (`TrayDrop.swift:95-114`). Kalıcılık `@PublishedPersist` ile `~/Documents/NotchDrop/Config/<key>` altında JSON dosyaları (`PublishedPersist.swift:16-34`).

**Bize uyarlama:** `Modules/Shelf/ShelfStore.swift`: depo `~/Library/Application Support/MyNotch/Shelf/<uuid>/<dosya>` olsun (kullanıcının `~/Documents`'ını kirletmeyelim). Kalıcılık `SettingsStore` desenine uyarak `UserDefaults`/`@AppStorage` yerine **küçük bir JSON dosyası** (item listesi büyüyebilir). Süre dolumu temizliği hem açılışta hem de modül her açıldığında; `keepInterval` ayarı Faz 5 `SettingsView`'a eklenir. Kopyalama, önizleme üretimi ve silme `nonisolated` bir aktörde; UI'ya yalnızca hazır model gider (Swift 6, varsayılan `MainActor` izolasyonu).

**Dikkat:** Önizleme PNG'sini persist edilen modele gömmek dosyayı şişirir (her item için onlarca KB base64/JSON); biz önizlemeyi ayrı bir dosyaya (`<uuid>/preview.png`) yazıp modelde yalnızca yolu tutalım. `QLThumbnailImageCreate` (`Ext+URL.swift:14-19`) uzun süredir deprecated — macOS 14+ hedefimizde `QuickLookThumbnailing.QLThumbnailGenerator` kullanılmalı (async API, bizim mimarimize daha uygun). Ayrıca "kopyala" davranışı disk tüketir: kullanıcıya toplam boyutu göstermek ve büyük dosyalarda uyarmak iyi olur.

### 3.4 Dışarı sürükleme ve AirDrop

**Nasıl çalışıyor:** Her item `Transferable`'dır; dışa aktarımda dosya **geçici dizine kopyalanır** ve `SentTransferredFile(newPath, allowAccessingOriginalFile: true)` döner (`TrayDrop+DropItem.swift:43-64`), hücrede `.draggable(item)` ile sürüklenebilir (`TrayDrop+DropItemView.swift:40`). Tıklama dosyayı `NSWorkspace.shared.open` ile açar ama önce notch kapanır ve 0.5 sn beklenir (`:41-47`) — açılan uygulamanın öne gelmesiyle çakışmasın diye. Paylaşım: `Share` sınıfı, isim verilmişse ilgili servisi (`.sendViaAirDrop`) `canPerform(withItems:)` ile doğrulayıp çalıştırır; isim yoksa `NSSharingServicePicker` gösterir (`Share.swift:29-52`). AirDrop bölgesi ayrı bir drop hedefidir: dosya bırakıldığında notch 0.25 sn sonra kapanır ve paylaşım arka planda başlar (`Share+View.swift:63-72`).

**Bize uyarlama:** `Modules/Shelf/ShelfShare.swift` içinde `enum ShelfShareTarget { case airdrop, picker }` ve tek bir `share(_ urls: [URL], via:)` fonksiyonu; `canPerform` kontrolü zorunlu (AirDrop kapalıysa/desteklenmiyorsa anlamlı hata). Expanded görünüm iki bölgeli olur (AirDrop | Raf), `docs/PLAN.md` §7'deki "notch'a sürükle-bırak → AirDrop" tanımına birebir uyar. Paylaşım paneli için bir `NSView` referansı gerektiğinden (`Share.swift:47-50`) panelimizin content view'ını kullanabiliriz — ama nonactivating panelde picker'ın konumlanması test edilmeli.

**Dikkat:** `NSSharingServicePicker.show(relativeTo:of:preferredEdge:)` `NSApp.keyWindow` bekliyor; bizim panelimiz key olmayacaksa picker'ı ayrı görünmez bir pencereden veya menü bar öğesinden sunmamız gerekebilir (§6/S2).

### 3.5 Etkileşim modeli: global monitörler vs tracking area, ve odak çalma

**Nasıl çalışıyor:** Hover ve tıklama, pencereye değil **global/local `NSEvent` monitörlerine** dayanıyor (`EventMonitor.swift:18-24` her maske için hem global hem local monitör kurar; `EventMonitors.swift:24-53` `mouseMoved`, `leftMouseDown`, `leftMouseDragged`, `flagsChanged` maskelerini singleton olarak açar). `NotchViewModel+Events.swift:14-65` bu akışları ekran koordinatlarındaki dikdörtgenlerle karşılaştırır: fare notch dikdörtgeninin içine girince `.popping`, çıkınca `.closed`; tıklama panel dışındaysa kapanır, notch üzerindeyse kapanır, başlık şeridindeyse içerik tipi döner. Durum değişimleri `withAnimation` ve `Combine` operatörleriyle yumuşatılır: `.popping` durumunda 0.5 sn throttle'lı haptic (`:75-93`), kapanışta 0.5 sn debounce ile görünürlük söndürme (`:95-104`). Panel açılırken uygulama **öne getirilir**: `NSApp.activate(ignoringOtherApps: true)` (`NotchViewModel.swift:85-90`). Ek olarak `AppDelegate` 1 sn'lik bir `Timer` ile hem PID dosyasını doğruluyor hem de açıkken pencereyi `makeKeyAndOrderFront` yapıyor (`AppDelegate.swift:31-38`, `:77-84`).

**Bize uyarlama:** **Bu deseni almıyoruz.** `docs/PLAN.md` §4.1 hover için `NSTrackingArea` (mouseEntered/Exited) + ~0.15 sn gecikme diyor; bu hem daha ucuz hem izin gerektirmez. Alınacak parçalar: (a) `.popping` (bizde `popup`) durumuna girerken haptic geri bildirim — hoş bir detay, `NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)`, ayarla kapatılabilir; (b) kapanışta debounce ile görünürlük söndürme fikri; (c) Option tuşuna basılıyken silme rozeti gösterme (`flagsChanged`) — bu, yalnızca panel açıkken kurulacak **lokal** bir monitörle yapılabilir.

**Dikkat:** Üç kritik uyumsuzluk: (1) `NSApp.activate(ignoringOtherApps:)` **odak çalar** — kullanıcının yazdığı uygulamadan çıkar; bizim `nonactivatingPanel` kararımızla çelişir, almayacağız. (2) Sürekli çalışan global `mouseMoved` monitörü + 1 sn'lik timer, `docs/PLAN.md` §13'teki CPU hedefiyle (boşta <%1) çelişir. (3) Global `NSEvent` monitörleri bazı maskeler için Erişilebilirlik izni gerektirebilir; izin akışına girmemek için tracking area yaklaşımı daha güvenli.

### 3.6 i18n: String Catalog ve dil değiştirme

**Nasıl çalışıyor:** Tüm metinler `NSLocalizedString`/`LocalizedStringKey` ile çağrılıyor; çeviriler `NotchDrop/Localizable.xcstrings` String Catalog'unda (53 anahtar; diller: `en` kaynak + `de`, `fr`, `ja`, `zh-Hans`, `zh-Hant`), ayrıca `InfoPlist.xcstrings` var. Biçimlendirilmiş metinler `String(format: NSLocalizedString("Drag files here to keep them for %@", …), storageTime)` şeklinde (`TrayDrop+View.swift:69-78`). Uygulama içi dil seçici `UserDefaults`'taki `AppleLanguages` anahtarını yazıp `Bundle.main`'in sınıfını `object_setClass` ile değiştiriyor ve kullanıcıya yeniden başlatma diyaloğu gösterip `/usr/bin/open -n` ile kendini yeniden başlatıyor (`Language.swift:25-112`).

**Bize uyarlama:** String Catalog (`.xcstrings`) + `LocalizedStringKey` yaklaşımını alalım — global kurallardaki "hardcoded metin yok, tüm metinler lang dosyalarından" ilkesinin macOS karşılığı bu. `Resources/Localizable.xcstrings` oluşturulup `project.yml`'e eklenir; MVP'de en + tr yeterli. Sayı/para/tarih biçimlendirmede (`$4.20`, "2h 15m") `NumberFormatter`/`Duration.formatted` ile locale'e saygılı olalım.

**Dikkat:** Uygulama içi dil değiştirme (`AppleLanguages` override + `Bundle` swizzle + yeniden başlatma) **almayacağız**: private-ish bir hile, yeniden başlatma gerektiriyor ve macOS 13+ zaten Sistem Ayarları'nda uygulama başına dil seçimi sunuyor.

---

## 4. Plan ile çelişkiler / doğrulamalar

1. **Notch geometrisi — doğrulandı.** `Ext+NSScreen.swift:10-20` bizimle aynı formülü kullanıyor: `safeAreaInsets.top > 0` kontrolü, genişlik = `frame.width - auxiliaryTopLeftArea.width - auxiliaryTopRightArea.width`. `docs/PLAN.md` §4.1 ve `Core/Window/NotchGeometry.swift` yaklaşımımız bağımsız bir implementasyonla teyit ediliyor. NotchDrop ek olarak `auxiliary` alanlardan biri 0 ise notch yok sayıyor (`:17`) — bizim tarafta da savunmacı bir kontrol olarak değerli.
2. **Pencere tipi ve odak — çelişki (bilinçli).** NotchDrop `NSWindow` + `canBecomeKey = true` + `NSApp.activate(ignoringOtherApps:)` kullanıyor; `docs/PLAN.md` §4.1 `NSPanel` + `nonactivatingPanel` diyor. Bizim kararımız doğru (menü bar uygulaması odak çalmamalı), ancak bedeli var: `onDrop` ve `NSSharingServicePicker` davranışları nonactivating panelde doğrulanmalı (§6/S1, S2).
3. **Pencere seviyesi — küçük fark.** `.statusBar + 8` vs planımızdaki `.screenSaver`. İkisi de menü barın üstünde; `.screenSaver` daha güvenli bir üst sınır. Değişiklik gerekmiyor.
4. **Tam ekran davranışı — doğrulandı.** `collectionBehavior` üçlüsü (`.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary`) `docs/PLAN.md` §4.1 ile birebir aynı; NotchDrop ek olarak `.ignoresCycle` kullanıyor — bizde de mantıklı.
5. **CPU/enerji — çelişki.** Sürekli global `mouseMoved` monitörü + 1 sn'lik `Timer` (`AppDelegate.swift:31-38`), `docs/PLAN.md` §13'teki "boşta <%1 CPU" hedefiyle uyuşmuyor. Bizim tracking-area + closed durumda timer durdurma kararımızı koruyoruz.
6. **Bağımlılıklar — çelişki.** `Package.resolved`: ColorfulX, ColorVector, LaunchAtLogin-Modern, LookInside-Release, MSDisplayLink, Pow, SpringInterpolation, swift-collections. `docs/PLAN.md` §3 "mümkün olduğunca sıfır SPM bağımlılığı" diyor → yalnızca **desen** alınacak, kütüphaneler alınmayacak; `OrderedSet` yerine dizi + `Set<UUID>`, Pow efektleri yerine `Anim` sabitlerimiz.
7. **Modül sistemi — uyum notu.** NotchDrop'ta durum makinesi `closed/opened/popping` ve içerik tipi `normal/menu/settings` (`NotchViewModel.swift:29-46`); bizim `NotchState` (`closed/compact/expanded/popup`) daha zengin. Shelf'i `docs/PLAN.md` §4.3 protokolüne oturturken: `compactLeading()` = raftaki dosya sayısı rozeti, `expandedView()` = AirDrop + raf, `activity` = raf boş değilse `.live`. `docs/PLAN.md` §9'daki klasör planında Shelf yok; `Modules/Shelf/` eklenmeli (plan güncellemesi).

---

## 5. Bilinçli almayacaklarımız

- **PID dosyası ile tek örnek zorlaması** (`main.swift:35-53`) ve **kendi binary'sini `DispatchSource` ile izleyip silinince çıkma** (`main.swift:58-73`), ayrıca 1 sn'de bir PID doğrulama (`AppDelegate.swift:66-75`). Bizde `SMAppService` + normal uygulama yaşam döngüsü yeterli.
- **`NSApp.activate(ignoringOtherApps: true)`** ile odak çalma (`NotchViewModel.swift:89`).
- **Global event monitörleri** ile hover/tıklama (`EventMonitors.swift:24-53`) — `NSTrackingArea` kullanacağız.
- **`AppleLanguages` override + `Bundle` sınıf değiştirme + kendini yeniden başlatma** (`Language.swift:75-112`).
- **`DispatchSemaphore` ile senkron `NSItemProvider` okuma** (`Ext+FileProvider.swift:27-45`) — Swift 6'da `loadItem` için `withCheckedThrowingContinuation` kullanacağız; semafor + ana thread kombinasyonu kilit riski taşır.
- **Önizleme PNG'sini persist edilen modele gömmek** (`TrayDrop+DropItem.swift:22`, `:32`) ve **deprecated `QLThumbnailImageCreate`** (`Ext+URL.swift:14`).
- **`~/Documents` altına yazmak** (`main.swift:16-20`) — Application Support daha doğru konum.
- **Hata akışı olarak `NSAlert` pop-up'ları** (`Ext+NSAlert.swift`, `TrayDrop.swift:76`): menü bar uygulamasında modal alert rahatsız edici; notch içi hata durumu + log tercih edilir.
- **Üçüncü parti görsel efekt kütüphaneleri** (ColorfulX gradyanları, Pow `.movingParts.poof` geçişleri).

---

## 6. Açık sorular

1. **S1 — SwiftUI `onDrop`, `nonactivatingPanel` içinde çalışıyor mu?** Faz 6 başında küçük bir deney: Debug Preview yerine gerçek `NotchPanel` üzerinde `onDrop(of: [.fileURL])` denenmeli. Çalışmıyorsa plan B: AppKit `NSView.registerForDraggedTypes([.fileURL])` + `NSDraggingDestination` ile kendi hedefimiz.
2. **S2 — `NSSharingServicePicker` nonactivating panelde nasıl konumlanır?** `Share.swift:47-50` `NSApp.keyWindow` bekliyor. Alternatif: paylaşımı menü bar öğesinden sunmak veya AirDrop'u doğrudan servis olarak çağırıp picker'ı hiç kullanmamak.
3. **S3 — Sürükleme oturumunu global olarak nasıl algılarız?** NotchDrop `leftMouseDragged` monitörü kuruyor ama fiilen dedektörün `isTargeted`'ına güveniyor. Bizde dedektör katmanının yalnızca sürükleme sırasında hit-test edilmesi için sürükleme oturumu tespiti gerekiyor mu, yoksa 32 pt'lik dedektörün her zaman açık olması menü bar tıklamalarını gerçekten bozmuyor mu? (Ölçülmeli.)
4. **S4 — Shelf ile Medya modülü öncelik çatışması.** Dosya sürüklenirken müzik çalıyorsa hangisi notch'u kazanır? `docs/PLAN.md` §4.3'e göre `urgent > live(priority)`; sürükleme muhtemelen geçici bir `urgent` olmalı ve bırakma bitince eski duruma dönmeli. `ModuleManager`'da "geçici öncelik devralma" kavramı gerekiyor mu?
5. **S5 — Depolama politikası.** Varsayılan saklama süresi (NotchDrop: 24 saat) bizde ne olmalı? Kopyalanan dosyaların toplam boyutu için üst sınır ve kullanıcıya gösterim gerekli mi? Silme "yalnızca raftan kaldır" mı yoksa "kopyayı da sil" mi (NotchDrop ikincisini yapıyor, `TrayDrop.swift:95-114`)?
6. **S6 — `Modules/Shelf/` planına eklenmeli mi?** `docs/PLAN.md` §9 klasör planı yalnızca Media ve ClaudeUsage içeriyor. Backlog modülü hayata geçtiğinde plan §7/§9 birlikte güncellenmeli.
