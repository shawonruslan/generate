# Wafid Desktop

wafid.com-এর জন্য আলাদা Windows ব্রাউজার। Center targeting, Auto Fill আর Live auto-assign monitor এর ভেতরেই আছে। কোনো Chrome extension লাগে না।

## GitHub Actions দিয়ে installer (.exe) বানানো

1. GitHub-এ একটা নতুন **Private** repository খুলুন (যেমন `wafid-desktop`)।
2. এই ফোল্ডারের সব ফাইল সেই repo-তে push করুন। `.github` ফোল্ডারটাও যেন যায়।
   ```powershell
   cd wafid-desktop
   git init
   git add .
   git commit -m "Wafid Desktop 1.0.0"
   git branch -M main
   git remote add origin https://github.com/<আপনার-username>/wafid-desktop.git
   git push -u origin main
   ```
3. push করলেই build শুরু হবে। repo-র **Actions** ট্যাবে গিয়ে **Build Windows installer** খুলুন। ৫ থেকে ৮ মিনিট লাগবে।
4. build শেষ হলে পেজের নিচে **Artifacts** অংশে `WafidDesktop-Setup` থাকবে। ডাউনলোড করে zip খুললে `WafidDesktop-Setup-1.0.0.exe` পাবেন।
5. নতুন ভার্সন: `package.json`-এ `version` বাড়ান, তারপর push করুন। চাইলে `git tag v1.0.1; git push --tags` দিলে exe-টা GitHub Releases-এও উঠে যাবে।

হাতে চালাতে চাইলে Actions ট্যাব থেকে **Run workflow** চাপুন।

## Windows যা বলতে পারে

installer-এ code-signing certificate নেই, তাই প্রথমবার "Windows protected your PC" আসতে পারে। তখন **More info** চাপুন, তারপর **Run anyway**।

## ব্যবহার

- অ্যাপ খুললেই Book Appointment পেজ আসে, ডান দিকে Wafid Assistant প্যানেল থাকে (Center / Auto Fill / Live)।
- **Live** মোড background-এ থাকলেও বা window minimize করা থাকলেও চলবে। টার্গেট সেন্টার এলে Windows notification আসবে আর taskbar জ্বলবে।
- টুলবারের ডান পাশে monitor-এর অবস্থা দেখায়, যেমন `SA live #6136 ...`। নিচের status bar-এ check-এর সংখ্যা আর পরের check কখন হবে, সেটা দেখায়।
- **Activity** (তরঙ্গের আইকন): সব ট্যাবের সেন্টার বদল, match, warning-এর তালিকা।
- **Settings** (গিয়ার আইকন):
  - *General:* home page, tab restore, notification, PC জাগিয়ে রাখা, always on top, zoom
  - *Profiles & proxy:* প্রতিটা profile আলাদা ব্রাউজার (আলাদা cookie/login), চাইলে আলাদা proxy। Test বোতাম দিয়ে proxy চেক করা যায়।
  - *Identity & privacy:* user agent, ভাষা, WebRTC leak protection, tracker block

## Shortcut

Ctrl+T নতুন ট্যাব · Ctrl+W বন্ধ · Ctrl+Tab ট্যাব বদল · F5 reload · Ctrl+L address bar · Ctrl +/- zoom · F12 dev tools

## ডাটা কোথায় থাকে

`%APPDATA%\Wafid Desktop\` ফোল্ডারে (Settings > General > App data folder > Open)। uninstall করলেও এগুলো মোছে না।

## লোকালি চালানো (দরকার হলে)

```powershell
npm install
npm start
```
