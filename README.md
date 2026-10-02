# TouchRemap

**[Türkçe](#türkçe) · [English](#english)**

Use a USB touch monitor as a second display on macOS: touches land on the touch monitor itself (not on your
main display), and three/four-finger swipes work like on a trackpad.

---

## Türkçe

macOS, USB dokunmatik monitörleri tek noktalı bir fare gibi görür ve dokunuşları **ana ekrana** uygular.
TouchRemap dokunmatik kontrolcüyü kendisi okur, dokunuşları ait oldukları ekrana yönlendirir ve çoklu dokunma
hareketleri ekler.

### Özellikler
- **Port ile otomatik eşleme:** Tek USB-C kabloyla bağlı monitörlerde dokunmatik kontrolcü ile görüntü aynı
  fiziksel porttan gelir. TouchRemap bunu IORegistry'den bulur; birden fazla ekran olsa da doğru ekranı seçer.
- Elle ekran seçimi ve **Dokunarak Tanımla** (her ekranda bir hedef gösterilir, dokunduğunuz hedef ekranı belirler).
- Dokunma = tıklama, çift dokunma = çift tıklama, dokunup sürükleme = sürükleme.
- Uzun basma veya iki parmakla dokunma = sağ tıklama.
- İki parmakla kaydırma (atalet ile), isteğe bağlı kıstırarak yakınlaştırma.
- **3 veya 4 parmak** (isteğe bağlı yalnızca 4): sola/sağa = masaüstü (Space) değiştir, yukarı = Mission Control, aşağı = Uygulama Exposé.
- Her hareket ayarlardan açılıp kapatılabilir; kalibrasyon (eksen değiştir / çevir), canlı dokunma testi.
- Menü çubuğu uygulaması, oturum açılışında başlatma, Türkçe ve İngilizce arayüz.

### Test edilen donanım
| | |
|---|---|
| Monitör | [ARZOPA A1-T 15.6" Full HD IPS dokunmatik taşınabilir monitör](https://www.hepsiburada.com/arzopa-a1-t-15-6-30-ms-60hz-full-hd-ips-ultra-ince-dokunmatik-tasinabilir-monitor-p-HBCV00008P3L28) (1920×1080, 60 Hz) |
| Dokunmatik kontrolcü | ILITEK-TOUCH, USB `222A:0001`, 10 parmak (Windows tipi HID dijitalleştirici) |
| Bağlantı | Tek USB-C kablo (DisplayPort Alt Mode + USB) |
| Bilgisayar | MacBook Pro, Apple M4 Pro, macOS 26 |

Başka bir dokunmatik monitörde denediyseniz sonucu bir *issue* ile paylaşırsanız listeye ekleyebiliriz.

### Kurulum
1. [Releases](https://github.com/hasanbahadirkoca/macTouchScreen/releases/latest) sayfasından `.dmg` dosyasını
   indirin, **TouchRemap**'i *Uygulamalar* klasörüne sürükleyin.
2. Uygulama Apple tarafından notarize edilmediği için ilk açılışta macOS uyarı verir:
   *Sistem Ayarları › Gizlilik ve Güvenlik* altında **Yine de Aç**'a tıklayın veya Terminal'de:
   ```bash
   xattr -dr com.apple.quarantine /Applications/TouchRemap.app
   ```
3. Menü çubuğundaki el simgesinden **Ayarlar…** › **Genel**'e gidip iki izni verin:
   - **Giriş İzleme** — dokunmatik ekranı okumak için
   - **Erişilebilirlik** — tıklama, kaydırma ve kısayol göndermek için
4. **Cihazlar** sekmesinde dokunmatik ekranın doğru monitöre eşlendiğini ve *Dokunma testi* alanında
   parmaklarınızın göründüğünü kontrol edin.

> Uygulama ad-hoc imzalıdır. Güncellemeden sonra izinler çalışmazsa TouchRemap'i *Giriş İzleme* ve
> *Erişilebilirlik* listelerinden kaldırıp yeniden ekleyin.

> Sola/sağa kaydırma *Sistem Ayarları › Klavye › Klavye Kısayolları › Mission Control* altındaki
> ⌃← / ⌃→ kısayollarını kullanır; bunlar açık olmalı ve ekranda en az iki masaüstü bulunmalıdır.

### Kaynaktan derleme
```bash
swift test
scripts/bundle.sh 0.1.4
```
Sorun giderme için ham dokunma verisini görmek: `build/TouchRemap.app/Contents/MacOS/TouchRemap --dump`
(çalıştırdığınız uygulamanın — örn. Terminal — Giriş İzleme izni olmalı).

### Sürüm yayınlama
`v0.2.0` gibi bir etiket gönderildiğinde GitHub Actions testleri çalıştırır, `.dmg`/`.zip` üretir ve Release oluşturur:
```bash
git tag v0.2.0 && git push origin v0.2.0
```

---

## English

macOS treats USB touch monitors as a single-point mouse mapped to the **main display**. TouchRemap reads the touch
controller itself, sends each touch to the display it belongs to, and adds multi-touch gestures.

### Features
- **Automatic mapping by port:** with single-cable USB-C monitors the touch controller and the video share one
  physical port. TouchRemap finds that link in the IORegistry, so it picks the right display even with several monitors.
- Manual display selection and **Identify by Touch** (each display shows a target; the one you touch wins).
- Tap = click, double tap = double click, touch and drag = drag.
- Long press or two-finger tap = right click.
- Two-finger scrolling with momentum, optional pinch to zoom.
- **Three or four fingers** (optionally four only): left/right = switch Space, up = Mission Control, down = App Exposé.
- Every gesture can be toggled; calibration (swap/flip axes) and a live touch test.
- Menu bar app, open at login, English and Turkish UI.

### Tested hardware
| | |
|---|---|
| Monitor | [ARZOPA A1-T 15.6" Full HD IPS portable touch monitor](https://www.hepsiburada.com/arzopa-a1-t-15-6-30-ms-60hz-full-hd-ips-ultra-ince-dokunmatik-tasinabilir-monitor-p-HBCV00008P3L28) (1920×1080, 60 Hz) |
| Touch controller | ILITEK-TOUCH, USB `222A:0001`, 10 points (Windows-style HID digitizer) |
| Connection | Single USB-C cable (DisplayPort Alt Mode + USB) |
| Computer | MacBook Pro, Apple M4 Pro, macOS 26 |

If you try another touch monitor, please report the result in an issue so it can be added here.

### Install
1. Download the `.dmg` from [Releases](https://github.com/hasanbahadirkoca/macTouchScreen/releases/latest) and drag
   **TouchRemap** to *Applications*.
2. The app is not notarized, so macOS warns on first launch: click **Open Anyway** in
   *System Settings › Privacy & Security*, or run
   ```bash
   xattr -dr com.apple.quarantine /Applications/TouchRemap.app
   ```
3. From the menu bar hand icon open **Settings…** › **General** and grant **Input Monitoring** and **Accessibility**.
4. In **Devices**, check the touch screen is mapped to the right monitor and your fingers show up in the touch test.

> The app is ad-hoc signed. If permissions stop working after an update, remove TouchRemap from the
> *Input Monitoring* and *Accessibility* lists and add it again.

> Left/right swipes send ⌃← / ⌃→; keep them enabled in *System Settings › Keyboard › Keyboard Shortcuts ›
> Mission Control* and have at least two Spaces on the display.

### Build from source
```bash
swift test
scripts/bundle.sh 0.1.4
```

### How port matching works (Apple silicon)
```
touch controller → usb-drdN (USB controller of a Type-C port)
                   atcN-dpphy → AppleATCDPAltModePort.DisplayHints (EDID vendor/product of the monitor)
                   → CoreGraphics display with the same vendor/model(/serial)
```
If the port cannot be resolved (Intel Macs, docks, Thunderbolt tunnels, identical monitors) choose the display
manually or use Identify by Touch.

## License
MIT
