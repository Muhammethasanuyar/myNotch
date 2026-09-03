# ccusage — Harvest Notu

| | |
|---|---|
| Repo | https://github.com/ryoppippi/ccusage (klonun `origin`'i; paket metadata artık https://github.com/ccusage/ccusage — `apps/ccusage/package.json:4`, `:12`) |
| Klon | `references/ccusage` @ `21c7f68` (2026-09-01) — sürüm `20.0.20` (`apps/ccusage/package.json:3`) |
| Lisans | **MIT** — `apps/ccusage/LICENSE:1` "MIT License", `:3` "Copyright (c) 2025 ryoppippi"; `apps/ccusage/package.json:9` `"license": "MIT"`. **Düzeltme:** repo kökünde LICENSE *var*, `./apps/ccusage/LICENSE`'a symlink (`ls -l LICENSE`), `README.md` de aynı şekilde symlink. Platform paketleri de MIT (`packages/ccusage-darwin-arm64/package.json:4`). |
| Devşirme modu | **Araç olarak çağır** (Faz 4: CLI'yi `Process` ile çalıştır, `--json` parse et); hesap mantığı v2'de adapte (Faz 6) |
| İlgili fazlar | 4 (CCUsageRunner), 6 (native Swift parser) |

---

## 1. Bizim için değeri

İki farklı seviyede:

**Faz 4 (araç):** `blocks --json` çıktısı, `docs/PLAN.md` §6.2'deki dashboard'un ihtiyacı olan her şeyi hazır veriyor — 5 saatlik blok sınırları, aktif blok, blok içi token/maliyet, **burn rate** ve **projeksiyon**. `claude daily --json` da bugünkü maliyet + model kırılımını veriyor. Maliyet hesabını (cache token'ları, 1 saatlik cache çarpanı, uzun bağlam kademeleri, model fiyat tablosu) sıfırdan yazmak haftalar alır ve sürekli bakım ister; `docs/PLAN.md` §6.1'deki "maliyet hesabını sıfırdan yazma" kararı doğru.

**Faz 6 (native parser):** Repo, JSONL şemasının ve tuzaklarının **referans dokümantasyonu** işlevi görüyor: hangi alanlar okunur, hangi satırlar atılır, dedupe nasıl yapılır, blok sınırı nasıl belirlenir. Bunlar Swift'e yeniden yazılırken doğrudan spesifikasyon olarak kullanılabilir (MIT → adapte serbest, dosya başına kaynak yorumu + `THIRD_PARTY_LICENSES.md`).

**Büyük yapısal değişiklik (klon tarihi itibarıyla):** ccusage artık TypeScript değil. `apps/ccusage/src` yalnızca 270 satırlık bir Node launcher (`cli.js`) içeriyor; gerçek uygulama `rust/` altında bir Rust workspace ve npm'de platforma özgü **native binary** paketleri olarak dağıtılıyor (`apps/ccusage/package.json:28-35`). Bu, plandaki bazı varsayımları değiştiriyor (bkz. §4).

---

## 2. Hedef dosyalar

| Kaynak dosya (path:line) | Ne yapıyor | Bizde hedef dosya (per docs/PLAN.md §9) | Faz |
|---|---|---|---|
| `apps/ccusage/src/cli.js:27-58` | `process.platform/arch` → `@ccusage/ccusage-darwin-arm64` gibi paket adı | `Modules/ClaudeUsage/CCUsageRunner.swift` (çalıştırma stratejisi) | 4 |
| `apps/ccusage/src/cli.js:99-109` | Native binary yoksa hata metni: "ccusage native binary is not available for …" | `CCUsageRunner.swift` (hata sınıflandırma) | 4 |
| `rust/crates/ccusage-cli-parser/src/cli-help.json` | Tüm bayrakların tam listesi, varsayılanları ve seçenek kümeleri | `CCUsageRunner.swift` (argüman kurucu) | 4 |
| `rust/crates/ccusage-cli-parser/src/cli-commands.json` | Komut ağacı (`blocks` = `shared_claude_options` + `blocks_options`) | `CCUsageRunner.swift` | 4 |
| `rust/crates/ccusage/src/commands/mod.rs:261-307` | `run_blocks`: yükle → blokla → filtrele → `{"blocks": [...]}` | `Modules/ClaudeUsage/UsageService.swift` | 4 |
| `rust/crates/ccusage/src/blocks.rs:184-232` | `block_json`: `blocks --json`'ın **kesin** alan isimleri | `CCUsageRunner.swift` (DTO) | 4 |
| `rust/crates/ccusage/src/blocks.rs:53-103` | `identify_session_blocks`: 5 saatlik blok tespiti + gap blokları | `UsageService.swift` (v2 native) | 6 |
| `rust/crates/ccusage/src/blocks.rs:567-601` | `calculate_burn_rate` + `project_block_usage` formülleri | `Modules/ClaudeUsage/Views/BlockRing.swift`, dashboard | 4/6 |
| `rust/crates/ccusage/src/commands/mod.rs:32-58` | `run_daily` (= `claude daily`): `{"daily": [...], "totals": {...}}` | `CCUsageRunner.swift` (DTO) | 4 |
| `rust/crates/ccusage-core/src/output.rs:27-117` | `summary_json` / `session_summary_json` / `totals_json` alan isimleri | `CCUsageRunner.swift` (DTO) | 4 |
| `rust/adapters/claude/src/paths.rs:12-52` | `CLAUDE_CONFIG_DIR` (virgüllü), XDG, `~/.claude` keşfi | `Modules/ClaudeUsage/ProjectsWatcher.swift` + `Settings/SettingsStore.swift` | 4 |
| `rust/adapters/common/src/lib.rs:14-34` | `projects/` altını rekürsif tarayıp `.jsonl` toplama | `ProjectsWatcher.swift` | 4 |
| `rust/crates/ccusage-core/src/types.rs:7-58` | JSONL şeması: `UsageEntry`, `UsageMessage`, `TokenUsageRaw` | `UsageService.swift` (v2 native parser) | 6 |
| `rust/adapters/claude/src/lib.rs:142-219` | `message.id` + `requestId` + `sessionId` ile dedupe | `UsageService.swift` | 6 |
| `rust/adapters/claude/src/lib.rs:472-500` | Geçersiz satır filtreleri (version/sessionId/requestId) | `UsageService.swift` | 6 |
| `rust/adapters/claude/src/lib.rs:583-615` | "Claude AI usage limit reached\|<epoch>" satırından reset zamanı | `UsageService.swift` (resmi endpoint'e yedek) | 4/6 |
| `rust/crates/ccusage-core/src/cost.rs:31-46`, `:118-175` | `--mode` semantiği + cache/uzun bağlam fiyatlandırması | `UsageService.swift` | 6 |
| `rust/crates/ccusage-core/src/pricing.rs:20-56` | Gömülü LiteLLM/models.dev snapshot'ı + ağ URL'leri | `Resources/` fiyat tablosu (v2) | 6 |
| `rust/crates/ccusage/src/http.rs:11-52` | Fiyat çekme: 10 sn timeout, ETag'li disk cache | (v2'de ağ yok; sadece bilgi) | 6 |
| `rust/adapters/common/src/lib.rs:84-126` | Dosya boyutuna göre dengelenmiş paralel okuma | `UsageService.swift` (v2 performans) | 6 |

---

## 3. Desenler

### 3.1 Dağıtım modeli: ince Node launcher + native binary

**Nasıl çalışıyor:** npm paketi yalnızca iki dosya yayınlıyor: `config-schema.json` ve `src/cli.js` (`apps/ccusage/package.json:20-23`). `cli.js` platform/mimariye göre optional dependency paketini çözer (`darwin+arm64` → `@ccusage/ccusage-darwin-arm64`, `cli.js:27-37`), içinden `bin/ccusage` yolunu `require.resolve` ile bulur (`:64-87`), gerekirse `chmod 0o755` yapar (`:123-143`) ve `spawn(..., { stdio: 'inherit' })` ile çalıştırıp sinyalleri iletir (`:178-226`). Binary bulunamazsa stderr'e "ccusage native binary is not available for `<platform>-<arch>`. Reinstall ccusage so optional native dependencies are installed." yazıp exit 1 (`:99-109`, `:233-247`). Binary'ler Rust'tan üretiliyor (`apps/ccusage/scripts/ensure-native-binary.nu`), macOS'ta yalnızca sistem dylib'lerine link olacak şekilde doğrulanıyor.

**Bize uyarlama:** `CCUsageRunner` üç yolu sırayla dener ve bulduğunu `SettingsStore`'a yazar: (1) `PATH`'te `ccusage` (Homebrew/nix kurulumu — en hızlı, Node gerektirmez), (2) `PATH`'te `npx` → `npx ccusage@latest …`, (3) hiçbiri yoksa modül "kurulum gerekli" durumuna düşer (`docs/PLAN.md` §6.3 kabul kriteri). Çalıştırma `Process` + `Pipe` ile, `CLAUDE.md` gereği ana thread dışında; `async` bir `run(_ arguments: [String]) async throws -> Data` sarmalayıcısı yazılır ve `Task` iptalinde `process.terminate()` çağrılır.

**Dikkat:** `npx ccusage@latest` her çağrıda registry'ye sürüm sorar ve gerekirse indirir — soğuk başlangıç saniyeler sürebilir, ağ yoksa başarısız olur. Bunu **her 30-60 sn'de bir** yapmak kabul edilemez (`docs/PLAN.md` §6.1'deki polling aralığı). Pratik çözüm: `@latest`'i bırakıp sürüm sabitlemek (`npx ccusage@20 …`) veya kullanıcıyı `brew install ccusage` benzeri kalıcı kuruluma yönlendirip binary yolunu ayarda saklamak. Ayrıca `stdio: 'inherit'` nedeniyle npx katmanı çıktıyı olduğu gibi geçirir — ama npm'in kendi uyarıları **stderr**'e karışabilir; stdout'u JSON, stderr'i log olarak ayrı ele alalım.

### 3.2 Komut yüzeyi: kök komutlar "unified", Claude'a özgü olanlar `claude` altında

**Nasıl çalışıyor:** `main.rs:28-65` dağıtımı yapıyor. Kökteki `daily`/`weekly`/`monthly`, **tüm ajanları** (18 adaptör: Claude, Codex, Copilot, Gemini…) birleştiren `Command::All`'a gider (`parser.rs:400-424`); Claude'a özgü olan `Command::Daily` yalnızca `ccusage claude daily` ile üretilir (`parser.rs:469-495`). Kökteki `session`, `--id` verilmişse Claude'a, verilmemişse unified'a gider (`parser.rs:426-467`). Buna karşılık **`blocks` her iki yazımda da yalnızca Claude verisini okur**: `Command::Blocks` → `commands::run_blocks` → `load_entries` = Claude adaptörü (`main.rs:7`, `:34`). Aynısı `statusline` için de geçerli.

**Bize uyarlama:** `CCUsageRunner` şu iki çağrıyı yapar:
- `ccusage claude blocks --json --active --offline` → aktif 5 saatlik blok (ring, burn rate, projeksiyon, popup eşikleri)
- `ccusage claude daily --json --since <YYYYMMDD> --offline` → bugünün maliyeti + model kırılımı (`--breakdown` istenirse)

`blocks` için `claude` önekini yazmak zorunlu değil ama **yazalım**: hem niyet açık olur hem de ileride kökteki komutun anlamı değişirse etkilenmeyiz.

**Dikkat:** `docs/PLAN.md` §6.1'de yazan `daily --json` bugün **unified** çıktı verir; satır anahtarı `date` değil `period`, her satırda `agent` alanı vardır ve Claude dışı ajanların maliyeti toplanır. Claude'a özgü rapor isteniyorsa `claude daily` şart (§4.1).

### 3.3 `blocks --json` çıktısının kesin şekli

**Nasıl çalışıyor:** Kök nesne tek anahtarlı: `{"blocks": [ … ]}` (`commands/mod.rs:289-295`); **`totals`/`summary` yoktur**. Çıktı `serde_json::to_writer_pretty` ile pretty-print edilir (`output.rs:151-155`). Her blok (`blocks.rs:184-232`, `:37-51`):

```json
{
  "id": "2026-09-02T09:00:00.000Z",
  "startTime": "2026-09-02T09:00:00.000Z",
  "endTime": "2026-09-02T14:00:00.000Z",
  "actualEndTime": "2026-09-02T11:42:13.501Z",
  "isActive": true,
  "isGap": false,
  "entries": 128,
  "tokenCounts": {
    "inputTokens": 11174,
    "outputTokens": 720366,
    "cacheCreationInputTokens": 896,
    "cacheReadInputTokens": 2304
  },
  "totalTokens": 734740,
  "costUSD": 336.47,
  "models": ["claude-sonnet-4-5-20250929"],
  "burnRate": {
    "tokensPerMinute": 2400.5,
    "tokensPerMinuteForIndicator": 310.2,
    "costPerHour": 12.5
  },
  "projection": { "totalTokens": 25000, "totalCost": 12.5, "remainingMinutes": 138 }
}
```

Notlar: `actualEndTime`, `burnRate` ve `projection` **null olabilir** (`burnRate`/`projection` yalnızca `isActive` bloklarda üretilir, `blocks.rs:184-194`). `--token-limit` verildiyse ek `tokenLimitStatus` anahtarı gelir (`limit`, `projectedUsage`, `percentUsed`, `status` ∈ `ok|warning|exceeds`; eşik 0.8, `blocks.rs:18`, `:195-204`). JSONL'de limit satırı görüldüyse `usageLimitResetTime` eklenir (`:228-230`). Zaman damgaları RFC 3339 milisaniyeli UTC. `costUSD` tam sayıysa JSON'a **integer** olarak yazılır (`json_float`, `output.rs:429-439`) → Swift'te `Double` olarak decode edilebilmeli.

**Bize uyarlama:** `CCUsageRunner` içinde `struct CCUsageBlock: Decodable` + iç içe `TokenCounts`, `BurnRate`, `Projection`; tüm opsiyoneller gerçekten `Optional`. `Date` decode'u için `.iso8601` yerine milisaniyeyi kabul eden özel formatter (fractional seconds) gerekir. Gap blokları (`isGap == true`) UI'da **atlanmalı** (token/maliyet 0, `blocks.rs:149-164`).

**Dikkat:** Resmî doküman sitesi bu şemayla **uyumsuz**: `docs/guide/json-output.md:408-439` hâlâ eski TS sürümünün şemasını gösteriyor (`{"type":"blocks","data":[…],"summary":{…}}`, `blockStart`/`blockEnd`, `burnRate` düz sayı, `projectedTotal`/`projectedCost`, `timeRemaining`). Parser'ı **koda göre** yazacağız ve şema kaymasına karşı toleranslı olacağız (`docs/PLAN.md` §13: "parser'ı toleranslı yaz"): bilinmeyen alanları yok say, eksik alanlarda son iyi değeri koru, decode hatasında modülü çökertme.

### 3.4 5 saatlik blok algoritması

**Nasıl çalışıyor:** `identify_session_blocks` (`blocks.rs:53-103`) girdileri zaman damgasına göre sıralar ve tek geçişte bloklar:

```rust
let since_start = entry.timestamp.duration_since(start);
let since_last = entry.timestamp.duration_since(last_time);
if since_start > session_duration || since_last > session_duration {
    blocks.push(create_block(start, std::mem::take(&mut current_entries), now, session_duration));
    if since_last > session_duration {
        blocks.push(create_gap_block(last_time, entry.timestamp, session_duration));
    }
    current_start = Some(floor_to_hour(entry.timestamp));
}
```
Kaynak: `references/ccusage/rust/crates/ccusage/src/blocks.rs:73-90` (MIT)

Kritik ayrıntılar: (a) blok başlangıcı **tam saate yuvarlanır** (`floor_to_hour`, `:105-107`) — yani 09:37'deki ilk mesaj 09:00 başlangıçlı blok üretir; (b) blok bitişi `start + 5 saat` (`:115`); (c) yeni blok, ya 5 saat dolduğunda ya da **iki mesaj arası 5 saatten uzun boşluk** olduğunda açılır; (d) boşluk durumunda araya `gap-<zaman>` id'li sanal bir blok eklenir; (e) aktiflik: `now - sonEntry < 5 saat` **ve** `now < endTime` (`:117`); (f) süre `-n/--session-length` ile değiştirilebilir, varsayılan `DEFAULT_SESSION_DURATION_HOURS = 5.0` (`ccusage-core/src/lib.rs:54`).

**Bize uyarlama:** Faz 4'te bu algoritmayı çalıştırmıyoruz (CLI yapıyor), ama **anlamak zorundayız**: ring'in "blok başlangıcı"nı 09:00 gösterip kullanıcının ilk mesajının 09:37 olması kafa karıştırıcı olabilir; dashboard'da hem `startTime` hem `actualEndTime` gösterelim. Faz 6 native parser'da bu fonksiyon `nonisolated func identifySessionBlocks(_:sessionDuration:)` olarak birebir yeniden yazılır ve XCTest ile (saate yuvarlama, gap, aktiflik sınırları) test edilir — `CLAUDE.md`'nin "saf yardımcılar `nonisolated` ve birim testli" kuralına ideal aday.

**Dikkat:** Aktiflik `now`'a bağlıdır; CLI çıktısını cache'lersek `isActive` bayatlayabilir. Ring'in "kalan süre"sini `endTime - Date()` ile **yerelde** hesaplayalım, `projection.remainingMinutes`'a güvenmeyelim (o da çağrı anına göredir).

### 3.5 Burn rate ve projeksiyon

**Nasıl çalışıyor:** `calculate_burn_rate` (`blocks.rs:567-584`) blok içindeki **ilk ve son entry arası** dakikaya böler (blok süresine değil): `tokensPerMinute = totalTokens / dakika`, `tokensPerMinuteForIndicator = (input + output) / dakika` (cache token'ları hariç — gösterge için daha dürüst), `costPerHour = costUSD / dakika * 60`. Süre 0 ise `nil`. `project_block_usage` (`:586-601`) yalnızca aktif blok için: `remainingMinutes = round((endTime - now)/60000)`, `totalTokens = mevcut + tokensPerMinute * remainingMinutes`, `totalCost = mevcut + (costPerHour/60) * remainingMinutes` (2 ondalığa yuvarlanır).

**Bize uyarlama:** `docs/PLAN.md` §6.2'deki "burn rate ($/saat) ve bu hızla blok şu saatte dolar" satırı doğrudan `burnRate.costPerHour` ve `projection` ile karşılanır. "Blok %80 doldu" popup'ı için iki seçenek var: (a) `--token-limit max` verip `tokenLimitStatus.status == "warning"` kullanmak, (b) resmi endpoint yüzdesini (codex-island yolu) kullanmak. `docs/PLAN.md` §6.2 birinciyi ccusage'a düşüş senaryosu olarak konumlandırıyor — aynen koruyalım.

**Dikkat:** `--token-limit max` verildiğinde limit, **geçmişteki en yüksek token'lı blok** olur (`commands/mod.rs:282-287`: gap ve aktif bloklar hariç maksimum) — gerçek Anthropic limiti değil, sadece "kendi rekorun". Bunu UI'da "tahmini" diye etiketlemeliyiz, yoksa yanıltıcı olur. Ayrıca burn rate blok başında (birkaç mesaj, kısa süre) çok oynaktır; ilk 5 dakikada göstermemek veya yumuşatmak iyi olur.

### 3.6 Claude veri dizinlerinin keşfi

**Nasıl çalışıyor:** `claude_paths()` (`adapters/claude/src/paths.rs:12-44`):

```rust
if let Ok(env_paths) = env::var("CLAUDE_CONFIG_DIR") {
    for raw in env_paths.split(',').map(str::trim).filter(|p| !p.is_empty()) {
        let path = normalize_claude_config_path(raw);
        if path.join("projects").is_dir() && seen.insert(path.clone()) { paths.push(path); }
    }
    if !paths.is_empty() { return Ok(paths); }
    return Err(cli_error(format!("No valid Claude data directories found in CLAUDE_CONFIG_DIR…")));
}
```
Kaynak: `references/ccusage/rust/adapters/claude/src/paths.rs:15-32` (MIT)

Yani: `CLAUDE_CONFIG_DIR` **virgülle ayrılmış çoklu yol** kabul eder; her yol ya `projects/` içermeli ya da doğrudan `projects/` dizininin kendisi olmalı (`~` genişletilir, `projects` verilmişse üst dizine çıkılır, `:46-52`); değişken set ama hiçbiri geçerli değilse **hata verir, fallback yapmaz**. Değişken yoksa iki varsayılan denenir ve **ikisi de** eklenir: `${XDG_CONFIG_HOME:-~/.config}/claude` ve `~/.claude` (`:34-42`). Dosya toplama `projects/` altını rekürsif tarar, `.jsonl` uzantılılara bakar (`adapters/common/src/lib.rs:14-34`), sonuç yola göre sıralanır. Proje adı yol içinde `projects`'ten sonraki bileşendir (`paths.rs:91-110`); `subagents/` alt yolu için özel oturum ayrıştırması var (`:130-141`).

**Bize uyarlama:** `ProjectsWatcher` aynı sırayı uygulasın: env override → yoksa iki varsayılan yol (ikisi de izlenir). `docs/PLAN.md` §6.1 "kullanıcı `CLAUDE_CONFIG_DIR` değiştirmiş olabilir — ayarlardan path override sun" diyor; ayarlardaki override, ccusage'a **aynı env değişkeniyle** geçirilmeli (`Process.environment`), aksi halde bizim izlediğimiz dizin ile ccusage'ın okuduğu dizin ayrışır. `~/.config/claude` yolunu unutmayalım — planda yalnızca `~/.claude` yazılı.

**Dikkat:** `docs/guide/environment-variables.md:11` de iki varsayılanı doğruluyor. Sandbox kapalı olduğu için (`docs/PLAN.md` §3) dosya erişimi doğrudan; yine de onboarding'de şeffaf anlatılmalı. FSEvents/`DispatchSource` ile izlerken **iki kökü birden** izlemek gerekebilir.

### 3.7 JSONL şeması ve geçersiz satır filtreleri

**Nasıl çalışıyor:** Üst düzey alanlar camelCase, `message.usage` içi snake_case (`ccusage-core/src/types.rs:7-39`):

```rust
#[derive(Debug, Clone, Copy, Default, Deserialize)]
pub struct TokenUsageRaw {
    pub input_tokens: u64,
    pub output_tokens: u64,
    #[serde(default)]
    pub cache_creation_input_tokens: u64,
    #[serde(default)]
    pub cache_read_input_tokens: u64,
    pub speed: Option<Speed>,
    #[serde(default)]
    pub cache_creation: Option<CacheCreationRaw>,
}
```
Kaynak: `references/ccusage/rust/crates/ccusage-core/src/types.rs:28-39` (MIT)

`UsageEntry` (`:7-19`): `sessionId`, `timestamp` (string), `version`, `message`, `costUSD` (açık `rename`), `requestId`, `isApiErrorMessage`, `isSidechain`. `UsageMessage` (`:21-26`): `usage`, `model`, `id`. Yeni `cache_creation` nesnesi varsa cache yaratma miktarı `ephemeral_5m_input_tokens + ephemeral_1h_input_tokens` olarak hesaplanır, yoksa düz `cache_creation_input_tokens` (`:41-50`). Geçersiz sayılan satırlar (`adapters/claude/src/lib.rs:472-500`): `version` semver öneki değilse, `sessionId` boş string ise, `requestId` boş string ise. Zaman damgası parse edilemeyen satır atlanır (`:321-323`). `model == "<synthetic>"` model sayılmaz (`:339-347`). Ayrıca hız artırılmış çağrılarda model adına `-fast` soneki eklenir. Limit satırı ayrıştırma: `isApiErrorMessage == true` olan satırda `"Claude AI usage limit reached"` metnini bulup `|` sonrası epoch **saniye** okunur (`:583-615`).

**Bize uyarlama:** Faz 6 parser'ında `Decodable` modeller birebir bu şekilde; `keyDecodingStrategy` karışık olduğu için (üst düzey camelCase, usage snake_case) **elle `CodingKeys`** yazmak en güvenlisi. Toleranslı olalım: bilinmeyen alanlar yok sayılır, `usage` yoksa satır atlanır, tarih parse hatası satırı düşürür ama dosyayı durdurmaz. "Claude çalışıyor" tespiti (`docs/PLAN.md` §6.1: son 10 sn'de `.jsonl` değişti mi) parse gerektirmez — sadece mtime.

**Dikkat:** Şema Anthropic tarafından değiştirilebilir (`docs/PLAN.md` §13 riski). `cache_creation` alt nesnesinin sonradan eklenmesi bunun canlı bir örneği: eski kod yalnızca `cache_creation_input_tokens` okusa 1 saatlik cache token'larını **iki kez veya hiç** saymazdı. MVP'de ccusage'a yaslanma kararı bu yüzden doğru.

### 3.8 Dedupe: aynı mesajı iki kez saymamak

**Nasıl çalışıyor:** Anahtar `message.id` + `requestId` + `sessionId` üçlüsünün hash'i (`adapters/claude/src/lib.rs:213-219`); ayrıca `requestId`'siz bir "sadece mesaj" hash'i tutulup sidechain (alt ajan) kopyalarını yakalamak için kullanılıyor (`:142-211`). Çakışma olduğunda hangi kaydın kalacağına kural karar veriyor (`:126-140`): sidechain olmayan tercih edilir; eşitse **daha yüksek toplam token**lı kayıt; o da eşitse `usage.speed` bilgisi olan. `message.id` yoksa dedupe yapılmaz, kayıt olduğu gibi eklenir.

**Bize uyarlama:** v2 parser'da `Set<DedupeKey>` yerine `[DedupeKey: Int]` (indeks) tutup aynı "kazanan seçimi" kuralını uygulayalım — aksi halde alt ajan (subagent) oturumları maliyeti şişirir. Faz 4'te bu bizi ilgilendirmiyor ama **"neden ccusage'ın rakamı benim naif toplamımdan düşük"** sorusunun cevabı burada.

**Dikkat:** Aynı mesaj birden fazla dosyada görünebilir (özet/replay dosyaları, `subagents/` alt dizinleri). Dosya bazlı artımlı okuma yaparken (v2 hedefi: offset'ten devam) dedupe durumunu da kalıcılaştırmak gerekir; yoksa artımlı okuma dedupe'u bozar. Bu, v2'nin en riskli kısmı.

### 3.9 Maliyet modu ve fiyat kaynağı

**Nasıl çalışıyor:** `--mode` üç değer alır (`cost.rs:31-46`): `display` → yalnızca JSONL'deki `costUSD` (yoksa 0), `calculate` → her zaman token × fiyat, `auto` (varsayılan) → `costUSD` varsa onu, yoksa hesaplama. Hesaplama tarafında: cache yaratma 5 dakikalık ve 1 saatlik olarak ayrılır, **1 saatlik cache girdi fiyatının 2 katıdır** (`cost.rs:7`, `:128-129`), modele özel `long_context_threshold` varsa istek tamamen üst kademeden fiyatlanır, yoksa LiteLLM'in 200K marjinal kademesi uygulanır (`:134-175`). Fiyat tabloları binary'ye **gömülü** (deflate'lenmiş LiteLLM + models.dev snapshot'ları, `pricing.rs:20-28`); `--offline` verilmezse çalışma anında `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json` ve `https://models.dev/api.json` çekilir (`pricing.rs:54-56`), 10 sn timeout ve `~/.cache/ccusage/http-cache` altında ETag'li cache ile (`http.rs:11-14`, `:37-52`). `--offline` ise yalnızca gömülü snapshot kullanılır (`pricing.rs:958-991`).

**Bize uyarlama:** **Her çağrıda `--offline` (veya `-O`) kullanacağız.** Gerekçe: (a) ağ gecikmesi ve başarısızlığı notch güncellemesini bloklamamalı, (b) kullanıcının makinesinden habersiz HTTP isteği çıkmasın, (c) gömülü tablo Claude modelleri için fazlasıyla yeterli. `--mode` varsayılan `auto` bırakılır (Claude Code zaten `costUSD` yazıyor; en doğru sonuç). Hız gerekiyorsa `--mode display` fiyat tablosunu hiç yüklemez (`adapters/claude/src/lib.rs:72-80`).

**Dikkat:** `--offline` ile yeni çıkmış bir model fiyatlanamayabilir → maliyet 0 görünür. `--mode auto` bu riski büyük ölçüde kapatır (JSONL'deki gerçek maliyet kullanılır). v2'de fiyat tablosunu biz bundle edeceğiz (`docs/PLAN.md` §6.1) — güncelleme mekanizması düşünülmeli (uygulama sürümüyle birlikte).

### 3.10 Performans: her çağrı tüm geçmişi okur

**Nasıl çalışıyor:** `load_entries_inner` (`adapters/claude/src/lib.rs:50-116`) her çalıştırmada tüm `.jsonl` dosyalarını bulur ve okur. Paralelleştirme: dosyalar boyutlarına göre sıralanıp worker sayısı kadar kovaya dengeli dağıtılır (`adapters/common/src/lib.rs:36-81`), worker sayısı `thread::available_parallelism()` (ya da `--single-thread` ile 1), `thread::scope` ile okunur ve sonuçlar dosya sırasına geri konur (`:84-126`). Artımlı/mtime tabanlı cache **yoktur** — tek istisna `statusline` komutunun oturum bazlı cache'i (`commands/mod.rs:326-370`, `--refresh-interval` varsayılan 1 sn, `--cache` varsayılan açık). `--since/--until` filtresi ise **okuduktan sonra** uygulanır (`common/src/lib.rs:36-48`; bloklarda `blocks.rs:166-175`) — yani veriyi azaltır, okuma işini azaltmaz.

**Bize uyarlama:** Faz 4'te polling aralığını dosya değişimine bağlayalım: `ProjectsWatcher` bir `.jsonl` değiştiğinde (debounce ~5 sn) çağrı yapsın; ayrıca tavan olarak 60 sn'lik periyot. Aynı anda birden fazla çağrı yapılmamalı (in-flight guard). Sonuç `UsageService` içinde cache'lenir, hata durumunda **son iyi değer korunur** (`docs/PLAN.md` §13 deseni). `--since` yine de verilsin: JSON çıktısı küçülür, decode ucuzlar.

**Dikkat:** Uzun geçmişli kullanıcılarda (binlerce oturum dosyası, yüzlerce MB) her çağrı tüm dosyaları okur; CPU ve disk I/O anlıktır ama görünür olabilir. Ölçüm Faz 4'te yapılmalı (`time ccusage claude blocks --json --offline`). Bu, v2 native parser'ın (artımlı okuma) asıl gerekçesidir — Node'dan kurtulmak değil, **her seferinde her şeyi okumaktan** kurtulmak.

### 3.11 `--json` çıktısını daraltmak ve `--no-cost`/`--jq` tuzakları

**Nasıl çalışıyor:** `wants_json` hem `--json` hem `--jq` ile true olur (`output.rs:14-16`). `--no-cost` verildiğinde JSON'dan maliyet alanları **silinir** (`costUSD`, `totalCost`, `cost`… — `output.rs:130-133` + `strip_cost_json`). `-q/--jq <ifade>` yardım listelerinde görünmez ama parser'da vardır (`ccusage-cli-parser/src/parser.rs:753`) ve uygulaması **sistemdeki harici `jq` binary'sini spawn eder** (`output.rs:134-150`); `jq` yoksa "failed to run jq" hatası.

**Bize uyarlama:** `--jq` **kullanmayacağız** (ek sistem bağımlılığı). `--no-cost` de kullanılmaz (maliyeti zaten gösteriyoruz). JSON pretty-print edildiği için çıktı biraz büyür; `--since` ile gün sayısını sınırlamak yeterli.

**Dikkat:** Bayrak isimlerini `cli-help.json`'dan doğrulayarak yazalım; kısa formlar bazen sezgiye aykırı: `-O` = `--offline` (küçük `-o` = `--order`), `-j` = `--json`, `-b` = `--breakdown`, `-t` = `--token-limit`, `-n` = `--session-length`, `-a` = `--active`, `-r` = `--recent`, `-z` = `--timezone`, `-m` = `--mode`, `-i` = `--instances` (session'da `--id`!).

---

## 4. Plan ile çelişkiler / doğrulamalar

1. **`daily --json` artık Claude'a özgü değil — plan düzeltilmeli.** `docs/PLAN.md` §6.1 ve §12/4'te geçen `npx ccusage daily --json`, bugün 18 ajanı birleştiren unified rapordur (`main.rs:29`, `parser.rs:400-424`); satırlarda `date` yerine `period`, ek olarak `agent` alanı vardır (`ccusage-adapter-all/src/report.rs:132-171`). **Claude için `ccusage claude daily --json` kullanılmalı** (`{"daily": [...], "totals": {...}}`, `commands/mod.rs:51-56`). `blocks` her iki yazımda da yalnızca Claude verisini okuduğu için `blocks --json` varsayımı geçerli.
2. **`blocks --json` burn rate + projeksiyon içeriyor — doğrulandı.** `blocks.rs:184-232` + `:567-601`. Ancak yalnızca `isActive` bloklarda; diğerlerinde `null`. `docs/PLAN.md` §6.2'nin ihtiyaç listesi ($/saat, "bu hızla ne zaman dolar") karşılanıyor.
3. **`CLAUDE_CONFIG_DIR` çoklu yol destekliyor — doğrulandı, fazlasıyla.** Virgülle ayrılmış liste, `projects/` doğrulaması, `~` genişletme (`paths.rs:12-52`). Plana eklenmesi gereken: değişken set edilmişse **fallback yoktur** (hata), ve değişken yokken `~/.config/claude` **ile** `~/.claude` birlikte taranır — planda yalnızca `~/.claude` yazıyor.
4. **`@ccusage/mcp` artık yok.** Klonun tamamında (`--include=*.md,*.json,*.rs`) `mcp` referansı yok; `packages/` yalnızca 6 platform binary paketi içeriyor. `docs/PLAN.md` §2.1 tablosundaki "`@ccusage/mcp`" ifadesi güncel değil; zaten "araç olarak çağır" kararımızı etkilemiyor.
5. **ccusage TypeScript değil, Rust.** `docs/PLAN.md` §2.1'deki "JSONL → maliyet/blok hesabı" değeri aynen geçerli ama v2'de "hesap mantığını adapte et" işi **Rust → Swift** çevirisi olacak (lisans MIT, sorun yok). Bir avantaj: mantık artık tek bir statik binary'de; kullanıcı Node kurmadan `brew`/`nix` ile ccusage kurabiliyorsa `npx` gecikmesi tamamen ortadan kalkar.
6. **`--mode calculate|display|auto` var — ama her komutta değil.** Yalnızca `claude` alt komutlarında ve `blocks`'ta (`shared_claude_options`); unified komutlarda (`agent_options`/`all_agent_options`) `--mode` **yok**. Bu da `claude` önekini kullanma gerekçemizi güçlendiriyor.
7. **`--offline` var ve bizim için varsayılan olmalı.** `-O, --offline` (`cli-help.json`, `agent_options`/`shared_claude_options`); `statusline`'da varsayılan `true`, diğerlerinde `false`. Planda "offline" ifadesi geçmiyordu; §6.1'e eklenmeli.
8. **Doküman sitesi güvenilmez.** `docs/guide/json-output.md:408-439` blocks şeması eski (bkz. §3.3). `docs/PLAN.md` §13'teki "parser'ı toleranslı yaz" önlemi burada birebir uygulanmalı; kabul kriteri olarak "gerçek çıktı ile karşılaştır" (`docs/PLAN.md` §12/4: önce terminalde tek satır deney) korunmalı.
9. **Node yokluğunda zarif düşüş — kabul kriteri karşılanabilir.** `cli.js:99-109` net bir hata metni veriyor; ayrıca `npx`/`ccusage` hiç yoksa `Process` başlatma hatası alırız. `docs/PLAN.md` §6.3'teki "ccusage/Node yoksa modül zarifçe 'kurulum gerekli' durumuna düşer" kriteri üç ayrı hata sınıfı ile karşılanmalı: binary yok · çalıştırma hatası · JSON decode hatası.

---

## 5. Bilinçli almayacaklarımız

- **18 ajan adaptörü** (`rust/adapters/*`): Codex, Copilot, Gemini, Amp… Bizim modülümüz Claude Code'a özgü (`docs/PLAN.md` §6). Unified komutları hiç çağırmayacağız.
- **Terminal sunum katmanı**: `ccusage-terminal/src/table.rs`, renk/compact mantığı, `print_blocks_table` (`blocks.rs:331-463`). Bizde sunum SwiftUI.
- **`statusline` komutu**: Claude Code'un status line hook'u için; bizim eşdeğerimiz notch'un kendisi. Yine de oturum-bazlı + mtime'lı cache fikri (`commands/mod.rs:326-370`) v2 için ilham.
- **`--jq`**: harici `jq` binary'si gerektiriyor (`output.rs:134-150`).
- **Konfigürasyon dosyası keşfi** (`ccusage-config`, `ccusage.json`, 506 KB'lık `config-schema.json`): bizim ayarlarımız `SettingsStore` + `@AppStorage`.
- **Çalışma anında fiyat çekme** (`http.rs`): `--offline` ile devre dışı; v2'de tabloyu bundle edeceğiz.
- **Codex'e özgü `--speed fast` çarpanları** ve `fast-multiplier-overrides.json`: Claude tarafında karşılığı sınırlı.
- **`--instances` / `--project-aliases` / `--sections` / `--by-agent`**: MVP dashboard'unda yok; "son aktif proje adı" (`docs/PLAN.md` §6.2) `ProjectsWatcher`'dan dosya yolu ile daha ucuza gelir.

---

## 6. Açık sorular

1. **S1 — Çağrı stratejisi ne olacak?** `npx ccusage@latest` (soğuk başlangıç + ağ) vs `npx ccusage@<sabit sürüm>` vs `PATH`'teki `ccusage`. Faz 4'ün ilk işi: üç yolu da ölçmek (`time`), onboarding'de hangisini önereceğimize karar vermek. `docs/PLAN.md` §6.1'deki `@latest` ifadesi ölçüm sonrası güncellenmeli.
2. **S2 — Polling mi, dosya olayı mı?** Plan "30-60 sn'de bir + dosya değişiminde" diyor. Tüm geçmişin her çağrıda okunduğu (§3.10) düşünülürse, saf dosya-olayı + tavan periyot daha doğru olabilir. Ölçüm sonrası netleşir.
3. **S3 — Büyük geçmişte süre nedir?** Kendi `~/.claude/projects` dizinimizde dosya sayısı/boyutu ve `claude blocks --json --offline` süresi ölçülmeli. 1 sn'yi aşıyorsa modülün "yenileniyor" durumu UI'da gösterilmeli.
4. **S4 — `blocks --active` boş çıktı davranışı?** JSON modunda aktif blok yoksa `{"blocks": []}` döner (`commands/mod.rs:278-295`; `active && blocks.is_empty()` dalı yalnızca tablo modunda mesaj basar). UI'nın "aktif blok yok" durumunu bu boş dizi ile ele alması gerekiyor — doğrulanmalı.
5. **S5 — `usageLimitResetTime` resmi endpoint'e iyi bir yedek mi?** JSONL'de yalnızca kullanıcı limite **çarptığında** yazılıyor (`adapters/claude/src/lib.rs:583-615`). Normal akışta gelmez; yani `docs/PLAN.md` §6.1'deki resmi endpoint yolunun yerini tutmaz, sadece "limite çarpıldı" olayını yakalar. Popup senaryosu olarak değerlendirilebilir mi?
6. **S6 — Sürüm sabitleme ve şema kayması nasıl izlenir?** ccusage 20.x içinde JSON şeması değişirse sessizce alanları kaybederiz. `CCUsageRunner` decode'unda "beklenen anahtar yok" durumunu loglayıp modülü "veri okunamadı" durumuna düşüren bir kontrol + `ccusage --version` kaydı tutulmalı mı?
7. **S7 — v2'de artımlı okuma + dedupe nasıl birlikte çalışacak?** (§3.8 Dikkat) Offset tabanlı okuma ile dedupe durumunun kalıcılaştırılması Faz 6'nın tasarım kararı; ccusage bunu hiç çözmüyor (her seferinde baştan okuyor), yani burada kendi yolumuzu çizeceğiz.
