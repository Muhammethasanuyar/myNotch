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

### Debug Preview

- Modül panelinde `media` satırı görünür; "Test popup" gerçek notch'ta popup tetikler.
- `demo` modülü yalnızca Debug build'de kayıtlı; medya canlıyken öncelik (10 > 0) medyada kalır.
