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
7. **Yeniden başlatma:** token dosyası (`~/Library/Application Support/MyNotch/spotify-oauth.json`, 0600) sayesinde bağlantı kalır; süresi dolan access token refresh token ile sessizce yenilenir.
8. **Bağlantıyı kesmek:** dosyayı sil ve uygulamayı yeniden başlat (Faz 5'te Ayarlar'a düğme olarak gelecek). Spotify hesabındaki yetkiyi geri alırsan (401) uygulama da bağlantısız duruma düşer ve kalp yeniden "bağlan" moduna geçer.
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
