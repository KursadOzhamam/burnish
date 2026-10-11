# Entitlement'lar ve Gerekçeleri

CLAUDE.md §13.2 uyarınca her entitlement burada gerekçesiyle belgelenir. Gerekçesi yazılmamış
entitlement projeye eklenmez.

## Ana uygulama (`com.purgeify.app`)

| Entitlement | Değer | Gerekçe |
|---|---|---|
| `com.apple.security.app-sandbox` | `false` | Sandbox, başka uygulamaların önbellek/artık klasörlerine ve sistem yollarına erişimi imkânsız kılar. Uygulamanın temel işlevi bununla bağdaşmaz; bu nedenle App Store dışı dağıtım seçildi (§2). |
| `com.apple.security.cs.allow-jit` | `false` | İhtiyaç yok. |
| `com.apple.security.cs.disable-library-validation` | `false` | İhtiyaç yok — tüm bileşenler aynı Team ID ile imzalanır. **Sparkle 2 kurulumunda gerekmez.** |
| `com.apple.security.automation.apple-events` | **değerlendiriliyor** | Yalnızca Finder/Fotoğraflar'da "öğeyi göster" gibi işlemler AppleScript gerektirirse. Mümkünse `NSWorkspace` ile çözülecek ve entitlement hiç eklenmeyecek. |

**Hardened Runtime: açık.** Yukarıdaki istisnaların hiçbiri varsayılan olarak etkin değildir.

### Kullanılmayacak entitlement'lar (bilinçli karar)

| Entitlement | Neden eklenmiyor |
|---|---|
| `com.apple.developer.endpoint-security.client` | Apple'dan özel başvuruyla alınır ve elimizde yok. Gerçek zamanlı koruma sunulmuyor — CLAUDE.md §6.4 ve §10.1. |
| `com.apple.developer.system-extension.install` | Sistem uzantısı/kernel extension kullanılmıyor (§10.1). |
| `com.apple.security.files.user-selected.read-write` | Sandbox kapalı olduğu için anlamsız. |

## Privileged Helper (`com.purgeify.app.helper`)

| Konu | Karar |
|---|---|
| Kurulum | `SMAppService.daemon(plistName:)` — eski `SMJobBless` kullanılmaz (§7) |
| Konum | Binary: `Contents/MacOS/`, launchd plist: `Contents/Library/LaunchDaemons/` |
| İmza | Ana uygulamayla **aynı Developer ID**, ayrı imzalanır (`--deep` kullanılmaz) |
| Sandbox | Kapalı (root daemon) |
| Hardened Runtime | Açık |
| İstemci doğrulama | XPC bağlantısında `audit_token` üzerinden kod imzası ve Team ID doğrulanır; yalnızca kendi uygulamamız bağlanabilir (§7) |
| Komut kümesi | Kapalı liste. Rastgele kabuk komutu **yok** (§10.8). Helper kendi içinde SafetyKit kurallarını tekrar uygular (§4.10) |

### Helper'ın izin verilen komut kümesi (taslak — Phase 7'de kesinleşir)

| Komut | İşlev | Risk sınırı |
|---|---|---|
| `purgeMemory` | `purge` eşdeğeri | Parametre almaz |
| `flushDNSCache` | DNS önbelleğini temizler | Parametre almaz |
| `rebuildLaunchServices` | Launch Services veritabanını yeniden kurar | Parametre almaz |
| `deleteAtSystemPath(paths:)` | Yalnızca `/Library/Caches`, `/Library/Logs` altındaki yolları siler | Yol izin listesine karşı **helper içinde** yeniden doğrulanır |
| `listLocalSnapshots` / `deleteLocalSnapshot(id:)` | Time Machine yerel anlık görüntüleri | Yalnızca `tmutil` API'si, yol parametresi yok |
| `setLaunchAgentEnabled(label:enabled:)` | `launchctl` ile etkinleştirme/devre dışı bırakma | Yalnızca kullanıcıya ait ajan label'ları; sistem daemon'ları reddedilir |

## Menü Çubuğu Ajanı (`com.purgeify.app.menubar`)

| Konu | Karar |
|---|---|
| Kurulum | `SMAppService.mainApp` ile giriş öğesi olarak kaydedilir (§6.8) |
| Sandbox | Kapalı (ana uygulamayla aynı veri alanını okur) |
| Hardened Runtime | Açık |

## Info.plist gizlilik açıklamaları (`NS*UsageDescription`)

Kullanıcıya gösterilen bu metinler String Catalog üzerinden TR/EN sağlanır ve **neden** gerektiğini
açıkça söyler (§10.3: korku pazarlaması yok).

| Anahtar | Ne zaman gerekir |
|---|---|
| `NSPhotoLibraryUsageDescription` | Benzer fotoğraf taraması (§6.7) — yalnızca o özellik ilk kullanıldığında istenir |
| `NSAppleEventsUsageDescription` | Yalnızca yukarıdaki apple-events entitlement'ı gerekirse |

> **Tam Disk Erişimi** bir entitlement değildir; kullanıcı Sistem Ayarları'ndan verir ve uygulama
> bunu yalnızca kontrol edip rehber gösterir (§7).
