# Release prosedürü

MyNotch GitHub Releases üzerinden dağıtılır; güncellemeleri Sparkle 2 okur. Bugün imza **ad-hoc**tur (bu Mac'te Developer ID yok); bölüm 5 kimlik gelince neyin değiştiğini anlatır. Tek komut: `scripts/release.sh <sürüm>`.

## 1. Ön koşullar (bir kez)

- `brew install xcodegen create-dmg gh` ve `gh auth login` (repo yazma yetkisi).
- Sparkle araçları paket çözümüyle gelir: `~/Library/Developer/Xcode/DerivedData/MyNotch/SourcePackages/artifacts/sparkle/Sparkle/bin/{generate_keys,sign_update}` (`scripts/build.sh` bir kez çalıştırıldıysa oradadır).
- **EdDSA anahtarı.** İlk üretim 2026-09-07'de bu Mac'te yapıldı: `generate_keys` özel anahtarı **giriş Keychain'ine** yazar ("Private key for signing Sparkle updates"), açık anahtar `project.yml` → `SUPublicEDKey` (`NyKDlpcr+qf81QzCWhQT5d952q0bpZQek/gtEVATV2k=`). Anahtar başka bir Mac'e taşınmadan ve yedeklenmeden **kaybedilirse güncelleme kanalı ölür**: kurulu her kopya yalnızca bu anahtarla imzalanmış güncellemeleri kabul eder.
  - Yedek: `generate_keys -x sparkle-private-key.txt` → dosyayı parola yöneticisine (1Password/Bitwarden "secure note") koy, sonra `rm -P sparkle-private-key.txt`. **Repo'ya, iCloud Drive'a ya da mesajlaşmaya asla.**
  - Yeni Mac'e taşıma: `generate_keys -i sparkle-private-key.txt`.
  - Mevcut açık anahtarı görmek: `generate_keys -p`.

## 2. Sürüm numaraları

- `project.yml` → `MARKETING_VERSION` (kullanıcıya görünen, `0.x.y`) ve `CURRENT_PROJECT_VERSION` (tam sayı, **her yayında +1**; Sparkle bunu karşılaştırır, geri gitmez).
- `scripts/release.sh 0.2.0` çağrısı `MARKETING_VERSION == 0.2.0` ister ve build numarasının önceki yayından büyük olduğunu doğrular; değilse durur. `CHANGELOG.md`'de `## [0.2.0]` bölümü olmalıdır — release notları oradan alınır.

## 3. Yayın akışı (`scripts/release.sh <sürüm> [--dry-run]`)

1. Çalışma ağacı temiz ve `main`'de olmalı; `xcodegen generate`; tüm testler (`scripts/test.sh`).
2. `xcodebuild archive -scheme MyNotch -configuration Release` → `build/release/MyNotch.xcarchive`.
3. İmza, **içten dışa**: `Contents/Frameworks/MediaRemoteAdapter.framework` → `Contents/Frameworks/Sparkle.framework` (XPC servisleri ve Autoupdate dahil) → `Contents/Resources/MediaRemoteAdapterTestClient` → `MyNotch.app`. Ad-hoc modda kimlik `-`; Developer ID modunda `--options runtime --timestamp` ve `Resources/MyNotch.entitlements`.
4. `codesign --verify --deep --strict` ve `spctl -a -t exec -vv` (ad-hoc'ta `rejected` beklenir ve yalnızca loglanır).
5. Paketleme: `MyNotch-<v>.zip` (`ditto -c -k --keepParent`; Sparkle bunu indirir) ve `MyNotch-<v>.dmg` (`create-dmg`; insanlar bunu indirir).
6. Developer ID modunda `xcrun notarytool submit --keychain-profile mynotch-notary --wait` + `xcrun stapler staple` (app, dmg).
7. `sign_update MyNotch-<v>.zip` → `sparkle:edSignature` ve `length`; `appcast.xml`'in başına `<item>` eklenir (`sparkle:version` = build numarası, `sparkle:shortVersionString` = sürüm, `minimumSystemVersion` 14.0, `pubDate` RFC 2822, enclosure `https://github.com/Muhammethasanuyar/myNotch/releases/download/v<v>/MyNotch-<v>.zip`).
8. `git commit` (appcast) → `git push` → `gh release create v<v> MyNotch-<v>.dmg MyNotch-<v>.zip --title "MyNotch <v>" --notes-file <CHANGELOG bölümü>`.
9. Doğrulama: `gh release view v<v>`; `curl -s https://raw.githubusercontent.com/Muhammethasanuyar/myNotch/main/appcast.xml | head`; kurulu bir önceki sürümde "Check for Updates…".

`--dry-run` 1–7'yi yapar (appcast'i **değiştirmez**, commit/push/release yok) ve ürünleri `build/release/` altında bırakır.

## 4. Ad-hoc sürede bilinmesi gerekenler

- Gatekeeper indirilen uygulamayı "doğrulanamadı" diye durdurur: Sistem Ayarları → Gizlilik ve Güvenlik → "Yine de Aç" (README'de anlatılır). Homebrew cask bu sürede yayınlanmaz (karantina hilesi reddedildi).
- Her yeni sürüm yeni bir ad-hoc imzadır: imzaya bağlı TCC izinleri (Otomasyon, Takvim, Ses kaydı, Erişilebilirlik) güncellemeden sonra yeniden istenir.
- Sparkle güncellemeyi EdDSA imzasıyla doğrular; Developer ID olmadığı için kod imzası eşleşmesi aramaz. İlk canlı doğrulama v0.1.0 → v0.1.1 ile yapılır ve sonucu buraya yazılır.

## 5. Developer ID'ye geçiş

1. Sertifikayı yükle (`security find-identity -v -p codesigning` listeler), `xcrun notarytool store-credentials mynotch-notary` (App Store Connect API anahtarı ya da uygulama parolası).
2. `MYNOTCH_SIGN_IDENTITY="Developer ID Application: <Ad> (<TEAM>)" MYNOTCH_TEAM=<TEAM> scripts/release.sh <v>` — script hardened runtime'ı açar, entitlements'ı bağlar, notarize eder ve mühürler. `project.yml` ad-hoc kalır; farklar komut satırı override'ıdır.
3. İlk notarization sonucunu `docs/harvest/mediaremote-adapter.md` S6'ya yaz (perl/framework/test client kabul edildi mi).
4. Ad-hoc kurulu kopyalar Developer ID'li güncellemeyi Sparkle üzerinden **alamaz** (imza değişimi): o sürüm için appcast'e `sparkle:informationalUpdate` bir öğe ve README'ye elle indirme notu eklenir.
5. Spotify token'ları bu adımla Keychain'e taşınır (`docs/PLAN.md` §18 7.7).

## 6. Sorun giderme

| Belirti | Neden / çözüm |
|---|---|
| `no such module 'Sparkle'` | `xcodebuild -resolvePackageDependencies` (build.sh bunu yapar); ağ gerekir |
| "Check for Updates…" hiçbir şey yapmaz | Debug derlemesi: updater yalnızca Release'te başlar |
| Sparkle "improperly signed" der | zip'i `sign_update` ile imzalamadan appcast'e yazdın ya da anahtar farklı bir Mac'te |
| Güncelleme indi ama kurulmadı | Konsol'da `Sparkle` süzgeci; ad-hoc → Developer ID geçişi olabilir (bölüm 5.4) |
| `gh release create` 422 | tag zaten var: `gh release view v<v>`; yeniden yayın için önce onay al, sonra `gh release delete` |
