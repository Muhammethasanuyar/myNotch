# Manuel Doğrulama Senaryoları

Otomatik testler mantık katmanını kapsıyor (`scripts/test.sh`). Bu dosya yalnızca elle yapılması gereken, izin veya gerçek uygulama isteyen senaryoları listeler. Her fazın kabul kriterleri `docs/PLAN.md` içindedir.

Genel hazırlık:

```bash
scripts/run.sh                       # varsayılan (closed)
scripts/run.sh --args -openDebugPreview YES
scripts/run.sh --args -debugState compact -debugTintNotch YES
```

Ekran görüntüsü almak için terminalin **Ekran Kaydı** iznine ihtiyacı var; ekran uykudaysa `caffeinate -u -t 2` ile uyandır.

## Faz 1 — Notch motoru (2026-09-03 doğrulandı)

- [x] Hover: imleç notch'a gelince ~0,15 s sonra expanded açılır; kartın çevresindeki görünmez bölgeden çıkınca **anında** kapanır.
- [ ] Hover toleransı (2026-09-04): expanded'dayken imleci kartın 32 pt yanına / 28 pt altına taşı → kart en fazla 0,8 s daha açık kalır, sonra kapanır. Bu sürede karta geri dön → kapanmaz. Bölgenin dışına çık → beklemeden kapanır. Debug Preview'daki "Close delay" slider'ı (0–1 s) toleransı değiştirir ("Apply to real notch").
- [x] Tıklama geçirgenliği: şeffaf piksele yapılan tıklama alttaki uygulamaya geçer ve notch kapanır.
- [x] Tam ekran: tam ekran bir uygulamanın üzerinde panel görünür kalır (özel CGS API'si olmadan).
- [x] Dört durum (closed / compact / expanded / popup) gerçek notch'ta doğru çizilir.
- [ ] Notch'suz ekran (harici monitör): floating kapsül menü barın altında görünür. *Harici ekran gerektirir.*

## Faz 3 — Medya modülü

İlk çalıştırmada macOS "MyNotch, Spotify'ı kontrol etmek istiyor" diyaloğunu gösterir; **İzin Ver** denmeli. Reddedilirse modül expanded'da "Automation permission needed" ekranını gösterir (bu da bir test senaryosudur). İzni sıfırlamak için:

```bash
tccutil reset AppleEvents com.emre.mynotch
```

Ad-hoc imza her build'de değiştiği için iznin tekrar sorulması normaldir.

### Spotify (`docs/PLAN.md` §5.3)

1. **Parça değişimi ≤1 sn:** Spotify'da çal, "sonraki parça"ya bas. Beklenen: notch popup ile açılır (kapak + başlık/sanatçı), ~2,5 sn sonra compact'a döner; compact'taki kapak yeni parçanın kapağı olur.
2. **Transport:** notch'a hover et → expanded. Play/pause, önceki, sonraki butonları Spotify'ı kontrol eder; ikon oynatma durumuna göre değişir (iyimser güncelleme, ~0,35 sn sonra gerçek durumla teyit edilir).
3. **Seek (2026-09-05 yenilendi):** ilerleme çubuğunun üstüne gel → çubuk kalınlaşır ve tutamak belirir; çubuğun herhangi bir yerine **tıkla** → o konuma atlar; tutamağı **sürükle** → süre etiketi canlı güncellenir, bırakınca oynatıcı oraya gider. Çubuğun 6 pt üstü ve altı da tıklamayı yakalar. Bırakır bırakmaz çubuk ve sözler yeni konuma geçer (iyimser), 350 ms sonra oynatıcıyla teyit edilir ve 1 sn sonra hassas çapa alınır. Duraklatılmışken de çalışır.
4. **Duraklatma:** pause'da equalizer çubukları düz çizgiye iner, playhead ilerlemez.
5. **Boşta:** Spotify'ı kapat. Beklenen: modül `idle`'a düşer, notch closed olur (Debug Preview'da "Active module: none").
6. **Tam ekran:** bir uygulamayı tam ekrana al, notch'a hover et; expanded açılır ve transport butonları **ilk tıklamada** çalışır (`NotchHostingView.acceptsFirstMouse`).

### Apple Music

1. Music'te bir parça çal → compact'ta kapak + equalizer görünür (kapak Music'ten geçici dosyaya yazılıp okunur).
2. Parça değişiminde popup oynar.
3. Transport ve seek çalışır (Music süreyi saniye verir).
4. Her iki uygulama da açıkken: son olay gönderen kazanır; diğerine geçince bir sonraki bildirimde kaynak değişir (expanded'da sağ üstteki kaynak ikonu değişir).

### Kontrol çubuğu

1. Butonlar kart genişliğince ortalı: shuffle · önceki · beyaz daire içinde oynat/duraklat · sonraki · repeat; kalp solda.
2. **Apple Music:** shuffle, repeat (kapalı → tümü → tek) ve kalp çalışır; ikonlar Music'teki gerçek durumu yansıtır ve tıklayınca anında değişir (iyimser güncelleme, ~0,4 sn sonra teyit).
3. **Spotify:** shuffle/repeat soluk ve tıklanamaz — Spotify bu yazımları yok sayıyor. Yine de Spotify'da açıksa ikon vurgulu görünmeli; tooltip nedeni söyler. Kalp bağlantı kurulmadan soluk ama **tıklanabilir**; tooltip sıradaki adımı söyler (aşağıdaki bölüm).
4. Önceki/oynat/sonraki her iki uygulamada da ilk tıklamada çalışır (başka uygulama önde olsa bile).

### Spotify favoriler (Web API)

Spotify'ın scripting arayüzü parça kaydedemez (`starred` -10000 verir), bu yüzden kalp Web API ile çalışır ve bir kerelik kurulum ister:

```bash
# 1) https://developer.spotify.com/dashboard → Create app; Redirect URI: http://127.0.0.1:48219/callback; API: Web API
# 2) client ID'yi uygulamaya ver (yeniden başlatma gerekmez, kalbe tıklayınca yeniden okunur)
defaults write com.emre.mynotch spotifyClientID <client-id>
```

1. **Client ID yokken** kalbe tıkla → tarayıcıda Spotify Dashboard açılır; tooltip `defaults write` komutunu gösterir. Kalp soluk kalır.
2. **Client ID varken** kalbe tıkla → tarayıcıda Spotify onay ekranı ("MyNotch ... kütüphaneni görüntülemek ve değiştirmek istiyor"). Onayla → sekmede "Spotify connected. You can close this tab." görünür; notch'ta kalp en geç ~2 sn içinde gerçek durumu alır (parça kütüphanedeyse dolu).
3. Kalbe tıkla → anında dolar; Spotify'da **Beğenilen Şarkılar**'da parça görünür. Tekrar tıkla → çıkar.
4. **Zaten beğenilmiş** bir parçaya geç → kalp dolu gelir (URI başına tek `contains` sorgusu; 60 sn önbellek). Spotify'ın kendi içinde beğen/kaldır → notch en geç ~1 dk içinde yakalar.
5. Onayı **reddet** (tarayıcıda Cancel) → kalp soluk kalır, uygulama takılmaz, tekrar tıklanabilir. Tarayıcıyı hiç dönmeden kapatırsan dinleyici 5 dk sonra zaman aşımına uğrar.
6. **Ağ yokken** kalbe tıkla → iyimser dolar, ~0,4 sn sonra eski haline döner (yazma başarısız, log'da görünür); okuma 30 sn boyunca tekrar denenmez.
7. **Yeniden başlatma:** token dosyası (`~/Library/Application Support/MyNotch/spotify-oauth.json`, 0600; Keychain'e taşıma Developer ID imzasıyla birlikte — `docs/PLAN.md` §18) sayesinde bağlantı kalır; Ayarlar → Medya → Spotify satırı "Bağlı" der; süresi dolan access token refresh token ile sessizce yenilenir. Dosyayı elle bozarsan (`echo x > …/spotify-oauth.json`) uygulama bağlantısız açılır ve durum satırı hatayı gösterir, çökmez.
8. **Bağlantıyı kesmek:** Ayarlar → Medya → **Bağlantıyı Kes** (dosya silinir, yeniden başlatma gerekmez; `Connect…` yeniden etkinleşir). Spotify hesabındaki yetkiyi geri alırsan (401) uygulama da bağlantısız duruma düşer ve kalp yeniden "bağlan" moduna geçer.
9. **Bölüm/yerel dosya:** podcast bölümlerinde ve yerel dosyalarda kalp etkisizdir (kütüphane girdisi yok).

### Şarkı sözleri

1. Sözleri olan bir parça çal → başlık ile progress bar arasında aktif satır kapak renginde, altında sonraki satır soluk görünür; parça ilerledikçe yukarı kayar.
2. Söz aralığının dışında (intro / outro) alan boş kalır — bu doğru davranış, sözler o anda yok demektir.
3. Sözü olmayan bir parça: alan boş kalır, hata gösterilmez.
4. Kapatma: `defaults write com.emre.mynotch lyricsEnabled -bool NO` → yeniden başlat, alan hep boş olur. Geri açmak için `defaults delete com.emre.mynotch lyricsEnabled`.
5. Ağ yokken: alan boş kalır, uygulama takılmaz (istek 10 sn'de zaman aşımına uğrar).
6. **Senkron:** çalan bir parçada satırın vurgulanma anı sesle örtüşmeli. Ölçmek için: `osascript -e 'tell application "Spotify" to return player position'` ile konumu oku, aynı anda ekran görüntüsü al ve LRCLIB'deki satır zamanlarıyla karşılaştır (2026-09-04'te "mor ve ötesi — Re" ile doğrulandı: 113,4 sn'de beklenen satır aktifti).
7. **Spotify'da ileri sar:** notch açıkken Spotify'dan konumu değiştir. Spotify seek'i bildirmediği için notch en geç ~2 sn içinde yakalamalı (expanded'dayken hızlı yeniden örnekleme).
8. **Kulaklık gecikmesi:** Bluetooth kullanıyorsan sözler erken gelir; `defaults write com.emre.mynotch lyricsLeadSeconds -0.1` ile geri al (varsayılan 0.15).
8b. **Hassas çapa (2026-09-05):** oynatıcılar konumu kaba adımlarla günceller; notch artık expanded açılınca ve 30 sn'de bir konumu "değiştiği anda" yakalayan bir osascript döngüsü (20 ms) ile çapalar, 2 sn'lik rutin okumalar seek değilse çapayı **oynatmaz** (titreme yok). Ayrıca ses çıkış aygıtının gecikmesi CoreAudio'dan okunup düşülür (hoparlör ~27 ms, Bluetooth 150–300 ms) — kulaklığa geçince sözler kendiliğinden geç gösterilir. Kontrol: Bluetooth kulaklık tak/çıkar → kart açılınca düzelmeli.
9. **Şarkı başına düzeltme (2026-09-05):** sözler sese göre erken/geç akıyorsa imleci söz bandının üstüne getir → sağ uçta `−` / `+` düğmeleri çıkar. `+` sözleri 0,25 sn **geciktirir**, `−` öne alır; tutar bantta "+1.0 s" gibi görünür ve imleç çekilince de kalır. Etikete tıklamak sıfırlar. Düzeltme şarkıya bağlıdır (Spotify/Music fark etmez) ve yeniden başlatmada korunur (`lyricsShifts`).
10. **Yanlış kayıt seçilmez:** LRCLIB araması başka bir şarkı, canlı/remix sürüm ya da yarım kalmış bir dosya döndürürse seçilmez: başlık ve sanatçı eşleşmeli (Türkçe harfler katlanır, "- Topic"/"(Paused)" gibi ekler hoş görülür), süre farkı ≤ 8 sn olmalı, son satır parçanın bitişini aşmamalı. Aynı şarkının kopyaları arasında albümü eşleşen ve tam olan kazanır. Doğru şarkı yalnızca düz metinle varsa senkronsuz gösterilir (beyaz), yanlış şarkının senkronlu sözü asla.

### Expanded'da araya giren olaylar

1. Notch açıkken (hover) parça değişir → **banner çıkmamalı**; kart yerinde kalır, başlık/kapak/sözler yeni parçaya geçer. (Eski davranışta küçük bir kapsül kartın üstüne biniyordu.)
2. Başka bir modülün olayı: `scripts/run.sh --args -debugState expanded -debugBanner YES` → kart 28 pt büyür, banner üstte kendi şeridinde durur, oynatıcı içeriği aşağı kayar; örtüşme olmaz.
3. Notch kapalı/compact iken gelen olay → popup durumu (kart değil, küçük şerit) ve süresi dolunca eski duruma döner.

### Ekran değiştirici (2026-09-04)

1. **Şerit görünür:** Spotify (ya da Music) açıkken notch'a hover et → kartın altında haplar: aktif ekranın adı yazılı ve vurgulu, diğerleri yalnızca ikon. Spotify hapında **Spotify'ın kendi ikonu** olmalı, Claude'unkinde ✳.
2. **Her çalışan oynatıcı ayrı hap:** Spotify ve Apple Music'i birlikte aç → şeritte **iki ayrı müzik hapı** olmalı (yeşil Spotify + kırmızı Music ikonu), üstüne gelince adları görünür. Sadece biri açıksa tek hap.
3. **Yeni açılan uygulama anında görünür:** notch açıkken Apple Music'i başlat → hapı ~1 sn içinde belirir; çalmaya başlamasını beklemek gerekmez (`NSWorkspace` açılma bildirimi).
4. **Değiştirme:** soluk hapa tıkla → kart kapanmadan o ekrana geçer, hap adıyla vurgulanır. `scripts/run.sh --args -debugState expanded -debugModule claude` ile hangi ekranın açılacağı zorlanabilir.
4b. **Seçim kalıcı:** Spotify çalarken Claude hapını seç, imleci çek (kart kapanır), tekrar hover et → **Claude açılır**, Spotify değil; compact şerit yine kapağı gösterir. Uygulamayı yeniden başlat → hâlâ Claude. Spotify'ı seç → hover Spotify'a açılır; Spotify'ı kapat → hover Claude'a düşer, Spotify'ı aç → tekrar Spotify. Sıfırlamak için `defaults delete com.emre.mynotch preferredModuleID`.
5. **Boş oynatıcıyı seçmek:** Spotify çalarken Music hapına tıkla (Music'te bir şey yüklü değilken) → kart "Nothing playing in Music" gösterir ve **Spotify'a geri dönmez**; Spotify hapına tıklayınca parça geri gelir.
6. **Çalışan uygulama:** Spotify'ı kapat → hapı düşer (kapanma bildirimi anında yakalanır); tek ekran kalırsa şerit hiç çizilmez ve kart 26 pt kısalır.
7. **Açık ekran kaybolmaz:** Music ekranındayken Music'i kapat → hap yerinde kalır (okurken kartın kendi sekmesi kaybolmamalı), başka ekrana geçince listeden düşer ve sabitleme çözülür.
8. **Banner ile birlikte:** `scripts/run.sh --args -debugState expanded -debugModule claude -debugBanner YES` → üstte banner şeridi, altta ekran şeridi; hiçbiri içeriğin üstüne binmez.
9. **Tıklama geçirgenliği bozulmadı:** kartın dışındaki şeffaf alana tıkla → alttaki uygulamaya geçer ve notch kapanır; menü bar öğeleri tıklanabilir kalır.

### Debug Preview

- Modül panelinde `media` satırı görünür; "Test popup" gerçek notch'ta popup tetikler.
- `demo` modülü yalnızca Debug build'de kayıtlı; medya canlıyken öncelik (10 > 0) medyada kalır.

## Faz 4 — Claude usage modülü

Hazırlık: Claude Code ile en az bir kez giriş yapılmış olmalı (`claude`). Maliyet için `ccusage` (`brew install ccusage` ya da `npm i -g ccusage`); yoksa uygulama nvm/Homebrew dizinlerinde `npx` arar ve `npx --yes ccusage@20` kullanır (ilk çalıştırma paketi indirir). Panel: `scripts/run.sh --args -debugState expanded -debugModule claude`.

1. **Dil:** ekran sistem diliyle gelir — Türkçe Mac'te çip başlıkları "harcama / token / hız", halka rozetleri "5s / 7g", açıklamalar Türkçe; İngilizce Mac'te İngilizce (`App/Localizable.xcstrings`).
2. **Açılış animasyonu:** kart açılırken halkalar, başlık, çipler, blok grafiği, bileşim çubuğu, model satırı ve alt satır sırayla (70 ms arayla) belirir; halka yayları 0'dan süpürülür, blok çubukları tabandan büyür, çubuklar paylarına oturur.
3. **Halkalar:** kalın yay kullanılan pay, ince dış yay pencerenin geçen kısmı (30 sn'de bir ilerler), içinde yüzde + rozet. Yüzdeler `/usage` ile aynı (2026-09-04: %6 / %52). Claude çalışırken 5s halkası nefes alır gibi parlar. Halkanın üstü çentiğin altına girmez (`expandedTopGap` 8 pt).
3b. **Modele özel limit halkası:** hesabın `limits[]` dizisinde `scope.model.display_name` taşıyan kayıt varsa (2026-09-05: `kind: weekly_scoped`, "Fable", %15) üçüncü bir halka gelir — rozeti model adı ("Fable"), dış yayı haftalık pencere, geri sayımı haftalık limitle aynı. Yüzdesi Claude Code `/usage` ekranındaki Fable satırıyla eşleşmeli. Eşik uyarıları bu halka için de çalışır ("Fable (haftalık) limit %8x"). Hover açıklaması "Fable (haftalık) limit — kullanılan pay %16, …" der. Kart bu yüzden 480 pt içerik genişliğine çıktı.
4. **Bugünün blokları (halkaların altı):** "bugünün 5 saatlik blokları" başlığı altında blok başına bir **kart**: üstte başlangıç saati, altta token ("31.0M"); aktif blok turuncu, kartın dibinde 5 saatlik pencerenin geçen kısmını gösteren ince çizgi, çalışırken parlar. Saat ekseni yok — gece yarısını aşan ya da yeni başlayan blok da aynı okunur. Her kartın hover açıklaması: "14:00–19:00 bloğu: 16.1M token; son etkinlik 14:25." / "Aktif blok 23:00–04:00: 0.4M token; 3s 20dk kaldı." Blokların toplamı `#` çipindeki günlük token'la örtüşmeli (`ccusage claude blocks --json --since <bugün> --offline`).
5. **Hover = öne çıkma + açıklama:** imleci herhangi bir göstergenin (halka, blok grafiği, çip, bileşim çubuğu, model satırı, durum noktası, plan çipi, çalışıyor göstergesi) üstüne getir → gösterge %8 büyür ve turuncu parlar, sağ alt bölgede siyah balon Türkçe tam cümle açıklama gösterir (ör. "5 saatlik limit — kullanılan pay %26, 4s 26dk sonra sıfırlanır. Dış yay: pencerenin geçen kısmı %11."). İmleç çekilince balon kayarak kapanır; balon tıklamaları yutmaz.
6. **Çipler ve çubuklar:** `$` harcama (fiyatı bilinmeyen model varsa "—"), `#` token, alev = hız ("3K/dk"); değerler değişince rakamlar kayar, ikon zıplar, alev çalışırken titrer. Altında **token bileşimi** çubuğu: çıkış (turuncu) · giriş · önbellek, her parçanın sayısı yanında. "Giriş" yalnızca önbellekten gelmeyen kısımdır (ham `usage.input_tokens`); Claude Code istemin çoğunu önbellekten okuduğu için 1K gibi küçük görünmesi normaldir — hover açıklaması okuma/yazma ayrımıyla birlikte bunu söyler. Doğrulama: `ccusage claude daily --json --since <bugün> --offline` → `inputTokens` / `outputTokens` / `cacheReadTokens + cacheCreationTokens` (2026-09-05: 1.456 / 213.054 / 38,2M, toplam 38,4M eşleşti). Sonra model satırı (tek model: nokta + ad; çok model: parçalı çubuk). ccusage yoksa tek çip "↓ ccusage / kur".
7. **Durum ve çalışma:** alt satırdaki nokta nabız atar (yeşil taze, turuncu bayat/ağ/rate-limit, kırmızı kimlik sorunu — o zaman yanında kısa komut). Başlık sağında Claude çalışırken proje adı + dalgalanan üç nokta, boştayken küçük sabit nokta. Sağda plan çipi.
8. **Çalışıyor algısı (≤5 sn):** Claude Code'da bir mesaj gönder → panel başlığı "Working · <proje>" olur ve ✳ nabız gibi atar; 10 sn sessizlikten sonra "Idle". Müzik çalmıyorsa compact şeritte ✳ + yüzde görünür; müzik çalarken şerit medyada kalır (öncelik 10 > 5), popup'lar yine gelir.
9. **Kimlik yok:** `security find-generic-password -s "Claude Code-credentials"` boş dönen bir hesapta alt satır "Sign in with `claude` in Terminal to see limits"; `claude` ile giriş yapınca ≤10 sn içinde halkalar dolar (5 sn'lik metadata izleme). Keychain şifresi **sorulmamalı**.
10. **Eşik popup'ı:** 5 saatlik pencere %80'i geçince bir kez "5-hour limit at 8x%" popup'ı; %95'te ikinci; aynı pencerede tekrar yok; pencere sıfırlanınca "5-hour window reset". Debug Preview → `claude` satırı → "Test popup" genel popup yolunu dener.
11. **ccusage yok:** `defaults write com.emre.mynotch ccusagePath /nonexistent` ile bile npx bulunursa çalışır; nvm/npx de yoksa "Cost needs ccusage · brew install ccusage" satırı, halkalar etkilenmez. Geri almak için `defaults delete com.emre.mynotch ccusagePath`.
12. **Ağ yok:** alt satır "Anthropic unreachable · showing last reading", halkalar soluk; 15 dk'dan eski okuma soluk kalır.
13. **Uyku/uyanma:** kapağı kapatıp açınca ilk istek en erken 60 sn sonra; log'da (`log stream --predicate 'subsystem == "com.emre.mynotch"'`) tek poll görünmeli, seri istek yok.

## Faz 5 — Ayarlar & cila

Hazırlık: `scripts/run.sh --args -openSettings general` (ya da menü bar → Ayarlar…, ⌘,). Sekmeye doğrudan gitmek için `-openSettings modules|media|claude|calendar|battery|pomodoro|shelf|setup|about`.

1. **Pencere:** kenar çubuğu saydam (liquid glass), geri/ileri okları sekme geçmişinde gezer; pencere 720×560 açılır, konumu/boyutu yeniden açılışta korunur (`NSWindow Frame SettingsWindow`). Türkçe sistemde tüm metinler Türkçe, İngilizce'de İngilizce.
2. **Genel → Çentik:** hover süresini 0,5 s yap → çentik ancak yarım saniye durunca açılır; kapanma süresini 0,2 s yap → karttan ayrılınca 0,2 s içinde kapanır. Slider en fazla 1,0 s'ye gider. Haptik kapalıyken açılışta titreşim yok. "Varsayılanlara dön" 0,15 / 0,80 / açık / Otomatik'e döner.
3. **Genel → Ekran:** harici ekran seçilince notch o ekranın üst ortasında floating stilde çıkar; kablo çekilince otomatiğe (dahili çentik) döner, ekran adı listede "(bağlı değil)" olarak kalır.
4. **Genel → Açılışta başlat:** açınca durum "MyNotch oturum açtığınızda başlar." (Applications dışından çalışan derlemede "Sistem MyNotch'un bu kopyasını görmüyor" beklenir); onay bekliyorsa "Giriş Öğeleri'ni aç…" düğmesi Sistem Ayarları'nı açar.
5. **Modüller:** Medya'yı kapat → compact şerit kapanır, değiştiricide Spotify/Müzik pilleri kalkar, popup gelmez; yeniden aç → oynatıcı çalışıyorsa şerit döner. Tercih yeniden açılışta korunur (`disabledModules`).
6. **Medya → Şarkı sözleri:** kapat → açık karttaki sözler anında kalkar; aç → sözler yeniden yüklenir. Öncelik slider'ı −500…+500 ms; "Şarkı bazlı ayarları unut" sayaç 0 iken pasif.
7. **Medya → Spotify:** client ID boşken durum "Kalbi açmak için bir client ID girin", Bağlan pasif; ID girilince "Bağlı değil" + Bağlan aktif; Bağlan… tarayıcıyı açar, onaydan sonra "Bağlı"; Bağlantıyı kes → "Bağlı değil" ve kart kalbi boş. ID silinirse bağlantı da düşer.
8. **Medya → Otomasyon:** izin verilmişse yeşil; `tccutil reset AppleEvents com.emre.mynotch` sonrası "Henüz sorulmadı", "Yeniden denetle" istemi tetikler.
9. **Claude → Uyarılar:** uyarı eşiğini %95'e çek → kritik otomatik %100'e çıkar; kritik uyarının altına inemez. Uyarılar kapalıyken eşik popup'ı gelmez, halkalar yine renk değiştirir.
10. **Claude → Sorgulama:** 15 dk seçilince log'da (`log stream --predicate 'subsystem == "com.emre.mynotch"'`) poll'lar 900 sn arayla; 5 dk altı seçenek yok.
11. **Claude → Maliyet:** yol alanına geçersiz bir yol yaz → durum otomatik bulunanla devam eder (override yalnızca çalıştırılabilirse kullanılır); "Seç…" dosya paneli açar. Yapılandırma dizini değişince modül yeniden başlar (log'da yeni `start`).
12. **Kurulum (ilk açılış):** `defaults delete com.emre.mynotch onboardingCompleted` + yeniden başlat → pencere Kurulum sekmesiyle açılır; "Bitti" sonrası bir daha açılmaz (`-debugState` ile başlatıldığında hiç açılmaz). Satırlar: Otomasyon, Spotify (isteğe bağlı), Claude girişi, oturum logları, ccusage (isteğe bağlı), açılışta başlat; "Medya'da ayarla…" / "Claude'da ayarla…" ilgili sekmeye geçer.
13. **Hakkında:** sürüm `MARKETING_VERSION (CURRENT_PROJECT_VERSION)`, dışarı giden veri listesi üç satır, kaynak bağlantıları tarayıcıda açılır, log komutu kopyalanır, "Debug Preview'ı aç" çalışır.
14. **CPU:** `scripts/measure-idle.sh 30` — kapalı ve compact durumda ≈%0; açık Claude kartı için §16.4'teki değerin altında.
15. **Parça değişimi popup'ı:** şarkı değişince compact satırı yerinde kalır — solda kapak, sağda seviye ölçer yüzeyin dış kenarlarına kayar ve yüzeyle birlikte büyür (≈21 pt'den 57 pt'ye; kapak popup'ın neredeyse tüm yüksekliğini kaplar) — ve çentiğin **altındaki** şeritte "Başlık — Sanatçı" tek satır ortalı görünür; uzun başlık kameranın arkasına girmez, sonu üç nokta ile kısalır; boş köşe kalmaz. Kontrol: `scripts/run.sh --args -debugState popup -debugModule media`. Harici (çentiksiz) ekranda aynı düzen 72 pt'lik kapsülde.

## Faz 6 — Gelişmiş

### Claude — native parser (hibrit maliyet)
1. **Parite:** `scripts/run.sh --args -debugState expanded -debugModule claude -onboardingCompleted YES -debugUsageDump YES`; `/usr/bin/log show --last 2m --info --predicate 'subsystem == "com.emre.mynotch" AND category == "claude-usage"'` içindeki `usage today` satırındaki blok id/token'ları `npx --yes ccusage@20 claude blocks --json --since $(date +%Y%m%d) --offline` ile karşılaştır — birebir olmalı; dolar `daily` ile aynı.
2. **ccusage yokken:** Ayarlar → Claude → ccusage yolu alanına geçersiz bir yol yaz ve npx'i PATH dışına al → `$` çipi "—" (caption `ccusage`), token/hız çipleri ve bloklar çalışır; açıklama metni ccusage'ın yalnızca dolar için gerektiğini söyler.
3. **Artımlı okuma:** Claude Code'da bir mesaj gönder → 1–2 sn içinde token çipi ve aktif blok güncellenir (log'da `ledger pass` satırı, bayt sayısı yalnızca yeni satırlar kadar artar).
4. **Soğuk başlangıç:** `ledger pass` ilk satırı < 60 MB ve `anchored true`.

### Battery
1. Adaptörü tak/çıkar → 2,5 s popup ("Şarj oluyor · %62 — 1s 20dk sonra dolar" / "Pilde"); compact şeritte şarjda nefes alan şimşek + yüzde.
2. Eşik popup'ı: `defaults write com.emre.mynotch batteryLowThreshold 0.95` → pil %95'in altına inince bir kez "Pil azaldı"; şarja takıp çıkarınca yeniden silahlanır (`defaults delete com.emre.mynotch batteryLowThreshold`).
3. Kart (`-debugState expanded -debugModule battery`): büyük gösterge dolgusu yüzdeyi izler, tahmin satırı yalnızca şarjda/pilde görünür, hover açıklamaları Türkçe.
4. `sudo pmset -a lowpowermode 1` → "Düşük Güç Modu açık" popup'ı ve kartta yaprak; `0` ile geri.
5. Pil olmayan Mac: modül boşta, şeritte hap yok, Modüller sekmesi özeti bunu söyler.

### Pomodoro
1. Kart (`-debugState expanded -debugModule pomodoro`): halka + `25:00`, Başlat/Atla/Sıfırla ilk tıklamada çalışır; Başlat → halka boşalmaya başlar, compact şeritte halka + kalan dakika; compact'ta CPU ≈%0 (`scripts/measure-idle.sh 20`).
2. `defaults write com.emre.mynotch pomodoroWorkMinutes 5` → 5 dk sonra "Odak bitti — 5 dakika mola" popup'ı + zil; Ayarlar'da otomatik başlat kapalıysa mola Başlat'ı bekler.
3. Sayaç çalışırken uygulamayı öldür ve yeniden aç → kaldığı yerden devam (kapalıyken bitmiş faz bir kez duyurulur).
4. 4 odak bloğu sonra uzun mola (15 dk); noktalar dolar.
5. Ayarlar → Pomodoro: süreler slider/stepper, zil ve otomatik başlat anahtarları anında etkili.

### Takvim
Hazırlık: izin durumunu sıfırlamak için `tccutil reset Calendar com.emre.mynotch`; Calendar.app'te **6 dk sonrasına** başlığında Zoom linki (`https://zoom.us/j/123`) olan bir etkinlik oluştur.
1. Ayarlar → Kurulum → "Takvim (isteğe bağlı)" satırı nötr; "Erişim ver…" → macOS izin istemi `NSCalendarsFullAccessUsageDescription` metnini gösterir. İzin ver → satır "İzin verildi", Takvim paneli takvim listesini ve sıradaki etkinliği gösterir. Reddet → satır problem tonunda "Gizlilik Ayarlarını Aç…" (`…?Privacy_Calendars`).
2. `scripts/run.sh --args -debugState expanded -debugModule calendar -onboardingCompleted YES`: kartta yatay zaman şeridi (takvim renginde bloklar), ilk etkinliğin başlığı büyük, saat aralığı + takvim adı, "Katıl" düğmesi (link varsa); etkinlik yoksa "Bugün toplantı kalmadı". Hover açıklamaları kart içinde.
3. Etkinliğe 15 dk kala (`calendarLeadMinutes`) compact: solda sağlayıcı glifi (`video.fill` Zoom/Meet/Teams için), sağda geri sayım (`12dk`, `4dk`, `şimdi`) dakika sınırında güncellenir. 5 dk kala popup 4 s, başlangıçta popup 6 s; ikisi de bir kez.
4. Karttan "Katıl" → Zoom linki açılır (`NSWorkspace.open`), kart kapanır. Tüm gün etkinlikler ve reddedilen davetler listede yer almaz.
5. Ayarlar → Takvim'de tek takvim seç → yalnızca o takvimin etkinlikleri; `calendarAlertsEnabled` kapalı → popup yok, compact geri sayım kalır. Calendar.app'te etkinliği taşı → `EKEventStoreChanged` ile kart birkaç saniyede güncellenir (poll yok). Uyku/uyanma sonrası sayaç doğru.
6. CPU: `scripts/measure-idle.sh 30` etkinlik yaklaşırken (compact) ≈ %0 — dakika sınırında tek uyanma.

### Medya — gerçek seviye ölçer (visualizer)
1. Ayarlar → Medya → "Çubuklar müziğe göre hareket etsin" aç; Spotify'da müzik başlat → macOS "MyNotch sistem sesini kaydetmek istiyor" istemini bir kez gösterir; İzin Ver → durum satırı "Sesi izliyor", çubuklar sese uyar (bas bölümlerde sol çubuk, tiz vokalde sağ). Sesi kısınca çubuklar tabana iner.
2. İzni reddet (`tccutil reset AudioCapture com.emre.mynotch` ile sıfırlanır): 3 sn sonra durum "Hiçbir şey duyulmuyor", çubuklar otonom dansa döner; Gizlilik → Ekran ve Sistem Sesi Kaydı'ndan izin verince tekrar sese uyar.
3. Duraklatınca 2 sn içinde tap kapanır (`/usr/bin/log show --last 2m --info --predicate 'subsystem == "com.emre.mynotch" AND category == "audio-tap"'` → başlatma satırı yalnızca çalarken); anahtar kapalıyken tap hiç açılmaz.
4. CPU: `scripts/measure-idle.sh 30` müzik çalarken ve anahtar açıkken ≤ %2 (hedef); `-debugAudioMeter YES` ile seviyeler log'a basılır.
5. Kulaklık/hoparlör değişimi: varsayılan çıkış değişince çubuklar en geç birkaç saniyede yeni cihazın sesini izler (aggregate cihaz yeniden kurulur — bu sürümde tap yeniden başlatılarak; başarısızlıkta 30 sn sonra tek deneme).

### Medya — sistem geneli oynatıcı (mediaremote-adapter)
1. Ayarlar → Medya → "Mac'te ne çalıyorsa göster" aç: durum satırı önce "Adaptör denetleniyor…" (`test` bir kez çalışır, ~1–3 sn), sonra "Dinliyor — başka yerde çalan yok" ya da "X izleniyor". `defaults read com.emre.mynotch genericPlayerHealth` → `ok|<os>|<sürüm>|<epoch>`; `pgrep -f mediaremote-adapter.pl` tek süreç.
2. Safari/Chrome/Edge'de YouTube başlat (Spotify ve Müzik kapalı): compact'ta kapak + seviye çubukları, şeritte tarayıcının kendi ikonu ve adı ("Safari"), kartta başlık/sanatçı/kapak, playhead akar. Oynat/duraklat, ileri/geri ve scrubber MediaRemote üzerinden çalışır (shuffle/repeat/kalp gizli — `capabilities` hepsi false). Parça değişimi → popup; değişimden ilk satıra gecikmeyi not et (hedef ≤ 0,5 sn, `--debounce=250`).
3. Spotify'da müzik başlat: generic **susar**, şeritte yalnızca Spotify görünür; Spotify'ı durdurup tarayıcıya dönünce generic yeniden devreye girer.
4. Anahtarı kapat → `pgrep -f mediaremote-adapter.pl` boş (birkaç ms). Uygulamayı `pkill -x MyNotch` ile kapat → perl de biter. `kill -9 $(pgrep -x MyNotch)` → perl öksüz kalır; uygulamayı yeniden aç → tek ve **yeni** pid'li perl (açılış süpürmesi).
5. "Yeniden test et" → `genericPlayerHealth` yeni epoch'la yazılır; stream kesilip yeniden kurulur. Adaptör kırılmış gibi görmek için: `defaults write com.emre.mynotch genericPlayerHealth "noData|<os>|<sürüm>|0"` (os/sürüm mevcut kayıttan) → yeniden açılışta durum "macOS adaptörün Now Playing'i okumasına artık izin vermiyor", perl açılmaz, Spotify/Music çalışır; "Yeniden test et" düzeltir.
6. Log: `/usr/bin/log stream --info --predicate 'subsystem == "com.emre.mynotch" AND category == "mediaremote-adapter"'` → "adapter item: <bundle id> pid <n> — <private>" her öğe değişiminde; stderr satırları "adapter: …".
7. CPU: `scripts/measure-idle.sh 30` kart açıkken ≈ %0; `top -pid $(pgrep -f mediaremote-adapter.pl)` boşta %0, çalarken ≤ %1 (hedef).

### Raf (sürükle-bırak → AirDrop)
1. Finder'dan bir dosyayı çentiğin **üzerine** sürükle (bırakmadan): imleç housing'e değer değmez kart **anında** raf ekranına açılır (hover gecikmesi yok; başka bir kart açıksa raf onu alır). Kartın üzerinde dolaşırken sol AirDrop bölgesi ve sağ raf, imlecin hangisine düşeceğini vurgular. Housing'in 32 pt yanına ya da altına sürüklemek de açmalı (dedektör yalnızca sürükleme sırasında var).
2. Rafa bırak: öğe önizlemesiyle (QuickLook; yoksa dosya ikonu) belirir, kart ~3 sn kalır sonra kendiliğinden kapanır (imleç kartın üzerinde durursa açık kalır). `~/Library/Application Support/MyNotch/Shelf/<uuid>/` altında kopya + `preview.png` + kökte `index.json`; özgün dosya yerinde. Log: `/usr/bin/log stream --info --predicate 'subsystem == "com.emre.mynotch" AND category == "shelf"'` yalnızca hatalarda konuşur.
3. Compact: bırakmadan sonra 2 dk boyunca solda tepsi, sağda sayı (`9+` tavanı); 2 dk sonra şerit sessizleşir, öğeler kalır. Şeritte "Raf" ekranı raf boşken görünmez.
4. AirDrop bölgesine bırak: sistemin AirDrop penceresi açılır (paneli key yapmadan), popup "1 dosya AirDrop'la gönderiliyor"; AirDrop kapalıysa dosya rafa düşer. Rafta dosya varken AirDrop bölgesine **dokun**: raftaki her şey gönderilir.
5. Öğeye dokun → dosya açılır (`NSWorkspace.open`). Üzerinde dururken ✕ → kopya silinir; Option ile dokunma da siler. Öğeyi Finder'a/ Mail'e **sürükle** → kopya oradan alınır (dışarı sürükleme, key olmayan panelden: `.draggable(Transferable)`).
6. Masaüstü/İndirilenler'den bırakılan dosya: TCC klasör istemi çıkıyor mu gözle; çıkarsa `project.yml`'e ilgili usage description eklenir.
7. Menü bar: sürükleme yokken çentiğin yanındaki menü bar öğeleri normal tıklanır (dedektör çizilmez). Bir pencereyi sürüklerken (dosya değil) kart açılmaz.
8. Ayarlar → Raf: sayı + boyut + yol, "Finder'da Göster", "Rafı boşalt" (yalnızca kopyalar gider), saklama süresi seçici; 1 saate çekip 1 saatten eski bir kopyanın raf yeniden yüklenince gittiğini gör (`defaults write com.emre.mynotch shelfKeepInterval 3600` + yeniden aç). Kurulum sekmesinde "Raf (isteğe bağlı)" satırı pane'e götürür.
9. `-debugState expanded -debugModule shelf -onboardingCompleted YES`: boş raf ipucu ("Dosyaları çentiğe bırak") + AirDrop bölgesi; Debug Preview → "Test popup" raf popup'ını gösterir. CPU: `scripts/measure-idle.sh 30` kart açıkken ≈ %0 (2026-09-06: %0,01, sürükleme monitörü kurulu).

