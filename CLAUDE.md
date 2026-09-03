# MyNotch — macOS Dynamic Notch App

MacBook notch'unu Dynamic Island benzeri canlı bir yüzeye çeviren menü bar uygulaması.
Yol haritası, mimari ve kararlar: `docs/PLAN.md` (Faz 0 iskelet tamam; sıradaki: Faz 0.5 referans madenciliği, Faz 1 notch motoru).

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
- Notch panelinde `ignoresMouseEvents` set edilmez (true da false da): set edilince pencere sunucusunun piksel-alfa tabanlı tıklama geçirgenliği kapanır ve menü bar panelin altında tıklanmaz olur. Geçirgenlik çizilen şeklin alfa'sına, hover `.onHover` + `contentShape(NotchShape)`'e bırakılır. Faz 0'daki geçici `ignoresMouseEvents = true` Faz 1'de kaldırılır (bkz. `docs/harvest/README.md`).
- Yeni özellik = yeni `NotchModule` (Faz 2'den itibaren); `Core/` dosyalarına modül-özel kod sızdırma.
- Animasyon parametreleri yalnızca `Core/State/Anim.swift` içinde tanımlanır (Faz 1).
- Private API yok (mediaremote-adapter hariç — sadece `Modules/Media/Generic` altında, feature flag arkasında).
- Ana thread'de AppleScript/Process çalıştırma; hepsi async.
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
- Faz 0: layout tint toggle + ekran/notch/panel metrikleri. Faz 1: state override butonları (closed/compact/expanded/popup), anim slider'ları, sahte veri.
- Gerçek notch'a deploy etmeden animasyon iterasyonu burada yapılır.
- Launch arg'ları: `-debugTintNotch YES` (panel ayak izi kırmızı, notch dikdörtgeni mavi), `-openDebugPreview YES` (açılışta preview penceresi).

## Test
- Mantık katmanları için XCTest (`MyNotchTests/`). Faz 0: `NotchGeometry` / `NotchLayout`.
- UI değişikliğinde: Debug Preview ekran görüntüsü + gerçek notch'ta manuel senaryo listesi.

## Commit
- Conventional Commits (`feat(scope): …`, `fix(scope): …`, `chore(scope): …`, `docs(scope): …`); onay almadan commit/push yapma.
