Gradey 2.9 brings Gradey for Web.

## What's new

- **Gradey for Web:** open Gradey in your computer's browser and sign in by scanning a QR code with your iPhone. Your school password never leaves your phone.
- **Linked devices:** a new page in Settings lists every browser you've signed in to, with when it was first and last used. Sign out one browser or all of them at once.
- **Christmas in Gradey:** from 29 November to Christmas Eve, Gradey turns red, snow falls on Today, and a countdown shows how many days are left until Christmas Eve.

## Co je nového (App Store, česky)

- **Gradey pro web:** otevři Gradey v prohlížeči na počítači a přihlas se naskenováním QR kódu iPhonem. Heslo do školy z telefonu nikam neodchází.
- **Propojená zařízení:** nová stránka v Nastavení ukazuje všechny prohlížeče s přihlášeným Gradey i to, kdy byly poprvé a naposledy použité. Můžeš odhlásit jeden prohlížeč nebo všechny najednou.
- **Vánoce v Gradey:** od 29. listopadu do Štědrého dne se Gradey zbarví do červena, na obrazovce Dnes padá sníh a odpočet ukazuje, kolik dní zbývá do Štědrého dne.

## What's new on Mac (App Store)

- **Linked devices:** a new page in Settings lists the browsers signed in to Gradey for Web and lets you sign them out. You link a new browser from Gradey on iPhone.
- **Christmas in Gradey:** from 29 November to Christmas Eve, Gradey turns red, snow falls on Today, and a countdown shows how many days are left until Christmas Eve.
- **Gradey AI is taking a break:** it's moving to a new provider and will be back in a later update.

## Co je nového na Macu (App Store, česky)

- **Propojená zařízení:** nová stránka v Nastavení ukazuje prohlížeče přihlášené do Gradey pro web a umožňuje je odhlásit. Nový prohlížeč propojíš z Gradey na iPhonu.
- **Vánoce v Gradey:** od 29. listopadu do Štědrého dne se Gradey zbarví do červena, na obrazovce Dnes padá sníh a odpočet ukazuje, kolik dní zbývá do Štědrého dne.
- **Gradey AI má pauzu:** přesouvá se k novému poskytovateli a vrátí se v některé z dalších aktualizací.

## Before release

- Linking needs the `web-linked-devices` Edge Function and the `20261125183000_gradey_web_device_linking` migration on production Supabase, plus a hosted Gradey for Web (see `Docs/GradeyForWeb.md`). Without them, Settings → Linked devices shows an error and there's no QR code to scan.
- iOS 2.8.3 (1) was uploaded on 25 November; Mac 2.8.3 (46) was not, so Mac goes straight from 2.8.2 to 2.9. Drop the Christmas line from the iPhone notes if 2.8.3 is released first.

## Builds

- iPhone, iPad, and Apple Watch: **2.9 (1)**.
- Mac and Mac widgets: **2.9 (47)**.
