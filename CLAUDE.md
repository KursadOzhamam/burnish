# Proje Spesifikasyonu: Burnish — macOS Bakım ve Optimizasyon Uygulaması

> Bu dosya projenin tek doğruluk kaynağıdır. Claude Code her oturumda bu dosyayı otomatik olarak context'e alır.
> Bir karar bu dosyayla çelişiyorsa önce bana sor. Yaptığın her mimari kararı §14 "Karar Günlüğü"ne, henüz
> karara bağlanmamış her konuyu §15 "Risk Kaydı ve Açık Sorular"a ekle.

**Platform sırası:** Önce macOS sürümü tamamlanır. Mobil (iOS) sürümü ancak macOS sürümü Phase 10'u geçtikten
sonra başlar — ayrıntılar için §12 Platform Stratejisi.

---

## 1. Vizyon

macOS için CleanMyMac sınıfında, hatta onu aşan bir sistem bakım uygulaması geliştiriyoruz. Uygulama şunları tek çatı altında yapmalı: gereksiz dosya temizliği, kötü amaçlı yazılım taraması, performans optimizasyonu, uygulama yönetimi, disk alanı analizi ve gizlilik temizliği.

Farkımız iki noktada olacak:
1. **Arayüz:** Animasyonları, derinliği ve canlı verileriyle kullanması keyifli, "premium" hissettiren bir deneyim.
2. **Güven:** Hiçbir dosya kullanıcının bilgisi dışında kalıcı olarak silinmez. Her işlem önizlenir, geri alınabilir ve kayıt altına alınır.

Görsel kimlik tamamen özgün olmalı. CleanMyMac'in logosu, ikonları, ekran düzeni, renk paleti veya metinleri kopyalanmayacak.

### 1.1 Kimlik Bilgileri

| Konu | Değer |
|---|---|
| Uygulama adı | **Burnish** (karar: 2026-10-12, §17) |
| Pazarlama adı | "Burnish for Mac" — Apple'ın izin verdiği referans biçimi (§16.1) |
| Ana uygulama bundle ID | `com.burnish.app` |
| Privileged helper bundle ID | `com.burnish.app.helper` |
| Menü çubuğu ajanı bundle ID | `com.burnish.app.menubar` |
| Log subsystem | `com.burnish.app` |
| Destek klasörü | `~/Library/Application Support/Burnish/` |
| Ayarlar (UserDefaults suite) | `com.burnish.app` |
| App Group (ileride iOS/companion için) | `group.com.burnish` |

> **Ad kesinleşti (2026-10-12).** Dokuz aday tarandı; "Burnish" yazılım/Mac alanında çakışmasız çıktı.
> Tarama kaydı ve yöntemi: `docs/PHASE0_CHECKLIST.md`. **Hukuki marka araştırması (TÜRKPATENT / USPTO /
> EUIPO, Sınıf 9 ve 42) ve domain kontrolü hâlâ yapılmalı** — kontrol listesindeki süzgecin 3. maddesi.
> Ad kodda hiçbir yere hard-code edilmez: `Info.plist` (`CFBundleName`) ve String Catalog üzerinden gelir,
> böylece olası bir rebrand tek noktadan yapılabilir.

### 1.2 Geliştirme ortamı taban çizgisi (2026-10-12 tespiti)

| Konu | Durum |
|---|---|
| Xcode | 26.5 (build 17F42) ✓ |
| Swift | 6.3.2 ✓ |
| Geliştirme Mac'i | macOS 27.0.1 ✓ |
| Mevcut SDK | macOS 26.5 (deployment target macOS 14 geriye dağıtımla desteklenir) ✓ |
| Homebrew | kurulu ✓ |
| SwiftLint | **kurulu değil** → `brew install swiftlint` |
| Kod imzalama kimliği | Yalnızca *Apple Development*. **Developer ID Application sertifikası yok** |
| Apple Developer Program | Doğrulanmadı. Mevcut kimlikler `k1453o@icloud.com` hesabına bağlı |

**Sonuç:** Phase 1–10 geliştirmesi için engel yok (yerel çalıştırma Apple Development ile mümkün).
Phase 0'ın imza/notarizasyon maddeleri (**R8 dahil**) Developer ID sertifikası alınana kadar bekler.
Geliştirme ortamı macOS 27 olduğu için macOS 14 uyumluluğu yalnızca derleyici hedefiyle garanti edilemez —
§16.2/R11 uyarınca gerçek macOS 14 doğrulaması gerekir.

---

## 2. Teknik Temel

| Konu | Karar |
|---|---|
| Dil | Swift 6 (strict concurrency açık) |
| Arayüz | SwiftUI; gerektiğinde AppKit köprüsü (`NSViewRepresentable`) |
| Minimum sürüm | macOS 14 Sonoma |
| Mimari | MVVM + Feature modülleri, `@Observable` makrosu |
| Eşzamanlılık | async/await, `actor`, `TaskGroup`; ana thread asla bloklanmaz |
| Grafikler | Swift Charts; özel çizimler Canvas/`TimelineView` |
| Proje yönetimi | Xcode projesi + yerel Swift Package'lar (modüller ayrı paket) |
| Kalıcı veri | SQLite üzerinde **GRDB** (gerekçe Karar Günlüğü'nde) |
| Ayrıcalıklı işlemler | `SMAppService.daemon(plistName:)` ile kurulan Privileged Helper + XPC |
| Kötü amaçlı yazılım | **YARA** (BSD-3-Clause) + kendi hash blocklist'imiz. ClamAV **kullanılmaz** (§6.4) |
| Güncelleme | Sparkle 2 (EdDSA imzalı appcast) |
| Dağıtım | App Store dışı; Developer ID imzası + notarizasyon. Sandbox kapalı, Hardened Runtime açık |
| Ödeme | **Paddle** (Merchant of Record) — vergi yükümlülüğü sağlayıcıda (§11.1) |
| Lisanslama | Çevrimdışı doğrulanabilir Ed25519 imzalı lisans dosyası (§11.2) |
| CI | **GitHub Actions** (macOS runner); imzalı derleme yalnızca `v*` etiketinde (§13.1) |
| İmza DB barındırma | **Cloudflare R2 + CDN** (§13.3) |
| Test | Swift Testing (`@Test`), kritik akışlar için XCUITest |
| Loglama | `os.Logger` (subsystem: bundle ID, kategori: modül adı) |
| Telemetri | Üçüncü parti analytics SDK'sı **yok**. Opt-in, kendi barındırdığımız minimal çökme raporu (§13.4) |

Harici bağımlılıkları minimumda tut. Yeni bir paket eklemeden önce gerekçesini Karar Günlüğü'ne yaz.
Onaylı bağımlılık listesi: **Sparkle 2**, **GRDB**, **YARA**. Bunların dışındaki her ekleme ayrı onay gerektirir.

---

## 3. Proje Yapısı

```
Burnish/
├── App/                      # Giriş noktası, pencere, menü çubuğu, ayarlar
├── Packages/
│   ├── DesignSystem/         # [cross-platform] Renkler, tipografi, boşluklar, animasyonlar, ortak bileşenler
│   ├── CoreKit/              # [cross-platform] Boyut hesaplama, model tipleri, loglama, yardımcılar
│   ├── CoreKitMac/           # [macOS] Dosya sistemi gezinmesi, izin kontrolü, sistem yolları
│   ├── SafetyKit/            # [cross-platform çekirdek] Politika motoru, karar modelleri, işlem kaydı
│   ├── SafetyKitMac/         # [macOS] Korunan yollar, trashItem, karantina, geri alma
│   ├── ScanEngine/           # [cross-platform] Tarayıcı protokolü, orkestrasyon, sonuç modelleri
│   ├── SystemMonitor/        # [macOS] CPU, RAM, disk, pil, ağ, sıcaklık okumaları
│   ├── Licensing/            # [cross-platform] Lisans doğrulama, deneme süresi, Pro kapıları
│   ├── HelperProtocol/       # [macOS] Helper ile paylaşılan XPC protokolü
│   └── Features/             # [macOS]
│       ├── Dashboard/
│       ├── SmartScan/
│       ├── Cleanup/
│       ├── Protection/
│       ├── Performance/
│       ├── Applications/
│       ├── Files/            # Space Lens, büyük/eski dosyalar, kopyalar, parçalayıcı
│       └── Privacy/
├── PrivilegedHelper/         # Ayrı hedef, root yetkili XPC servisi
├── MenuBarAgent/             # Menü çubuğu mini paneli
└── Tests/
```

Her Feature modülü kendi View, ViewModel ve Scanner/Service dosyalarını içerir. Modüller birbirini doğrudan import etmez; ortak ihtiyaçlar CoreKit veya ScanEngine üzerinden karşılanır.

**Platform disiplini (iOS sürümünü mümkün kılan kural):** `[cross-platform]` işaretli paketler
`Package.swift` içinde hem macOS hem iOS platformu bildirir ve macOS'a özgü API kullanmaz. Platforma özgü
ihtiyaçlar `*Mac` kardeş paketine veya protokol arkasına konur — `#if os(macOS)` bir kaçış yolu değil, son
çaredir. Bu kural Phase 1'den itibaren geçerlidir; sonradan ayrıştırma pahalıdır.

---

## 4. Güvenlik Kuralları (en yüksek öncelik — asla esnetilmez)

Bu bölüm uygulamanın en önemli kısmıdır. Tüm silme işlemleri `SafetyKit` içindeki tek bir `DeletionService` üzerinden geçer; başka hiçbir kod doğrudan `FileManager.removeItem` çağırmaz.

1. **Varsayılan davranış Çöp Kutusu'na taşımaktır** (`FileManager.trashItem`). Kalıcı silme yalnızca kullanıcının açıkça seçtiği durumlarda (Parçalayıcı, Çöp'ü boşaltma) ve ek onayla yapılır.
2. **İzin listesi yaklaşımı:** Her tarayıcı yalnızca kendi tanımlı klasörlerinde çalışır. Tanımlı kökün dışına çıkan hiçbir yol silinemez.
3. **Korunan yollar listesi** (hiçbir koşulda dokunulmaz):
   - Sistem: `/System`, `/usr` (`/usr/local` hariç), `/bin`, `/sbin`, `/private/var/db`, `/Library/Apple`,
     `/Library/Developer/CommandLineTools`
   - Kullanıcı verisi: `Documents`, `Desktop`, `Pictures`, `Movies`, `Music` klasörlerinin **kendisi**;
     `~/Library/Mobile Documents` (iCloud Drive), `*.photoslibrary` paketleri
   - Kimlik ve güvenlik: `~/Library/Keychains`, `/Library/Keychains`, `.ssh`, `.gnupg`,
     `/Library/Application Support/com.apple.TCC`, FileVault kurtarma anahtarı dosyaları
   - Posta verisi: `~/Library/Mail` ve `~/Library/Containers/com.apple.mail` içindeki `V*` posta veritabanı
     (yalnızca indirilen ekler klasörü temizlenebilir — §6.3)
   - Yedek ve anlık görüntü: aktif Time Machine yedekleri, mount edilmiş yedek birimleri
   - Çalışma zamanı: `/private/var/folders` (aktif geçici alan), **çalışan** uygulamaların
     `~/Library/Containers/<bundleID>` klasörleri
   - İndeks: harici disklerdeki `.Spotlight-V100` (yeniden indeksleme maliyeti kullanıcıya aittir, sessizce silinmez)
   - Burnish'ın kendi veri klasörü (yalnızca §6.9'daki açık "tamamen kaldır" eylemiyle silinir)
4. **Sembolik bağlantılar takip edilmez.** Silmeden önce yol `resolvingSymlinksInPath` ile çözülür ve tekrar izin listesine karşı kontrol edilir. Hard link'ler ve firmlink'ler de aynı kontrole tabidir.
5. **Çalışan uygulamalara ait dosyalar** silinmez; ilgili uygulama açıksa kullanıcı uyarılır ve öğe atlanır.
6. **Kuru çalıştırma (dry-run):** Her temizlik önce "ne silinecek" listesini üretir, kullanıcı onaylamadan hiçbir şey değişmez.
7. **İşlem kaydı:** Her silme işlemi zaman, yol, boyut ve işlem tipiyle `~/Library/Application Support/Burnish/history.sqlite` içine yazılır. Geçmiş ekranından görüntülenebilir; Çöp'e taşınanlar geri yüklenebilir.
8. **Hata toleransı:** Tek bir dosyada hata olursa işlem durmaz; hata kaydedilir ve sonuç ekranında listelenir.
9. `SafetyKit` için birim test kapsamı en az %90 olmalı. Korunan yolların her biri için "silinemez" testi yazılır.
10. **Helper de aynı kurallara tabidir.** Root yetkisiyle çalışan kod, `SafetyKit` politikasını kendi içinde tekrar uygular; ana uygulamanın gönderdiği yola güvenmez.

---

## 5. Tasarım Sistemi

### 5.1 Genel his
- Koyu tema öncelikli, açık tema da tam destekli.
- Arka planlar buzlu cam (`.ultraThinMaterial` / `.regularMaterial`), katmanlı derinlik, yumuşak gölgeler.
- Pencere: kenar çubuklu `NavigationSplitView`, şeffaf başlık çubuğu, tam boyutlu içerik.
- Boşluklar cömert, yoğun tablo görünümünden kaçın; bilgi kartlarla sunulur.

### 5.2 macOS sürümleri arası görünüm kararı
Burnish **kendi özgün görsel kimliğini** macOS 14'ten en güncel sürüme kadar aynı şekilde korur. Yeni
macOS sürümlerinin tasarım dili (ör. macOS 26 Tahoe'nun materyal davranışı) sistem kontrollerini
etkilediğinde, uygulamanın kendi bileşenleri değişmez; yalnızca **sistem tarafından çizilen** öğeler
(pencere kromu, standart kontroller, menüler) platformun doğal halinde bırakılır. Amaç: markanın her
sürümde tutarlı görünmesi, ama sistemle kavga etmemesi.

Pratik kurallar:
- Kendi bileşenlerimiz (`GlassCard`, `GradientRing` vb.) sistem materyali davranışına bağımlı olmayacak
  şekilde yazılır; materyal yalnızca arka plan katmanı olarak kullanılır.
- Sürüme özgü API'ler `if #available` ile ilerici geliştirme (progressive enhancement) olarak eklenir,
  asla zorunlu olmaz.
- Her yeni macOS major sürümünde görsel regresyon kontrolü yapılır ve bulgular §15'e yazılır.

### 5.3 Token'lar (`DesignSystem` paketinde)
- **Renk:** Her bölümün kendine ait gradyanı var. Örnek başlangıç paleti (özgün, değiştirilebilir):
  - Genel Bakış: çivit → mor
  - Temizlik: turkuaz → yeşil
  - Koruma: kırmızı-pembe → turuncu
  - Hız: amber → sarı
  - Uygulamalar: mavi → camgöbeği
  - Dosyalar: mor → pembe
  - Gizlilik: lacivert → mavi
- **Tipografi:** SF Pro; büyük sayılar için `.rounded` tasarım ve `monospacedDigit()`.
- **Köşe yarıçapı:** 8 / 14 / 22 / 32.
- **Boşluk ölçeği:** 4, 8, 12, 16, 24, 32, 48.
- **Animasyon:** `Motion.snappy`, `Motion.smooth`, `Motion.bouncy` adlı hazır spring tanımları; süreler tek yerden yönetilir.
- **Erişilebilirlik:** "Hareketi Azalt" açıksa tüm dekoratif animasyonlar sadeleşir; kontrast oranları WCAG AA'yı sağlar; tüm etkileşimli öğelerin VoiceOver etiketi vardır.

### 5.4 Ortak bileşenler
- `GlassCard`: buzlu cam kart, hover'da %2 büyüme ve gölge artışı.
- `GradientRing`: animasyonlu ilerleme halkası (disk doluluğu, tarama ilerlemesi).
- `AnimatedCounter`: sayıyı yumuşakça artıran/azaltan metin (`contentTransition(.numericText())`).
- `MetricTile`: ikon + başlık + değer + mini grafik.
- `SectionHeader`: bölüm gradyanlı başlık ve açıklama.
- `ScanButton`: büyük, nefes alan (hafif pulse) birincil eylem düğmesi.
- `ResultRow`: onay kutusu, ikon, ad, yol, boyut; genişletilebilir alt öğeler.
- `ConfirmationSheet`: silinecek toplam boyut, öğe sayısı ve "Çöp'e taşı / kalıcı sil" seçimi.
- `EmptyState` ve `PermissionPrompt` görünümleri.
- `ProGate`: Pro özelliklerinde gösterilen, baskı kurmayan yükseltme kartı (§11.3).

### 5.5 Animasyon ilkeleri
- **Tarama ekranı** uygulamanın imza anıdır: dönen gradyan halka, arka planda yavaşça akan parçacıklar (Canvas + TimelineView), anlık olarak taranan klasör adı, artan "bulunan alan" sayacı.
- Tarama bitince sonuç kartları sırayla (stagger, 60 ms aralık) yaylı animasyonla belirir.
- Kart → detay geçişi `matchedGeometryEffect` ile yapılır.
- Temizlik tamamlanınca kısa bir kutlama animasyonu ve kazanılan alanın büyük gösterimi.
- SF Symbols için `symbolEffect` (bounce, pulse, variableColor) kullanılır.
- Animasyonlar 60 fps'te kalmalı; ağır çizimler `drawingGroup()` ile optimize edilir.

---

## 6. Ekranlar ve Özellikler

Her özellik için: tarayıcı, sonuç modeli, arayüz, testler. Tüm tarayıcılar `ScanEngine` içindeki ortak protokolü uygular:

```swift
protocol Scanner: Sendable {
    var id: ScannerID { get }
    var title: LocalizedStringResource { get }
    var requiresFullDiskAccess: Bool { get }
    var weight: ScannerWeight { get }   // .light → Akıllı Tarama'ya dahil, .heavy → ayrı başlatılır
    func scan(progress: @Sendable (ScanProgress) -> Void) async throws -> [ScanItem]
}
```

### 6.1 Genel Bakış (Dashboard)
- Üstte büyük karşılama alanı: Mac modeli, macOS sürümü, son tarama zamanı, genel "sağlık skoru" (0–100, animasyonlu halka).
- Bilgi kartları ızgarası (uyarlanabilir sütun sayısı):
  - Disk: kullanılan / boş / temizlenebilir (purgeable dahil), halka grafik.
  - Bellek: kullanılan, sıkıştırılmış, swap; canlı çizgi grafik (son 60 sn).
  - CPU: toplam ve çekirdek bazında yük; canlı grafik.
  - Pil: şarj, sağlık, döngü sayısı (IOKit `AppleSmartBattery`).
  - Ağ: anlık indirme/yükleme hızı.
  - Koruma durumu: son tehdit taraması ve sonucu.
- "Akıllı Tarama" birincil düğmesi.
- Öneri kartları: "Xcode artıkları 14 GB yer kaplıyor", "3 uygulamanın güncellemesi var" gibi bağlama duyarlı öneriler.

**Sağlık skoru dürüstlüğü:** Skor, ölçülebilir ve kullanıcıya açıklanabilir girdilerden hesaplanır
(boş disk yüzdesi, bellek baskısı, bulunan tehdit sayısı, bekleyen güncellemeler, temizlenebilir alan).
Formül arayüzde "nasıl hesaplandı?" bağlantısıyla gösterilir. Yeni kurulumda skoru yapay olarak düşük
göstermek yasaktır (§10).

### 6.2 Akıllı Tarama
- `weight == .light` olan Temizlik, Koruma ve Hız tarayıcılarını paralel çalıştırır (`TaskGroup`).
- Sonuçta üç özet kart: temizlenebilir alan, bulunan tehditler, hız önerileri.
- Tek tıkla "Hepsini Çalıştır" veya kart bazında detaya inme.
- Ağır tarayıcılar (kopya bulucu, benzer fotoğraflar, Space Lens tam tarama) Akıllı Tarama'ya **dahil
  edilmez**; sonuç ekranında "ayrıca şunları da tarayabilirsin" önerisi olarak sunulur.

### 6.3 Temizlik
Tarayıcılar (her biri ayrı ve ayarlardan açılıp kapatılabilir):
- Kullanıcı önbellekleri: `~/Library/Caches` (Apple'ın kritik önbellekleri hariç tutulur).
- Sistem önbellekleri ve loglar: `/Library/Caches`, `/Library/Logs`, `~/Library/Logs` (sistem yolları helper üzerinden).
- Dil dosyaları: uygulama paketlerindeki kullanılmayan `.lproj` klasörleri. **Varsayılan kapalı**, imzalı uygulamalarda imzayı bozma riski açıkça belirtilir; Apple uygulamalarına asla dokunulmaz.
- Geliştirici artıkları: Xcode `DerivedData`, `Archives`, `iOS DeviceSupport`, eski simülatörler (`xcrun simctl delete unavailable`), CocoaPods/Carthage/SPM önbellekleri, `node_modules` bulucu (yalnızca listeler, kullanıcı seçer), Homebrew önbelleği.
- Tarayıcı önbellekleri: Safari, Chrome, Firefox, Edge, Brave, Arc (tarayıcı açıksa atlanır).
- Mail ekleri indirme klasörü (posta veritabanının kendisine dokunulmaz — §4.3).
- iOS/iPadOS yedekleri ve yazılım güncelleme dosyaları (`.ipsw`).
- Bozuk tercih dosyaları (okunamayan `.plist`'ler).
- Çöp kutuları: kullanıcı Çöp'ü, harici disklerin `.Trashes` klasörleri, uygulamaların kendi çöpleri (Fotoğraflar, Mail).
- Time Machine yerel anlık görüntüleri: `tmutil listlocalsnapshots` ile listeleme, onayla silme.

Arayüz: kategori kartları → öğe listesi → onay sayfası → ilerleme → sonuç.

### 6.4 Koruma

> **Konumlandırma — arayüzde ve pazarlamada açıkça yazılır:** Burnish **talep üzerine çalışan (on-demand)
> bir tarayıcıdır**, gerçek zamanlı antivirüs değildir. Gerçek zamanlı dosya izleme Apple'ın Endpoint
> Security framework'ünü ve özel başvuruyla alınan `com.apple.developer.endpoint-security.client`
> entitlement'ını gerektirir; bu bizde yoktur. Kullanıcıya "antivirüs" izlenimi veren hiçbir metin
> kullanılmaz; Burnish macOS'un kendi savunmasını (XProtect, Gatekeeper, notarizasyon) **tamamlar**.

- **Kötü amaçlı yazılım taraması:**
  - **İmza motoru: YARA** (BSD-3-Clause). Kendi kural setimiz + lisansı ticari kullanıma uygun olduğu
    tek tek doğrulanmış topluluk kuralları. Her kural kaynağının lisansı `THIRD_PARTY_LICENSES.md`
    dosyasında kayıtlıdır.
  - **ClamAV kullanılmaz.** Gerekçe: ClamAV GPL-2.0 lisanslıdır; kapalı kaynak ticari bir uygulamaya
    bağlanması veya birlikte dağıtılması tüm uygulamayı GPL'e tabi kılar. İmza veritabanı (CVD) de ayrı
    kısıtlara tabidir. Bu karar Karar Günlüğü'nde kayıtlıdır ve yeniden açılmayacaktır.
  - **Hash blocklist'i:** Bilinen zararlı dosyaların SHA-256 listesi; kendi sunucumuzdan imzalı olarak
    güncellenir (güncelleme kanalı Sparkle'dan ayrıdır).
  - **Kalıcılık noktaları analizi:** `LaunchAgents`, `LaunchDaemons`, oturum öğeleri, tarayıcı uzantıları,
    konfigürasyon profilleri.
  - **Apple savunma durumu kontrolü:** Kod imzası doğrulama (`SecStaticCodeCheckValidity`), notarizasyon
    durumu, `com.apple.quarantine` özniteliği, Gatekeeper ve XProtect sürüm bilgisi.
  - Şüpheli bulgular silinmez; karantina klasörüne taşınır ve geri alınabilir.
  - **Yanlış pozitif politikası:** Her bulgu için "neden işaretlendi" açıklaması ve "bu güvenli, bir daha
    sorma" seçeneği bulunur.
- **Gizlilik:** Tarayıcı geçmişi, çerezler, form verileri, son kullanılan öğeler listeleri, Wi-Fi ağ geçmişi (helper ile). Her tarayıcı ayrı seçilebilir; tarayıcı açıksa işlem yapılmaz.
- **Uygulama izinleri görünümü:** Kamera, mikrofon, ekran kaydı, tam disk erişimi gibi izinlere sahip uygulamaları listeler (okunabildiği ölçüde) ve kullanıcıyı ilgili Sistem Ayarları paneline yönlendirir. TCC veritabanına **yazma yapılmaz**.

### 6.5 Hız
- **Bakım görevleri:** DNS önbelleğini temizleme, Spotlight'ı yeniden indeksleme, Launch Services veritabanını yeniden kurma, disk izinlerini doğrulama (`diskutil verifyVolume`), RAM'i boşaltma (`purge`, helper ile), periyodik bakım betikleri. Her görevin ne yaptığı sade dille açıklanır.
- **Başlangıç öğeleri:** Oturum öğeleri ve arka plan ajanlarını listeleme; kullanıcıya ait ajanları devre dışı bırakma (plist'i yeniden adlandırarak değil, `launchctl` ile ve geri alınabilir şekilde).
- **Yoğun kaynak tüketenler:** CPU ve RAM'i en çok kullanan süreçler; seçilen uygulamayı kapatma (sistem süreçleri hariç).
- **Bellek izleme:** Bellek baskısı yüksek olduğunda bildirim (ayarlanabilir).

> **Dürüstlük notu:** "RAM boşaltma" ve benzeri görevlerin ölçülebilir faydası sınırlıdır ve macOS bellek
> yönetimini zaten kendi yapar. Arayüzde bu görevler "hızlandırma" olarak değil, ne yaptıkları olduğu gibi
> anlatılır. Ölçülemeyen performans iddiası yapılmaz (§10).

### 6.6 Uygulamalar
- **Kaldırıcı:** `/Applications` ve `~/Applications` taraması; her uygulama için bundle ID ile ilişkili artıkların bulunması (`Application Support`, `Caches`, `Preferences`, `Containers`, `Group Containers`, `Saved Application State`, `LaunchAgents`, `HTTPStorages`, `WebKit`). Kullanıcı tek tek seçebilir.
- **Artık dosyalar:** Silinmiş uygulamalardan kalan dosyaları bulma (bundle ID'si yüklü hiçbir uygulamayla eşleşmeyen klasörler; düşük güvenli eşleşmeler varsayılan olarak seçilmez).
- **Sıfırlama:** Uygulamayı silmeden ayarlarını ve önbelleğini temizleme.
- **Güncelleyici:** Sparkle akışı olan uygulamaların güncel sürümlerini kontrol etme ve App Store uygulamaları için Mac App Store'a yönlendirme. Güncellemeyi uygulamanın kendisine bırakır.
- **Uzantılar:** Safari uzantıları, tercih panelleri, QuickLook eklentileri, giriş öğeleri listesi.
- Uygulama ızgarası: ikon, ad, boyut, son kullanım tarihi; sıralama ve filtreleme.

### 6.7 Dosyalar
- **Space Lens (alan haritası):** Seçilen birimin interaktif sunburst grafiği (Canvas ile özel çizim). Dilime tıklayınca içine animasyonla zoom; üstte gezinti yolu (breadcrumb). Boyutlar `totalFileAllocatedSizeKey` ile hesaplanır, sert bağlantılar bir kez sayılır, APFS klonları için not düşülür. `weight: .heavy`
- **Büyük ve eski dosyalar:** Boyut ve son erişim tarihine göre filtreleme; tür bazında gruplama.
- **Kopya bulucu:** Boyuta göre grupla → ilk/son 64 KB karşılaştırması → tam hash (SHA-256 veya xxHash). Hangi kopyanın tutulacağını otomatik öneren kurallar (en eski, en kısa yol vb.). `weight: .heavy`
- **Benzer fotoğraflar:** Vision framework `VNFeaturePrintObservation` ile benzerlik; seri çekimleri gruplama. Fotoğraflar kütüphanesine doğrudan yazma yok; yalnızca listeleme ve Fotoğraflar'da gösterme. `weight: .heavy`
- **Parçalayıcı:** Kalıcı silme. SSD'lerde ve APFS üzerinde (kopyala-yaz, wear leveling, TRIM nedeniyle) güvenli üzerine yazmanın **garanti edilemeyeceği** arayüzde dürüstçe belirtilir; gerçek güvenlik için FileVault önerilir.

### 6.8 Menü Çubuğu Paneli
- `MenuBarExtra` (window stili) ile açılan mini panel: CPU, RAM, disk, ağ, pil özetleri; hızlı eylemler (RAM boşalt, Çöp'ü boşalt, tarama başlat).
- Ayarlardan açılıp kapatılabilir; giriş öğesi olarak `SMAppService.mainApp` ile kaydedilir.

### 6.9 Ayarlar
- Genel: başlangıçta açıl, menü çubuğu, dil (Türkçe ve İngilizce, String Catalog ile).
- Tarama: tarayıcıları aç/kapat, hariç tutulan klasörler listesi, büyük dosya eşiği.
- Silme: varsayılan davranış (Çöp / kalıcı), onay seviyesi.
- Zamanlanmış tarama ve bildirimler.
- İşlem geçmişi ve geri yükleme.
- İzinler: tam disk erişimi ve helper durumu, yeniden yükleme düğmeleri.
- Lisans: lisans anahtarı girişi/durumu, cihaz yönetimi, deneme süresi durumu (§11).
- Gizlilik: çökme raporu gönderimi (varsayılan **kapalı**), imza veritabanı güncelleme kanalı.
- **Burnish'ı tamamen kaldır:** Tek eylemle (a) privileged helper'ı `SMAppService.unregister` ile söker,
  (b) menü çubuğu giriş öğesini kaldırır, (c) `~/Library/Application Support/Burnish/`, Preferences ve
  Caches artıklarını temizler, (d) uygulamayı Çöp'e taşımayı önerir. İşlem öncesi ne silineceğini listeler.
  **Bir temizlik uygulaması kendi arkasında artık bırakmaz.**

---

## 7. İzinler ve Ayrıcalıklı İşlemler

- **Tam Disk Erişimi:** Açılışta kontrol edilir (korumalı bir yolun okunabilirliği denenerek). Yoksa adım adım rehber ekranı gösterilir ve `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` ile ilgili panel açılır. İzin olmadan da uygulama çalışır, etkilenen tarayıcılar "izin gerekli" olarak işaretlenir.
- **Privileged Helper:** `SMAppService.daemon(plistName:)` ile kurulur (eski `SMJobBless` kullanılmaz). Launchd plist'i `Contents/Library/LaunchDaemons/` içinde, helper binary'si `Contents/MacOS/` içinde bulunur ve ana uygulamayla aynı Developer ID ile ayrı ayrı imzalanır. XPC bağlantısında istemcinin kod imzası `audit_token` üzerinden doğrulanır (yalnızca kendi uygulamamız bağlanabilir). Helper'ın yapabileceği işlemler küçük, açıkça tanımlı bir komut kümesiyle sınırlıdır (ör. `purge`, DNS temizleme, belirli sistem klasörlerinde silme). Helper asla rastgele kabuk komutu çalıştırmaz ve kendi içinde de `SafetyKit` kurallarını uygular (§4.10).
- **Bildirimler:** `UNUserNotificationCenter`, ilk ihtiyaç anında izin istenir.
- **Fotoğraflar:** Benzer fotoğraf taraması için `PHPhotoLibrary` okuma izni, yalnızca o özellik ilk kez kullanıldığında istenir.

---

## 8. Performans Hedefleri

- Uygulama açılışı: 1 saniyenin altında ilk kare.
- **Akıllı Tarama (yalnızca `.light` tarayıcılar):** tipik bir Mac'te 60 saniyenin altında.
- **Ağır tarayıcılar** (`.heavy`: kopya bulucu, benzer fotoğraflar, Space Lens tam tarama) için süre hedefi
  yoktur; bunun yerine zorunlu gereksinimler: canlı ilerleme yüzdesi, kalan süre tahmini, her an iptal
  edilebilirlik, kısmi sonuçların gösterilmesi ve uygulama kapanıp açıldığında kaldığı yerden devam
  (ya da en azından sonucun önbelleklenmesi).
- Dosya taraması `FileManager.enumerator` ve `URLResourceValues` önceden istenmiş anahtarlarla yapılır; büyük ağaçlar paralel taranır.
- Tarama sırasında arayüz akıcı kalır; ilerleme güncellemeleri saniyede en fazla 20 kez yayınlanır.
- Canlı sistem metrikleri 1 saniye aralıkla okunur ve yalnızca ilgili görünüm ekrandayken çalışır.
- Bellek kullanımı boşta 150 MB'ın altında; ağır tarama sırasında 1 GB'ın altında (hash tamponları akış halinde okunur, dosya belleğe tümüyle alınmaz).
- Tarama iptal edilebilir olmalı (`Task.checkCancellation()`).
- Enerji: ağır taramalar pil modunda kullanıcıyı uyarır; zamanlanmış taramalar pil düşükken ertelenir.

---

## 9. Test Stratejisi

- `SafetyKit`: korunan yollar, symlink kaçışları, izin listesi dışı yollar, çalışan uygulama dosyaları için kapsamlı testler.
- Her tarayıcı geçici bir sahte dosya ağacı (`FileManager.temporaryDirectory`) üzerinde test edilir; gerçek sistem klasörlerine testlerde dokunulmaz.
- Kopya bulucu ve boyut hesaplama için doğruluk testleri (sert bağlantılar, boş dosyalar, izinsiz klasörler, APFS klonları).
- ViewModel'ler için durum geçişi testleri (boşta → taranıyor → sonuç → temizleniyor → tamamlandı / hata).
- `Licensing`: geçerli/geçersiz/süresi geçmiş imza, saat ileri alma, bozuk lisans dosyası testleri.
- Kritik akışlar için UI testleri: Akıllı Tarama, temizlik onayı, uygulama kaldırma.
- SwiftUI önizlemeleri (`#Preview`) sahte verilerle her ekran ve bileşen için tanımlanır.

---

## 10. Yapmayacaklarımız (yazılı taahhüt)

Bu bölüm §4 kadar bağlayıcıdır. Burnish'ın "güven" farkı buradan gelir.

1. **Kernel extension veya Endpoint Security iddiası yok.** Gerçek zamanlı koruma sunmuyoruz, sunduğumuzu ima etmiyoruz.
2. **TCC veritabanına yazma yok.** İzinler yalnızca okunur ve kullanıcı Sistem Ayarları'na yönlendirilir.
3. **Korku pazarlaması yok.** "Mac'iniz tehlikede", "N sorun bulundu!" gibi abartı yok; kırmızı uyarı rengi yalnızca gerçek tehdit bulgularında kullanılır.
4. **Bulgu sayısı veya kazanılacak alan şişirilmez.** Temizlenebilir alan gerçek, doğrulanabilir bayt sayısıdır; purgeable alan ayrı etiketlenir ve "kazanç" olarak sayılmaz.
5. **Ölçülemeyen performans iddiası yok.** "%300 daha hızlı" türü ifadeler kullanılmaz.
6. **Karanlık arayüz deseni yok.** İptal düğmesi gizlenmez, abonelik yenilemesi sürpriz olmaz, deneme süresi bitince kullanıcı verisi rehin alınmaz.
7. **Kullanıcı verisi dışarı çıkmaz.** Dosya adları, yollar, dizin yapısı, disk içeriği hiçbir koşulda sunucuya gönderilmez. Üçüncü parti analytics SDK'sı kullanılmaz.
8. **Rastgele kabuk komutu çalıştırılmaz** — özellikle helper içinde. Her ayrıcalıklı işlem adı belli, parametreleri doğrulanmış bir komuttur.
9. **Başka ürünlerin varlıkları kopyalanmaz** — ikon, metin, düzen, palet dahil.
10. **Otomatik silme yok.** Hiçbir ayar, kullanıcı onayı olmadan dosya silen bir otomasyon açmaz; zamanlanmış tarama yalnızca *tarar* ve rapor eder.

---

## 11. Lisanslama ve Para Kazanma

App Store dışı dağıtım seçildiği için ödeme, lisans ve vergi tamamen bizim sorumluluğumuzdadır. Bu bölüm
mimariyi etkiler ve Phase 0'da kararlaştırılır, Phase 10'da uygulanır. `Licensing` paketi Phase 1'den
itibaren var olur ve başlangıçta her şeyi "Pro" döndürecek sahte bir uygulamayla çalışır — böylece Pro
kapıları baştan doğru yerlere konur.

### 11.1 Ödeme sağlayıcısı — **Paddle** (karar verildi)
**Merchant of Record (MoR) modeli.** Gerekçe: KDV/satış vergisi yükümlülüğünü sağlayıcı üstlenir;
Türkiye'den global dijital satışta bu en büyük operasyonel yükü kaldırır. Paddle masaüstü yazılım
satışında olgun, lisans anahtarı üretimi ve iade/fatura akışları hazır geliyor.

Stripe daha düşük komisyonlu ama satış vergisi beyanı bize kalır — tek kişilik bir ekip için kabul
edilemez bir yük. Lemon Squeezy de MoR'dur ancak Stripe tarafından satın alındı ve Stripe Billing'e
taşınıyor; bağımsız MoR olarak sürekliliği belirsiz. **Hesap açmadan önce bu durumu güncel olarak
doğrula** (Phase 0 kontrol listesi).

Entegrasyon ilkesi: Paddle yalnızca **satış ve lisans anahtarı üretimi** için kullanılır. Uygulama
içinde Paddle SDK'sı bulunmaz, uygulama çalışma zamanında Paddle'a bağlanmaz — satın alma tarayıcıda
gerçekleşir, kullanıcı e-posta ile aldığı anahtarı uygulamaya girer. Böylece sağlayıcı değişirse
uygulama kodu etkilenmez ve §10.7 (veri dışarı çıkmaz) korunur.

### 11.2 Lisans doğrulama (çevrimdışı çalışmalı)
- Satın alma sonrası kullanıcıya **Ed25519 ile imzalanmış lisans dosyası / anahtarı** verilir. İçerik:
  lisans ID'si, e-posta, ürün, sürüm üst sınırı, cihaz limiti, düzenleme tarihi.
- Doğrulama **tamamen yerel ve çevrimdışıdır**; açık anahtar uygulamada gömülüdür. Uygulama lisans
  kontrolü için internete çıkmaz.
- Cihaz aktivasyonu (limit takibi) için **isteğe bağlı** çevrimiçi kayıt; başarısız olursa uygulama
  çalışmaya devam eder. İnternet yokken Burnish asla kilitlenmez.
- Saat geri/ileri alma testleri yazılır; saat manipülasyonu uygulamayı bozmaz, en kötü halde deneme
  süresi dürüst davranan kullanıcı lehine yorumlanır.

### 11.3 Ücretsiz / Pro ayrımı
İlke: **güvenlik ve şeffaflık asla ücretli değildir.** Ücretsiz sürüm gerçek, kullanışlı bir araç olmalı —
sakatlanmış bir demo değil.

| Ücretsiz | Pro |
|---|---|
| Genel Bakış ve tüm canlı sistem metrikleri | Akıllı Tarama orkestrasyonu |
| Menü çubuğu paneli | Ağır tarayıcılar: kopya bulucu, benzer fotoğraflar, Space Lens |
| Temel temizlik (kullanıcı önbellekleri, çöp kutuları, geliştirici artıkları) | Uygulama kaldırıcı ve artık bulucu |
| Kötü amaçlı yazılım **taraması** ve bulgu raporu | Karantina yönetimi ve toplu işlem |
| Tüm güvenlik özellikleri: dry-run, geçmiş, geri alma, "tamamen kaldır" | Hız bakım görevleri, başlangıç öğeleri |
| | Zamanlanmış tarama, gizlilik temizliği |

- **Deneme:** 14 gün, tüm Pro özellikleri açık, kredi kartı istenmez. Deneme bitince bulunan sonuçlar
  görünmeye devam eder; yalnızca Pro eylemleri kapanır (kullanıcı verisi rehin alınmaz — §10.6).
- **Fiyat modeli (karar verildi): 1 yıl güncelleme içeren tek seferlik lisans.** Yıl sonunda uygulama
  çalışmaya devam eder ve o ana kadarki tüm Pro özellikleri açık kalır; yalnızca yeni sürüm güncellemeleri
  durur. Devam etmek isteyen kullanıcı indirimli yenileme alır. Abonelik modeli seçilmedi — §10.6
  (karanlık desen yok) ve abonelik yorgunluğu nedeniyle.
- **Fiyat (geçici, lansmandan önce gözden geçirilecek):** 1 Mac için **49 USD**, 3 Mac için **79 USD**;
  yenileme %50 indirimli; lansmanda ilk dönem için %30 indirim. Para birimi USD (Paddle yerel para
  dönüşümünü kendisi yapar). Bu sayılar Phase 10'da pazar kontrolüyle doğrulanacak.
- Deneme durumu saklama: Keychain + destek klasöründe imzalı kayıt. Kolayca sıfırlanabilmesi kabul edilebilir
  bir maliyettir; dürüst kullanıcıyı cezalandıran agresif önlemler alınmaz.

---

## 12. Platform Stratejisi: macOS → iOS

**Sıralama kesindir:** macOS sürümü Phase 10 (Cila) tamamlanıp onaylanana kadar iOS kodu yazılmaz.
Bu bölümün amacı iOS'u şimdi yapmak değil, macOS'u **iOS'u imkânsız kılmayacak şekilde** kurmaktır.

### 12.1 Acı gerçek: iOS aynı uygulama olamaz
iOS sandbox'ı nedeniyle §6'daki özelliklerin büyük kısmı iOS'ta **teknik olarak imkânsızdır** — başka bir
uygulamanın önbelleğini okuyamazsın, sistem klasörü ve `launchd` erişimi yoktur, disk ağacını gezemezsin.
"Telefon temizleyici" diye pazarlanan uygulamaların yaptığı şeyin çoğu tiyatrodur; biz onu yapmayacağız (§10.4, §10.5).

| iOS'ta gerçekten yapılabilir | iOS'ta imkânsız |
|---|---|
| Fotoğraf kopya / benzer / seri çekim bulucu (PhotoKit + Vision) | Uygulama ve sistem önbelleği temizliği |
| Büyük video ve Live Photo avcısı, ekran görüntüsü yığını temizliği | Kötü amaçlı yazılım taraması |
| Fotoğraf kütüphanesi ve uygulama sandbox'ı için depolama görselleştirme | Başlangıç öğeleri, bakım görevleri, RAM/`purge` |
| Rehber kopya temizleyici, takvim/hatırlatıcı yığını | Diğer uygulamaların artıkları, kaldırıcı |
| "Offload / depolama boşaltma" rehberi (kullanıcıyı Ayarlar'a yönlendirme) | Space Lens (tam disk ağacı) |
| **Mac'in uzaktan izlenmesi ve tarama başlatma (companion)** | Ayrıcalıklı işlemler |

### 12.2 Konumlandırma kararı
iOS sürümü **"Burnish for iPhone"**: (a) fotoğraf/medya temizleyici + (b) Mac companion paneli.
Mac sürümünün küçültülmüş bir kopyası olarak sunulmaz; ayrı ve dürüst bir ürün olarak konumlanır.

### 12.3 Bugünden uyulacak kurallar
- `DesignSystem` cross-platform yazılır. `NSColor`/`NSImage`/`NSView` doğrudan kullanılmaz; `Color`,
  `Image` ve platform-agnostik soyutlamalar tercih edilir. Pencere/hover gibi macOS'a özgü davranışlar
  `#if os(macOS)` ile **bileşenin içinde izole** edilir, API yüzeyi aynı kalır.
- `CoreKit` ve `SafetyKit` platform-agnostik çekirdek olarak kalır (politika, modeller, boyut
  hesaplama, işlem kaydı). Dosya sistemi gezinmesi ve macOS yolları `CoreKitMac`/`SafetyKitMac`'e taşınır.
- `ScanEngine` protokolü platform-agnostik kalır (zaten öyle) — iOS'taki fotoğraf tarayıcıları aynı
  `Scanner` protokolünü uygulayacak.
- `Licensing` cross-platform yazılır; lisans tek olup her iki platformu kapsayacak şekilde tasarlanır.
- İşlem kaydı şeması (`history.sqlite`) platform alanı içerir, böylece companion senkronizasyonu
  ileride mümkün olur.
- Hedef iOS sürümü: **iOS 17+** (Observation makrosu ve SwiftUI paritesi için).
- Companion senkronizasyonu için teknoloji kararı §15'te açık (CloudKit vs. yerel ağ + App Group).

---

## 13. Dağıtım Altyapısı

### 13.1 Sürüm kontrolü ve CI
- Git deposu zorunlu. Dal modeli: `main` (kararlı) + özellik dalları.
- SemVer: `MAJOR.MINOR.PATCH`; `CFBundleShortVersionString` = SemVer, `CFBundleVersion` = artan derleme sayısı.
- `CHANGELOG.md` elle tutulur ve Sparkle sürüm notlarının kaynağıdır.
- **CI: GitHub Actions** (karar verildi). `macos-latest` runner'ında her push ve PR'da: SwiftLint →
  `swift build` (paketler) → `swift test` → `xcodebuild build` (uygulama hedefi). Gerekçe: ek altyapı
  bakımı yok, macOS runner hazır geliyor. İmzalı derleme + notarizasyon yalnızca `v*` etiketinde çalışan
  ayrı bir iş akışıdır ve sertifika secret'ları gerektirir; bu iş akışı Developer ID alınana kadar devre
  dışı kalır.
- Derleme süresi veya runner dakikası sorun olursa self-hosted Mac runner'a geçilir (§16.2/R12).
- Sırlar: Developer ID sertifikası (p12), App Store Connect API key, Sparkle özel anahtarı CI secret olarak
  tutulur; depoya asla girmez.

### 13.2 İmzalama ve notarizasyon
- Developer ID Application sertifikası; Hardened Runtime açık, App Sandbox kapalı.
- İmza sırası içten dışa: yerel paketler → helper → menü çubuğu ajanı → ana uygulama (`--deep` kullanılmaz,
  her bileşen ayrı imzalanır).
- Notarizasyon `notarytool` ile App Store Connect API key kullanılarak; sonra `stapler`.
- Gerekli entitlement'lar gerekçeleriyle belgelenir (`ENTITLEMENTS.md`).
- Dağıtım paketi: imzalı ve notarize edilmiş DMG (özel arka plan, sürükle-bırak yerleşimi).

### 13.3 Sparkle güncelleme kanalı
- **EdDSA anahtar çifti Phase 0'da üretilir.** Özel anahtar kaybolursa tüm güncelleme zinciri ölür;
  mevcut kullanıcılara bir daha güncelleme gönderilemez.
- Yedekleme politikası: özel anahtar en az iki ayrı şifreli konumda saklanır (parola yöneticisi + çevrimdışı
  şifreli yedek). Bu, projenin tek telafisi olmayan sırrıdır.
- `appcast.xml` HTTPS üzerinden barındırılır; sürüm notları TR/EN olarak sunulur.
- **Barındırma: Cloudflare R2 + Cloudflare CDN** (karar verildi) — hem `appcast.xml` ve DMG'ler hem de
  imza veritabanı için. Gerekçe: egress ücreti yok (imza veritabanı sık indirilecek), statik barındırma
  için sunucu bakımı gerekmez, kendi alan adımız altında sunulabilir.
- İmza veritabanı (YARA kuralları + hash listesi) güncellemesi Sparkle'dan **ayrı** bir kanaldır ve
  kendi Ed25519 imzasıyla doğrulanır. Sürümlenir (`manifest.json` + içerik hash'i), böylece kısmi
  indirme ve geri alma mümkün olur.

### 13.4 Çökme raporu ve telemetri
- Üçüncü parti analytics veya çökme SDK'sı kullanılmaz (§10.7).
- Opsiyonel, **varsayılan kapalı**, açık rızayla çalışan minimal çökme raporu: yalnızca çağrı yığını,
  uygulama sürümü, macOS sürümü ve donanım modeli. Dosya yolu, dosya adı, kullanıcı adı veya disk içeriği
  **asla** gönderilmez; gönderim öncesi rapor kullanıcıya ham haliyle gösterilir.
- Kullanım istatistiği toplanmaz.

### 13.5 Yasal metinler (dağıtımdan önce zorunlu)
- **EULA:** lisans kapsamı, cihaz limiti, iade koşulları.
- **Gizlilik Politikası:** "kullanıcı dosya verisi işlenmez ve iletilmez" taahhüdü, çökme raporu opt-in'i,
  lisans aktivasyonunda işlenen veriler (e-posta, cihaz tanımlayıcısı).
- **Sorumluluk reddi:** özellikle Parçalayıcı (SSD/APFS'te güvenli silme garanti edilemez) ve kötü amaçlı
  yazılım taraması (on-demand tarayıcı, antivirüs değil) için.
- `THIRD_PARTY_LICENSES.md`: Sparkle (MIT), GRDB (MIT), YARA (BSD-3-Clause) ve kullanılan her YARA kural
  kaynağının lisansı. Uygulama içinde "Hakkında" ekranından erişilebilir.
- İade politikası (MoR sağlayıcısının kurallarıyla uyumlu).

---

## 14. Geliştirme Aşamaları

Her aşamanın sonunda proje derlenir, testler geçer, ben ekranları kontrol ederim ve onayımdan sonra bir sonrakine geçilir. Bir aşama içinde bile büyük değişikliklerden önce kısa bir plan sun.

0. **Kuruluş (kod yazılmadan):** "Burnish" marka ve domain müsaitliği kontrolü; Apple Developer hesabı ve
   Developer ID sertifikası; git deposu + `.gitignore`; bundle ID'lerin kaydı; Sparkle EdDSA anahtar çifti
   üretimi ve yedeklenmesi; ödeme sağlayıcısı ve fiyat modeli kararı; uygulama ikonu konsepti; CI iskeleti.
1. **Temel:** Proje yapısı, paketler (platform ayrımına uygun), `DesignSystem` (token'lar + ortak bileşenler), ana pencere ve kenar çubuğu, sahte verili Genel Bakış ekranı, tarama animasyonu prototipi, `Licensing` iskeleti (her şey Pro).
2. **Güvenlik çekirdeği:** `SafetyKit`, `DeletionService`, GRDB işlem kaydı, geri yükleme, testleri (%90 kapsam).
3. **Sistem izleme:** `SystemMonitor` ile gerçek CPU/RAM/disk/pil/ağ verileri, Genel Bakış'ın canlı hale gelmesi.
4. **Temizlik:** Tarayıcı protokolü, Temizlik bölümündeki tüm tarayıcılar, sonuç ve onay akışı.
5. **Dosyalar:** Space Lens, büyük/eski dosyalar, kopya bulucu, benzer fotoğraflar, parçalayıcı (ağır tarayıcı ilerleme/iptal altyapısı dahil).
6. **Uygulamalar:** Kaldırıcı, artıklar, sıfırlama, uzantılar, güncelleyici.
7. **Helper ve Hız:** Privileged Helper (imza doğrulama + kendi SafetyKit katmanı), bakım görevleri, başlangıç öğeleri, kaynak tüketenler, "tamamen kaldır" akışı.
8. **Koruma ve Gizlilik:** YARA motoru, hash blocklist'i, kalıcılık analizi, karantina, yanlış pozitif yönetimi, gizlilik temizliği.
9. **Akıllı Tarama ve menü çubuğu:** Orkestrasyon, öneri motoru, sağlık skoru (açıklanabilir), menü çubuğu paneli.
10. **Cila:** Ayarlar, lisanslama ve deneme akışının gerçek hale gelmesi, yerelleştirme, erişilebilirlik, performans profillemesi (Instruments), boş/hata durumları, ilk açılış karşılama akışı.
11. **Dağıtım:** Uygulama ikonu, Developer ID imzası, notarizasyon betiği, Sparkle güncelleme akışı, DMG paketleme, yasal metinler, satış sayfası.
12. **(macOS onayından sonra) iOS:** §12'ye göre ayrı planlama yapılır. Bu aşamaya macOS Phase 11 tamamlanmadan geçilmez.

---

## 15. Çalışma Kuralları (Claude Code için)

- Kod yazmadan önce ilgili bölümü bu dosyadan tekrar oku.
- Küçük, derlenebilir adımlarla ilerle; her adımdan sonra `xcodebuild` ile derle ve testleri çalıştır.
- Gerçek dosya sistemi üzerinde silme yapan kodu test etmeden önce mutlaka dry-run modunda çalıştır ve çıktıyı bana göster.
- Belirsiz bir konuda tahmin yürütmek yerine sor; özellikle silme ve izinlerle ilgili kararlarda.
- **İsimlendirme:** Tüm kod İngilizce — tip, değişken, fonksiyon, dosya ve dal adları dahil. Kod içi
  açıklamalar İngilizce. Kullanıcıya görünen **her** metin String Catalog üzerinden Türkçe ve İngilizce;
  kaynak kodda hard-coded kullanıcı metni bulunmaz.
- Kullanımdan kalkmış API'ler kullanma; macOS 14+ API'lerini tercih et.
- `[cross-platform]` işaretli paketlere macOS'a özgü kod ekleme (§3).
- Her aşama sonunda kısa bir özet yaz: ne yapıldı, ne test edildi, bilinen eksikler.
- Yeni bir bağımlılık, yeni bir ayrıcalıklı işlem veya yeni bir ağ çağrısı eklemek her zaman ayrı onay gerektirir.

---

## 16. Risk Kaydı ve Açık Sorular

Karara bağlanan her madde buradan çıkarılıp §17 Karar Günlüğü'ne yazılır.

### 16.1 Açık kararlar
| # | Konu | Durum | Ne zaman gerekli |
|---|---|---|---|
| A6 | iOS companion senkronizasyonu | Açık — bilinçli olarak erteledi | Phase 12 |
| A7 | Ücretsiz/Pro ayrımının son hali | §11.3 taslağıyla başlanacak, geri bildirimle ayarlanacak | Phase 10 |
| A3' | Fiyat noktasının doğrulanması | §11.3'te geçici değer var (49/79 USD), pazar kontrolü bekliyor | Phase 10 |

Karara bağlananlar: A1 (Paddle), A2 (tek seferlik + 1 yıl), A4 (GitHub Actions), A5 (Cloudflare R2),
**A8 (ad: Burnish)** — §17.

### 16.2 Riskler
| # | Risk | Etki | Azaltma |
|---|---|---|---|
| R1 | Sparkle özel anahtarının kaybı | Telafisi yok — güncelleme zinciri ölür | §13.3 çift şifreli yedek, Phase 0'da kurulur |
| R2 | Yanlış silme ile kullanıcı veri kaybı | Marka ölümü | §4 kuralları, %90 test kapsamı, Çöp varsayılanı, geri alma |
| R3 | YARA kural kaynaklarının lisans uyumsuzluğu | Hukuki risk | Her kaynak tek tek doğrulanır, `THIRD_PARTY_LICENSES.md` |
| R4 | Yanlış pozitif malware bulgusu | Güven kaybı, destek yükü | Silme yok (karantina), "neden işaretlendi" açıklaması, allowlist |
| R5 | Yeni macOS sürümünün API/izin değişiklikleri | Özellikler bozulur | Her beta döneminde regresyon taraması, özellik bazında kapatılabilirlik |
| R6 | `SMAppService` helper kurulumunun kullanıcıda başarısız olması | Hız/sistem temizliği çalışmaz | Net hata ekranı, helper'sız çalışabilen uygulama, yeniden kurma düğmesi |
| R7 | Marka adı çakışması ("Burnish") | Rebrand maliyeti | Phase 0'da doğrulama; §1.1 tek değişiklik noktası |
| R8 | Notarizasyon reddi (sandbox kapalı + helper) | Dağıtım gecikir | Phase 0'da boş bir iskeletle uçtan uca notarizasyon denemesi |
| R9 | Ağır taramaların beklenenden çok yavaş olması | Kullanıcı memnuniyetsizliği | §8 ağır tarayıcı sözleşmesi (ilerleme, iptal, kısmi sonuç) |
| R10 | Lisans korumasının kırılması | Gelir kaybı | Kabul edilen risk; dürüst kullanıcıyı cezalandıran önlem alınmaz (§11.2) |
| R11 | Geliştirme Mac'i macOS 27, hedef macOS 14 | macOS 14'te çalışmayan kod fark edilmez | Gerçek macOS 14 VM/Mac'te aşama sonu doğrulaması; CI'da `-destination` ile eski SDK derlemesi; `if #available` disiplini |
| R12 | GitHub Actions macOS runner dakikası/hızı | CI maliyeti veya yavaşlık | Önce GitHub-hosted; sorun olursa self-hosted Mac runner (§13.1) |
| R13 | Paddle hesap onayının gecikmesi/reddi | Satış başlamaz | Phase 0'da erken başvuru; yedek plan Stripe + vergi danışmanı |
| R14 | ~~"Purgify" ile ad benzerliği~~ | — | **Kapandı:** ad Burnish olarak değişti (§17). Ad yine hard-code edilmez; §1.1 tek değişiklik noktası |
| R15 | Burnish için hukuki marka araştırması henüz yapılmadı | Geç aşamada rebrand | Lansmandan (Phase 11) önce TÜRKPATENT/USPTO/EUIPO Sınıf 9 ve 42; bulgu çıkarsa §1.1 tek noktadan değişir |

---

## 17. Karar Günlüğü

| Tarih | Karar | Gerekçe |
|---|---|---|
| 2026-10-12 | Uygulama adı **Burnish**, bundle ID `com.burnish.app` | §1.1'de tek değişiklik noktası olarak toplandı; marka doğrulaması Phase 0 görevi |
| 2026-10-12 | Spesifikasyon dosyası `CLAUDE.md` olarak adlandırıldı | Claude Code bu adı her oturumda otomatik context'e alır; "her oturumda oku" talimatı böylece garanti altında |
| 2026-10-12 | **ClamAV kullanılmayacak**, yerine YARA + kendi hash blocklist'i | ClamAV GPL-2.0; kapalı kaynak ticari uygulamaya bağlanması tüm uygulamayı GPL'e tabi kılar. YARA BSD-3-Clause, ticari kullanıma uygun |
| 2026-10-12 | Gerçek zamanlı koruma **yok**; on-demand tarayıcı olarak konumlandırılacak | Endpoint Security entitlement'ı Apple'dan özel başvuruyla alınır ve elimizde yok. Kullanıcıya antivirüs izlenimi vermemek etik ve hukuki zorunluluk |
| 2026-10-12 | Kalıcı veri katmanı **GRDB** | Ham SQLite C API çok fazla kod ve hata yüzeyi; SwiftData append-only işlem kaydı için fazla ağır ve migration riski taşıyor. GRDB olgun, Sendable-uyumlu ve MIT lisanslı. "Bağımlılığı minimumda tut" kuralından bilinçli sapma |
| 2026-10-12 | Paketler `[cross-platform]` / `[macOS]` olarak ayrıldı, platforma özgü kod `*Mac` kardeş paketlere alındı | iOS sürümü için sonradan yapılacak ayrıştırma çok pahalı; Phase 1'den itibaren disiplin uygulanması gerekiyor |
| 2026-10-12 | iOS sürümü ayrı bir ürün olarak konumlanacak: fotoğraf/medya temizleyici + Mac companion | iOS sandbox'ı §6'daki özelliklerin çoğunu imkânsız kılıyor; "telefon temizleyici" tiyatrosu yapmamak §10 ile tutarlı |
| 2026-10-12 | 60 saniyelik tarama hedefi yalnızca `.light` tarayıcılara uygulanacak | Kopya bulucu (SHA-256) ve Vision tabanlı fotoğraf karşılaştırması terabaytlarda dakikalar sürer; hedef gerçekçi değildi. Ağır tarayıcılar için süre yerine ilerleme/iptal/kısmi sonuç sözleşmesi tanımlandı |
| 2026-10-12 | macOS sürümleri arasında **kendi özgün görsel kimliğimiz** korunacak, sistem kromu doğal bırakılacak | Marka tutarlılığı; her macOS sürümünde tasarım dilini takip etmek sürekli yeniden yazma demek. Yeni API'ler progressive enhancement olarak eklenir |
| 2026-10-12 | Üçüncü parti analytics/çökme SDK'sı kullanılmayacak; çökme raporu opt-in ve varsayılan kapalı | Gizlilik odaklı bir temizlik uygulamasında veri toplama marka ile çelişir; §10.7 taahhüdü |
| 2026-10-12 | Lisans doğrulaması tamamen **çevrimdışı** (Ed25519 imzalı lisans) | İnternet yokken uygulamanın kilitlenmesi kabul edilemez; lisans sunucusu tek hata noktası olmamalı |
| 2026-10-12 | Güvenlik ve şeffaflık özellikleri (dry-run, geçmiş, geri alma, malware taraması, "tamamen kaldır") **ücretsiz** katmanda | Güveni paywall arkasına koymak §1'deki temel farkımızı yok eder |
| 2026-10-12 | "Burnish'ı tamamen kaldır" akışı zorunlu özellik | Privileged helper kuran bir uygulama kaldırılırken root daemon artığı bırakmamalı; temizlik uygulaması kendi arkasında artık bırakamaz |
| 2026-10-12 | **A1: Ödeme sağlayıcısı Paddle** (MoR). Uygulama içinde SDK yok, lisans anahtarı e-posta ile verilir | Vergi yükümlülüğü sağlayıcıda; tek kişilik ekip için global KDV beyanı sürdürülemez. SDK'sız entegrasyon sağlayıcı bağımlılığını ve §10.7 veri riskini ortadan kaldırır |
| 2026-10-12 | **A2: Tek seferlik lisans + 1 yıl güncelleme**, sonrasında indirimli yenileme. Abonelik yok | Abonelik yorgunluğu; §10.6 karanlık desen yasağı. Süre bitince uygulama çalışmaya devam eder, yalnızca güncelleme durur |
| 2026-10-12 | **A4: CI = GitHub Actions** (`macos-latest`). İmzalı derleme ayrı, yalnızca `v*` etiketinde | Ek altyapı bakımı yok, macOS runner hazır. İmzalama Developer ID gelene kadar devre dışı |
| 2026-10-12 | **A5: Dağıtım ve imza DB barındırma = Cloudflare R2 + CDN** | Egress ücreti yok (imza DB sık indirilir), statik barındırmada sunucu bakımı gerekmez |
| 2026-10-12 | Geliştirme ortamı doğrulandı: Xcode 26.5 / Swift 6.3.2 / macOS 27.0.1. **Developer ID sertifikası yok** | Phase 1–10 engelsiz; Phase 0'ın imza/notarizasyon maddeleri ve R8 testi sertifika alınana kadar bekler |
| 2026-10-12 | Uygulama adı **kesinleşmedi** (A8). "Burnish" çalışma adı olarak kullanılıyor; ad hiçbir yere hard-code edilmeyecek | App Store'da "Purgify" bulundu: tek harf fark, aynı kategori, §12.2'deki iOS planımızla aynı iş. Rebrand şimdi bedava, lansmandan sonra çok pahalı |
| 2026-10-12 | **A8: Uygulama adı Burnish.** Pazarlamada "Burnish for Mac" | Dokuz aday tarandı, yalnızca Burnish ve Hone temiz çıktı (kayıt: `docs/PHASE0_CHECKLIST.md`). "Cilalamak" anlamı §1'deki premium/güven konumlandırmasına "purge/clean"den iyi oturuyor; işlevi tanımlamadığı için kalabalığa düşmüyor. "Mac" içeren adlar Apple kuralı madde (g) nedeniyle tescil edilemediği için reddedildi; Mac bağı referans kullanımıyla bedavaya kuruluyor |
| 2026-10-12 | Tarayıcı protokolü `Scanner` yerine **`Scanning`** (§6) | `Foundation.Scanner` somut bir sınıf; aynı adlı protokol yüzünden `extension Scanner` sessizce Foundation'ın sınıfını genişletti ve protokol varsayılanları hiç uygulanmadı. Somut tipler `*Scanner` sonekini korur |
| 2026-10-12 | Palet **ikiye ayrıldı**: dekoratif `palette` + WCAG AA doğrulanmış `textSafePalette` (§5.3) | §5.3'teki sekiz gradyanın altısı beyaz metinle AA'yı geçmiyor (amber→sarı 1.53:1). Paletleri köreltmek §5.1'in canlı kimliğini yok ederdi; metin taşıyan dolgular için ayrı, test edilen varyant kullanılıyor |
| 2026-10-12 | Xcode projesi **XcodeGen** ile üretiliyor; `project.yml` kaynak, `.xcodeproj` gitignore'da | 15+ modülle elle bakılan `pbxproj` birleştirme çatışması üretir. XcodeGen derleme zamanı aracıdır, uygulama bağımlılığı değil |
| 2026-10-12 | `Licensing` paketi Phase 1'de kuruldu (her şey Pro döndürür) | Pro kapılarının doğru yerlere baştan konması için; Phase 10'da sonradan serpiştirmek hata üretir |
| 2026-10-12 | Sağlık skoru **bileşenlerinin toplamıdır**, sonradan eğri uygulanmaz (§6.1) | "Nasıl hesaplandı?" panelinin gerçek aritmetiği gösterebilmesi için. Ölçülmemiş etken tam puan alır — §10.4 gereği kullanıcı yapmadığı tarama yüzünden cezalandırılmaz |
| 2026-10-12 | `PathGuard` yolları **kanonik biçimde** karşılaştırır (`/var` → `/private/var`) | `standardizedFileURL` tutarsız: `/private/var/db`'yi `/var/db`'ye çeviriyor ama `/private/var/db/x`'i olduğu gibi bırakıyor. İki taraf farklı normalleştiği için `/private/var/db` koruması altındaki hiçbir şeyi korumuyordu. Üretimde sessizce başarısız olacak bir hata sınıfı |
| 2026-10-12 | `BlockedReason` ayrıştırıldı: `protectedPath` ve `outsideScope` eklendi | Korumalı bir sistem yolu için kullanıcıya "sen hariç tuttun" demek küçük bir yalan; §10 bunları yasaklıyor. Arayüz artık gerçek nedeni söyleyebiliyor |
| 2026-10-12 | `DeletionService.execute` kalıcı plan için `confirmedIrreversible` şart koşar | §4.1'in ikinci onayı tip düzeyinde zorunlu; çağıranın unutması mümkün değil, unutursa atar |
| 2026-10-12 | `RestoreService` hedefte dosya varsa geri yüklemeyi **reddeder** | Geri alma işleminin ikinci bir veri kaybına yol açması kabul edilemez |
| 2026-10-12 | `/private/var/folders` korumalı kaldı; testler `/private/tmp` kullanıyor | Kullanıcı başına geçici alan aktif durum tutuyor. Muhafazakâr taraf seçildi; `NSTemporaryDirectory()` oraya düştüğü için test fixture'ları taşındı |
| 2026-10-12 | `ScanButton`'ın nabzı **gölge yarıçapını değil ölçeği** animasyonlar | `shadow(radius:)` animasyonu bulanıklığı her karede yeniden hesaplatıyor; 120 Hz ekranda tek başına gösterge panelinin CPU'sunun yarısıydı (ölçüldü: %74 → %42). `scaleEffect` derleyici dönüşümü, bedavaya yakın |
| 2026-10-12 | `MetricTile` canlı değerleri **animasyonsuz** gösterir (`animatesValue` varsayılan kapalı) | Saniyede bir yenilenen metrikte `contentTransition(.numericText())` kalan CPU'nun yarısını ve ~90 MB belleği yiyordu (ölçüldü: %42 → %18, 203 → 110 MB). `AnimatedCounter` imza anlarında kalır: tarama toplamı ve sağlık skoru |
| 2026-10-12 | `Sparkline` `drawingGroup()` kullanmaya devam eder | Bitmiş panelde iki yönlü ölçüldü: açıkken 10 sn'de 1,84 sn CPU / 110 MB, kapalıyken 2,11 sn / 122 MB. "Küçük çizimde zarar verir" sezgisi yanlış çıktı |
| 2026-10-12 | Model adı `IODeviceTree:/product` yolundan okunur | `IOPlatformExpertDevice` üzerinde `product-name` yok; oradan okuyunca kullanıcıya "Mac16,8" gösteriliyordu. Doğru yol "MacBook Pro (14-inch, Nov 2024)" veriyor |
| 2026-10-12 | Bellek baskısı **wired + compressed / fiziksel** olarak hesaplanır | "kullanılan / toplam" sağlıklı bir Mac'te bile 1'e yakın çıkıyor ve sağlık skorunu kalıcı olarak kötümser yapardı. Inactive ve speculative sayfalar hariç — §10.4 kullanımı şişirmeyi yasaklıyor |
| 2026-10-12 | Her yol tek bir tarayıcıya ait; örtüşme katalogda yasak | Kuru çalıştırma `~/Library/Caches` içindeki tarayıcı ve geliştirici klasörlerinin iki tarayıcı tarafından birden sayıldığını gösterdi: toplam 9,95 GB görünüyordu, gerçek 7,77 GB. Dahası `userCaches` tarayıcı sahipliği bildirmediği için Safari açıkken onun önbelleğini silmeye hazırdı — §4.5 baypas ediliyordu |
| 2026-10-12 | `DeletionPlan` iç içe öğeleri tekilleştirir (`nestedInAnotherItem`) | Katalog örtüşmemeli, ama örtüşürse rakam yanlış çıkmasın diye savunma hattı. Üst öğe silinince alt öğe zaten gider; ikisini de saymak §10.4'ün yasakladığı şişirme olur |
| 2026-10-12 | `Tools/DryRun` kalıcı geliştirici aracı olarak eklendi | §15 her silme kodunu kuru çalıştırmayla göstermeyi şart koşuyor. Tek seferlik betik yerine kalıcı araç: sonraki her tarayıcı aynı süzgeçten geçecek |


| 2026-10-12 | `DeletionService` çalışan sürecin kendi paketini içeren hiçbir öğeyi silmez | §4.5 sahibi bundle ID ile buluyor; ama Xcode derleme klasörü `Burnish-<hash>` adlı, bundle ID içermiyor. Tarama, uygulamanın çalıştığı klasörü önceden seçili olarak öneriyordu — onaylansa uygulama kendi çalışan dosyasını Çöp'e atardı. Yol karşılaştırması bundle ID'den daha sağlam |
| 2026-10-12 | Güvenlik elemesi **taramadan hemen sonra** uygulanır (`DeletionService.screened`) | Eleme yalnızca plan kurulurken yapılınca inceleme ekranı 7,81 GB, onay sayfası daha az gösterecekti. Ekranın ve sayfanın aynı rakamı göstermesi, kullanıcının onayladığı şeyin yapılan şey olması demek |
| 2026-10-12 | Onay sayfası her öğenin klasörünü de gösterir | "Adobe" gibi adlar hem Caches'te hem Logs'ta geçiyor; yalnızca ada bakan kullanıcı neyin gittiğini ayırt edemez |
\n