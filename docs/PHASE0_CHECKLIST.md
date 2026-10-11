# Phase 0 — Kuruluş Kontrol Listesi

CLAUDE.md §14/Phase 0. **Phase 1 (kod) bu listedeki A8 kararı verilmeden başlamaz.**
Diğer maddeler Phase 1 ile paralel yürüyebilir.

Durum: ✅ bitti · 🟡 sende · ⏸ bloke

---

## 0. Yapıldı (Claude)

- ✅ Git deposu + `.gitignore` (sertifika/anahtar/`.env` baştan bloklu)
- ✅ `CLAUDE.md` — spesifikasyon, kararlar işlendi
- ✅ `.github/workflows/ci.yml` — SwiftLint + paket derleme/test + uygulama derlemesi
  (henüz dosya olmadığı için adımlar sessizce geçer)
- ✅ `.swiftlint.yml` — §4 ve §10 kurallarını **derleme zamanında zorlayan** özel kurallar dahil:
  doğrudan `FileManager.removeItem` **hata**, helper'da kabuk komutu **hata**, hard-coded kullanıcı
  metni **uyarı**, `print` **uyarı**
- ✅ `CHANGELOG.md`, `THIRD_PARTY_LICENSES.md`, `ENTITLEMENTS.md`
- ✅ Geliştirme ortamı tespiti (CLAUDE.md §1.2)
- ✅ Ad taraması — **sonuç aşağıda, A8**

---

## 1. 🟡 A8 — Uygulama adı (EN ÖNCELİKLİ)

**Bulgu (2026-10-12):** "Purgeify" diye bir uygulama yok. Ancak App Store'da **"Purgify"** var:
iPhone, fotoğraf temizleme, Utilities kategorisi, geliştirici Cian Striffler
([App Store](https://apps.apple.com/us/app/purgify/id6787660976)).

Neden bu önemli:
- Tek harf fark (`Purgeify` / `Purgify`) — sesletim neredeyse aynı
- Aynı ürün kategorisi (temizlik/utility yazılımı)
- **Ve** bu tam olarak CLAUDE.md §12.2'de iOS sürümü için planladığımız iş: fotoğraf temizleyici

Ayrıca aynı alanda `Purge` (açık kaynak Mac temizleyici), `Cleanify: Purge Lite`, `Purge for Safari`
gibi isimler de var — "purge" kökü bu kategoride kalabalık.

**Önerim: adı değiştir.** Şimdi maliyeti sıfır (tek tablo, kod yok). Lansmandan sonra ikon, domain,
appcast URL'i, lisans anahtarları, kullanıcı tabanı ve SEO'ya yayılmış olur.

### Ad süzgeci — her aday bundan geçer

**1. Apple marka kuralları.** Adın içinde "Mac" (veya herhangi bir Apple markası) geçiyorsa
[Apple'ın üçüncü parti kuralları](https://www.apple.com/legal/intellectual-property/guidelinesfor3rdparties.html)
sekiz koşulun **tamamını** şart koşar:

| # | Koşul | Bizim için not |
|---|---|---|
| (a) | Ürün bir bilgisayar, bilgisayar sistemi veya **işletim sistemi yazılımı** olmayacak | Sistem bakım aracıyız, işletim sistemi değiliz — sınıra yakın ama geçer |
| (b) | Ürün Mac uyumlu olacak | ✅ |
| (c) | "Mac" **jenerik olmayan başka bir kelimeyle** birlikte kullanılacak | ⚠️ **En sık takılan madde.** Son ek (`-ify`, `-er`) kelime sayılmaz |
| (d) | "Mac" adın geri kalanından daha baskın görünmeyecek (boyut, renk, yazı tipi) | Logo tasarımını bağlar |
| (e) | Apple ile yanlış bir ilişki çağrıştırmayacak | |
| (f) | Apple'ın herhangi bir markasıyla karıştırılacak kadar benzer olmayacak | |
| (g) | "Mac" markasının tek sahibinin Apple olduğunu kabul edecek ve Apple'ın tescilini engellemeyeceksin | ⚠️ **Stratejik bedel: adı kendi markamız olarak tescil edemeyiz.** Marka kiralanmış olur |
| (h) | Apple programlarına üyeysen ek kısıtlar olabilir | |

**Sonuç: "Mac" içeren bir ad seçersek markayı asla sahiplenemeyiz (madde g).** Bu yüzden
platformdan bağımsız bir ad tercih ediyoruz. Mac çağrışımı **referans olarak serbesttir** ve
bedavadır: "<Ad> for Mac" / "<Ad> — Mac için" — Apple bunu açıkça izin veriyor, yeter ki Apple
markası ürün adının parçası olmasın ve adımızdan daha az baskın görünsün.

**2. Kategori çakışması.** App Store + Mac App Store + Google aramasında benzer ad yok.
**3. Marka araştırması.** TÜRKPATENT, USPTO, EUIPO — Nice sınıf 9 ve 42.
**4. Varlıklar.** `.com` (tercihen `.app` de), GitHub org, X/Mastodon kullanıcı adı.

### Değerlendirilen ve reddedilen adlar

| Ad | Durum | Gerekçe |
|---|---|---|
| **Macify** | ❌ reddedildi | Apple kuralı madde **(c)**: `-ify` son ektir, kelime değil — izin verilen birleşim biçimi değil. Madde **(g)** nedeniyle tescil edilemez, marka kiralanmış olur. Ayrıca §12 iOS sürümünü anlamsızlaştırır (ve orada App Store incelemesi var). Benzer ad mevcut: Macaify |
| **Purgeify** | ⚠️ riskli | App Store'da "Purgify" — tek harf fark, aynı kategori, §12.2'deki iOS planımızla aynı iş. `-ify` ayrıca kalabalık |

### Yapılacaklar

- [ ] Karar: "Purgeify" ile devam mı, yeni ad mı?
- [ ] Seçilen ad için kontroller:
  - [ ] App Store / Mac App Store aramasında çakışma yok
  - [ ] [TÜRKPATENT marka araştırması](https://www.turkpatent.gov.tr/arastirma-yap) — Nice sınıf 9 ve 42
  - [ ] [USPTO TESS](https://tmsearch.uspto.gov/) — aynı sınıflar
  - [ ] [EUIPO eSearch](https://euipo.europa.eu/eSearch/) (AB satışı yapılacaksa)
  - [ ] `.com` domain müsait (ve `.app` tercihen)
  - [ ] GitHub org adı, X/Twitter ve Mastodon kullanıcı adı müsait
  - [ ] Google'da "<ad> mac" aramasında kafa karıştıran sonuç yok
- [ ] Karar verilince: CLAUDE.md §1.1 tablosu + §16.1/A8 + §17 güncellenir (bana söyle, yaparım)

> Ad hiçbir yere hard-code edilmeyecek: Info.plist (`CFBundleName`) + String Catalog üzerinden gelecek.
> Bu yüzden Phase 1'in büyük kısmı ad kesinleşmeden de yazılabilir — ama bundle ID'ler ada bağlı olduğu
> için projeyi **bir kez** doğru adla oluşturmak en temizi.

---

## 2. 🟡 Apple Developer Program ve imzalama

Mevcut durum: makinede yalnızca *Apple Development* kimliği var (`k1453o@icloud.com` hesabına bağlı).
**Developer ID Application sertifikası yok** → dağıtım, imzalama ve notarizasyon şu an mümkün değil.

- [ ] Apple Developer Program üyeliği (yıllık 99 USD) — hangi Apple ID ile olacağına karar ver
      (mevcut `k1453o@icloud.com` mi, yoksa kurumsal bir hesap mı?)
- [ ] **Developer ID Application** sertifikası oluştur ve Keychain'e kur
- [ ] **Developer ID Installer** sertifikası (DMG değil PKG kullanılacaksa — şimdilik gerekmiyor)
- [ ] Sertifikayı `.p12` olarak yedekle (şifreli, iki ayrı konum) — CI secret'ı olacak
- [ ] App Store Connect API Key (`AuthKey_*.p8`) oluştur — `notarytool` için
- [ ] Team ID'yi not et (helper XPC imza doğrulamasında kullanılacak — §7)

Doğrulama komutu:

```bash
security find-identity -v -p codesigning
```

`Developer ID Application: ...` satırını görene kadar bu madde ⏸ bloke.

---

## 3. ⏸ R8 — Notarizasyon ön testi (madde 2'ye bağlı)

**Bu testi Phase 1'den önce yapmak istiyorum.** Sandbox kapalı + privileged helper kombinasyonunun
notarizasyondan geçtiğini, içi boş bir iskelet uygulamayla uçtan uca doğrulayacağız. Bunu Phase 7'de
öğrenmek çok pahalı olur.

- [ ] Boş SwiftUI uygulaması + `SMAppService` ile kurulan boş bir helper
- [ ] İçten dışa imzalama (paketler → helper → ajan → uygulama, `--deep` yok)
- [ ] `notarytool submit --wait` ile gönder, `stapler validate` ile doğrula
- [ ] Başka bir Mac'te (veya karantina özniteliği eklenmiş halde) açılışı test et

Madde 2 tamamlanınca bunu ben kurarım.

---

## 4. 🟡 Paddle hesabı

- [ ] Paddle satıcı hesabı başvurusu (onay süreci günler alabilir — erken başvur)
- [ ] **Önce doğrula:** Lemon Squeezy'nin Stripe'a taşınma durumu ve Paddle'ın Türkiye'den satıcı
      kabul koşulları güncel mi? (CLAUDE.md §11.1'de bu doğrulama notu var)
- [ ] Vergi/şahıs şirketi durumu: Paddle MoR olarak KDV'yi üstlenir, ama bizim gelir beyanımız
      yerel mevzuata tabi — muhasebeciye sor
- [ ] Ürün ve fiyat tanımları (geçici: 49 USD / 1 Mac, 79 USD / 3 Mac — §11.3)
- [ ] Lisans anahtarı üretim akışı (Paddle webhook → Ed25519 imzalı anahtar → e-posta)

---

## 5. 🟡 Sparkle EdDSA anahtar çifti — **projenin telafisi olmayan sırrı**

Bu anahtar kaybolursa mevcut kullanıcılara **bir daha güncelleme gönderemezsin** (CLAUDE.md R1).

- [ ] Sparkle'ın `generate_keys` aracıyla anahtar çifti üret (özel anahtar Keychain'e yazılır)
- [ ] Özel anahtarı dışa aktar ve **en az iki ayrı şifreli konumda** yedekle
      (parola yöneticisi + çevrimdışı şifreli yedek)
- [ ] Açık anahtarı not et — `Info.plist` içine `SUPublicEDKey` olarak girecek
- [ ] Yedeğin gerçekten geri yüklenebildiğini test et

> Bu maddeyi uygulama adı kesinleştikten sonra yap (anahtar ada bağlı değil ama appcast URL'i bağlı).

---

## 6. 🟡 Barındırma (Cloudflare)

- [ ] Cloudflare hesabı + R2 bucket'ı (`appcast.xml`, DMG'ler, imza veritabanı)
- [ ] Alan adını Cloudflare'e bağla, R2'yi özel alan adıyla yayınla
- [ ] `appcast.xml` ve imza DB için cache kuralları

---

## 7. 🟡 GitHub

- [ ] Depo oluştur (private başla), yerel depoyu bağla:

```bash
git remote add origin git@github.com:<kullanici>/<depo>.git && git push -u origin main
```

- [ ] Branch protection: `main`'e doğrudan push kapalı, CI geçmesi zorunlu
- [ ] Secret'lar (madde 2 bitince): `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`,
      `APPSTORE_API_KEY_P8`, `APPSTORE_API_KEY_ID`, `APPSTORE_API_ISSUER_ID`, `SPARKLE_PRIVATE_KEY`

---

## 8. 🟡 İkon konsepti

- [ ] Ada bağlı olduğu için A8'den sonra. CleanMyMac'in ikonuna benzemeyecek (§1).
- [ ] 1024×1024'ten 16×16'ya kadar okunabilirlik testi

---

## 9. ✅ Yerel araçlar

- [ ] SwiftLint kur (CI'da var, yerelde de gerekli):

```bash
brew install swiftlint
```

---

## Phase 1'e geçiş koşulu

| Koşul | Durum |
|---|---|
| A8 — uygulama adı kesin | 🟡 **bekliyor** |
| Geliştirme ortamı hazır | ✅ |
| CI iskeleti çalışıyor | ✅ |
| Spesifikasyon onaylı | ✅ |
| Developer ID + R8 testi | ⏸ Phase 1 ile paralel yürüyebilir, engel değil |

**Yani:** adı kararlaştır, Phase 1'e başlayabiliriz.
