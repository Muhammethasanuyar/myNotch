# mediaremote-adapter — Harvest Notu

| | |
|---|---|
| Repo | https://github.com/ungive/mediaremote-adapter |
| Klon | `references/mediaremote-adapter` @ `3ac3d4b` (2026-05-11) |
| Lisans | **BSD-3-Clause** — `LICENSE:1` "BSD 3-Clause License", `LICENSE:3` "Copyright (c) 2025, Jonas van den Berg and contributors". Her kaynak dosyanın başında ikili satırlık lisans yorumu var (ör. `src/adapter/get.m:1-2`, `bin/mediaremote-adapter.pl:2-3`). `test` komutu dosyaları ayrı telif taşıyor ama aynı lisans (`src/adapter/test.m:1-2`, "Copyright (c) 2025 Alexander5015"). |
| Devşirme modu | **Bundle + adapte et** — ikili artefaktlar (framework + `.pl` + test client) `.app` içine gömülür, Swift tarafı sıfırdan yazılır; feature flag arkasında |
| İlgili fazlar | Faz 6 (`GenericNowPlayingProvider`), Faz 3 (fallback sözleşmesinin tasarımı) |

---

## 1. Bizim için değeri

macOS 15.4'ten beri `MediaRemote.framework` entitlement'sız uygulamalara kapalı (README.md:464-474 ve `docs/PLAN.md` §5.1). Bu repo, sorunu **süreç sınırı** ile çözüyor: framework'ü bizim uygulamamız değil, Apple'ın kendi platform binary'si olan `/usr/bin/perl` yüklüyor; perl'in bundle identifier'ı `com.apple.perl` olduğu için `mediaremoted` ona izin veriyor (README.md:450-462). Bize üç şey kazandırıyor:

1. **Kapsam:** Spotify/Music AppleScript sağlayıcılarımızın göremediği her kaynak (Safari, Chrome, YouTube, IINA, podcast uygulamaları) tek bir akıştan gelir — `MediaController` için "son event gönderen kazanır" modelini bozmadan üçüncü bir sağlayıcı.
2. **Push tabanlı akış:** `stream` komutu polling yapmaz; MediaRemote bildirimlerine abone olup satır satır JSON basar (`src/adapter/stream.m:367-486`). Bizim CPU hedefimize (boşta <%1) AppleScript polling'inden daha uygun.
3. **Kırılmayı tespit etme:** `test` komutu, private API erişimi kesildiğinde sıfırdan farklı bir exit kodu döner (`src/adapter/test.m:87-216`). `docs/PLAN.md` §13'teki "adapter'ı feature flag arkasında tut, kırılırsa AppleScript'e düş" önlemini **çalışan bir mekanizmaya** bağlayabiliyoruz.

Ek olarak `now_playing.m`'deki `elapsedTime + timestamp + playbackRate` matematiği, progress bar'ı saniyede bir polling yapmadan sürdürmenin doğru yolunu gösteriyor — bunu Spotify/Music sağlayıcılarımızda da kullanabiliriz (Faz 3 kazancı).

---

## 2. Hedef dosyalar

| Kaynak dosya (path:line) | Ne yapıyor | Bizde hedef dosya (per docs/PLAN.md §9) | Faz |
|---|---|---|---|
| `bin/mediaremote-adapter.pl:80-123` | Argümanları doğrular, framework'ü `DynaLoader::dl_load_file` ile yükler, komut adını doğrular | `Modules/Media/Generic/MediaRemoteAdapterProcess.swift` (yeni) | 6 |
| `bin/mediaremote-adapter.pl:125-268` | Bayrakları `MEDIAREMOTEADAPTER_OPTION_*` / parametreleri `MEDIAREMOTEADAPTER_PARAM_*` env değişkenlerine çevirir | `MediaRemoteAdapterProcess.swift` (argüman kurucu) | 6 |
| `bin/mediaremote-adapter.pl:270-280` | `dl_find_symbol` + `dl_install_xsub` ile `adapter_<komut>[_env]` sembolünü çağırır | (sadece anlamak için; bizde karşılığı yok) | 6 |
| `src/adapter/stream.m:147-494` | `stream`: bildirim aboneliği, diff üretimi, tek satır JSON çıktısı | `Modules/Media/Generic/GenericNowPlayingProvider.swift` | 6 |
| `src/adapter/stream.m:23-99` | `{type,diff,payload}` zarfı, `createDiff`, `isSameItemIdentity`, `printOutUnique` | `GenericNowPlayingProvider.swift` (diff birleştirme) | 6 |
| `src/adapter/stream.m:326-339` | Artwork "kaybolma" düzeltmesi: aynı parçada eski artwork'ü koru | `Modules/Media/ArtworkCache.swift` | 6 (+3'te fikir) |
| `src/adapter/get.m:18-146` | `get`: tek seferlik anlık görüntü, 2000 ms timeout, zorunlu alan kontrolü, yoksa `null` | `MediaRemoteAdapterProcess.swift` (`snapshot()`) | 6 |
| `src/adapter/keys.m:8-83` | JSON anahtar isimleri; zorunlu ve "kimlik" anahtar kümeleri | `Modules/Media/MediaProvider.swift` (`NowPlayingSnapshot` decode) | 6 |
| `src/adapter/test.m:87-216` | `test`: sahte medya yayınlayıp erişimi doğrular, exit kodu 0/1/2/3/4 | `Modules/Media/Generic/AdapterHealthCheck.swift` (yeni) | 6 |
| `src/adapter/now_playing.m:26-53` | `elapsedTimeNow` tahmini: `elapsed + (now - timestamp) * playbackRate` | `Modules/Media/MediaController.swift` (progress hesabı) | 3 ve 6 |
| `src/adapter/now_playing.m:110-159` | `--micros` dönüşümü (saniye → mikrosaniye, timestamp → epoch µs) | `MediaRemoteAdapterProcess.swift` (birim seçimi) | 6 |
| `src/adapter/send.m:15-63`, `seek.m:15-30`, `speed.m:15-30` | Komut ID tablosu, seek pozisyonu **mikrosaniye**, komut sonrası bekleme | `Modules/Media/MediaController.swift` (transport komutları) | 6 |
| `src/utility/helpers.m:19-30` | `printOut` / `printOutUnique` (aynı satırı iki kez basmaz) | `GenericNowPlayingProvider.swift` (satır okuma sözleşmesi) | 6 |
| `src/utility/helpers.m:108-135` | JSON sanitizasyonu: `NSData` → base64, `NSDate` → `yyyy-MM-dd'T'HH:mm:ss'Z'` | `NowPlayingSnapshot` decode (tarih/veri tipleri) | 6 |
| `CMakeLists.txt:35-91` | Universal (`x86_64;arm64`) framework + ad-hoc imza + test client hedefi | `project.yml` (Copy Files fazları) + `scripts/` | 6 |
| `README.md:51-121` | Bundle etme ve çağırma talimatları, "bundle et ama link etme" | `docs/harvest/mediaremote-adapter.md` (bu not) + `THIRD_PARTY_LICENSES.md` | 6 |

---

## 3. Desenler

### 3.1 Platform binary üzerinden entitlement devralma

**Nasıl çalışıyor:** Uygulama `MediaRemote.framework`'ü kendi süreci içinde yükleyemiyor. Adapter, çağrıyı `/usr/bin/perl`'e taşıyor: perl `com.apple.` önekli bir bundle identifier ile imzalı olduğundan `mediaremoted` ona istemci olarak izin veriyor (README.md:450-462; log satırı README.md:462: `Adding client <MRDMediaRemoteClient ..., bundleIdentifier = com.apple.perl5, ...>`). Bu makinede doğrulandı: `codesign -dv /usr/bin/perl` → `Identifier=com.apple.perl`, `Platform identifier=26`, entitlement bloğu yok; perl sürümü 5.34.1; sistem macOS 26.6.2 (25G83). Framework'ün kendisi MediaRemote'u `CFBundleCreate` + `CFBundleGetFunctionPointerForName` ile açıyor (`src/private/MediaRemote.m:77`, `:96-112`) — yani private sembollere **link edilmiyor**, dinamik çözülüyor.

**Bize uyarlama:** `Modules/Media/Generic/MediaRemoteAdapterProcess.swift` içinde `Process` ile `/usr/bin/perl <bundle>/Contents/Resources/mediaremote-adapter.pl <bundle>/Contents/Frameworks/MediaRemoteAdapter.framework <bundle>/Contents/Resources/MediaRemoteAdapterTestClient <komut>` çalıştırılır. Tüm yollar `Bundle.main` üzerinden **mutlak** üretilir (README.md:447 mutlak yol şart diyor). `CLAUDE.md` "ana thread'de Process çalıştırma" kuralı gereği süreç kurulumu ve `stdout` okuma `nonisolated` bir aktör/`AsyncStream` içinde, yayınlanan snapshot `@MainActor` tarafında `MediaController`'a verilir.

**Dikkat:** Apple, scripting runtime'larını (perl/python/ruby) yıllardır "deprecated" ilan ediyor; `/usr/bin/perl` bir gün kalkarsa mekanizma tamamen ölür. Ayrıca bu, tanım gereği private API kullanımıdır → App Store hedeflenemez (zaten `docs/PLAN.md` §3 sandbox kapalı diyor) ve `CLAUDE.md`'deki "private API yok (mediaremote-adapter hariç, feature flag arkasında)" kuralına birebir uymak gerekir.

### 3.2 Perl → framework köprüsü ve env ile parametre taşıma

**Nasıl çalışıyor:** Script framework dizininin adından binary yolunu türetir (`bin/mediaremote-adapter.pl:105-110`), `DynaLoader::dl_load_file` ile yükler (`:112-113`), komut adını beyaz listeye karşı doğrular (`:114-123`), sonra bayrakları ayrıştırıp env'e yazar ve `adapter_<komut>_env` sembolünü XSUB olarak kurup çağırır (`:270-277`). Parametre isimlendirmesi sabit: `MEDIAREMOTEADAPTER_PARAM_<func>_<index>_<name>` ve `MEDIAREMOTEADAPTER_OPTION_<name>` (`:154-163`; okuma tarafı `src/adapter/env.m:24-28`, `:97-104`). Tire'ler alt çizgiye çevrilir, yani `--no-artwork` → `MEDIAREMOTEADAPTER_OPTION_no_artwork`. Test client yolu ikinci argümandan alınıp `MEDIAREMOTEADAPTER_TEST_CLIENT_PATH` env'ine konur (`:94-99`) — "yolda `/` varsa test client'tır" heuristiği ile.

**Bize uyarlama:** Bu iç detayları taklit etmiyoruz; sadece **CLI sözleşmesini** sabitliyoruz. `MediaRemoteAdapterProcess` iki tip çağrı sunar: kısa ömürlü (`get`, `send`, `seek`, `test` → `Process` + `waitUntilExit` + exit kodu) ve uzun ömürlü (`stream` → satır satır okuyan `AsyncStream<Data>`). Bayraklar `enum AdapterOption` ile tip güvenli üretilir; asla string birleştirme ile kullanıcı verisi geçilmez.

**Dikkat:** README.md:81-83 API'nin minor sürümler arasında kırılabileceğini açıkça yazıyor. Bundle ettiğimiz sürümü `THIRD_PARTY_LICENSES.md` içinde SHA ile sabitleyelim (`3ac3d4b`); güncelleme bilinçli bir işlem olsun. Ayrıca argüman sırası katı: `FRAMEWORK_PATH [TEST_CLIENT_PATH] FUNCTION [OPTIONS]` (`bin/mediaremote-adapter.pl:15-17`); argümansız çağrı yardım basıp `exit 0` yapar (`:80-82`, `:101-103`) — yani "boş çıktı + 0" durumunu başarı sanmayalım.

### 3.3 `get` — anlık görüntü ve zorunlu alan sözleşmesi

**Nasıl çalışıyor:** `internal_get` dört MediaRemote çağrısını bir `dispatch_group` içinde paralel yürütür: PID + bundle id (`src/adapter/get.m:37-54`), `parentApplicationBundleIdentifier` (`:57-69`), `playing` (`:72-77`), tam now-playing sözlüğü (`:79-95`). Toplam bütçe `GET_TIMEOUT_MILLIS = 2000` (`:15`, `:98-107`); aşılırsa stderr'e yazıp `nil` döner. Ardından **zorunlu anahtar** kontrolü yapılır ve eksikse tüm çıktı `null` string'i olur (`:117-121`, `:133-141`). Zorunlu anahtarlar kodda `processIdentifier`, `title`, `playing` (`src/adapter/keys.m:59-61`); boş string de geçersiz sayılır (`:63-76`).

```objc
NSArray<NSString *> *mandatoryPayloadKeys(void) {
    return @[ kMRAProcessIdentifier, kMRATitle, kMRAPlaying ];
}
```
Kaynak: `references/mediaremote-adapter/src/adapter/keys.m:59-61` (BSD-3-Clause)

**Bize uyarlama:** `NowPlayingSnapshot` decode'unda `title` ve `playing` zorunlu, **`bundleIdentifier` opsiyonel** olmalı (aşağıdaki "Dikkat"). Çıktının tek satırı `null` olabildiği için decode'dan önce trim + `== "null"` kontrolü şart; bu durum "medya yok" demektir, hata değil → modül `activity = .idle`.

**Dikkat:** README.md:180-186 zorunlu anahtarları `bundleIdentifier`, `playing`, `title` olarak sayıyor; **kod ise `processIdentifier`, `title`, `playing` diyor**. `bundleIdentifier`, PID'den `NSRunningApplication` ile çözülür (`src/utility/helpers.m:198-209`) ve çözülemezse payload'a hiç girmez. Yani "bundleIdentifier her zaman var" varsayımı yanlış; kaynak ikonu (Spotify/Music/Safari) için fallback zinciri (`bundleIdentifier` → `parentApplicationBundleIdentifier` → jenerik ikon) kurmalıyız.

### 3.4 `stream` — diff protokolü ve satır sözleşmesi

**Nasıl çalışıyor:** Her satır tek bir JSON nesnesidir; zarf üç anahtarlı: `type` (her zaman `"data"`), `diff` (bool), `payload` (sözlük) — `src/adapter/stream.m:23-31`.

```objc
static NSString *serializeData(NSDictionary *data, BOOL diff, BOOL pretty) {
    return serializeJsonDictionarySafe(
        @{
            @"type" : @"data",
            @"diff" : @(diff),
            @"payload" : data ?: @{},
        },
        pretty);
}
```
Kaynak: `references/mediaremote-adapter/src/adapter/stream.m:23-31` (BSD-3-Clause)

`diff == false` → payload tam durumdur (önceki her şeyi unut). `diff == true` → yalnızca değişen alanlar; kaybolan alan `null` olarak gelir ve silinmelidir (README.md:249-259). Diff yalnızca "aynı parça" ise üretilir; kimlik anahtarları `processIdentifier, bundleIdentifier, parentApplicationBundleIdentifier, title, artist, album` (`src/adapter/keys.m:78-83`, karşılaştırma `stream.m:55-71`, karar `stream.m:75-99`). Parça değişince otomatik olarak tam (non-diff) payload gelir — bu bizim "parça değişti popup'ı" için doğal tetikleyici. Boş payload (`{}`) "hiçbir oynatıcı bildirim yapmıyor" demektir (README.md:243-244). Aynı seri satır iki kez basılmaz (`helpers.m:24-30`). Kaynak uygulama sonlanınca tüm durum sıfırlanıp yeniden istenir (`stream.m:466-482`).

**Bize uyarlama:** `GenericNowPlayingProvider` içinde `private var live: [String: JSONValue]` sözlüğü tutulur: `diff == false` → `live = payload`; `diff == true` → merge, `null` değerler `removeValue`. Merge sonrası `NowPlayingSnapshot`'a map edilip `MediaProvider` publisher'ına verilir. Satır okuma `stdout` üzerinde `\n` ile bölünerek yapılmalı (bir `read` çağrısı birden fazla satır veya yarım satır getirebilir). `--debounce=250` gibi küçük bir değer kullanmayı düşünelim (varsayılan 0, `stream.m:157-161`): notch'ta 100 ms'den sık güncelleme zaten görünmez, ama bir parça değişiminde 3-5 ardışık satır gelebiliyor.

**Dikkat:** `stderr`'e yazılan her satır bir hata mesajıdır ama süreç sıfırdan farklı kodla çıkmadıysa **fatal değildir** (README.md:441-443); loglayıp yutalım, `assertionFailure` etmeyelim. Buna karşılık fatal hatada (`exit != 0`) süreci **yeniden başlatmamalıyız** (README.md:445-446) — o durumda AppleScript'e düşüp feature flag'i kapatmak doğru davranış.

### 3.5 `test` komutu ve otomatik AppleScript fallback

**Nasıl çalışıyor:** Önce normal `get` denenir; veri varsa hemen `exit(0)` (`src/adapter/test.m:95-99`). Veri yoksa `MEDIAREMOTEADAPTER_TEST_CLIENT_PATH` ile verilen yardımcı süreç `NSTask` olarak başlatılır (`:104-130`), stdout'tan `setup_done` satırı beklenir (3.0 s timeout, `:188-202`), sahte "now playing" kaydı yayınlanırken `get` tekrar denenir (`:206-212`), sonra yardımcı süreç `cleanup` komutu + gerekiyorsa `terminate`/`SIGKILL` ile kapatılır (`:16-75`). Exit kodları: **0** çalışıyor · **1** test client yolu verilmemiş · **2** test client başlatılamadı · **3** `setup_done` gelmedi · **4** her iki `get` de boş döndü. Sahte kaydın gerçek akışı kirletmemesi için `get`/`stream` `kMRMediaRemoteNowPlayingInfoServiceIdentifier == "com.vandenbe.MediaRemoteAdapter.TestClient"` olan veriyi eler (`get.m:82-90`, `stream.m:302-309`).

**Bize uyarlama:** `Modules/Media/Generic/AdapterHealthCheck.swift`: uygulama açılışında ve modül ilk kez etkinleştirildiğinde `test` çalıştırılır (async, `Process` + `terminationStatus`). Sonuç `SettingsStore`'a tarih damgasıyla yazılır; `0` değilse `GenericNowPlayingProvider` hiç başlatılmaz ve `MediaController` yalnızca Spotify/Music sağlayıcılarıyla çalışır, ayarlarda "sistem geneli medya erişimi bu macOS sürümünde kullanılamıyor" satırı gösterilir. Testi **her açılışta değil**, sürüm değişiminde (macOS build numarası veya uygulama sürümü değişince) ve manuel "Yeniden dene" düğmesinde koşturalım.

**Dikkat:** README.md:408-416 açık uyarı veriyor — hiçbir medya çalmıyorken `test`, kısa süreliğine **sahte bir now-playing kaydı** yaratır; bu, MediaRemote kullanan diğer uygulamalarda (boring.notch, BetterTouchTool, Discord rich presence...) görünebilir. Bu yüzden testi periyodik/otomatik döngüye sokmak kabalık olur. Ayrıca `test`, `MediaRemoteAdapterTestClient` executable'ının da bundle edilmesini zorunlu kılar (README.md:107-115) → notarization yüzeyi büyür (§3.9).

### 3.6 Artwork: taşıma biçimi, boyut ve kaybolma düzeltmesi

**Nasıl çalışıyor:** Artwork iki anahtarla gelir: `artworkMimeType` (ör. `image/jpeg`) ve `artworkData`. `artworkData` bir `NSData`'dır ve JSON'a **base64 string** olarak yazılır (`src/utility/helpers.m:131-132`). README.md:219-222 `--no-artwork` bayrağını "güncelleme başına birkaç yüz kilobayt base64 yaymayı önler" diye tanımlıyor. `--no-diff` ile birlikte kullanıldığında artwork **her güncellemede yeniden** yayınlanır (README.md:277-279). MediaRemote artwork'ü kısa süreliğine boşaltabildiği için `stream`, parça kimliği aynıyken kaybolan artwork'ü eskisiyle doldurur (`src/adapter/stream.m:326-339`; README.md:419-427). Artwork "eninde sonunda" gelir; ilk payload'da olmayabilir (README.md:193-200). `--human-readable` modunda binary veri `<image/jpeg 123456 bytes...>` gibi kısaltılır (`helpers.m:235-246`) — sadece debug için.

**Bize uyarlama:** Diff açık bırakılır (varsayılan), böylece artwork sadece değiştiğinde gelir. `ArtworkCache` anahtarı olarak parça kimliği (`bundleIdentifier|title|artist|album`) kullanılır; base64 çözülüp `NSImage`'e dönüştürme ve baskın renk çıkarımı (`CIAreaAverage`, `docs/PLAN.md` §5.2) ana thread dışında yapılır, cache'e hazır `NSImage` + renk konur. Compact görünüm 20×20 px kullandığı için decode sonrası küçültülmüş bir kopya saklamak yeterli. Artwork gelmemişse UI placeholder gösterir ve sonraki payload'ı bekler — "artwork yok" durumu hata değildir.

**Dikkat:** Payload büyüklüğü doğrudan bizim IPC maliyetimizdir: 300 KB'lık bir JPEG base64'te ~400 KB'a çıkar ve pipe üzerinden geçer. Diff kapalıyken bu her `elapsedTime` güncellemesinde tekrarlanırdı — bu yüzden `--no-diff` **kullanmayacağız**. `--no-artwork`'ü ise ayarlarda "notch'ta albüm kapağı gösterme" kapalıyken kullanmak mantıklı bir optimizasyon.

### 3.7 Zaman birimleri ve pozisyon matematiği

**Nasıl çalışıyor:** Varsayılan olarak `duration` ve `elapsedTime` **saniye** (double), `timestamp` ise ISO-8601 UTC string'idir (`helpers.m:118-128`). `--micros` bayrağı bu üçünü `durationMicros`, `elapsedTimeMicros`, `timestampEpochMicros` ile değiştirir (`src/adapter/now_playing.m:110-159`; README.md:210-217). `--now` bayrağı `get` için `elapsedTimeNow` ekler ama README.md:204-208 bunun ±1 sn hatalı olabileceğini söyleyip **doğru yolu** gösteriyor: `elapsedTime`, `timestamp` anındaki değerdir; şu anki pozisyon `elapsed + (now - timestamp) * playbackRate` (`now_playing.m:26-53`; `playbackRate` negatifse eklenmez).

**Bize uyarlama:** `MediaController` progress bar'ı **timer ile artırmaz**; `NowPlayingSnapshot` içine `elapsed`, `timestamp`, `playbackRate`, `duration` konur ve view katmanında `TimelineView(.animation)` bu formülle anlık pozisyonu hesaplar (`docs/PLAN.md` §4.4: sürekli animasyonlar yalnızca görünürken çalışsın). Aynı yaklaşımı Faz 3'te Spotify/Music sağlayıcılarına da uygulayalım: `player position`'ı saniyede bir pollemek yerine bildirimde bir kez okuyup lokal olarak ekstrapole etmek CPU'yu düşürür. Spotify'ın `duration of current track` değerinin **milisaniye** olduğunu (`docs/PLAN.md` §5.1) unutmayıp adapter'ın saniyesiyle karışmaması için `MediaProvider` protokolünde birim tek olsun: `TimeInterval` (saniye).

**Dikkat:** `--micros` seçilirse orijinal anahtarlar **yok olur** (yeniden adlandırma, ekleme değil); decode'u tek moda sabitleyelim (varsayılan saniye) ve `--micros`'u kullanmayalım. `timestamp` string'i ISO-8601'dir, `ISO8601DateFormatter` ile parse edilmeli; `playbackRate` yoksa 0 kabul edilip pozisyon dondurulmalı.

### 3.8 Kontrol komutları: ID tabloları ve birimler

**Nasıl çalışıyor:** `send <ID>` MediaRemote komutu gönderir; kabul edilen ID'ler `include/MediaRemoteAdapter.h:75-90` ve `src/adapter/send.m:17-38`: `0 play`, `1 pause`, `2 togglePlayPause`, `3 stop`, `4 nextTrack`, `5 previousTrack`, `6 toggleShuffle`, `7 toggleRepeat`, `8/9` ileri seek başlat/bitir, `10/11` geri seek başlat/bitir, `12` 15 sn geri, `13` 15 sn ileri. `seek <POSITION>` **mikrosaniye** alır ve içeride saniyeye bölünür (`src/adapter/seek.m:15-24`); negatif değer hata. `shuffle` 1/2/3 = kapalı/albüm/parça, `repeat` 1/2/3 = kapalı/parça/liste (`include/MediaRemoteAdapter.h:101-114`). Her komut sonrası `waitForCommandCompletion` çağrılır: bir `getNowPlayingApplicationPID` isteği semafor ile beklenir, üst sınır 2000 ms (`src/adapter/now_playing.m:11-24`).

**Bize uyarlama:** `MediaController` transport arayüzü sağlayıcıdan bağımsız kalır (`play/pause/next/previous/seek(to:)`); generic sağlayıcıda bunlar ayrı ayrı kısa ömürlü perl süreçlerine dönüşür. `seek` çağrısında saniyeyi `Int(position * 1_000_000)` ile mikrosaniyeye çeviren tek bir yardımcı olsun (`nonisolated` + birim testli). ID'ler için Swift `enum MediaRemoteCommand: Int` tanımlayalım — `docs/PLAN.md` §6/global kurallardaki "kod içinde statik dizi/sihirli sayı yok" ilkesi gereği.

**Dikkat:** Her komut yeni bir perl süreci demek (fork+exec+perl başlangıcı+framework yükleme). Kullanıcı play/pause'a hızlı hızlı basarsa süreç yığılması olur; `MediaController` tarafında komutları serileştiren bir aktör ve son komutu kazandıran küçük bir coalescing gerekir. Ayrıca komut gönderimi 2 sn'ye kadar bloke olabildiği için kesinlikle ana thread dışında.

### 3.9 Bundle etme, imza ve notarization

**Nasıl çalışıyor:** CMake hedefleri: `MediaRemoteAdapter` bir **shared framework** (`CMakeLists.txt:37-50`), `-fvisibility=default` ile derlenir çünkü perl sembolleri dışarıdan bulmak zorunda (`:67-69`), build sonrası **ad-hoc** imzalanır (`:71-76`), mimari `x86_64;arm64` (`:35`). İkinci hedef `MediaRemoteAdapterTestClient` bir executable'dır (`:78-91`). README.md:102-105 kritik cümleyi içeriyor: framework uygulamayla **bundle edilmeli ama link edilmemeli**; sadece script'e argüman olarak verilir. Gerçek bir örnekte (boring.notch, GPL — yalnızca davranış incelendi, kod alınmadı) artefaktlar repo içinde `mediaremote-adapter/` klasöründe hazır tutuluyor ve `.app` içinde `.pl` → `Resources`, framework → `Contents/Frameworks` (`Bundle.main.privateFrameworksPath`), test client → uzantısız `Resources` kaynağı olarak yer alıyor; SPM bağımlılığı olarak **eklenmemiş** (`Package.resolved` içinde yok). Vendored artefaktların ölçümü: framework 332 KB (`x86_64 arm64` universal, `Identifier=com.vandenbe.MediaRemoteAdapter`, `Signature=adhoc`), test client 128 KB (universal, `adhoc, linker-signed`), `.pl` 7940 bayt.

**Bize uyarlama:** `project.yml`'e üç Copy Files fazı: `mediaremote-adapter.pl` → Resources, `MediaRemoteAdapter.framework` → Frameworks ("Code Sign On Copy" işaretli), `MediaRemoteAdapterTestClient` → Resources. Kaynak artefaktları repoya `Vendor/mediaremote-adapter/` altında (git'e girecek şekilde, `references/` değil) tutalım; nereden geldiği ve SHA'sı `THIRD_PARTY_LICENSES.md`'de yazsın. Dağıtımda Developer ID ile **yeniden imzalanmalı** (ad-hoc imza notarization'dan geçmez); framework önce, sonra `.app` (inside-out imzalama).

**Dikkat:** (a) Framework'ü *biz* yüklemediğimiz için Hardened Runtime'ın library validation kuralı bizi bağlamaz; ama `.app` içindeki her Mach-O notarization taramasından geçer → hem framework hem test client geçerli Developer ID imzası taşımalı. (b) `.pl` bir script olduğundan imzalanmaz, ancak `Resources` içinde olduğu için `.app` code seal'ine dahildir; kurulumdan sonra düzenlenirse imza bozulur. (c) Test client'ı bundle etmemek `test` komutunu (dolayısıyla otomatik fallback'i) devre dışı bırakır — boyut/karmaşıklık ile güvenilirlik arasında bilinçli bir seçim; **bundle etmekten yanayız**. (d) Framework identifier'ı `com.vandenbe.MediaRemoteAdapter` (bizim değil) — bunu değiştirmek yeniden derleme gerektirir, gerek yok, ama bundle içinde yabancı bir identifier bulunacağını bilelim.

### 3.10 Süreç yaşam döngüsü, gecikme ve CPU

**Nasıl çalışıyor:** `stream` bir `CFRunLoopRun` üzerinde durur (`src/adapter/stream.m:486`); `SIGINT`/`SIGTERM` alınca `CFRunLoopStop` ile temiz kapanır (`:498-515`) ve bildirim kayıtları geri alınır (`:488-493`). Tüm MediaRemote geri çağrıları tek bir seri kuyrukta işlenir (`src/adapter/globals.m:11-19`). Push modeli olduğu için boşta iş yok; `--debounce=N` (ms) yalnızca patlamaları birleştirir (`stream.m:157-161`, README.md:267-273). `get` ve komutlar için bütçe 2000 ms'dir (`get.m:15`, `now_playing.m:11`). Repoda ölçülmüş gecikme/CPU sayısı yok; ölçüm bize kalıyor.

**Bize uyarlama:** Tek bir uzun ömürlü `stream` süreci tutulur ve yaşam döngüsü modülün `isEnabled` + notch görünürlüğüne değil, **medya modülünün etkinliğine** bağlanır (kapalıyken süreç tamamen sonlandırılır → `docs/PLAN.md` §13 "kapalıyken sıfır maliyet"). `applicationWillTerminate` ve modül kapatmada `SIGTERM` gönderip `waitUntilExit`; zombi süreç bırakmayalım. Süreç beklenmedik şekilde ölürse (exit != 0) yeniden başlatma **yok** (README.md:445-446), doğrudan AppleScript sağlayıcılarına düşülür ve Faz 5 ayarlarında durum gösterilir.

**Dikkat:** Uygulama çökerse perl süreci öksüz kalabilir; başlangıçta aynı komut satırına sahip eski süreçleri temizleyen bir kontrol iyi olur. Ayrıca Faz 5'te Instruments ölçümü yaparken **perl sürecinin CPU'su bizim uygulamamızın altında görünmez** — ayrı ölçmek gerekir.

---

## 4. Plan ile çelişkiler / doğrulamalar

1. **`test` komutu gerçekten var ve kırılmayı tespit ediyor — doğrulandı.** `docs/PLAN.md` §2.1 ve §5.1'deki "`test` komutu kırılmayı tespit edip AppleScript'e otomatik düşüş sağlar" ifadesi doğru (`src/adapter/test.m:87-216`, README.md:368-406). Plana **eklenmesi gereken** iki nüans: (a) `test`, ayrıca bundle edilmesi gereken `MediaRemoteAdapterTestClient` executable'ını şart koşar; (b) hiçbir medya çalmazken sahte bir now-playing kaydı yaratıp diğer uygulamaları geçici olarak etkiler (README.md:408-416) → periyodik değil, olay tabanlı çalıştırılmalı.
2. **`ejbills/mediaremote-adapter` fork'u — doğrulanamadı.** Bilgi yalnızca README.md:85-87'de tek cümle olarak var ("For a maintained Swift package look at this excellent fork"); klonda ne submodule (`.gitmodules` boş), ne `Package.swift`, ne başka kanıt var. Üstelik en olgun tüketici olan boring.notch bile fork'u SPM ile değil, **derlenmiş artefaktları vendor'layarak** kullanıyor (`Package.resolved` içinde mediaremote yok, repo kökünde `mediaremote-adapter/` klasöründe prebuilt framework + `.pl` + test client var). Sonuç: `docs/PLAN.md` §2.1'deki "bakımlı Swift package fork'u" ifadesi **doğrulanmamış** durumda; Faz 6'da fork ayrıca klonlanıp incelenmeli (§6/S1). Şu anki plan (upstream artefaktlarını bundle edip Swift sarmalayıcıyı kendimiz yazmak) fork'a bağımlı olmadığı için risksiz.
3. **Zorunlu alan listesi planı etkiliyor.** README ile kod uyuşmuyor (README.md:180-186 vs `src/adapter/keys.m:59-61`); `bundleIdentifier` zorunlu değil. `docs/PLAN.md` §5.2'deki "kaynak ikonu (Spotify/Music)" için fallback zinciri gerekir.
4. **Kapsam iddiası doğrulandı, ama isimlendirme nüanslı.** Safari/Chrome içindeki oynatıcılar için uygulamanın kendi bundle id'si ile `parentApplicationBundleIdentifier` farklı olabilir (`get.m:57-69`, `stream.m:271-289`) — "hangi uygulama çalıyor" etiketini üretirken ikisini de değerlendirmeliyiz.
5. **Min. macOS 14 hedefi ile uyumlu.** Framework yalnızca Foundation/AppKit (+ varsa UniformTypeIdentifiers) kullanıyor (`CMakeLists.txt:52-58`); macOS 14'te sorun beklenmiyor. Adapter'ın kendisi zaten macOS 15.4 **öncesi** sürümlerde de çalışır (README.md:27-28), yani tek kod yolu yeter.
6. **`docs/PLAN.md` §13 risk satırı yerinde ama eksik.** "macOS güncellemesi MediaRemote workaround'unu kırar" riskine ek olarak "Apple `/usr/bin/perl`'i kaldırır" ve "notarization'a giren ek Mach-O'lar" risklerini de tabloya eklemek isteyebiliriz.

---

## 5. Bilinçli almayacaklarımız

- **`src/private/MediaRemote.h/.m`'i uygulamaya gömmek.** Private sembol tablosunu kendi binary'mize koymak, adapter'ın tüm varlık sebebini (süreç sınırı) ortadan kaldırır ve `CLAUDE.md`'deki private API kuralını çiğner. Sadece perl tarafında kalsın.
- **`--experimental-peculiar-debounce:com.tidal.desktop`** (`stream.m:176-187`, README.md:283-294): tek bir oynatıcı için deneysel; bizim MVP kapsamımızda değil.
- **`shuffle` / `repeat` / `speed` komutları:** `docs/PLAN.md` §5.2'deki expanded UI'da yok. Sonradan eklenirse ID tabloları bu notta hazır.
- **`--micros` ve `--human-readable`:** tek birim (saniye) ve tek çıktı formatı ile ilerlemek decode'u sadeleştirir; `--human-readable` zaten yalnızca debug içindir (`bin/mediaremote-adapter.pl:67-69`).
- **`--no-diff`:** artwork'ü her güncellemede yeniden yayınlar (README.md:277-279); bant genişliği ve CPU açısından kabul edilemez.
- **`Debounce` sınıfı (`src/utility/Debounce.m`):** Swift tarafında Combine'ın `debounce`/`throttle` operatörleri var; ayrıca sınıf yazmayacağız.
- **`test` komutunu periyodik koşturmak:** diğer uygulamaları etkileme yan etkisi nedeniyle (README.md:408-416) yalnızca sürüm değişimi + manuel tetikleme.

---

## 6. Açık sorular

1. **S1 — ejbills fork'u ne ekliyor?** Faz 6 başında `git clone --depth 1 https://github.com/ejbills/mediaremote-adapter` yapıp: (a) gerçekten `Package.swift` içeren bir SPM paketi mi, (b) framework/`.pl` artefaktlarını binary target olarak mı taşıyor, (c) upstream `3ac3d4b` üzerine hangi düzeltmeleri almış, (d) lisansı BSD-3 olarak koruyor mu? Yanıt "olgun bir SPM paketi" ise `docs/PLAN.md` §3'teki "sıfır SPM bağımlılığı" tercihine karşı **bakım maliyeti** açısından yeniden değerlendirilmeli.
2. **S2 — Artefaktları nasıl üreteceğiz?** Upstream release'i yok gibi; CMake ile kendimiz mi derleyeceğiz (`cmake .. && cmake --build .`, README.md:89-100) yoksa boring.notch'un vendored ikili dosyalarını mı alacağız? İkincisi GPL bir repodan **binary** almak olurdu — artefaktın kendisi BSD-3 lisanslı upstream'den türese de provenance karışır; **kendimiz derlemek** tercihimiz olmalı (derleme adımı `scripts/` altında belgelenir).
3. **S3 — Gerçek gecikme ve CPU nedir?** Faz 6'da ölçülecek: parça değişiminden ilk `stream` satırına kadar geçen süre, artwork'ün kaç ms sonra geldiği, boşta ve çalarken perl sürecinin CPU'su, `--debounce` değerinin optimum noktası.
4. **S4 — Aynı anda hem AppleScript hem generic sağlayıcı açıkken çakışma nasıl çözülür?** Spotify çalarken hem `SpotifyProvider` hem `GenericNowPlayingProvider` event üretir. `MediaController`'ın "son event kazanır" kuralı titremeye yol açabilir; muhtemelen `bundleIdentifier` bilinen bir AppleScript sağlayıcısına aitse generic sağlayıcı susturulmalı (öncelik: resmi arayüz).
5. **S5 — Test client'ın sahte kaydı bizim kendi `stream`'imizi bozar mı?** Kodda filtre var (`stream.m:302-309`) ama `test` başka bir uygulama tarafından çalıştırıldığında "bundle identifier yok" hata satırı üretilebiliyor (README.md:444). Kendi log/hata yönetimimizde bu satırı gürültü olarak sınıflandırmalıyız.
6. **S6 — Notarization pratikte sorunsuz mu?** İlk Developer ID + notarization denemesinde (Faz 5/6) bundle edilmiş framework + test client + `.pl` üçlüsünün ret almadığı doğrulanmalı; ret gelirse `.pl`'yi Resources yerine ayrı bir yardımcı konuma taşıma seçenekleri değerlendirilir.
