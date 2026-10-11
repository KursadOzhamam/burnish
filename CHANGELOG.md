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

### Kararlar
- Ödeme sağlayıcısı: Paddle (Merchant of Record).
- Lisans modeli: tek seferlik + 1 yıl güncelleme.
- CI: GitHub Actions; dağıtım barındırma: Cloudflare R2 + CDN.
- Kötü amaçlı yazılım motoru: YARA (ClamAV lisans nedeniyle reddedildi).

### Bilinen eksikler
- Uygulama adı kesinleşmedi (CLAUDE.md §16.1/A8 — "Purgify" ad benzerliği).
- Developer ID sertifikası yok; imzalı derleme ve notarizasyon iş akışı henüz oluşturulmadı.
- Henüz kod yok (Phase 1 başlamadı).
