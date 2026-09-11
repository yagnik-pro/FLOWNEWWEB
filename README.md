# OTP Flow

**Receive · Manage · Stay Ahead**

Meesho seller na badha accounts na return-delivery OTP ek j screen par —
account-wise ane courier-wise. Koi server nahi, koi license key nahi, account limit nahi.
Badhu tamara phone ma j.

---

## Su chhe ema

| Feature | Vigat |
|---|---|
| **Fast API fetch** | Meesho na pot-ana API (`fetchDeliveryOTPs`) seedhu call kare — WebView nahi, etle 1-2 second ma badha accounts |
| **Multi-account** | Ketla pan accounts, koi limit nahi |
| **Account-wise / Courier-wise** | Be view — jem joiye tem |
| **Tap to copy** | OTP par tap = clipboard ma copy + haptic |
| **Auto re-login** | Session expire thay to jaate fari login kari OTP laave |
| **Bulk relogin** | Select all → Relogin — badha accounts ek sathe |
| **Auto-refresh** | 2/5/10/15/30/60 min — tamari marji |
| **Notifications** | Navo OTP aave etle turant push |
| **24/7 background** | App band hoy to pan refresh chalu rahe |
| **Store name auto** | Meesho mathi j store nu naam laave (SPARROW PRIME, Madhavv...) |
| **Diagnostics** | Settings ma "Raw API response" — kai atake to joi shakay |

Password ane OTP phone ni bahar **kyaay** nathi jata — koi server j nathi.

---

## APK banavvo (sauthi saralthi)

### Rasto 1 — GitHub Actions (PC par kai install karvani jarur nahi)

1. **GitHub par free account** banavo: https://github.com/signup
2. Navu **repository** banavo (Private rakhi shako) → "uploading an existing file" par click
3. Aa folder ni **badhi file** upload karo (`lib/`, `assets/`, `pubspec.yaml`, `.github/`, `android_overrides/`)
4. Repo ma **Actions** tab → `Build OTP Flow APK` → **Run workflow** dabaavo
5. 8-12 min ma build puru → **Artifacts** ma `OTPFlow-APK` download karo
6. Zip kholi `app-release.apk` phone ma install karo

### Rasto 2 — PC par Flutter thi

```bash
# Flutter install: https://docs.flutter.dev/get-started/install/windows
flutter create --platforms=android --org com.otpflow --project-name otpflow .
cp android_overrides/AndroidManifest.xml android/app/src/main/AndroidManifest.xml
flutter pub get
flutter build apk --release
# APK ahi banse: build/app/outputs/flutter-apk/app-release.apk
```

---

## Vaparvu

1. App kholo → **Accounts** tab
2. Meesho supplier **email + password** naakho → **Login** (2-3 second)
3. Badha accounts aa rite umero
4. **OTPs** tab → Account-wise / Courier-wise → OTP par tap = copy
5. **Settings** → auto-refresh 5 min, notifications on, 24/7 background on

Phone ma pehli vaar chalavo tyare Android **notification permission** ane
**battery optimization** ma OTP Flow ne "Unrestricted" karo — nahi to background
ma Android app ne suvadi de che.

---

## Kai atake to

**Login fail thay:** Meesho kyarek nava device thi login vakhte SMS-OTP maange.
Ek vaar phone na browser ma supplier.meesho.com ma login kari lo, pachhi app ma
Relogin dabaavo.

**OTP na aave pan login thai jay:** Settings → **Raw API response** kholo → copy
kari mane moklo. Meesho e response nu format badlyu hoy to `lib/services/meesho_api.dart`
ma `parseOtps()` ni key list ma nava naam umerva pade — 2 minute nu kaam.

**Background ma refresh atke:** Phone na Settings → Apps → OTP Flow → Battery →
**Unrestricted** karo.

---

## API endpoints (reference)

```
POST /api/container/user/v2-login                  → login (email + password)
GET  /api/container/supplier/getSupplierDetails    → store name, supplier id
POST /api/fulfillment/returnRto/fetchDeliveryOTPs  → return OTPs
POST /api/payouts/payments/all-ui-data2            → payments
```

Cookies `cookie_jar` thi phone ma save thay chhe — dar vakhte login karvani jarur nahi.

---

## Dhyan rakhjo

Supplier panel ne automate karvu Meesho na Terms of Service virudh hoi shake chhe.
Aa app khali tamara **pot-ana** accounts mate chhe. Tamari jawabdari par vaparo.
