# DynamicNotchKit — Harvest Notu

| | |
|---|---|
| Repo | https://github.com/MrKai77/DynamicNotchKit |
| Klon | `references/DynamicNotchKit` @ `cd0b3e5` (2026-02-18) |
| Lisans | MIT (`LICENSE`, "Copyright (c) 2025 Kai Azim") |
| Devşirme modu | **Kod adapte et** |
| İlgili fazlar | 1 (notch motoru: panel, shape, state, hover, animasyon), 2 (compact leading/trailing sözleşmesi), 4 (ProgressRing deseni), 5 (fallback/floating stil) |

## 1. Bizim için değeri

Notch motorumuzun birebir referansı: `NSPanel` kurulumu, notch ölçülerinin ekrandan okunması, içbükey "kulaklı" `NotchShape`, closed/compact/expanded morfolojisi, hover davranışı ve göster/gizle koreografisi burada çalışır durumda ve MIT. Bizim mimarideki `NotchPanel` / `NotchShape` / `NotchViewModel` / `Anim` sözleşmelerinin karşılığı neredeyse satır satır bu repoda mevcut, dolayısıyla Faz 1'de sıfırdan icat etmemiz gereken tek şey modül sistemi ile bağlantı noktaları. Buna karşılık kütüphane "bildirim gösteren geçici popover" için tasarlanmış: pencereyi her gizlemede yok ediyor, `await notch.expand()` gibi imperatif bir API sunuyor ve compact↔expanded geçişini araya `hidden` adımı sokarak yapıyor. Bizim kalıcı, state-driven ve modül tabanlı motorumuza bu üç şey **taşınmaz**.

## 2. Hedef dosyalar

| Kaynak dosya (path:line) | Ne yapıyor | Bizde hedef dosya (per docs/PLAN.md §9) | Faz |
|---|---|---|---|
| `Sources/DynamicNotchKit/Utility/DynamicNotchPanel.swift:10-31` | Borderless + nonactivating `NSPanel`; `level = .screenSaver`, `collectionBehavior`, şeffaf zemin | `Core/Window/NotchPanel.swift` (mevcut) | 1 |
| `Sources/DynamicNotchKit/DynamicNotch/DynamicNotch.swift:350-392` | Pencere kurulumu: notch ölçüsü, hosting view, sabit yarım-ekran frame, konumlama | `Core/Window/NotchWindowController.swift` (mevcut) | 1 |
| `.../DynamicNotch.swift:144-153` | `didChangeScreenParametersNotification` gözlemi ve pencerenin yeniden kurulması | `Core/Window/ScreenObserver.swift` | 1 |
| `Sources/DynamicNotchKit/Utility/NSScreen+Extensions.swift:19-66` | `hasNotch`, `notchSize`, `notchFrame`, `menubarHeight`, notch'suz ekran fallback ölçüsü | `Core/Window/NotchGeometry.swift` (mevcut) | 1 |
| `Sources/DynamicNotchKit/Views/NotchShape.swift:10-118` | İçbükey "kulak" + konveks alt köşe Bezier'i; `animatableData` ile iki yarıçap | `Core/Window/NotchShape.swift` | 1 |
| `Sources/DynamicNotchKit/Views/NotchView.swift:56-101` | Sabit pencere içinde mask + background ile shape morfolojisi, içerik yerleşimi, hover | `Core/Window/NotchRootView.swift` | 1 |
| `.../NotchView.swift:103-153` | compact leading/trailing ve expanded içerik kutuları, güvenli alan insets'leri | `Core/Modules/NotchModule.swift` (compact/expanded sözleşmesi) | 2 |
| `Sources/DynamicNotchKit/DynamicNotch/DynamicNotchState.swift:17-26` | `expanded` / `compact` / `hidden` durum enum'ı | `Core/State/NotchState.swift` | 1 |
| `Sources/DynamicNotchKit/DynamicNotch/DynamicNotchStyle.swift:31-80` | notch/floating/auto stil + stil başına açılış/kapanış/dönüşüm animasyonları | `Core/State/Anim.swift` + `Core/Window/NotchShape.swift` | 1 |
| `.../DynamicNotchTransitionConfiguration.swift:24-57` | Animasyon override'ları ve `skipIntermediateHides` | `Core/State/Anim.swift` | 1 |
| `.../DynamicNotchHoverBehavior.swift:17-37` | Hover davranışı OptionSet (keepVisible / haptic / gölge) | `Core/State/NotchViewModel.swift` + `Settings/SettingsStore.swift` | 1, 5 |
| `.../DynamicNotch.swift:177-331` | expand / compact / hide koreografisi, alpha fade, kapatma gecikmeleri | `Core/State/NotchViewModel.swift` | 1 |
| `Sources/DynamicNotchKit/Views/NotchContentView.swift:20-55` | Duruma/hover'a bağlı gölge ve hover animasyonu | `Core/Window/NotchRootView.swift` | 1 |
| `Sources/DynamicNotchKit/Views/NotchlessView.swift:19-44` | Notch'suz ekranda yüzen panel (material, kenarlık, yukarıdan kayma) | `Core/Window/NotchShape.swift` (capsule modu) + `NotchRootView` | 1 |
| `Sources/DynamicNotchKit/Utility/BlurModifier.swift:30-43` | `blur` + `scale` custom `AnyTransition`'ları | `Core/State/Anim.swift` | 1 |
| `Sources/DynamicNotchKit/DynamicNotchInfo/DynamicNotchInfo+Label.swift:110-151` | `ProgressRing` (trim + gradient + yükleme animasyonu) | `Modules/ClaudeUsage/Views/BlockRing.swift` | 4 |
| `.../DynamicNotchInfo+HelperViews.swift:19-27, 52-68` | compact ikon ↔ expanded ikon arası `matchedGeometryEffect` | `Modules/Media/Views/` (artwork morph) | 3 |
| `Sources/DynamicNotchKit/Utility/VisualEffectView.swift:10-23` | `NSVisualEffectView` sarmalayıcı | `Core/Window/` yardımcı (gerekirse) | 1 |

## 3. Desenler

### 3.1 NSPanel yapılandırması ve pencere seviyesi

**Nasıl çalışıyor:** Pencere `DynamicNotchPanel` (`Utility/DynamicNotchPanel.swift:10`), `styleMask: [.borderless, .nonactivatingPanel]` ile `DynamicNotch.swift:360-365`'te üretiliyor. Panel ayarları yalnızca dört satır: `hasShadow = false`, `backgroundColor = .clear`, `level = .screenSaver`, `collectionBehavior = [.canJoinAllSpaces, .stationary]` (satır 23-26). `canBecomeKey` `true`'ya override edilmiş (satır 29-31). `isOpaque`, `hidesOnDeactivate`, `ignoresMouseEvents`, `isFloatingPanel`, `isMovable`, `animationBehavior` **hiç set edilmiyor**.

```swift
self.hasShadow = false
self.backgroundColor = .clear
self.level = .screenSaver
self.collectionBehavior = [.canJoinAllSpaces, .stationary]
```
Kaynak: references/DynamicNotchKit/Sources/DynamicNotchKit/Utility/DynamicNotchPanel.swift:23 (MIT)

**Bize uyarlama:** `Core/Window/NotchPanel.swift` bu deseni zaten kapsıyor ve üzerine çıkıyor: `isOpaque = false`, `hidesOnDeactivate = false`, `isFloatingPanel = true`, `isMovable = false`, `animationBehavior = .none`, `isReleasedWhenClosed = false` ve `collectionBehavior`'a `.fullScreenAuxiliary` + `.ignoresCycle`. `.screenSaver` seviyesi DNK tarafından doğrulanmış oldu — PLAN §4.1'deki karar değişmiyor. `canBecomeKey`'i bizde `false` tutuyoruz (menü bar uygulaması odak çalmamalı); ESC ile collapse için Faz 1'de `NSEvent.addLocalMonitorForEvents` veya panel'e özel bir key handler kullanacağız.

**Dikkat:** (a) DNK `collectionBehavior`'a `.fullScreenAuxiliary` **koymuyor** → tam ekran uygulamaların üstünde görünmesi garanti değil; PLAN §5.3'ün "tam ekranda kontroller çalışmaya devam eder" kriteri için bizim setimiz doğru olan. (b) `NSPanel`'de `hidesOnDeactivate` varsayılanı `true`'dur ve DNK bunu set etmiyor; bizim açık `false`'umuzu koru. (c) `isOpaque` set edilmediği için şeffaflık `backgroundColor = .clear` davranışına bırakılmış — bizde açık `false` kalmalı. (d) `ignoresMouseEvents` hiç set edilmediğinden yarım ekran boyundaki panel, SwiftUI hit-test'ine bağlı olarak fare olaylarını yutabilir (bkz. 3.4 Dikkat).

### 3.2 Notch tespiti, otomatik stil ve notch'suz fallback

**Nasıl çalışıyor:** `NSScreen+Extensions.swift:19-21`'de `hasNotch`, yalnızca `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`'nın nil olmamasına bakıyor (`safeAreaInsets.top`'a bakmıyor). `notchSize` (23-34) genişliği `frame.width - leftWidth - rightWidth`, yüksekliği `safeAreaInsets.top` olarak alıyor; `notchFrame` (36-44) ise x'i **ekranın `midX`'ine göre** kuruyor, yani auxiliary alanların gerçek x'lerini kullanmıyor. `menubarHeight = frame.maxY - visibleFrame.maxY` (46-48). Notch'suz ekran için `notchFrameWithMenubarAsBackup` (50-66) **300pt sabit genişlik** + menü bar yüksekliği uyduruyor. Stil seçimi `DynamicNotch.swift:340-345`: `.auto` ise `screen.hasNotch ? .notch : .floating`. Floating durumda `compact()` çağrısı sessizce `hide()`'a düşüyor (`DynamicNotch.swift:226-229`) — yani notch'suz Mac'te compact durumu **yok**.

**Bize uyarlama:** `NotchGeometry.notchRect(for:)` bizde daha sağlam: `safeAreaTop > 0` **ve** iki auxiliary alan şartı, genişlik `right.minX - left.maxX` ve `width > 0` guard'ı (`Core/Window/NotchGeometry.swift:19-33`). DNK'nin `menubarHeight`'ını alıyoruz — hover'da compact şeridi menü bar yüksekliğine büyütmek için gerekli (3.7). `notchFrameWithMenubarAsBackup`'ın 300pt sabitini **almıyoruz**; `NotchLayout.fallbackNotchSize` yerine Faz 1'de floating capsule ölçüsünü içerikten (compact şerit genişliği) türeteceğiz. Notch'suz ekranda compact'ı kapatma kararı bizde de mantıklı: `NotchState.compact` yalnızca `metrics.hasNotch` iken anlamlı; aksi halde `closed` ↔ `popup/expanded` kapsülü.

**Dikkat:** DNK'nin `notchFrame`'i notch'un ekran ortasında olduğunu varsayıyor; bu donanımda doğru ve `auxiliaryTop*Area`'nın koordinat uzayı (ekran-yerel mi global mi) belirsizliğinden **kaçınıyor**. Bizim `NotchGeometry` `x: left.maxX` ile global y'yi karıştırıyor; dahili ekranın `frame.origin`'i (0,0) olmadığı çoklu ekran dizilimlerinde bunu doğrulamak gerekiyor (§6). `hasNotch`'un yalnızca auxiliary alanlara bakması, harici ekranlarda `nil` döndüğü için pratikte çalışıyor ama `safeAreaInsets.top` şartı olmadan macOS sürüm değişikliklerine daha kırılgan.

### 3.3 NotchShape: içbükey "kulak" Bezier'i

**Nasıl çalışıyor:** `Views/NotchShape.swift:35-118` tek bir `Path` ile 8 segment çiziyor: üst-sol köşeden başlıyor, `control` noktasını köşenin **kendisine** koyan bir `addQuadCurve` ile içe doğru bükülen (concave) "kulak" üretiyor, sol kenardan aşağı iniyor, altta klasik konveks yuvarlatma yapıyor, sağda aynısını ayna simetrisiyle tekrarlıyor ve üst kenar boyunca kapanıyor. İki parametre var: `topCornerRadius` (kulak yarıçapı) ve `bottomCornerRadius` (alt köşe yarıçapı); ikisi `animatableData: AnimatablePair<CGFloat, CGFloat>` üzerinden interpolate ediliyor (satır 22-33). Kullanılan somut değerler: compact `(top: 6, bottom: 14)` (`NotchView.swift:28-30`), expanded preset `(top: 15, bottom: 20)` (`DynamicNotchStyle.swift:45`), floating `cornerRadius: 20` (satır 48). Shape'in gövdesi her iki yandan `topCornerRadius` kadar içe kayıyor; bu yüzden minimum genişlik `notchSize.width + topCornerRadius * 2` (`NotchView.swift:32-34`) ve içerik `padding(.horizontal, topCornerRadius)` alıyor (satır 97).

```swift
path.move(to: CGPoint(x: rect.minX, y: rect.minY))
path.addQuadCurve(
    to: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY + topCornerRadius),
    control: CGPoint(x: rect.minX + topCornerRadius, y: rect.minY)
)
```
Kaynak: references/DynamicNotchKit/Sources/DynamicNotchKit/Views/NotchShape.swift:38 (MIT)

**Bize uyarlama:** Bu shape'i `Core/Window/NotchShape.swift`'e adapte ediyoruz (`// Adapted from MrKai77/DynamicNotchKit (MIT)` + `THIRD_PARTY_LICENSES.md`). PLAN §4.4 tek parametrik shape istiyor: `bottomCornerRadius` + `topOuterCurve` (= DNK'nin `topCornerRadius`'u) doğrudan eşleşiyor. Faz 0'daki `NotchRootView`'ın `UnevenRoundedRectangle`'ı bununla değişecek. Değişiklikler: (1) closed durumda `topCornerRadius = 0` verip fiziksel notch ile birebir dikdörtgen elde etmek — DNK closed'ı hiç çizmiyor, bizde `closed` gerçek bir durum; (2) `animatableData`'yı üçüncü parametreyle (capsule/floating için tek yarıçap) genişletmek yerine `NotchShape` içinde `style` enum'ı taşımak; (3) `nonisolated` + birim testli tutmak (path köşe noktaları için XCTest).

**Dikkat:** Quad curve'ün control noktası köşe noktasıyla çakıştığı için kulak "dairesel" değil parabolik; büyük `topCornerRadius` değerlerinde donanım notch'unun gerçek köşesiyle hafif uyumsuzluk olur — expanded'da 15 civarı iyi, 25+ değerlerde göz alıyor. `topCornerRadius` arttıkça shape'in çizim alanı daraldığı için genişlik hesabını (`minWidth`) parametreye bağlamayı unutmamak gerekiyor, yoksa expanded'a geçişte kulaklar içeriği kırpıyor. `#Preview` (satır 121-124) 200×32 ile `(6, 14)` gösteriyor; Debug Preview'da aynı ölçekte başlamak iyi bir kalibrasyon noktası.

### 3.4 Sabit pencere + animasyonlu içerik (bizim "panel her zaman expanded boyutta" kuralı)

**Nasıl çalışıyor:** Pencere boyutu ekranın **yarısı** olarak sabitleniyor: `size = (screen.frame.width / 2, screen.frame.height / 2)`, origin `x: screen.frame.midX - size.width/2`, `y: screen.frame.maxY - size.height` (`DynamicNotch.swift:368-383`) — yani üst kenara yapışık, yatayda ortalı, ve **hiçbir durum geçişinde yeniden boyutlanmıyor**. Görsel değişimin tamamı SwiftUI içinde: `NotchView.swift:56-77` içeriğin arkasına düz siyah bir `Rectangle` koyuyor ve ona `padding(-50)` veriyor ("açılış/kapanış animasyonu overshoot edebilir, siyah kalsın" — satır 61), sonra tüm yığını `NotchShape` ile `mask` ediyor. `hidden` durumda mask `minWidth × notchSize.height`'a sabitleniyor (satır 70-72), diğer durumlarda içeriğin doğal boyutunu alıyor. İçerik boyutlandırma tamamen `safeAreaInset` ile yapılıyor: expanded içerik üstten `notchSize.height` (satır 148), diğer üç kenardan 15pt (satır 149-151); compact yan içerikler dıştan 8pt, üstten 4pt, alttan 8pt (satır 108-110, 121-123). `fixedSize()` + `frame(minWidth:minHeight:)` (satır 98-99) pencereyi değil içeriği ölçüyor.

```swift
let size = NSSize(width: screen.frame.width / 2, height: screen.frame.height / 2)
let origin = NSPoint(x: screen.frame.midX - (size.width / 2),
                     y: screen.frame.maxY - size.height)
panel.setFrame(NSRect(origin: origin, size: size), display: false)
```
Kaynak: references/DynamicNotchKit/Sources/DynamicNotchKit/DynamicNotch/DynamicNotch.swift:368 (MIT)

**Bize uyarlama:** PLAN §4.1'in "pencere her zaman expanded boyutta dursun, içerik animasyonu yapılsın" kuralı burada bire bir doğrulanıyor — DNK pencereyi hiç resize etmiyor. `NotchLayout.expandedPanelSize = 600×240` yaklaşımımızı koruyoruz (yarım ekran yerine sabit ve küçük), ancak (a) gölge için pay bırakmalı (skills reposundaki `shadowPadding = 20` mantığı), (b) `NotchRootView` içinde mask edilen shape'in overshoot'unda siyahın kaybolmaması için DNK'nin `padding(-50)` hilesini `Anim.morph`'un overshoot'una göre boyutlandırmalıyız. `safeAreaInset` kalıbı `NotchModule` sözleşmesine iyi oturuyor: modül view'ları kendi padding'ini bilmez, `NotchRootView` compact/expanded slotlarına insets'i uygular.

**Dikkat:** `mask` SwiftUI'da hit-test'i kırpmaz; `-50` padding'li siyah `Rectangle` de layout'u büyütmese bile hit-test'e katılabilir. DNK `ignoresMouseEvents` kullanmadığından, görünür silüetin dışındaki ~50pt bant tıklamaları yutabilir. Bizde menü barın notch'un sağı/solu **tıklanabilir kalmalı**: Faz 1'de `contentShape(NotchShape(...))` (veya codex-island'ın silüet-dışı click-through'u) zorunlu; `ignoresMouseEvents = true` bırakılırsa hover hiç tetiklenmez (bkz. 3.7). Ayrıca yarım ekran şeffaf pencere = büyük compositing yüzeyi; 600×240 tercihimiz boşta CPU/GPU açısından da doğru.

### 3.5 Göster/gizle koreografisi

**Nasıl çalışıyor:** Açılışta sıra bilinçli olarak ters: pencere `orderFront` **edilmeden** yaratılıyor (`initializeWindow(screen:orderFront: false)`), animasyon `withAnimation` ile başlatılıyor, **sonra** pencere gösteriliyor (`DynamicNotch.swift:184-194`; yorum: "Start animation BEFORE showing window - this eliminates stutter"). `showWindow()` (395-408) pencereyi `alphaValue = 0` ile `orderFrontRegardless()` yapıp 0.15s `easeOut` ile 1'e fade ediyor. Kapanışta: `withAnimation(closing) { state = .hidden }`, ardından `Task` 0.25s bekliyor ("animasyonun büyük kısmı"), 0.15s `easeIn` alpha fade-out (318-331), sonra `deinitializeWindow()` (304-314). Her `expand()/compact()` çağrısı sonunda API `Task.sleep(0.4)` ile animasyon süresini elle bekliyor (satır 216, 272). Animasyon eğrileri stile bağlı: açılış notch'ta `.bouncy(duration: 0.4)`, floating'de `.snappy(duration: 0.4)`; kapanış `.smooth(duration: 0.4)`; dönüşüm `.snappy(duration: 0.4)` (`DynamicNotchStyle.swift:66-80`), hepsi `DynamicNotchTransitionConfiguration` ile override edilebiliyor.

```swift
initializeWindow(screen: screen, orderFront: false)
withAnimation(effectiveOpeningAnimation) { self.state = .expanded }
showWindow()
```
Kaynak: references/DynamicNotchKit/Sources/DynamicNotchKit/DynamicNotch/DynamicNotch.swift:186 (MIT)

**Bize uyarlama:** Bizde panel kalıcı ve `closed` durumda da ekranda (fiziksel notch ile birebir siyah), dolayısıyla "animasyonu pencereden önce başlat" hilesine **ihtiyacımız yok** — stutter kaynağı zaten ortadan kalkıyor. Alpha fade'i yalnızca panelin gerçekten `orderOut` edildiği durumlarda (hiç modül aktif değil + `closed`, ya da hedef ekran kayboldu) kullanacağız. Süreleri `Core/State/Anim.swift`'e taşıyoruz: `Anim.morph` ≈ DNK'nin `.bouncy(0.4)`/`.snappy(0.4)` bandı, `Anim.popIn` popup için overshoot'lu, `Anim.subtle` opacity/blur için. DNK'nin açılış/kapanış/dönüşüm ayrımı iyi bir fikir; `Anim`'e üç isim olarak (`open`, `close`, `convert`) veya `NotchState` geçiş matrisi olarak taşınabilir.

**Dikkat:** `Task.sleep` ile animasyon süresini beklemek kırılgan (animasyon değişince sabitler kayıyor) ve bizim state-driven modelimize uymaz — `NotchViewModel` sadece `state`'i değiştirir, süre bilgisi `Anim`'de kalır. `_hide` içindeki `closePanelTask` iptal edilmezse pencere yanlış anda kapanır; bizde `closed`'a dönüş kalıcı panelle olduğu için bu risk yok. `withAnimation` bloğu `@Published` bir alanı değiştirdiği için tüm hosting view yeniden değerlendiriliyor; bizde `@Observable` + dar scope'lu view'lar tercih edilmeli.

### 3.6 compact ↔ expanded dönüşümü ve ara `hidden` adımı

**Nasıl çalışıyor:** Pencere zaten varken compact→expanded (veya tersi) geçişi varsayılan olarak **doğrudan yapılmıyor**: `withAnimation(closing) { state = .hidden }` → 0.25s bekle → `withAnimation(conversion) { state = .expanded }` (`DynamicNotch.swift:196-211` ve simetriği 251-268). Yani içerik önce notch'a kapanıp sonra yeni haliyle açılıyor. Bu davranış `transitionConfiguration.skipIntermediateHides` ile kapatılabiliyor (`DynamicNotchTransitionConfiguration.swift:39`); `DynamicNotchInfo` compact ikonu expanded ikonundan türettiğinde bunu `true` yapıyor (`DynamicNotchInfo.swift:95-100`) çünkü `matchedGeometryEffect` ile ikonu uçurmak istiyor (`DynamicNotchInfo+HelperViews.swift:19-27, 52-60`, id: `"info_icon"`, `isSource` state'e göre seçiliyor). İçerik geçişleri custom transition'larla: compact yan içerikler `blur(intensity: 10) + scale(x: 0, anchor: .trailing/.leading) + opacity` (`NotchView.swift:112, 125`), expanded içerik `blur(intensity: 10) + scale(y: 0.6, anchor: .top) + opacity` (satır 145).

**Bize uyarlama:** Bizim hedefimiz PLAN §4.4'teki "akışkan büyüme" — yani **her zaman `skipIntermediateHides = true` davranışı**: `NotchShape` parametrelerini (`topCornerRadius`, `bottomCornerRadius`, genişlik/yükseklik) tek `withAnimation(Anim.morph)` içinde interpolate edip araya `closed`/`hidden` sokmamak. Ortak öğeler (albüm kapağı, ✳ ikonu) için `matchedGeometryEffect` deseni ve `namespace`'i tek yerde tutma fikri (`DynamicNotch.swift:69` + `NotchContentView.swift:56-60`) doğrudan alınabilir: `NotchRootView` bir `@Namespace` üretir, `NotchModule` view'larına environment ile geçer. `blur + scale + opacity` üçlüsü `Anim`'e `AnyTransition` yardımcıları olarak taşınacak (`BlurModifier.swift:30-43` adapte).

**Dikkat:** DNK'nin araya `hidden` sokmasının sebebi büyük olasılıkla mask'lanan shape ile `matchedGeometryEffect`'in aynı anda düzgün çalışmaması — bu tam olarak bizim yapmak istediğimiz şey, dolayısıyla Faz 1'de **erken prototiplenmeli** (Debug Preview'da). Eğer morph titrerse çözüm shape'i mask yerine `clipShape` + tek `Canvas`/`Shape` katmanına almak veya içerik geçişini `.transition` yerine `opacity/blur` sürücüsüne bağlamak olabilir. Ayrıca `matchedGeometryEffect`'te `isSource` iki tarafta birden `true` olursa SwiftUI uyarı verip geometriyi bozar; DNK bunu `state` karşılaştırmasıyla çözüyor, biz de aynı disiplini uygulamalıyız.

### 3.7 Hover davranışı

**Nasıl çalışıyor:** Hover tespiti SwiftUI `.onHover` ile, hem notch (`NotchView.swift:100`) hem floating (`NotchlessView.swift:43`) yolunda; `NSTrackingArea` **kullanılmıyor**. `updateHoverState` (`DynamicNotch.swift:157-167`) yalnızca durum değiştiğinde ve `state != .hidden` iken çalışıyor, `hoverBehavior` içinde `.hapticFeedback` varsa `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)` çağırıyor. `hoverBehavior` bir `OptionSet`: `.keepVisible`, `.hapticFeedback`, `.increaseShadow`, varsayılan `.all` (`DynamicNotchHoverBehavior.swift:27-36`). Hover'ın görsel etkileri: compact şeridin yüksekliği `notchSize.height` → `menubarHeight`'a çıkıyor (`NotchView.swift:86`), gölge opacity 0.5 → 0.8 ve radius 10 → 20 (`NotchContentView.swift:20-38`), tüm hover geçişi `.snappy(duration: 0.4)` (satır 55). `.keepVisible` varsa `_hide` fare üzerindeyken kendini 0.1s aralıkla erteliyor (`DynamicNotch.swift:290-296`). **Hover expand'i tetiklemiyor** — bu tamamen çağıran uygulamanın işi.

**Bize uyarlama:** PLAN §4.1 hover→expand'i (ayarlanabilir ~0.15s gecikmeyle) bizim sorumluluğumuza bırakıyor; DNK'den alacağımız `.onHover` + `isHovering` + hover'a bağlı gölge/yükseklik kalıbı. `NotchViewModel`'de `hoverIntent` ve iki timer'lı davranış: giriş için `SettingsStore.hoverDelay` (varsayılan 0.15s) sonra `state = .expanded(moduleID:)`; çıkış için kısa bir grace period (DNK'nin `.keepVisible` 0.1s retry'ı bunun ilkel hali) sonra `compact`/`closed`. `.hapticFeedback` ve `.increaseShadow` opsiyonları `SettingsStore`'a birer toggle olarak taşınabilir (Faz 5). `menubarHeight`'a büyüyen compact şerit hoş bir detay — notch yüksekliği menü bar yüksekliğinden küçük olduğu için hover'da şerit "menü bar hizasına" oturuyor.

**Dikkat:** `.onHover` yalnızca panel fare olaylarını alıyorsa çalışır → `NotchPanel.ignoresMouseEvents` Faz 1'de `false` olmak zorunda; hit alanını `contentShape` ile silüete kısmak şart, aksi halde 600×240'lık şeffaf alan menü bar tıklamalarını yutar. `NSTrackingArea` alternatifi (PLAN §4.1) shape'e göre kırpılamadığı için `.onHover` + `contentShape` daha isabetli; PLAN'daki `NSTrackingArea` ifadesi bu yüzden gözden geçirilmeli (§4). Tam ekran/Space geçişlerinde `.onHover` "exited" olayını kaçırabiliyor — `NotchViewModel`'e "fare gerçekten dışarıda mı" doğrulaması (`NSEvent.mouseLocation` + panel frame) eklemek gerekebilir. Hover animasyonu `.snappy(0.4)` tüm ağacı etkilediği için canlı animasyonlarla (equalizer) çakışmamasına dikkat.

### 3.8 Compact yan içeriklerin ölçülmesi ve merkez dengelemesi

**Nasıl çalışıyor:** Compact leading ve trailing içerikler genişliklerini `onGeometryChange(for: CGFloat.self, of: \.size.width)` ile bildiriyor (`NotchView.swift:111, 124`). Aradaki boşluk tam olarak fiziksel notch genişliği kadar bir `Spacer` (satır 116). İki yan asimetrik olduğunda tüm yığın `compactXOffset = (compactTrailingWidth - compactLeadingWidth) / 2` kadar kaydırılıyor (satır 52-54, 75) ki fiziksel notch şeridin ortasında kalsın; expanded'da offset 0'a dönerken içerik ters offset alıyor (satır 83, 95) — böylece geçişte içerik yerinde durur gibi görünüyor. Genişlik değişimleri `.animation(.smooth, value: [compactLeadingWidth, compactTrailingWidth])` ile yumuşatılıyor (satır 76).

**Bize uyarlama:** Bu, `NotchModule.compactLeading()/compactTrailing()` sözleşmemizin (PLAN §4.3) tam karşılığı: modül iki bağımsız view verir, motor ölçer ve notch'u ortada tutar. `NotchRootView` bu ölçüm + offset mantığını üstlenir; modül hiçbir konumlama bilgisi taşımaz. Asimetrik compact (solda albüm kapağı 20×20, sağda equalizer ~30) bizim MVP senaryomuz olduğu için offset dengelemesi kesinlikle gerekli.

**Dikkat:** `onGeometryChange(for:of:action:)` **macOS 15.0+**; DNK `Package.swift:9`'da macOS 13 iddia etmesine rağmen bu API'yi kullanıyor (yani paket beyan ettiği minimumda derlenmez). Bizim minimumumuz macOS 14 → bu satırlar `GeometryReader` + `PreferenceKey` (veya `#available(macOS 15)` ile iki yollu) olarak **yeniden yazılmalı**. Aynı dosyadaki `.bouncy/.snappy/.smooth(duration:)` macOS 14+ olduğu için bizde sorunsuz; `@Entry` makrosu (`EnvironmentValues+Extensions.swift:11-12`) Xcode 16+ toolchain gerektiriyor ama derleme zamanı genişlediği için macOS 14'te çalışır (bizde Xcode 26.4 var). Ölçüm→offset döngüsü her frame'de layout tetikleyebilir; boşta CPU hedefimiz için ölçümü yalnızca compact durumda aktif tutmalıyız.

### 3.9 Notch'suz ekran: floating panel

**Nasıl çalışıyor:** `NotchlessView.swift` ayrı bir görsel dil kullanıyor: `VisualEffectView(material: .popover, blendingMode: .behindWindow)` zemin, üzerine `RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.quaternary, lineWidth: 1)` kenarlık, `clipShape(.rect(cornerRadius:))` ve 20pt dış padding (satır 29-37). Giriş/çıkış animasyonu offset ile: `offset(y: state == .expanded ? notchSize.height : -windowHeight)` (satır 42) — yani panel ekranın üstünden aşağı kayarak giriyor, kapanırken kendi yüksekliği kadar yukarı çıkıp tamamen ekran dışına gidiyor; `windowHeight` `onGeometryChange` ile ölçülüyor (38-41). Bu modda compact yok (3.2).

**Bize uyarlama:** PLAN §4.1 notch'suz Mac'te "üst-ortada yüzen hap (floating capsule)" istiyor — DNK'nin konumu (üst-orta, aşağı kayarak giriş) bizimle uyumlu; şekil olarak biz `NotchShape`'i `topCornerRadius = 0` + tek yarıçapla capsule'e indirerek **aynı shape ailesinden** üreteceğiz, ayrı bir view hiyerarşisi kurmayacağız (DNK iki paralel view ağacı tutuyor: `NotchView` + `NotchlessView`). `ultraThinMaterial`/`.popover` malzemesi ve 1pt quaternary kenarlık fikri doğrudan alınabilir; PLAN §5.2'deki "artwork baskın rengiyle tint + ultraThinMaterial" ile birleşir. Yukarı kayıp kaybolma animasyonu (`-windowHeight`) closed durumumuzun capsule karşılığı olabilir.

**Dikkat:** Bu modda `level = .screenSaver` kalıyor; harici ekranda menü barın üstünde duran yarı saydam bir panel rahatsız edici olabilir — Faz 5'te "harici ekranda göster" ayarı ve muhtemelen daha alçak bir seviye (`.floating`) düşünülmeli. `.behindWindow` blending, panel `.screenSaver` seviyesinde ve tüm Space'lerde iken beklenmedik sonuç verebilir (arkasında ne olduğu belirsiz); ölçmek gerek.

### 3.10 DynamicNotchInfo / Progress presetleri

**Nasıl çalışıyor:** `DynamicNotchInfo` (`DynamicNotchInfo.swift:47-125`) `DynamicNotch`'u sarmalayıp hazır bir bilgi kartı sunuyor: `icon` + `title` + `description` + opsiyonel `compactLeading`/`compactTrailing`, hepsi `@Published` olduğu için gösterim sırasında `withAnimation` içinde değiştirilebiliyor (testlerdeki kullanım: `Tests/DynamicNotchKitTests/DynamicNotchKitTests.swift:40-46`). `Label` (`DynamicNotchInfo+Label.swift:16-152`) dört varyant taşıyor: `image`, `systemImage(systemName:color:)`, `progress(progress:color:overlay:)`, `customView`. `progress` varyantı `ProgressRing` çiziyor: `Circle().stroke(lineWidth:)` tertiary zemin + `trim(from: 0, to: target)` gradient üst katman, `lineCap: .round`, `rotationEffect(-90°)`, ilk görünümde `withAnimation(.timingCurve(0, 0.55, 0.45, 1, duration: 0.8).delay(0.1))` ile 0'dan hedefe dolan yükleme animasyonu (satır 127-149); kalınlık expanded'da 4, compact'ta 3 (satır 95). `InfoView` düzeni: `HStack(spacing: 10)` + ikon + `VStack` (title `.headline`, description `.caption2` %50 opacity), sabit `frame(height: 40)` (satır 52-68).

**Bize uyarlama:** `DynamicNotchInfo`'nun tamamını almıyoruz (bizde içeriği modüller verir), ama iki parça çok işimize yarar: (1) `ProgressRing` → `Modules/ClaudeUsage/Views/BlockRing.swift`'in temeli (5 saatlik ve haftalık pencere doluluğu, PLAN §6.2); gradient + round cap + `-90°` başlangıç + ilk açılışta dolma animasyonu aynen adapte edilebilir. (2) `Label` enum'ının "compact'ta 3pt, expanded'da 4pt" gibi bölüme duyarlı stil seçimi → bizde `EnvironmentValues.notchSection` benzeri bir environment key (`EnvironmentValues+Extensions.swift:10-19`, `DynamicNotchSection`) ile modül view'larının hangi slotta çizildiğini bilmesi. Bu, `NotchModule` protokolünün üç view'ının aynı alt bileşenleri paylaşmasını sağlar.

**Dikkat:** `Label.Style.progress` bir `Binding<CGFloat>` taşıyor ve `Equatable` karşılaştırması `wrappedValue` üzerinden yapılıyor — bizde `@Observable` model + düz `Double` yeterli, `Binding` taşımayacağız. `frame(height: 40)` gibi sabitler DNK'nin tek satırlık bilgi kartı için; bizim dashboard'umuz (progress ring + model kırılımı + burn rate) çok daha yüksek olacak, `expandedPanelSize`'ı buna göre doğrulamak lazım.

### 3.11 Çoklu ekran, ekran parametresi gözlemi ve pencere yaşam döngüsü

**Nasıl çalışıyor:** `observeScreenParameters()` (`DynamicNotch.swift:144-153`) `init` içinde bir `Task` başlatıyor ve `NotificationCenter.default.notifications(named: NSApplication.didChangeScreenParametersNotification)` akışını sonsuza kadar dinliyor; her olayda `NSScreen.screens.first` ile pencereyi **yeniden kuruyor** (varsayılan `orderFront: true`). Hedef ekran API seviyesinde çağırana bırakılmış: `expand(on: NSScreen.screens[0])` (satır 173). Ekran değiştiyse pencere yeniden yaratılıyor (`needsNewWindow = state == .hidden || windowController?.window?.screen != screen`, satır 182/238). `initializeWindow` her çağrıda önce `deinitializeWindow()` yapıyor (satır 352), yeni `NSHostingView` ve yeni panel üretiyor. `NSScreen.screenWithMouse` yardımcısı tanımlı ama motorda kullanılmıyor (`NSScreen+Extensions.swift:11-17`).

**Bize uyarlama:** Bizde tek uzun ömürlü panel var ve `NotchWindowController.reposition()` (mevcut `Core/Window/NotchWindowController.swift:45-59`) yalnızca frame + metrics güncelliyor — bu daha doğru ve DNK'nin yeniden-yaratma maliyetinden kurtuluyoruz. `Core/Window/ScreenObserver.swift`'e taşınacak kısım: bildirim akışını modern `Task`/`AsyncSequence` ile dinlemek (bizim `@objc` selector'ının yerine) ve **hedef ekran seçimi politikası**: varsayılan `screens.first { $0.hasNotch } ?? .main` (mevcut davranışımız), ayarla "tüm ekranlarda göster" (her ekrana bir panel) veya "farenin olduğu ekran" (`screenWithMouse` deseni). `didChangeScreenParametersNotification` yeterli değilse `NSWorkspace.activeSpaceDidChangeNotification` de eklenebilir.

**Dikkat:** DNK'nin `Task`'ı hiç iptal edilmiyor ve closure `self`'i güçlü tutuyor → `DynamicNotch` asla dealloc olmaz (sızıntı) ve `state == .hidden` iken bile ekran değişiminde pencere yaratıp `orderFrontRegardless` ediyor. Bizim `ScreenObserver`'ımız `Task`'ı sahibinin ömrüne bağlamalı (`deinit`'te cancel veya `withTaskCancellationHandler`) ve `NotificationCenter` observer'ı `deinit`'te kaldırmalı. `NSScreen.screens[0]`/`screens.first` **notch'lu ekran demek değil** — menü barın olduğu ekrandır; kullanıcı harici ekranı primary yaptığında DNK notch'u yanlış ekrana çizer. Bizim `hasNotch` filtreli seçimimizi koruyalım. Ekran uyandığında/çözünürlük değiştiğinde bildirim birkaç kez üst üste gelir; `reposition()` idempotent ve ucuz kalmalı (debounce düşünülebilir).

## 4. Plan ile çelişkiler / doğrulamalar

| PLAN varsayımı | DNK'de durum | Sonuç |
|---|---|---|
| `level = .screenSaver` (§4.1) | `DynamicNotchPanel.swift:25` aynen `.screenSaver` | **Doğrulandı.** `CGShieldingWindowLevel()` (macos-app-skills) alternatifi gerekmiyor; ölçümle karşılaştırılacak (§6). |
| `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` (§4.1) | DNK yalnızca `[.canJoinAllSpaces, .stationary]` — `.fullScreenAuxiliary` **yok** | **Bizde kalsın.** Tam ekran görünürlüğü PLAN §5.3 kabul kriteri; DNK bu senaryoyu desteklemiyor. |
| Pencere her zaman expanded boyutta, içerik animasyonlu (§4.1) | Pencere ekranın yarısı ve **hiç resize edilmiyor**; tüm morph SwiftUI'da | **Doğrulandı ve güçlendi.** Biz 600×240 sabitini koruyoruz (yarım ekran gerekmiyor); gölge payı eklenecek. |
| Hover: `NSTrackingArea` + ~0.15s gecikme (§4.1) | DNK SwiftUI `.onHover` kullanıyor, **gecikme yok**, hover expand'i tetiklemiyor (sadece görsel) | **Kısmi çelişki.** `.onHover` + `contentShape(NotchShape)` shape'e duyarlı olduğu için `NSTrackingArea`'ya tercih edilmeli; PLAN §4.1'deki ifade Faz 1'de güncellenmeli. Hover gecikmesi tamamen bizim eklememiz. |
| Dışarı tıklama / ESC → collapse (§4.1) | DNK'de yok; `canBecomeKey = true` ama klavye işlenmiyor | **Bizim işimiz.** `canBecomeKey = false` + `NSEvent.addLocalMonitorForEvents` (ESC) + panel dışı tıklama için global monitor. |
| Click-through (codex-island'dan, §2.1) | DNK `ignoresMouseEvents` kullanmıyor; `mask` + `-50` padding hit-test'i büyütüyor | **Boşluk.** DNK'den click-through gelmiyor; silüete kısıtlı hit-test codex-island notundan alınacak. `mask` yerine `contentShape` şart. |
| Notch'suz Mac: üst-ortada yüzen hap (§4.1) | DNK üst-orta yüzen **rounded rect** (r=20, `.popover` material), aşağı kayarak giriyor; compact desteklemiyor | **Uyumlu.** Konum ve giriş animasyonu alınır; şekli ayrı view ağacı yerine `NotchShape` parametreleriyle üreteceğiz. |
| Notch ölçüleri `safeAreaInsets` / `auxiliaryTop*Area`'dan, sabit yok (§13) | DNK notch'suz ekran için **300pt sabit** genişlik uyduruyor (`NSScreen+Extensions.swift:54`) | **Çelişki — almıyoruz.** Fallback ölçüsü içerikten türetilecek. |
| Min. macOS 14 (§3) | DNK `Package.swift:9`'da macOS 13 diyor ama `onGeometryChange` (macOS 15+) kullanıyor | **Dikkat.** Adapte ederken bu iki çağrı `GeometryReader`+`PreferenceKey` ile yeniden yazılacak; `@available` gerekmeyecek. |
| Anim tek yerde: `Anim.swift` spring(response:dampingFraction:) (§4.4) | DNK isimli eğriler kullanıyor: `.bouncy(0.4)` / `.snappy(0.4)` / `.smooth(0.4)`, stil ve geçiş tipine göre ayrı | **Uyumlu, zenginleştirilecek.** `Anim`'e geçiş tipine göre üç isim (open/close/convert) eklenmesi mantıklı; sayısal kalibrasyon Debug Preview slider'ları ile. |
| MVVM + `@Published var state` tek `NotchViewModel`'de (§4.2) | DNK `ObservableObject` + `@Published` (5 ayrı alan) ve imperatif `async` API (`await expand()` + `Task.sleep`) | **Kısmi çelişki.** Bizde `@Observable` (macOS 14+) ve saf state-driven geçişler; `Task.sleep` ile animasyon bekleme alınmıyor. |
| Boşta CPU < %1 (§4.4, §13) | DNK'de sürekli çalışan iptal edilmemiş `Task` + her gizlemede pencere yeniden yaratma + yarım ekran şeffaf yüzey | **Dikkat.** Üçünü de yapmayacağız; `closed` durumda ölçüm/animasyon yok. |

## 5. Bilinçli almayacaklarımız

1. **Pencereyi her gizlemede yok edip yeniden yaratmak** (`initializeWindow`/`deinitializeWindow`): bizde tek uzun ömürlü `NotchPanel` var; yeniden yaratma hem stutter hem `NSHostingView` maliyeti.
2. **compact↔expanded arasında ara `hidden` adımı ve 0.25s bekleme**: PLAN §4.4 doğrudan morph istiyor; `matchedGeometryEffect` + shape interpolasyonu ile.
3. **`Task.sleep(0.4)` ile animasyon süresini elle beklemek** ve `await expand()` tarzı imperatif API: `NotchViewModel` state değiştirir, süreler `Anim`'de.
4. **`NSScreen.screens[0]` / `screens.first` varsayılanı**: notch'lu ekranı garanti etmiyor.
5. **`notchFrameWithMenubarAsBackup`'ın 300pt sabiti** ve genel olarak uydurma ölçüler.
6. **Yarım ekran pencere footprint'i**: 600×240 + gölge payı yeterli; büyük şeffaf yüzey compositing ve hit-test riski.
7. **`onGeometryChange`** (macOS 15+) — macOS 14 minimumumuzu bozar.
8. **`canBecomeKey = true`**: menü bar uygulaması odak çalmamalı.
9. **`DynamicNotchInfo`'nun hazır bilgi kartı UI'ı** (title/description/Label seti): içeriği modüller verir; sadece `ProgressRing` ve "section-aware stil" fikri alınır.
10. **İptal edilmeyen `NotificationCenter` `Task`'ı** (retain cycle + gizliyken pencere açma).
11. **İki paralel view ağacı** (`NotchView` + `NotchlessView`): tek `NotchRootView` + parametrik `NotchShape`.

## 6. Açık sorular

1. `.screenSaver` (1000) macOS 26'da menü barın ve tam ekran uygulamaların üstünde kalmaya devam ediyor mu? `CGShieldingWindowLevel()` (macos-app-skills'in tercihi) gerçekten gerekiyor mu — gerçek makinede ölçülecek. DNK'de macOS 26'ya özel tek satır yok (`grep -i 'tahoe|glass|macOS 26'` → 0 sonuç), son commit 2026-02-18.
2. `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` ekran-yerel mi global koordinatta mı? Dahili ekran primary değilken (`frame.origin != .zero`) bizim `NotchGeometry.notchRect`'imiz doğru x veriyor mu? DNK `midX` kullanarak bu soruyu tamamen atlıyor — fallback olarak biz de `screen.frame.midX` ile karşılaştırmalı bir assert koyabiliriz.
3. `ignoresMouseEvents = false` + `contentShape(NotchShape)` kombinasyonu menü barın notch yanındaki tıklanabilirliğini gerçekten koruyor mu? `mask` ile hit-test ilişkisi ölçülmeli (codex-island'ın silüet click-through'u ile karşılaştır).
4. `matchedGeometryEffect` + mask'lanan animasyonlu `NotchShape` birlikte titremeden çalışıyor mu? (DNK'nin araya `hidden` sokmasının sebebi bu olabilir.) Faz 1'in ilk prototipi bunu ölçmeli.
5. `.bouncy(duration: 0.4)` mı `spring(response: 0.42, dampingFraction: 0.72)` mi MyNotch'un hareket kimliği olacak? Debug Preview'a iki preset + slider koyup karar verilecek.
6. Panel `sharingType`: notch içeriği ekran görüntüsü/kaydında görünsün mü? (macos-patterns `.none` seçeneğini hatırlatıyor; DNK hiç dokunmuyor.)
7. Hover'da compact şeridin `menubarHeight`'a büyümesi bizim compact tasarımımızda isteniyor mu, yoksa yükseklik sabit kalıp yalnızca genişlik mi büyüsün?
8. `NSPanel.hidesOnDeactivate` varsayılanının (`true`) `.nonactivatingPanel` ile birlikte davranışı — bizim açık `false`'umuz gerçekten gerekli mi, yoksa savunma amaçlı mı kalıyor?
