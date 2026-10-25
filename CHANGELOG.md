# Changelog

Bu dosya [Keep a Changelog](https://keepachangelog.com/) biçimini ve
[Semantic Versioning](https://semver.org/lang/tr/) kurallarını izler.
**Sparkle sürüm notlarının kaynağıdır** (CLAUDE.md §13.1) — her sürüm için TR/EN karşılığı buradan üretilir.

## [Yayınlanmadı]

### Eklendi
- Proje spesifikasyonu (`CLAUDE.md`): güvenlik kuralları, tasarım sistemi, özellikler, lisanslama,
  platform stratejisi ve dağıtım altyapısı.
- Phase 0 iskeleti: git deposu, `.gitignore`, GitHub Actions CI, SwiftLint yapılandırması,
  üçüncü parti lisans ve entitlement belgeleri, Phase 0 kontrol listesi.
- **Phase 1 temeli** — 8 yerel paket, 85 test:
  - `CoreKit`, `ScanEngine`, `SafetyKit`, `Licensing`, `DesignSystem` (platformdan bağımsız)
  - `SystemMonitor`, `Features/Dashboard`, `Features/SmartScan` (macOS)
  - XcodeGen ile üretilen uygulama hedefi, kenar çubuklu ana pencere
  - Sahte verili Genel Bakış ekranı ve açıklanabilir sağlık skoru
  - Tarama animasyonu prototipi (gradyan halka, parçacık alanı, canlı sayaç)
  - Türkçe/İngilizce String Catalog'lar
- **Phase 2 güvenlik çekirdeği** — `SafetyKit` + yeni `SafetyKitMac`, 71 test:
  - `ProtectedPaths` — §4.3 korunan yollar listesi, her girdi için ayrı test
  - `PathGuard` — izin listesi, symlink çözümü, `/private` firmlink normalleştirmesi
  - `DeletionService` — kuru çalıştırma → onay → uygulama; tek silme kapısı
  - `HistoryStore` — GRDB tabanlı işlem kaydı, filtreleme, budama
  - `RestoreService` — Çöp'ten geri yükleme; üzerine yazmayı reddeder
  - Kapsam: `SafetyKit` %96–100, `SafetyKitMac` %92–100 (§4.9 eşiği %90)
- **Phase 3 sistem izleme** — gerçek okumalar, 44 test:
  - `Sampling` — tik/sayaç farkı aritmetiği, sayaç sıfırlanması ve ilk örnek durumları
  - `KernelReaders` — `host_processor_info`, `host_statistics64`, `getifaddrs`, volume kapasitesi
  - `IOKitReaders` — pil şarjı/sağlığı/döngü sayısı, IORegistry'den model adı
  - `LiveSystemMonitor` — aktör tabanlı önceki örnek durumu, 1 sn akış
  - Genel Bakış artık canlı: gerçek disk, bellek, işlemci, pil, ağ
- **Phase 4 Temizlik ekranı** — kategori kartları, öğe listesi, onay sayfası, sonuç ekranı;
  `CleanupModel` §4.6 sırasını (tara → incele → onayla → uygula) tip düzeyinde zorluyor.
  Uygulamaya bağlı; **silme yolu artık açık** — gerçek silme henüz çalıştırılmadı.
- **Phase 4 (kısmi) temizlik tarayıcıları** — 26 test:
  - `CoreKitMac/FileTreeWalker` — sert bağlantı tekilleştirmesi, symlink dışlama, iptal, ilerleme
  - `CleanupCatalogue` — 8 tarayıcı kuralı, dokunulmayacak Apple önbellekleri listesi
  - `CleanupScanner` — kural tabanlı tarama, çalışan uygulama engellemesi
  - `Tools/DryRun` — hiçbir şey silmeden ne önerileceğini yazdıran geliştirici aracı
  - `DeletionPlan` artık iç içe öğeleri tekilleştiriyor (çift sayım koruması)
- `scripts/test.sh` — tüm paketlerin testleri + lint; `--clean` bayat SwiftPM önbelleği için
- `scripts/run.sh` — derleyip çalıştırır; uygulama `/Applications`'a kurulmaz, derleme
  çıktısından çalışır ki açılan sürüm daima depodaki kod olsun
- **CleanerSon'dan aktarılanlar** — 10 yeni test:
  - Temizlik: `packageManagerCaches` (npm, Gradle, CocoaPods spec depoları, pnpm, Yarn, Go
    indirme önbellekleri; aracın kendi klasörü değil yalnızca önbellek klasörü) ve `toolCaches`
    (`~/.cache`, hiçbir öğe önceden seçilmez); cihaz desteğine visionOS eklendi
  - Gizlilik: `firefox` (çerezler, form geçmişi, oturum; yer imleriyle aynı dosyada olduğu için
    geçmiş yok), `chromiumProfiles` (ek ve misafir profilleri), Vivaldi, `downloadLog`
    (karantina olay kaydı), Chromium'da journal/Visited Links/Shortcuts dosyaları, Safari'nin
    kapsayıcı içindeki çerez dosyası ve geçmiş WAL dosyası
  - `CleanupRoot.profiles` — klasör adları önceden bilinmeyen tarayıcı profilleri için; izin
    listesine kök değil yalnızca var olan adlandırılmış dosyalar girer (kayıtlı parolalar erişilemez)
  - Hız: `resetQuickLook` ve `resetFontCache` bakım görevleri (yalnızca kullanıcının önbelleği,
    yardımcı gerekmez)
  - `Tools/DryRun` gizlilik tarayıcılarını da gösterir
  - Opera ve Opera GX: tarayıcı önbellekleri, ana profil (Default klasörü yok) ve
    `_side_profiles` altındaki ek profiller
  - Hız: `thinLocalSnapshots` (yerel Time Machine anlık görüntülerini inceltme, yardımcı ile);
    DNS temizliği artık `mDNSResponder`'a HUP da gönderiyor
  - Açılış öğeleri: kullanıcının kendi (Apple dışı) ajanı kaldırılabilir — onay sayfası,
    plist Çöp'e, işlem geçmişine yazılır, ardından `launchctl bootout`
  - Yardımcı protokolü **2**: bir komut birden çok sabit adım çalıştırabilir; eski yardımcı
    sürüm uyuşmazlığı olarak görünür ve yeniden kurulması istenir
- **Ayarlar** (§6.9):
  - Kenar çubuğunun altında "Ayarlar" satırı (standart ⌘, penceresini açar)
  - Genel: dil seçimi (Sistem / Türkçe / English; uygulamanın kendi `AppleLanguages` ayarı,
    yeniden başlatma düğmesiyle) ve görünüm (Sistem / Açık / Koyu)
  - Lisans: durum, Ücretsiz/Pro tablosu (`Feature` listesinden), lisans anahtarı girme,
    etkinleştirme ve kaldırma; anahtar Keychain'de, doğrulama çevrimdışı
  - Hakkında: sürüm, sistem, işlem geçmişini açma, tanılama bilgisini kopyalama
  - `LicenseActivation` (Licensing): yalnızca doğrulanan lisans saklanır; açık anahtar yoksa
    (`LicenseConfiguration.publicKey == nil`, Faz 10'a kadar) "yapılandırılmadı" der — 6 yeni test

### Düzeltildi
- `SpaceLensView` derlenmiyordu (`scheme` tanımsızdı; son tasarım commit'inde kalmıştı).
- `CleanupModel` tarama ilerlemesi Swift 6.2 derleyicisinde "sending closure" hatası veriyordu;
  ilerleme artık ana aktöre kendi geçen `@Sendable` bir kapanışla bildiriliyor.

### Performans
- Genel Bakış boşta: CPU tek çekirdeğin %74'ünden **%18'ine**, RSS 203 MB'tan **110 MB**'a indi
  (§8 hedefi <150 MB). Statik ekranda ölçülen CPU: %0.

### Kararlar
- Ödeme sağlayıcısı: Paddle (Merchant of Record).
- Lisans modeli: tek seferlik + 1 yıl güncelleme.
- CI: GitHub Actions; dağıtım barındırma: Cloudflare R2 + CDN.
- Kötü amaçlı yazılım motoru: YARA (ClamAV lisans nedeniyle reddedildi).
- Uygulama adı: **Burnish** ("Burnish for Mac").
- Tarayıcı protokolü `Scanning` olarak adlandırıldı (`Foundation.Scanner` çakışması).
- Palet ikiye ayrıldı: dekoratif + WCAG AA doğrulanmış `textSafePalette`.
- Proje dosyası XcodeGen ile üretiliyor; `project.yml` kaynaktır.

### Bilinen eksikler
- `DeletionService` henüz arayüze bağlı değil; Temizlik akışı Phase 4'te gelecek.
- Developer ID sertifikası yok; imzalı derleme ve notarizasyon iş akışı henüz oluşturulmadı (R8).
- "Burnish" için hukuki marka araştırması yapılmadı (R15).
- Gerçek silme uçtan uca denenmedi: `DeletionService` arayüze bağlı ve test edildi, ama ilk gerçek
  temizlik kullanıcı onayıyla yapılacak (CLAUDE.md §15).
- Akıllı Tarama simüle; gerçek tarayıcılara bağlanması Temizlik arayüzünden sonra.
- `Licensing` her şeyi Pro döndürüyor; gerçek doğrulama Phase 10'da.
- Kenar çubuğundaki 6 bölüm yer tutucu.
- macOS 14 üzerinde doğrulama yapılmadı; geliştirme macOS 27'de (R11).
