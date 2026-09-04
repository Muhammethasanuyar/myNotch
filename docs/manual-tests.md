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

- [x] Hover: imleç notch'a gelince ~0,15 s sonra expanded açılır, ayrılınca kapanır.
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
3. **Seek:** ilerleme çubuğunu sürükle, bırakınca Spotify o konuma atlar; süre etiketleri (geçen/toplam) doğru — Spotify süreyi milisaniye verir, saniyeye çevriliyor.
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

### Expanded'da araya giren olaylar

1. Notch açıkken (hover) parça değişir → **banner çıkmamalı**; kart yerinde kalır, başlık/kapak/sözler yeni parçaya geçer. (Eski davranışta küçük bir kapsül kartın üstüne biniyordu.)
2. Başka bir modülün olayı: `scripts/run.sh --args -debugState expanded -debugBanner YES` → kart 28 pt büyür, banner üstte kendi şeridinde durur, oynatıcı içeriği aşağı kayar; örtüşme olmaz.
3. Notch kapalı/compact iken gelen olay → popup durumu (kart değil, küçük şerit) ve süresi dolunca eski duruma döner.

### Debug Preview

- Modül panelinde `media` satırı görünür; "Test popup" gerçek notch'ta popup tetikler.
- `demo` modülü yalnızca Debug build'de kayıtlı; medya canlıyken öncelik (10 > 0) medyada kalır.
