# Zásady ochrany soukromí

**Zveřejněno: 5. listopadu 2026. Účinnost: 5. listopadu 2026.**

Tato revize popisuje rozvrhy kamarádů, taneční v TŠ Vavruška a domácí úkoly, zprávy z Komensu a vysvědčení z Bakalářů (Gradey 2.7). Zachovává popis změn v Gradey 2.1 a přechodu ze starších verzí aplikace. Výmaz hesel z aktivní databáze popsaný níže byl dokončen 8. září 2026.

Tyto Zásady ochrany soukromí vysvětlují, jak **Open Side**, které provozuje **Filip Bukovina** („my“, „nás“), zpracovává osobní údaje prostřednictvím aplikace **Gradey** a souvisejících služeb.

Gradey je neoficiální klient školních systémů pro studenty a rodiče. Je dostupný na podporovaných zařízeních Apple, včetně iPhonu, iPadu, Apple Watch a Macu, spolu s widgety. Gradey je nezávislý na systémech Bakaláři, EduPage a Strava.cz i na TŠ Vavruška; tyto organizace aplikaci neprovozují ani nedoporučují.

## 1. Kdo je správcem

Správcem je **Filip Bukovina**, který Gradey vydává pod označením **OpenSide** na [openside.tech](https://openside.tech).

- Žádosti týkající se ochrany soukromí: **filip@openside.tech**
- Další kontakt: **tom@openside.tech**

## 2. Na co se tyto zásady vztahují

Tyto zásady se vztahují na Gradey ID, připojené školní účty a účty jídelen, funkce se školními daty, rozvrhy kamarádů, volitelné propojení s tanečními, Apple Watch a widgety, osobní Plánovač a volitelný export do Kalendáře, Gradey AI, podporu, nákupy a oznámení.

Nenahrazují zásady vaší školy, oficiálních školních systémů a systémů jídelen ani služeb, které používáte nezávisle na Gradey.

## 3. Jaké údaje zpracováváme

### 3.1 Gradey ID

Gradey ID používá Přihlášení přes Apple (Sign in with Apple). Podle vašich voleb a toho, co Apple poskytne, dostaneme identifikátor účtu, vaše jméno a e-mailovou adresu nebo soukromou přeposílací adresu od Applu.

Náš backend pro účty, provozovaný službou Supabase, ukládá váš účet Gradey, záznamy o propojených účtech a předvolby. Slouží pro nastavení účtu, export údajů a smazání účtu.

### 3.2 Účty Bakaláři a hesla

**V Gradey 2.1 a novějších se při přihlášení ke škole, propojení ani opětovném připojení vaše heslo do Bakalářů na backend Gradey nenahrává.** Starším verzím se věnuje odstavec níže.

Při přímém přihlášení ke škole odešle vaše zařízení školní uživatelské jméno a heslo na HTTPS server vaší školy. Gradey tyto přihlašovací údaje uchovává v Klíčence (Keychain) zařízení, aby se mohl ke škole v případě potřeby znovu přímo přihlásit. Platí také chování Apple Watch popsané v oddílu 3.4.

Když účet Bakaláři propojíte s Gradey ID, náš backend zpracovává:

- adresu serveru vaší školy;
- vaše uživatelské jméno, identifikátory účtu a zobrazované údaje, například vaše jméno a název školy;
- přístupové a obnovovací tokeny školní relace a související údaje o jejich platnosti;
- školní údaje používané pro cloudové funkce popsané níže.

Gradey 2.1 zakládá pro kontrolu nových známek na pozadí samostatnou relaci se školními tokeny. **Tokeny relace jsou citlivé údaje: dokud platí, mohou umožnit přístup k vašim školním údajům.** Tokeny relací uložené na backendu šifrujeme. Naše služba na pozadí je používá ke kontrole nových známek; kde je to podporováno, může přístup obnovit obnovovací token. Uloženým školním heslem se nepřihlašuje.

Pokud relace na pozadí přestane fungovat, připojte školní účet v Gradey znovu. Zařízení bez vlastní místní školní relace se také musí ke škole přihlásit.

**Přechod ze starších verzí:** Starší nainstalované verze aplikace mohou během zavádění změny stále odeslat heslo v požadavku na propojení nebo opětovné připojení školy. Od 8. září 2026 zápisy do databáze odstraňují pole s heslem ještě před uložením šifrovaných záznamů poskytovatele. Tato ochrana uložení neznamená, že starší aplikace nikdy heslo na backend neodešle. Abyste se tomuto staršímu přenosu vyhnuli, aktualizujte před propojením nebo opětovným připojením na Gradey 2.1 nebo novější. Historické záznamy hesel a omezení záloh popisuje oddíl 7.

Připojujte jen účty, které jste oprávněni používat. Tato ochrana se týká požadavků na přihlášení ke škole; hesla nevkládejte do chatů s AI, zpráv podpoře ani příloh, kde by se stala součástí odeslaného obsahu.

### 3.3 Další připojené účty a školní údaje

U EduPage Gradey k přihlášení používá přihlašovací údaje uložené v zařízení. Backend dostává identifikátory relace, uživatelské jméno, autentizační hashe a údaje o studentovi a předmětech potřebné pro podporované funkce, bez hesla do EduPage.

U Strava.cz Gradey používá k přihlášení do jídelny přihlašovací údaje uložené v zařízení. Údaje o propojeném účtu odesílané na náš backend zahrnují identifikátory relace, služby, jídelny a účtu, bez hesla.

Podle vaší školy a funkcí, které používáte, Gradey zpracovává jména, údaje o třídě, známky, předměty, absenci, rozvrhy, domácí úkoly, zprávy a příspěvky z nástěnky v Komensu včetně příloh, vysvědčení, údaje o učitelích a učebnách a údaje o jídelně nebo obědech.

Rozvrh, absenci, domácí úkoly, Komens a vysvědčení stahuje přímo zařízení. Když v Gradey označíte úkol jako hotový nebo otevřete nepřečtenou zprávu z Komensu, zařízení tento stav pošle na server vaší školy, stejně jako oficiální aplikace. Zprávy z Komensu a vysvědčení zůstávají ve vašem zařízení; neposílají se na backend Gradey ani do Gradey AI a odhad vysvědčení se počítá přímo v zařízení. Cloudové kontroly na pozadí stahují známky a vedou související historii známek a oznámení. Školní údaje se mohou objevit také v místních mezipamětech, widgetech a na Apple Watch, nebo být součástí volitelného kontextu Gradey AI, jak je popsáno níže.

### 3.4 Apple Watch a widgety

iPhone může do spárovaných Apple Watch přenést školní údaje a přihlašovací informace, včetně školních přihlašovacích údajů, aby hodinky mohly obnovovat data přímo ze školy. Hodinky proto mohou mít vlastní místní kopii vašeho školního hesla a tokenů relace.

Widgety používají místně sdílená data k zobrazení podporovaných funkcí. Chraňte kódy svých zařízení a před předáním zařízení jiné osobě se odhlaste nebo hodinky odpárujte.

### 3.5 Gradey AI

Gradey AI je volitelná a žádá o samostatný souhlas v aplikaci. K zobrazení známek, rozvrhu ani absence AI potřeba není.

Když ji používáte, zpracováváme vaše zprávy a historii dané konverzace. Obecný chat k nim vaše školní údaje automaticky nepřikládá. Můžete vybrat předmět, týden, studijní priority nebo konkrétní test; sdílí se jen vybrané souhrny prospěchu, nedávné známky, hodiny a odpovídající názvy a termíny z Plánovače. Poznámky z Plánovače se vynechávají, pokud výslovně nezvolíte zahrnutí poznámek k vybranému testu. Přihlašovací údaje, adresy škol, jména učitelů a identifikátory Kalendáře jsou z tohoto automaticky vybraného kontextu vyloučené.

Vybrané informace se posílají přes náš backend pro AI, provozovaný v Google Firebase, do Microsoft Azure OpenAI, který vytvoří odpověď. Vybraný kontext si můžete před odesláním prohlédnout. Místní výpočty, simulace a postřehy na Dnes AI nevyžadují a svůj obsah poskytovateli AI nesdílejí. Podstatná změna zpracovatele AI vyžaduje nový souhlas s AI v aplikaci.

Zpracování související s AI zahrnuje také autentizační identifikátory, stav souhlasu, údaje o požadavcích a využití a ověřený stav předplatného tam, kde je potřeba pro uplatnění denních limitů Compute. Krátkodobý přístupový token Gradey ID ověřuje backend, aby propojil využití napříč zařízeními; nevkládá se do promptů modelu ani se neukládá do evidence Compute. Ověření nároků přes RevenueCat určuje příslušný limit služby. Účetní záznamy obsahují identifikátory požadavků, ceny, rezervace, výsledky vyúčtování a náklady poskytovatele, bez ukládání dalšího archivu školního kontextu pro obnovu. Konverzace se mohou uchovávat, abyste se k nim mohli vrátit. Použijte dostupné možnosti mazání konverzací a nastavení souhlasu, nebo nás o odstranění požádejte.

Odesílejte jen informace, které jste oprávněni sdílet. Odpovědi AI mohou být nepřesné. Odvolání souhlasu s AI samo o sobě vaše Gradey ID nesmaže.

### 3.6 Podpora v aplikaci

Gradey na podporovaných platformách používá pro podporu službu Intercom. Po kroku s potvrzením věku v aplikaci se může ještě předtím, než napíšete, založit neidentifikovaná relace podpory. „Neidentifikovaná“ neznamená, že se nezpracovávají žádné technické údaje.

Pokud kontaktujete podporu, Intercom a my můžeme zpracovávat vaše zprávy, kontaktní údaje, které uvedete, technické údaje o zařízení a aplikaci a přílohy, které se rozhodnete poslat. Přístup k fotoaparátu, mikrofonu nebo fotkám je volitelný a závisí na vybrané příloze. Podpoře můžete psát i bez udělení těchto oprávnění.

### 3.7 Nákupy

Platby za spropitné a předplatné podpory zpracovává Apple. RevenueCat zpracovává údaje o nákupech a nárocích, aby Gradey poznal stav podpory a uplatnil odpovídající výhody nebo limity využití.

Prostřednictvím těchto nákupů nedostáváme úplné údaje o vaší platební kartě ani heslo k Apple ID. Na nákupy a správu předplatného se vztahují také podmínky Applu.

### 3.8 Oznámení

Pokud povolíte push oznámení, náš backend zpracovává token zařízení pro push oznámení, údaje o registraci zařízení a vaše předvolby oznámení. Díky nim můžeme posílat například upozornění na novou známku. Co se zobrazí na zamčené obrazovce, závisí na zvoleném nastavení podrobností.

Předvolby oznámení můžete změnit v Gradey a v nastavení systému. Vypnutí oznámení v nastavení systému určuje, co zařízení zobrazí; neznamená nutně okamžité smazání tokenu na backendu. Ani odinstalování aplikace není žádostí o smazání účtu.

### 3.9 Provozní a bezpečnostní údaje

Gradey používá autentizaci Firebase, backendové funkce a App Check k zajištění přístupu k AI a ochraně požadavků. Naši poskytovatelé hostingu a služeb mohou zpracovávat technické údaje o připojení, údaje o aplikaci a zařízení, časy požadavků, chyby a bezpečnostní signály, aby službu provozovali a chránili.

Vaše osobní údaje neprodáváme a v Gradey nepoužíváme reklamní sítě třetích stran.

### 3.10 Osobní Plánovač a Kalendář

Osobní položky Plánovače, včetně názvů, poznámek, termínů a souvisejících nastavení, ukládá Gradey místně. Funkce Plánovače je na backend Gradey nenahrává. Pokud zvolíte kontextovou AI, mohou se vybraná pole Plánovače sdílet, jak popisuje oddíl 3.5. Volitelné denní připomínky Plánovače se plánují místně v tomto zařízení a respektují oprávnění k oznámením, tichý režim a nastavení soukromí na zamčené obrazovce. Když je aplikace zavřená, nové školní informace nezjišťují.

Pokud zapnete export do Kalendáře, Gradey požádá o oprávnění vytvářet a spravovat své události v Kalendáři Apple. Může přistupovat ke stávajícím informacím v Kalendáři, které potřebuje k nalezení, úpravě nebo odstranění těchto událostí. Exportované informace se mohou synchronizovat přes kalendářový účet, který používáte, například iCloud nebo jiného poskytovatele, podle jeho nastavení a zásad.

Plánovač můžete používat i bez přístupu ke Kalendáři. Osobní položky Plánovače se ukládají odděleně od školních mezipamětí a při odpojení školního účtu se automaticky nemažou. Domácí úkoly, které Plánovač zobrazuje ze školy, pocházejí ze školních dat popsaných v oddílu 3.3; neukládají se jako osobní položky Plánovače.

### 3.11 Rozvrhy kamarádů

Gradey umí vedle vašeho rozvrhu zobrazit rozvrh kamaráda, partnera nebo spolužáka. U každého si vyberete, jak ho přidáte:

- **Jeho přihlášení do Bakalářů.** Kamarád zadá své uživatelské jméno a heslo na vašem zařízení. Zařízení je pošle na HTTPS server jeho školy a přihlašovací údaje i výslednou školní relaci uloží do Klíčenky tohoto zařízení, vázané na toto zařízení, aby Gradey mohl rozvrh znovu načíst, až relace vyprší. Gradey toto přihlášení používá jen k načtení rozvrhu, nikdy ke známkám, absenci ani zprávám.
- **Veřejný rozvrh školy.** Pokud škola rozvrh zveřejňuje, Gradey stáhne vybranou třídu ze serveru školy. Přihlášení není potřeba.
- **PDF nebo fotka.** Gradey soubor přečte přímo v zařízení, z textu v PDF nebo u fotek pomocí rozpoznávání textu od Applu, které běží v zařízení. Soubor se nikam nenahrává. Výsledek můžete před uložením zkontrolovat a opravit.

Jména kamarádů, odkud jejich rozvrh pochází, a samotné rozvrhy se ukládají jen do vašeho zařízení. Neposílají se na backend Gradey, do Gradey AI, do Apple Watch ani do widgetů.

Přidávejte jen lidi, kteří s tím souhlasí, a používejte jen přihlášení, které sami zadali do vašeho zařízení. Přihlášení do Bakalářů dává přístup k celému jejich školnímu účtu na serveru školy, i když ho Gradey používá jen pro rozvrh; kamarád ho může kdykoli zrušit změnou hesla. Odebráním kamaráda v Nastavení se jeho uložené přihlášení i rozvrh z vašeho zařízení smažou a odhlášením z Gradey se odeberou všichni kamarádi.

### 3.12 Taneční (TŠ Vavruška)

Gradey může volitelně propojit kurz tanečních pro mládež v TŠ Vavruška. Zadáte heslo z kartičky kurzu a zařízení ho pošle přes HTTPS na vavruska.info, aby našlo váš kurz. Gradey toto heslo neukládá. Do Klíčenky tohoto zařízení uloží váš kurz a soukromý odkaz na kalendář kurzu, protože odkaz funguje i bez hesla.

Termíny lekcí, příspěvky z nástěnky a začátky prodeje vstupenek se stahují z vavruska.info a ukládají do mezipaměti v zařízení. Připomínky začátku prodeje vstupenek se plánují přímo v zařízení. Nic z toho se neposílá na backend Gradey. Odpojením kurzu v Nastavení se z vašeho zařízení odstraní kurz, jeho data v mezipaměti i připomínky.

## 4. Proč údaje zpracováváme

Osobní údaje používáme k poskytování funkcí, o které požádáte, ke správě vašeho účtu, ke stahování školních informací, k doručování oznámení, k podpoře, k rozpoznání nákupů a k ochraně služby.

Podle GDPR závisí právní základ na konkrétním zpracování:

- **Smlouva – čl. 6 odst. 1 písm. b):** zpracování nezbytné k poskytování požadovaných služeb týkajících se účtu, školy, oznámení, podpory a nákupů.
- **Oprávněný zájem – čl. 6 odst. 1 písm. f):** nezbytné a přiměřené zabezpečení, prevence zneužití a provozní diagnostika s ohledem na vaše práva a zájmy.
- **Souhlas – čl. 6 odst. 1 písm. a):** volitelná Gradey AI a další volitelné zpracování tam, kde se o souhlas žádá a kde je vyžadován. Souhlas můžete odvolat, aniž by to ovlivnilo zákonnost dřívějšího zpracování.
- **Právní povinnost – čl. 6 odst. 1 písm. c):** zpracování vyžadované platnými právními předpisy.

Oprávnění zařízení řídí přístup k funkcím, jako je Kalendář, fotky nebo mikrofon. Udělení oprávnění zařízení ale samo nečiní každé použití získaných informací zákonným. Více o těchto právních základech najdete na stránkách [Evropské komise](https://commission.europa.eu/law/law-topic/data-protection/information-business-and-organisations/legal-grounds-processing-data_cs).

## 5. Kdo údaje dostává

Podle funkcí, které používáte, mezi příjemce patří:

- **Open Side / Filip Bukovina:** provoz Gradey a jeho služeb.
- **Apple:** přihlášení, platby, oznámení, služby zařízení a cloudové služby Apple, které používáte.
- **Supabase:** Gradey ID, propojené účty, šifrované tokeny relací a push oznámení, předvolby a školní údaje používané pro známky na pozadí, historii a oznámení.
- **Google Firebase:** přihlášení k AI, zpracování na backendu, konverzace, záznamy o využití a souhlasu a zabezpečení požadavků.
- **Microsoft Azure OpenAI:** zprávy a výslovně vybraný kontext potřebný k vytvoření odpovědí.
- **Intercom:** relace podpory, zprávy, přílohy a související technické údaje.
- **RevenueCat:** zpracování nákupů a nároků.
- **Vaše škola, školy vašich kamarádů, vaše jídelna, TŠ Vavruška a váš poskytovatel kalendáře:** údaje potřebné pro připojení a akce, o které požádáte.

Poskytovatelé mohou podle činnosti vystupovat jako naši zpracovatelé, nebo jako samostatní správci svých vlastních služeb. Údaje můžeme zpřístupnit také tam, kde to vyžaduje zákon nebo kde je to nezbytné k určení, výkonu nebo obhajobě právních nároků.

## 6. Předávání do zahraničí

Někteří poskytovatelé působí mimo Evropský hospodářský prostor nebo mohou k údajům přistupovat z jiných zemí. Kde GDPR vyžaduje záruky pro předávání, musí být předání kryto rozhodnutím o odpovídající ochraně nebo vhodnými zárukami, například standardními smluvními doložkami Evropské komise.

Informace o zárukách, které se vztahují na vaše údaje, získáte na **filip@openside.tech**.

## 7. Uchovávání a mazání

Záznamy o účtu, informace o propojených účtech a související údaje služby uchováváme, dokud jsou potřeba k poskytování služby nebo ke splnění příslušného právního požadavku. Doba uchování závisí na účelu záznamu, na tom, zda je váš účet nebo připojení stále aktivní, na nevyřešených záležitostech podpory nebo zabezpečení a na případné zákonné povinnosti záznam uchovat.

Propojené účty můžete odpojit, vyžádat si export a smazat Gradey ID pomocí dostupných nastavení účtu. Smazáním Gradey ID se jeho účet a související záznamy odstraní z našeho aktivního backendu Gradey ID. Nesmaže se tím účet, který vede vaše škola, jídelna, Apple nebo jiná nezávislá služba.

Konverzace s AI, záznamy podpory a záznamy o nákupech mohou být v samostatných systémech. Použijte jejich možnosti mazání, nebo nás kontaktujte se žádostí, která se těchto záznamů týká. Omezené informace si můžeme ponechat, pokud je to nezbytné kvůli právní povinnosti, bezpečnostní záležitosti nebo právnímu nároku.

**Historická hesla do Bakalářů:** Dřívější verze nahrávaly hesla na náš backend. Dne **8. září 2026** jsme z aktivní databáze backendu odstranili pole s hesly a ověřili, že v jejích šifrovaných záznamech poskytovatelů žádné nezůstalo. Zápisy do databáze nyní pole s heslem před uložením odstraňují.

Historické zálohy a protokoly služeb jsou oddělené od aktivní databáze. Mohou uchovávat starší kopie podle plánu uchovávání příslušného systému a případné zákonné povinnosti. Výmaz z 8. září neověřil ani nesmazal každou historickou zálohu, protokol nebo export, a nelze ho proto chápat jako potvrzení, že k tomuto datu byly smazány všechny historické kopie. Informace o konkrétním záznamu, jeho uchovávání nebo žádost o výmaz vyřídíme na **filip@openside.tech**.

Data v zařízení a exporty do Kalendáře jsou oddělené od záznamů na backendu. Odhlášením se vymaže příslušná školní relace a odeberou se přihlášení a rozvrhy kamarádů, osobní data Plánovače ale mohou zůstat. Smazání aplikace nezaručuje odstranění každé položky Klíčenky, cloudového záznamu, kopie v hodinkách nebo exportované události v Kalendáři. Tyto záznamy spravujte v příslušné aplikaci, zařízení nebo službě.

## 8. Děti a oprávnění ke školním účtům

Gradey zpracovává školní informace, které se mohou týkat dětí. Připojte jen účet, který jste oprávněni používat, ať už jako student, rodič, zákonný zástupce nebo jiná oprávněná osoba.

Aplikace žádá uživatele o výběr věkové skupiny. Uživatelé mladší 16 let, včetně mladších 13 let, jsou před pokračováním požádáni o potvrzení souhlasu rodiče nebo zákonného zástupce. Jde o prohlášení uložené v zařízení; kontrola věku nezjišťuje celé datum narození ani neověřuje totožnost zákonného zástupce.

Kde je pro určité použití nebo zpracování na základě souhlasu ze zákona vyžadován souhlas rodičů, musí být tento souhlas získán. Pokud se domníváte, že se údaje dítěte zpracovávají bez potřebného souhlasu, kontaktujte nás, abychom mohli přístup a případnou žádost o výmaz posoudit.

## 9. Vaše práva

Za příslušných podmínek a s výjimkami patří mezi práva podle GDPR přístup, oprava, výmaz, omezení zpracování, námitka a přenositelnost údajů. Souhlas se zpracováním založeným na souhlasu můžete odvolat a můžete podat stížnost u dozorového úřadu. Práva se vztahují také na některá rozhodnutí založená výhradně na automatizovaném zpracování. Viz [vysvětlení práv jednotlivců od Evropské komise](https://commission.europa.eu/law/law-topic/data-protection/information-individuals_cs).

Použijte dostupný export a mazání v aplikaci, nebo napište na **filip@openside.tech**. Můžeme si vyžádat informace potřebné k ověření, že jste k žádosti oprávněni.

Oficiální školní záznamy zůstávají pod kontrolou školy nebo provozovatele školního systému. Gradey sám oficiální záznam školy opravit nemůže; s takovými opravami se obracejte na školu.

## 10. Zabezpečení

Mezi bezpečnostní opatření patří spojení přes HTTPS, ukládání do Klíčenky zařízení, šifrování tokenů relací uložených na backendu, řízení přístupu k backendu a App Check pro chráněné požadavky.

Místní záznamy školních relací v Klíčence, včetně přihlášení kamarádů a odkazu na kalendář tanečních, jsou nastavené pro zařízení, které je ukládá, a nesynchronizují se přes Klíčenku mezi zařízeními. Přenos do spárovaných Apple Watch probíhá zvlášť, jak je popsáno výše.

Žádný systém nemůže zaručit absolutní bezpečnost. Chraňte své Gradey ID, školní účet a kódy zařízení. Tokeny pro přístup ke škole je potřeba chránit, i když se heslo na Gradey nenahrává.

## 11. Změny těchto zásad

Tyto zásady můžeme upravit, když se změní aplikace, zpracování údajů nebo platné požadavky. Aktuální verzi označuje datum účinnosti a o podstatných změnách vás tam, kde je to vhodné, informujeme v aplikaci nebo v centru nápovědy.

Zásady jsou k dispozici [anglicky](https://help.bukovinafilip.com/en/articles/10-privacy-policy) a [česky](https://help.bukovinafilip.com/cs/articles/10-privacy-policy).

## 12. Kontakt a stížnosti

Žádosti týkající se ochrany soukromí: **filip@openside.tech**. Další kontakt: **tom@openside.tech**.

Stížnost můžete podat u **Úřadu pro ochranu osobních údajů (ÚOOÚ)**, Pplk. Sochora 27, 170 00 Praha 7. Aktuální kontaktní údaje najdete na [webu ÚOOÚ](https://uoou.gov.cz/kontakt). Můžete se obrátit také na příslušný dozorový úřad v zemi svého bydliště, místa výkonu práce nebo místa údajného porušení.
