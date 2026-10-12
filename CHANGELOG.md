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
- Developer ID sertifikası yok; imzalı derleme ve notarizasyon iş akışı henüz oluşturulmadı (R8).
- "Burnish" için hukuki marka araştırması yapılmadı (R15).
- `SafetyKit` yalnızca model katmanı; `DeletionService` Phase 2'de gelecek.
- `SystemMonitor` sahte veri üretiyor; gerçek okumalar Phase 3'te.
- Akıllı Tarama simüle; gerçek tarayıcılar Phase 4'te.
- `Licensing` her şeyi Pro döndürüyor; gerçek doğrulama Phase 10'da.
- Kenar çubuğundaki 6 bölüm yer tutucu.
- macOS 14 üzerinde doğrulama yapılmadı; geliştirme macOS 27'de (R11).
