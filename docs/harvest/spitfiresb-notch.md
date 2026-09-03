# spitfiresb/notch — Harvest Notu

| | |
|---|---|
| Repo | https://github.com/spitfiresb/notch |
| Klon | `references/notch` @ `eb8f26a` (2026-08-31) |
| Lisans | LICENSE dosyası yok (tüm hakları saklı varsayılır). README "personal project" der, lisans ifadesi içermez. `PermissionPrompt/PermissionPrompt.swift` başlığı bu alt sistemin *kısmen* MIT'li bir kaynaktan türetildiğini söyler; bu, reponun kendisini lisanslamaz. |
| Devşirme modu | **Sadece davranış — kod kopyalama yok** |
| İlgili fazlar | 1 (pencere, hover, morph), 3 (Spotify AppleScript disiplini), 4/v2 (Claude oturumları), 5 (izin UX'i, CPU), 6 (gerçek visualizer) |

Bu not kod içermez; dosya yolları, sayısal sabitler ve Apple API adları olgu olarak verilir. Tasarım önerileri bizim sözleşmelerimize (NotchPanel / NotchState / NotchViewModel / Anim / NotchShape / NotchModule) göre sıfırdan yazılmıştır.

## 1. Bizim için değeri

Sıfırdan yazılmış, tek geliştiricili, Xcode projesiz (SwiftPM + `build.sh`) bir Dynamic Island. Üç konuda en iyi referans: (1) sabit boyutlu pencere içinde `matchedGeometryEffect` ile compact↔expanded morph'un *neden* çalıştığına dair yorumlarla belgelenmiş dersler, (2) CoreAudio process tap ile gerçek ses-reaktif çubuklar ve bunun boşta sıfır maliyetle kapılanması, (3) Claude Code lifecycle hook'larını daemon'suz, dosya tabanlı bir spool ile izleme. Ayrıca "her döngü olay-güdümlü ya da kapılı" disiplini bizim <%1 boşta CPU hedefimizin somut kanıtı. Karşı-örnek olarak da değerli: tam ekran ve Space geçişleri için özel (private) CGS/SkyLight ve MultitouchSupport API'lerine dayanır; biz bunları almayız.

## 2. İncelenen dosyalar

| Kaynak dosya (path) | Hangi davranışı gösteriyor | Bizde ilgili bileşen | Faz |
|---|---|---|---|
| `README.md`, `BUILD.md` | Ürün davranışı, mimari harita, izinler, ad-hoc imza sonuçları | `docs/PLAN.md`, `CLAUDE.md` | — |
| `Sources/Notch/Window/NotchPanel.swift` | `ScreenMetrics` (ekran/notch ölçüleri), `NotchShape`, `NotchPanel` (seviye, collectionBehavior, viewport), swipe algılama, tracking area | `Core/Window/NotchPanel.swift`, `NotchGeometry.swift`, `NotchShape.swift` | 1 |
| `Sources/Notch/Views/NotchRootView.swift` | Sabit pencerede büyüyen blob, morph, toast'lar, gölge, retract | `Core/Window/NotchRootView.swift`, `Core/State/Anim.swift` | 1, 2 |
| `Sources/Notch/App/AppDelegate.swift` | Hover değerlendirme (mouse-moved monitörleri), Mission Control tespiti, Space yeniden bağlama | `NotchWindowController.swift`, `NotchViewModel.swift` | 1, 5 |
| `Sources/Notch/App/AppEnvironment.swift` | `NotchState` (open/close/pin/toast süreleri), servis kapılama (ses tap'i yalnızca çalarken) | `NotchViewModel.swift`, `ModuleManager.swift` | 1, 2 |
| `Sources/Notch/Services/SpaceAttacher.swift` | Özel CGS overlay space ile Space'lere sabitleme | (alınmaz) | — |
| `Sources/Notch/Services/TrackpadGestureMonitor.swift` | Özel MultitouchSupport ile 3 parmak jest tespiti | (alınmaz) | — |
| `Sources/Notch/Services/AudioMeter.swift`, `Views/DancingBars.swift` | Process tap → 6 bant → çubuklar; sahte wiggle fallback | `Modules/Media/Views/EqualizerBars.swift`, Faz 6 `AudioMeter` | 3, 6 |
| `Sources/Notch/Services/NowPlaying.swift` | Özel MediaRemote köprüsü + Spotify Apple Events fallback, AppleScript derleme önbelleği, konum ekstrapolasyonu, artwork accent rengi | `Modules/Media/SpotifyProvider.swift`, `MediaController.swift`, `ArtworkCache.swift` | 3 |
| `Sources/Notch/Services/ClaudeHooks.swift`, `ClaudeSessions.swift` | Hook kurulumu, spool tail, oturum durum makinesi, interrupt tespiti, ölü süreç temizliği | Claude modülü v2 (`ProjectsWatcher` ötesi) | 4/v2 |
| `Sources/Notch/Views/Shared/TrackedHover.swift` | `.onHover` yerine AppKit probe view ile hover | (davranış) | 1 |
| `Sources/Notch/Services/Permissions.swift`, `PermissionPrompt/*` | TCC durum sorgusu, System Settings derin linkleri, rehberli izin overlay'i | `Settings/Onboarding.swift` | 5 |
| `Tests/NotchRenderTests/RenderTests.swift` | `ImageRenderer` ile ekran dışı PNG render harness'i | `MyNotchTests/` (Faz 1+), Debug Preview | 1 |

## 3. Davranışlar ve yaklaşımlar

### 3.1 Sabit boyutlu pencere, içeride büyüyen blob ("viewport" fikri)
**Ne yapıyor:** Pencere her zaman gösterilebilecek en büyük blob boyutunda durur (300×256 pt; normal expanded 300×108, toast 252×46, sürükleme damlası 110×34). Görünen siyah blob bu pencerenin içinde SwiftUI ile büyür/küçülür; açma-kapama tek bir SwiftUI animasyonudur, pencere hiç resize edilmez. Hosting view ekran boyutundadır ve pencere ona bir "viewport" gibi bakar; bu, notch'u kenardan kenara sürüklerken bile aynı view'ın çizmeye devam etmesini sağlar. `NSHostingView.sizingOptions` boşaltılmıştır: varsayılan ayarla içerik pencereyi ekran dışına büyütmüş ve pencere bir daha küçülmemiş. `constrainFrameRect(_:to:)` override edilerek AppKit'in pencereyi menü barın altına itmesi engellenir.
**Bizde nasıl yapacağız:** Faz 0'da zaten böyle: panel 600×240 sabit, `sizingOptions = []`. Faz 1'de `NotchWindowController`'a `constrainFrameRect` override'ı (kendi yazımımız) eklenir; ekran-boyutlu hosting view fikri bizim için gereksiz (kenara sürükleme kapsam dışı).
**Dikkat:** Pencere büyüdükçe şeffaf compositing alanı artar; 600×240 makul.

### 3.2 NotchShape: içbükey kenar kıvrımı + animatable parametreler
**Ne yapıyor:** Şekil üç parametreyle tanımlı: ekranla birleştiği yerdeki küçük ters kıvrım (8 pt), üst köşe yarıçapı (0) ve alt köşe yarıçapı (kapalıyken min(10, kısa kenar/2), açıkken 20, toast'ta 16). Her parametre `animatableData` ile anime edilir; ters kıvrım 0'a, üst yarıçap yarı yüksekliğe çekilince şekil kapsüle dönüşür (sürükleme damlası). Yan kenarlara affine transpoze ile taşınır.
**Bizde nasıl yapacağız:** `Core/Window/NotchShape.swift` parametrik: `earInset`, `topRadius`, `bottomRadius`; `AnimatablePair` zinciri; closed/compact/expanded parametre setleri `Anim`/`NotchLayout`'ta. DynamicNotchKit (MIT) notundaki radii (compact 6/14, expanded 15/20) başlangıç değeri; bu repodaki 8 pt kıvrım ve 20 pt açık yarıçap ikinci referans.
**Dikkat:** Kıvrım şeridi (8 pt) gölge ve stroke'un "dışarı taşmasına" açık; bkz. 3.4.

### 3.3 compact↔expanded morph ile ilgili dersler
**Ne yapıyor:** Albüm kapağı ve çubuklar paylaşılan bir `@Namespace` içinde iki kimlikle (`chromeArt`, `chromeBars`) hem küçük peek'te (14×14 kapak, 20×14 çubuk) hem müzik sekmesinde işaretlenir. Kritik dersler, yorumlarda belgelenmiş: (a) peek ile sekme arasında `if/else` kullanılır, iki view'ı aynı anda ağaçta tutup opacity ile değiştirmek matched geometry'ye interpolasyon yapacak iki düzen bırakmaz ve "ışınlanma" olur; (b) `.animation(_:value:)` doğrudan bu `if/else`'i içeren gruba konur, üst seviyedeki animasyon değişikliğe her zaman sızmıyor; (c) eşlenen kapak görselinde `.id`/`.transition` ve `.aspectRatio` kullanılmaz, bunlar interpolasyonla kavga edip "zıpla-sonra-yerleş" hissi verir; (d) açılış easeOut 0.32 s, kapanış easeOut 0.22 s (asimetrik, kapanış daha hızlı); (e) içerik `clipShape(blob şekli)` ile kırpılır.
**Bizde nasıl yapacağız:** `NotchRootView` `NotchState`'e göre `switch` ile tek bir alt ağaç seçer (closed/compact/expanded/popup); ortak öğeler için modül `compactLeading()`/`expandedView()` içinde aynı namespace'i kullanır (namespace `NotchModule` protokolüne environment ile verilir). `Anim.morph` spring'i açılış/kapanış için asimetrik iki varyanta ayrılabilir (`morphOpen`, `morphClose`). Debug Preview'da "ışınlanma" testi: kapak ve çubuk konumlarının ara karelerde sürekli hareket ettiğini gözle doğrula.
**Dikkat:** DynamicNotchKit notunun uyardığı gibi, animasyonlu maskeli şekil + matched geometry birlikte takılabilir; Faz 1 prototipinde ölçülür.

### 3.4 Gölge, stroke ve overlay yerleşimi
**Ne yapıyor:** Blob'un etrafına `.shadow()` uygulanınca gölge 8 pt kıvrım şeritlerine sızıp onları gri boyamış; çözüm, blob'un serbest kenarının hemen ötesine yerleştirilen ayrı, bulanık (10 pt blur), %36 siyah bir kapsül gölge. 1 pt %6 beyaz stroke blob şekliyle kırpılır. Köşe kontrolleri (dişli, Claude spinner) padding değil `.offset` ile konumlanır: padding düzene katılır ve kapalı pill'den yüksek bir inset tüm yığını şişirip peek'i klipin dışına iter.
**Bizde nasıl yapacağız:** Expanded gölgesi ayrı yönlü katman; stroke `clipShape` ile; köşe öğeleri `.offset` ile. Bunlar `NotchRootView`'ın tasarım kuralları olarak `CLAUDE.md`'ye alınabilir.

### 3.5 Hover: SwiftUI `.onHover` yerine geometri tabanlı cursor izleme
**Ne yapıyor:** Panelde hiç `.onHover` yok. AppDelegate global + local `NSEvent` monitörleriyle (`mouseMoved`, `leftMouseDragged`) her fare hareketinde `NSEvent.mouseLocation`'ı görünen blob dikdörtgeniyle (pencere çerçevesi değil) test eder; 0,5 s'lik yavaş bir emniyet zamanlayıcısı, blob'un hareketsiz imlecin altında değiştiği durumları (toast bitişi, kapanış) yakalar. Girişte **gecikmesiz** açılır, çıkışta (sabitlenmemişse) kapanır. Blob küçülüp imleç eski alanda kaldığında eski dikdörtgen "grace" olarak kilitlenir; imleç gerçekten çıkınca normal akış. Panel içi kontrollerin hover'ı için `.onHover` yerine içerik arkasına gömülen bir AppKit probe view'ı imleçle karşılaştırılır (offset ile taşınmış hosting view'da `.onHover` gecikmeli ve güvenilmez bulunmuş). Ekrandaki gerçek panelin tracking area'sı da `mouseMoved` üretir çünkü global monitör kendi pencerelerimiz için tetiklenmez.
**Bizde nasıl yapacağız:** İki aday: (A) DynamicNotchKit yolu, `.onHover` + `contentShape(NotchShape)`; (B) bu reponun yolu, global `mouseMoved` monitörü + `NotchGeometry` hit-test. B'nin avantajı hızlı imleci kaçırmaması ve `ignoresMouseEvents`'e ihtiyaç duymadan çalışması (monitör pencereden bağımsız); dezavantajı her fare hareketinde bir dikdörtgen testi (ucuz). Faz 1'de `NotchWindowController` içinde B ile başlanıp, `.onHover` yalnızca panel-içi butonlar için kullanılması önerilir; ~0,15 s açılma gecikmesi bizim kararımız olarak `NotchViewModel`'de uygulanır (imleç menü bara uzanırken kazara açılmayı önler).
**Dikkat:** `mouseMoved` global monitörü Erişilebilirlik izni gerektirmez (klavye olayları gerektirir). Grace-rect fikri, popup küçülürken imleç yerinde kalınca faydalı.

### 3.6 Tıklama geçirgenliği ve anahtar pencere
**Ne yapıyor:** Kapalıyken `ignoresMouseEvents` true, açıkken false yapılır (state'e bağlı toggle). Kapalı pill fiziksel notch'la çakıştığı için altında tıklanacak bir şey yoktur; açıkken 300×256 pencere menü barın o kısmını kapatır, geçici olduğu için kabul edilmiş. `canBecomeKey` true (scrubber ve metin alanları için), ilk tıklamayı `acceptsFirstMouse` ile SwiftUI hedefine iletir; `onTapGesture` yerine `DragGesture(minimumDistance: 0)` kullanır çünkü nonactivating panelde tap ilk (odak çalan) tıklamayı yutar.
**Bizde nasıl yapacağız:** claude-notch-tracker notundaki bulguyla çelişir ("`ignoresMouseEvents`'i hiç set etme, piksel-alfa geçirgenliği kapanır"). Bizim varsayılan tasarımımız: hiç set etmemek, geçirgenliği çizilen şeklin alfa'sına bırakmak; compact'ta yan şeritler (kapak/çubuk) tıklanabilir kalır, şeffaf alan menü bara geçer. Faz 1 prototipinde iki yaklaşım aynı testle karşılaştırılır: notch'un 20 pt yanındaki menü bar ögesine tıklama, compact ve expanded durumlarında. Tap için `DragGesture(minimumDistance: 0)` dersini alırız; `canBecomeKey` compact'ta false, expanded'da metin girişi gerekirse (arama) değerlendirilir.

### 3.7 Tam ekran, Space'ler ve Mission Control
**Ne yapıyor:** `.fullScreenAuxiliary` bilinçli olarak kullanılmaz: WindowServer, tam ekran bir Space içinde 3 parmak jesti algıladığı anda yardımcı pencereleri gizler (kendi cross-fade'i için). Bunun yerine özel CGS/SkyLight çağrılarıyla (`CGSSpaceCreate`, `CGSSpaceSetAbsoluteLevel` 400, `CGSAddWindowsToSpaces`, yönetilen Space'lerden çıkarma) kendi "overlay space"ini yaratır; pencere Space kaydırmalarında hiç hareket etmez. Space değişiminde yeniden bağlanır. Mission Control / App Exposé / Launchpad'i `CGWindowListCopyWindowInfo` ile Dock'a ait büyük pencereleri (katman > 0, genişlik > ekranın %50'si, yükseklik > %40'ı ya da üstte 80 pt'den yüksek şerit) arayarak tespit eder: boşta 2 s, overlay açıkken 0,4 s poll + occlusion-state bildirimi. Tespit edilince notch kapanır, blob kenarın ötesine (yükseklik + 24 pt) easeIn 0,26 s ile çekilir, 0,32 s sonra pencere `orderOut`; çıkışta yeniden konumlanır ve kritik sönümlü spring (response 0,40, damping 1,0) ile geri düşer. Pencere seviyesi imleç seviyesinin bir altı (çok yüksek).
**Bizde nasıl yapacağız:** Özel API yok (plan kuralı). `.fullScreenAuxiliary` + `.canJoinAllSpaces` + `.stationary` ile kalırız ve tam ekran Space'lerdeki jest sırasında kısa görünmezliği kabul edilmiş kısıt olarak belgeleriz. Mission Control'de saklanma isteğe bağlı Faz 5 cilası: `NSWindow.didChangeOcclusionStateNotification` (ücretsiz) birincil sinyal, `CGWindowList` taraması yalnızca occlusion tetiklediğinde bir kez çalıştırılır (sürekli 2 s poll yok). Geri dönüş animasyonu için kritik sönümlü spring dersi `Anim`'e alınır.
**Dikkat:** Sürekli `CGWindowList` IPC'si CPU hedefimizle çelişir; seviye olarak `.screenSaver` yeterli, imleç seviyesi gerekmez.

### 3.8 Boşta ~%0 CPU disiplini
**Ne yapıyor:** Her döngü olay-güdümlü ya da kapılı: ses tap'i yalnızca bir şey çalarken yaşar (duraklamada 2 s debounce ile kapatılır); hover fare hareketine bağlı, poll yok; imleç konumu yalnızca notch açıkken yayınlanır ("her publish ekran-boyutlu hosting view'ın düzenini geçersiz kılar"); ses ölçer çubuk 0,004'ten fazla oynadıysa yayınlar (aksi halde sessizlikte saniyede 60 objectWillChange tüm notch'u yeniden çizer); 60 Hz'den 30 Hz'e düşürülmüş poll ve zarf katsayıları buna göre dönüştürülmüş; sahte wiggle `TimelineView` 30 fps'e kapılı (ProMotion'da 120 Hz boşa); Now Playing için 15 s (çalarken) / 60 s (duraklamada) yalnızca kurtarma amaçlı poll, gerçek güncellemeler `com.spotify.client.PlaybackStateChanged` dağıtık bildiriminden; Claude spool'u vnode `DispatchSource` + 1 s emniyet poll'u; `NSAppleScript` derlemesi her seferinde XProtect YARA taraması (~25 ms ana thread CPU) tetiklediği için derlenmiş script'ler önbelleklenir, seek için pozisyon argümanlı tek derlenmiş handler kullanılır.
**Bizde nasıl yapacağız:** Bunlar doğrudan plan §4.4 ve §13'teki hedeflerin uygulama listesi: (1) `TimelineView`'lar görünürlüğe bağlı ve fps sınırlı; (2) modül `activity` yayınları `removeDuplicates` ve eşikli; (3) `SpotifyProvider` derlenmiş `NSAppleScript` önbelleği + parametreli seek handler; (4) konum için 1 s polling **yok**, yerel ekstrapolasyon (bkz. 3.10); (5) izleme kaynakları (`DispatchSource`) + seyrek emniyet zamanlayıcısı. Faz 5'te Instruments ile doğrulanır.

### 3.9 Gerçek ses visualizer'ı: CoreAudio process tap
**Ne yapıyor:** macOS 14.2 ile gelen `CATapDescription` (tüm süreçleri kapsayan stereo global tap) + `AudioHardwareCreateProcessTap`, tap'i içeren özel bir aggregate device (ana alt cihaz = varsayılan çıkış, drift compensation, otomatik başlatma) ve `AudioDeviceCreateIOProcIDWithBlock` ile IO proc. IO thread'inde örnek başına 6 RBJ direct-form-I bandpass biquad (Q 2,4; merkezler 80/200/500/1200/3000/7000 Hz), tampon başına bant RMS'i, kilitli anlık görüntü; ana thread 30 Hz'de okuyup dBFS'e çevirir, bant başına eğik pencere (taban −44…−62 dB, tavan −14…−32 dB; bas ağır müzik alt çubukları tavana yapıştırmasın) ile 0,10–1,0 aralığına eşler ve bant başına asimetrik atak/bırakma zarfı uygular. İlk çalmada sistem ses-yakalama TCC izni ister; reddedilirse çubuklar iki sinüs toplamı "wiggle"a düşer; duraklamada 0,14 dinlenme yüksekliği. Kapatmada IO proc, aggregate ve tap yok edilir.
**Bizde nasıl yapacağız:** Faz 6 opsiyonel `AudioMeter` bu yolu izler; plan §5.2'deki ScreenCaptureKit + Ekran Kaydı izni yolu yerine process tap tercih edilir (yalnızca ses yakalama onayı, ekran kaydı izni yok). `EqualizerBars` üç modlu: duraklama (düz), ölçer çalışıyor (gerçek), fallback (sahte). Bant sayısı ve pencereler `Anim` değil modül sabitleri.
**Dikkat:** macOS 14.2 alt sınırı (bizim min 14.0 → `if #available(macOS 14.2, *)` kapısı); gerçek zamanlı IO thread'inde ayırma/kilit yok; ad-hoc imzada TCC izni her build'de sıfırlanabilir (bkz. 3.13).

### 3.10 Now Playing ve Spotify Apple Events disiplini
**Ne yapıyor:** Özel MediaRemote framework'ü `dlopen` ile yüklenir (bilgi alma, bildirim kaydı, komut gönderme, konum ayarlama); payload boş gelirse (macOS 15.4+ kilidi) Spotify Apple Events'e düşer. AppleScript gövdesi tüm alanları tek çağrıda linefeed ile birleştirip döndürür (başlık, sanatçı, albüm, id, artwork url, durum, süre ms, konum s); süre milisaniyeden saniyeye çevrilir. Konum yerel olarak ekstrapole edilir: örneklenen konum + geçen duvar saati × oynatma hızı; poll sadece 15 s'de bir. Komut sonrası iyimser UI güncellemesi, 0,35–0,5 s sonra refresh. Artwork accent rengi `CIAreaAverage` sonrası doygunluk ×1,4 (min 0,55) ve parlaklık ×1,25 (0,75–0,95 aralığı) ile "punch"lanır; parça geçişinde son geçerli kapak/renk tutulur (placeholder flaşı yok).
**Bizde nasıl yapacağız:** Faz 3 `SpotifyProvider`: tek çağrılık toplu AppleScript, derlenmiş script önbelleği, dağıtık bildirimle olay-güdümlü yenileme, konum ekstrapolasyonu (plan §5.1'deki 1 s `player position` poll'u kaldırılır), `ArtworkCache` + accent hesaplama (plan §5.2 ile uyumlu, çarpanlar başlangıç değeri). Özel MediaRemote `dlopen` **alınmaz**; Faz 6'da mediaremote-adapter feature flag arkasında.
**Dikkat:** AppleScript çağrıları ana thread'de senkron (~40 ms); plan kuralı "ana thread'de AppleScript yok" ile çelişir → bizde `NSAppleScript` yerine ayrı bir aktörde `OSAScript`/`Process(osascript)` ya da ana thread dışı çalıştırma seçilir; TCC izin uyarısı ana thread gerektirdiği için ilk tetikleme onboarding'de ana thread'de yapılır.

### 3.11 Claude Code oturumlarını daemon'suz izleme
**Ne yapıyor:** Ayarlar'daki anahtar açılınca `~/Library/Application Support/Notch/claude-hook.sh` yazılır ve `~/.claude/settings.json`'a 15 lifecycle olayı için `{"type":"command","command":"\"<yol>\"","timeout":5,"async":true}` girdileri eklenir (yalnızca kendi girdilerini tanıyan bir imza alt dizesiyle; kaldırma yalnızca onları siler; idempotent). Script stdin'deki JSON'u `{"ts","pid","event"}` zarfıyla spool JSONL dosyasına ekler; **soket değil dosya**, böylece uygulama kapalıyken olaylar birikir ve açılışta sessizce (toast'sız) yeniden oynatılıp dosya kesilir. Store vnode `DispatchSource` (write/extend/delete/rename) + 1 s poll ile bayt ofsetinden artımlı okur, 4 MB'ta keser. Durumlar: idle → thinking → working (araç) → done/failed, `needs you` (izin/soru), `compacting`. Ölü süreçler 3 s'de bir liveness ile, pid'i çözülemeyenler cwd'de claude süreci yoksa 60 s'de ya da 1 saatte temizlenir. Interrupt tespiti iki yolla: transcript JSONL'in son 64 KB'ında son user/assistant mesajının `[Request interrupted…` ya da `interruptedMessageId` olması; ya da `nettop` çocuk süreciyle pid başına ağ trafiği ölçüp "thinking" durumunda 5 s yerleşme sonrası neredeyse sıfır byte gelirse "sessiz interrupt". Toast süreleri: tamamlandı 2,7 s, izin/soru 5,6 s, hata 4,6 s; "sana ihtiyaç var" toast'ı kullanıcı terminalde cevaplayınca erken kapanır. Terminal sekmesi tty ile, VS Code penceresi başlıkla (Erişilebilirlik) öne getirilir.
**Bizde nasıl yapacağız:** Claude modülü v2 için spool yaklaşımı vibe-notch'un soket yaklaşımına tercih edilebilir (offline biriktirme + replay). `~/.claude/settings.json` yazımı bizim salt-okunur doktrinimizi deldiği için açık opt-in, yedek dosyası, atomik minimal yazım ve tek tıkla geri alma şart (README'deki gibi anahtar kapalıyken hiçbir şey yazılmaz). Transcript kuyruğu okuyarak interrupt tespiti, `ProjectsWatcher` ile aynı dosyalara bakar; `nettop` gibi çocuk süreçler alınmaz. Toast süreleri `NotchEvent` önceliklerine başlangıç değeri.
**Dikkat:** Hook `timeout: 5` ve `async: true` ile Claude Code'u bloklamaz (vibe-notch 300 s bekletir). Hook JSON şeması Claude Code sürümüyle değişebilir; bilinmeyen olay adları `settings.json`'ı bozabilir (vibe-notch notu) → sürüm kapısı.

### 3.12 İzin UX'i
**Ne yapıyor:** Erişilebilirlik zorunlu (`AXIsProcessTrusted`; oturum pencerelerini öne getirmek için), Automation (Spotify) ve Dosyalar & Klasörler isteğe bağlı. Automation için sorgu API'si kalmadığından yalnızca kullanıcı bir kez "bağlan" dedikten sonra zararsız bir Apple Event göndererek durum yoklanır. `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` gibi derin linklerle ilgili pane açılır ve pane'in yanına non-activating bir overlay penceresi konup ne yapılacağı (listeye sürükle / anahtarı aç) animasyonla gösterilir; Settings penceresi Ekran Kaydı izni olmadan konumlanır.
**Bizde nasıl yapacağız:** Bizim tek ön koşulumuz Automation (Faz 3); Erişilebilirlik istemeyiz. Onboarding (Faz 5): "probe only after opt-in" kuralı, derin link ve pane yanında küçük rehber overlay (kendi tasarımımız). Ses yakalama izni yalnızca gerçek visualizer açıldığında istenir.

### 3.13 Ad-hoc imza ve TCC/keychain sonuçları
**Ne yapıyor:** `build.sh` `codesign --sign -` kullanır; her build'de imza kimliği değiştiği için ses yakalama ve Automation izinleri unutulabilir, keychain öğesi için her açılışta "Notch keychain'inizi kullanmak istiyor" diyaloğu çıkar, Erişilebilirlik grant'ı ayar anahtarıyla temizlenmez (`tccutil reset Accessibility <bundle>`), ilk çalıştırmada XProtect/Gatekeeper taraması kısa CPU sıçraması yapar.
**Bizde nasıl yapacağız:** Faz 0'da aynı durumdayız (identity yok). Faz 3'ten önce en azından kendinden imzalı sabit bir sertifika ya da Developer ID ile imzalamak Automation izninin kalıcılığı için gerekli; `tccutil reset AppleEvents com.emre.mynotch` geliştirme sırasında temizlik komutu. Keychain'e biz yazmayız (Claude token'ı yalnızca okunur), diyalog riski yok.

### 3.14 Ekran dışı render harness'i
**Ne yapıyor:** XCTest içinde `ImageRenderer` (ölçek 2) ile kök view ekran boyutunda çizilir, pencere çerçevesine kırpılır ve her dock/durum/tekerlek için `.build/renders/*.png` yazılır; piksel assert'i yoktur, gözle bakma ve diff amaçlıdır. `NowPlayingManager` DEBUG'a özel bir seed metoduyla sahte veri alır.
**Bizde nasıl yapacağız:** Debug Preview'ı tamamlayan bir `NotchRenderTests`: `NotchRootView`'ı her `NotchState` için sahte modül verisiyle render edip `build/renders/` altına PNG yazar; Claude Code oturumlarında bu PNG'ler okunarak görsel iterasyon yapılabilir (plan §12/1'in otomatik versiyonu). Test verisi için modüllere `previewData` sağlayıcıları.

## 4. Plan ile çelişkiler / doğrulamalar

- **Pencere seviyesi:** imleç seviyesinin bir altı (çok yüksek) vs bizim `.screenSaver` → plan geçerli; yorumlarına göre seviye Space geçişindeki boşluğu etkilemiyor, sadece menü bar/tam ekran üstüne çizim için.
- **`.fullScreenAuxiliary`:** kullanmıyor (jest sırasında gizlenme) ve özel CGS ile çözüyor → biz özel API almadığımız için `.fullScreenAuxiliary` kalır; kısıt belgelenir.
- **Hover gecikmesi:** 0 (anında) vs bizim ~0,15 s → plan geçerli; grace-rect fikri eklenir.
- **`ignoresMouseEvents`:** duruma göre toggle ediyor; claude-notch-tracker "asla set etme" diyor → Faz 1 deneyi; varsayılan: set etmemek.
- **Panel her zaman expanded boyutunda:** doğrulandı (hem burada hem DynamicNotchKit'te). `sizingOptions = []` ve `constrainFrameRect` override'ı ders.
- **Sahte vs gerçek visualizer:** burada gerçek; MVP'de sahte kararı geçerli, Faz 6'da process tap (ScreenCaptureKit değil).
- **§5.1 konum polling'i (1 s):** yerel ekstrapolasyon + 15 s kurtarma poll'u ile değiştirilmeli.
- **§5.1 AppleScript ana thread:** bu repo ana thread'de senkron çalıştırıyor; plan kuralımız ("hepsi async") geçerli, ama TCC ilk tetiklemesi ana thread ister.
- **§6.1 "Claude çalışıyor" tespiti:** mtime yaklaşımımız MVP için yeter; hook/spool modeli v2'ye aday (opt-in şartıyla).
- **CPU hedefleri:** yayın eşikleme, fps kapağı, olay-güdümlü poll ve tap kapılama teknikleri hedefi ulaşılabilir kılıyor.
- **Swift dil modu:** repo Swift 5 modunda; bizim Swift 6 + MainActor varsayılanımızda IO-thread/ana-thread ayrımı `nonisolated` + kilitli snapshot türüyle aynı biçimde kurulur (kendi yazımımız).

## 5. Bilinçli almayacaklarımız

- Özel CGS/SkyLight space API'leri (`SpaceAttacher`) ve özel MultitouchSupport jest monitörü.
- MediaRemote'u doğrudan `dlopen` etmek (Faz 6'da adapter, feature flag arkasında).
- Erişilebilirlik iznini zorunlu kılmak; pencere/sekme odaklama.
- `ignoresMouseEvents` toggle'ı ve `canBecomeKey = true` (compact'ta).
- Kenardan kenara sürükleme (droplet, landing ghost'ları), sürekli `CGWindowList` poll'u, `nettop` çocuk süreci.
- Ayarlara yazmadan hook kurma (bizde açık opt-in + yedek + geri alma).
- Spotify Web API kütüphane aynası, ekran görüntüsü sekmesi (kapsam dışı).

## 6. Açık sorular

1. `ignoresMouseEvents`'i hiç set etmeden compact'ta yan şeritlerin tıklanabilir, aradaki şeffaf alanın geçirgen kaldığı Faz 1'de doğrulanacak (iki repo çelişiyor).
2. `.fullScreenAuxiliary` ile tam ekran Space'te 3 parmak jesti sırasındaki görünmezlik süresi kabul edilebilir mi? macOS 26'da ölç.
3. `CATapDescription` yolu macOS 26'da onların testinde çalışıyor; bizim Swift 6 modunda IO callback'inin izolasyon modeli (nonisolated + kilit) derleyiciyle uyumlu mu? Faz 6 prototipi.
4. Hook JSON'unun 2026-09 itibarıyla Claude Code'daki güncel olay adları listesi (15 olay) hâlâ geçerli mi? v2 öncesi `claude --version` ile sürüm kapısı.
