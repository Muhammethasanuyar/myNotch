# MyNotch — macOS Dynamic Notch App

MacBook notch'unu Dynamic Island benzeri canlı bir yüzeye çeviren menü bar uygulaması.
Yol haritası, mimari ve kararlar: `docs/PLAN.md` (Faz 0–3 tamam: iskelet, referans madenciliği, notch motoru, modül sistemi, medya modülü; sıradaki: Faz 4 Claude usage — başlamadan `docs/harvest/README.md` "Öne çıkan bulgular" bölümünü oku).

## Build & Run
- Proje dosyası XcodeGen ile üretilir: `xcodegen generate`. `project.yml` tek gerçek kaynaktır; `MyNotch.xcodeproj` ve `Resources/Info.plist` üretilir, git'e girmez.
- Build: `scripts/build.sh` (= `xcodebuild -project MyNotch.xcodeproj -scheme MyNotch -configuration Debug -derivedDataPath build build`)
- Test: `scripts/test.sh`
- Çalıştır: `scripts/run.sh [--args -debugTintNotch YES -openDebugPreview YES]` — önce build alır, çalışan örneği kapatır, `build/Build/Products/Debug/MyNotch.app`'i açar.
- Her değişiklikten sonra build al; derleme hatası ve uyarı bırakma.
- UI değişikliklerini önce Debug Preview penceresinde doğrula.

## Mimari kurallar
- UI = SwiftUI, pencere yönetimi = AppKit (`NotchPanel`, `NSWindowController` alt sınıfları). Bu sınırı koru.
- Swift 6 dil modu. Uygulama hedefinde varsayılan izolasyon `MainActor`; saf yardımcılar (geometri, layout hesapları) `nonisolated` ve birim testli.
- Notch ölçüleri her zaman `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`'dan hesaplanır (`Core/Window/NotchGeometry.swift`); sabit ölçü yok.
- Notch panelinde `ignoresMouseEvents` set edilmez (true da false da): set edilince pencere sunucusunun piksel-alfa tabanlı tıklama geçirgenliği kapanır ve menü bar panelin altında tıklanmaz olur. Geçirgenlik çizilen şeklin alfa'sına, hover `.onHover` + `contentShape(NotchShape)`'e bırakılır (bkz. `docs/harvest/README.md`).
- Durum makinesi: `Core/State/NotchState.swift` (closed/compact/expanded/popup), kurallar `NotchTransition` (saf, testli), zamanlama `NotchViewModel` (`@Observable`). Modül içeriği `NotchContentProvider` üzerinden gelir; sağlayıcıyı `ModuleManager.contentProvider()` üretir.
- Yeni özellik = `Modules/<Ad>/` altında yeni bir `NotchModule` + `AppDelegate`'te `ModuleManager.register(...)`; `Core/` dosyalarına modül-özel kod sızdırma.
- Modüller `NotchViewModel`'e dokunmaz: `start(context:)` ile aldıkları `ModuleContext` üzerinden `activityChanged()` ve `post(event)` çağırır; öncelik çözümü (`urgent > live(priority) > idle`) saf `ModuleResolver`'da, uygulama `ModuleManager`'da.
- `EventBus` bilinçli olarak Combine değil: her şey main-actor UI bağlantısı ve callback kaydı Swift 6 `Sendable` gereksinimlerini modül sözleşmesinden uzak tutuyor.
- Animasyon parametreleri yalnızca `Core/State/Anim.swift` içinde tanımlanır; Debug Preview'daki slider'lar `NotchViewModel.animation` kopyasını değiştirir.
- Ağ erişimi gerektiren modül parçaları (ör. `Modules/Media/LyricsService.swift` → LRCLIB) kapatılabilir bir bayrağın arkasında durur ve dışarı ne gönderdiğini dosya başlığında yazar.
- Private API yok (mediaremote-adapter hariç — sadece `Modules/Media/Generic` altında, feature flag arkasında).
- Ana thread'de AppleScript/Process çalıştırma; hepsi async. AppleScript `AppleScriptRunner` (osascript + özel seri kuyruk) üzerinden gider; sağlayıcılar script'i üretir ve çıktıyı saf `parse` fonksiyonlarıyla ayrıştırır (testli). Medya güncellemeleri olay güdümlüdür (dağıtık bildirimler), playhead yerel olarak ekstrapole edilir; poll yalnızca kaçan olaylar için 15 sn / 60 sn.
- Spotify favorileri Web API + PKCE ile (`Modules/Media/Spotify/`): client secret yok; kullanıcı kendi client ID'sini `spotifyClientID` default'uyla verir; redirect `http://127.0.0.1:48219/callback` sabittir; token'lar Application Support'ta 0600 dosyada (Keychain Faz 5). Ağa yalnızca kullanıcı bağlandıysa çıkılır, dışarı giden veri parça ID'sidir. Kalbin durumu `MediaProvider.favoriteSupport` ile anlatılır; kontrol gizlenmez, tıklama eksik adımı başlatır.
- Hataları sessizce yutma; açıkça fırlat ya da `assertionFailure` ile görünür kıl.

## Referans repolar ve skill'ler
- Referans klonları `references/` altında (git dışı); lisans denetimi ve desen notları `docs/harvest/README.md` + `docs/harvest/<repo>.md`. Bir deseni aktarmadan önce ilgili notu ve README'deki prompt şablonunu kullan.
- macOS skill'leri (`macos-patterns`, `macos-notch-ui`, `macos-settings-ui`, `macos-build`, `macos-auto-update`, `macos-release`) `~/.claude/skills/` altında kurulu; kaynak `fayazara/macos-app-skills`. Bu repoda `CLAUDE.md` ve `scripts/*.sh` skill talimatlarından önceliklidir.

## Lisans / devşirme kuralları (bağlayıcı)
- `references/` altından proje ağacına dosya KOPYALAMA. MIT/BSD/Apache kaynaklardan adapte et, dosya başına `// Adapted from <repo> (<lisans>)` ekle ve `THIRD_PARTY_LICENSES.md`'yi güncelle.
- boring.notch (GPL-3.0) ve LICENSE dosyası olmayan repolardan tek satır kod alma — sadece davranış incele.
- `references/` `.gitignore`'dadır; asla commit'lenmez.

## Debug Preview
- Menü bar → "Debug Preview": notch içeriğini normal, yeniden boyutlanabilir bir pencerede render eder.
- State butonları (closed/compact/expanded/popup) hem preview modeli hem gerçek notch için; modül paneli (aç/kapa, `DemoModule` için aktivite seçici ve "Next track", her modül için "Test popup"); floating stil simülasyonu; layout tint; animasyon slider'ları ve "Apply to real notch".
- Gerçek notch'a deploy etmeden animasyon iterasyonu burada yapılır.
- Launch arg'ları: `-debugTintNotch YES` (panel ayak izi kırmızı, şekil mavi), `-openDebugPreview YES` (açılışta preview penceresi), `-debugState closed|compact|expanded|popup` (durumu zorlar ve dışarı-tıklama monitörünü kapatır; ekran görüntüsü için), `-liveContent YES` (compact ile başla), `-demoLive YES` (demo modülü canlı yap), `-debugBanner YES` (başka modülden banner gönder).

## Test
- Mantık katmanları için XCTest (`MyNotchTests/`): `NotchGeometry`, `NotchLayout`, `NotchTransition`, `NotchViewModel` (async hover/popup zamanlaması), `ModuleResolver`, `EventBus`, `ModuleManager`.
- UI değişikliğinde: Debug Preview ekran görüntüsü + gerçek notch'ta manuel senaryo listesi (`docs/manual-tests.md`).
- AppleScript değiştirdiğinde sözdizimini `osacompile` ile doğrula (uygulamaya olay göndermez).

## Commit
- Conventional Commits (`feat(scope): …`, `fix(scope): …`, `chore(scope): …`, `docs(scope): …`); mesajlarda yapay zeka referansı yok.
- Faz/iş parçası bittiğinde build + test yeşilse onay sormadan commit'le ve `origin main`'e push et (kullanıcı 2026-09-03'te yetki verdi). Geri alınamaz işlemler (force-push, geçmiş yeniden yazma) için yine onay al.
