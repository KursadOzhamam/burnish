# Üçüncü Parti Lisanslar

CLAUDE.md §13.5 uyarınca bu dosya uygulama içinde "Hakkında" ekranından erişilebilir olmalıdır.

> **Kural:** Yeni bir bağımlılık veya veri kaynağı (ör. bir YARA kural seti) eklenmeden önce lisansı
> **ticari, kapalı kaynak dağıtıma uygun** olduğu doğrulanır ve bu dosyaya işlenir. Doğrulanmamış
> kaynak kullanılmaz.

## Onaylı bağımlılıklar

| Bileşen | Sürüm | Lisans | Ticari kapalı kaynak kullanım | Not |
|---|---|---|---|---|
| Sparkle | 2.x | MIT | ✅ Uygun | Otomatik güncelleme (§13.3) |
| GRDB.swift | 7.x | MIT | ✅ Uygun | `history.sqlite` işlem kaydı (§2) |
| YARA | 4.x | BSD-3-Clause | ✅ Uygun | İmza motoru (§6.4) |

> Sürüm numaraları Phase 1'de `Package.resolved` ile kesinleştirilecek.

## Reddedilen bileşenler

| Bileşen | Lisans | Red gerekçesi |
|---|---|---|
| **ClamAV** | GPL-2.0 | Kapalı kaynak ticari uygulamaya bağlanması veya birlikte dağıtılması tüm uygulamayı GPL'e tabi kılar. İmza veritabanı (CVD) ayrıca kısıtlı. Karar kalıcıdır — CLAUDE.md §6.4 ve §17. |

## YARA kural kaynakları

Her kural kaynağı **tek tek** lisans doğrulamasından geçer. Doğrulanana kadar `Durum` sütunu
`beklemede` kalır ve kural üretime alınmaz.

| Kaynak | Lisans | Durum | Doğrulayan / Tarih |
|---|---|---|---|
| Burnish kendi kuralları | Tescilli (bizim) | ✅ kullanımda | — |
| _(eklenecek)_ | | beklemede | |

## Hash blocklist kaynakları

| Kaynak | Kullanım koşulu | Durum |
|---|---|---|
| Burnish kendi listesi | Tescilli (bizim) | ✅ kullanımda |
| _(eklenecek)_ | | beklemede |

## Apple framework'leri

Apple'ın işletim sistemiyle gelen framework'leri (SwiftUI, AppKit, Vision, PhotoKit, IOKit,
Security, ServiceManagement, UserNotifications, Swift Charts) Apple Developer Program lisans
sözleşmesi kapsamında kullanılır; ayrı atıf gerektirmez.
