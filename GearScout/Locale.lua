-- GearScout / Locale.lua
-- Optional translation of GearScout's OWN text. Loaded second, right after
-- Core.lua, because every file below it captures ns.L when it loads.
--
-- The scheme: the English sentence IS the key.
--
--   L["Nothing to fix. Gear is clean."]
--
-- Nothing has to be invented, nothing has to be kept in sync, and a string
-- that has no translation yet renders as the English it already was. A
-- half finished language therefore reads as a mix of Swedish and English
-- rather than as a screen full of MISSING_KEY_47, which is the failure mode
-- that makes people turn a translation off again. It also means a key that
-- is identical in both languages is simply left out of the table below
-- rather than repeated into it.
--
-- What is deliberately NOT translated, anywhere:
--   * Item names, spell names, enchant names, faction names, zone and
--     dungeon names. They arrive from the client already in whatever language
--     the player installed, and replacing them would break both the tooltip
--     and every lookup keyed on them. A player hunting for Scarlet Monastery
--     on their own map has to read the same words GearScout used.
--   * Class names, stat names, armor weights, equipment slot names. Swedish
--     players say warrior, agility, plate, cloak and main hand, in English,
--     and translating them would also drag Swedish gender agreement into
--     every sentence that names one ("din" against "ditt"), which is exactly
--     how a machine translated addon starts sounding wrong.
--   * Slash command keywords. /gearscout scan stays /gearscout scan in every
--     language, because a command that moves breaks every macro, note and
--     forum post that ever mentioned it. Only the output moves.
--   * ns.PrintRotationDebug, which is a diagnostic. A bug report is easier to
--     read when the diagnostic in it is in one language.
--
-- Format strings keep their argument ORDER between languages on purpose.
-- Positional specifiers such as %1$s exist in this client but not in plain
-- Lua, so translations are written to fit the arguments as they are passed.

local ADDON, ns = ...

local type, pairs, setmetatable = type, pairs, setmetatable

-- Offered in the settings tab, in this order. A language name is written in
-- its own language and is never translated, which is how every language
-- picker works. Adding a language means adding a row here and a table below,
-- and nothing else.
ns.LOCALE_OPTIONS = {
    { value = "enUS", text = "English" },
    { value = "svSE", text = "Svenska" },
}

-- [locale] = { [English source text] = translated text }
-- enUS has no table at all: English is the source, so it is what every lookup
-- already falls back to.
local translations = {}
ns.translations = translations

-- ---------------------------------------------------------------------------
-- svSE
--
-- Written as spoken Swedish, not word for word. GearScout's whole voice is
-- plain language a first time player understands, and that has to survive the
-- translation, so a sentence is rebuilt where a literal one would read like a
-- manual. Game jargon every Swedish player already says in English is left in
-- English: buff, gear, item level, enchant, socket, gem, slot, tank, heal,
-- drop, pull, cast, quest, mount, pet, vendor, auction house, soulbound, and
-- every class, stat, armor weight and equipment slot name.
--
-- Sentences that name an equipment slot are built around it rather than in
-- front of it, "Foremalet pa main hand" rather than "Ditt main hand", because
-- an English noun has no Swedish gender and the possessive would have to
-- guess between din and ditt.
-- ---------------------------------------------------------------------------
translations.svSE = {

    -- -----------------------------------------------------------------------
    -- settings tab, tab names, chips, headings, buttons, empty states
    -- -----------------------------------------------------------------------
    ["LANGUAGE"]                    = "SPRÅK",
    ["Language"]                    = "Språk",
    ["Translates GearScout's own text. Item names, enchant names and everything else the game itself supplies stay in your game client's language."] =
        "Översätter GearScouts egen text. Föremålsnamn, enchant-namn och allt annat som spelet självt levererar står kvar på spelklientens språk.",
    ["PRIVACY"]                     = "INTEGRITET",
    ["BEHAVIOUR"]                   = "BETEENDE",
    ["PEOPLE YOU ALWAYS SHARE WITH"] = "PERSONER DU ALLTID DELAR MED",
    ["GearScout only ever sends your own gear, and only when someone asks for it. You never receive anyone else's gear: the code that displays other players lives in a separate addon that raid leads install."] =
        "GearScout skickar bara ditt eget gear, och bara när någon frågar efter det. Du tar aldrig emot någon annans gear: koden som visar andra spelare ligger i ett separat addon som raidledare installerar.",
    ["Answer gear requests from"]   = "Svara på gear-förfrågningar från",
    ["Group leader and assistants"] = "Gruppledare och assistenter",
    ["Anyone in my guild"]          = "Alla i mitt guild",
    ["Anyone who asks"]             = "Alla som frågar",
    ["Nobody, decline every request"] = "Ingen, neka alla förfrågningar",
    ["Include a rotation summary in my reply"] = "Skicka med en rotationssammanfattning i svaret",
    ["Scan automatically when gear changes"]   = "Skanna om automatiskt när gear ändras",
    ["Add GearScout lines to item tooltips"]   = "Lägg till GearScout-rader i item-tooltips",
    ["Show the minimap button"]     = "Visa minimap-knappen",
    ["How far under your median counts as a weak link"] =
        "Hur långt under din median som räknas som en svag länk",
    ["Strict, 6 item levels"]       = "Strikt, 6 item levels",
    ["Relaxed, 20 item levels"]     = "Tillåtande, 20 item levels",
    ["Nobody yet. When someone asks for your gear you can tick the box on that prompt to stop being asked again, and their name will appear here."] =
        "Ingen än. När någon frågar efter ditt gear kan du kryssa i rutan i den frågan för att slippa bli tillfrågad igen, och då dyker deras namn upp här.",
    ["1 name: %s. This player gets your gear without being asked each time."] =
        "1 namn: %s. Den spelaren får ditt gear utan att du blir tillfrågad varje gång.",
    ["%d names: %s. These players get your gear without being asked each time."] =
        "%d namn: %s. De spelarna får ditt gear utan att du blir tillfrågad varje gång.",
    ["Forget them all"]             = "Glöm allihop",
    ["Removes every saved name, so the next request from anyone prompts you again."] =
        "Tar bort alla sparade namn, så nästa förfrågan från vem som helst frågar dig igen.",
    ["Cleared. Everyone will be asked again from now on."] =
        "Rensat. Alla kommer att bli tillfrågade igen från och med nu.",

    ["Upgrades"]                    = "Uppgraderingar",
    ["Settings"]                    = "Inställningar",
    ["Rescan"]                      = "Skanna om",
    ["Read your equipment again right now."] = "Läs av din utrustning igen på en gång.",

    -- Chip captions. The code uppercases these, and Lua uppercases bytes
    -- rather than characters, so a chip caption is deliberately written
    -- without a, o or a-ring diacritics: they would survive :upper() as
    -- lowercase letters in the middle of a capitalised word.
    ["Average item level"]          = "Snitt item level",
    ["Missing enchants"]            = "Saknade enchants",
    ["Empty sockets"]               = "Tomma sockets",
    ["Empty slots"]                 = "Tomma slots",
    ["MISSING ENCHANTS, OK UNTIL %d"] = "SAKNADE ENCHANTS, OK TILL %d",

    ["EQUIPPED"]                    = "UTRUSTAT",
    ["WHAT TO FIX, HIGHEST IMPACT FIRST"] = "VAD DU BÖR FIXA, STÖRST EFFEKT FÖRST",
    ["%d ISSUE"]                    = "%d PROBLEM",
    ["%d ISSUES"]                   = "%d PROBLEM",
    ["Nothing to fix. Gear is clean."] = "Inget att fixa. Ditt gear är rent.",
    ["Not scanned yet"]             = "Inte skannat än",
    ["No problems found"]           = "Inga problem hittade",
    ["1 thing worth fixing"]        = "1 sak värd att fixa",
    ["%d things worth fixing"]      = "%d saker värda att fixa",
    ["none"]                        = "inget",

    ["Gear score"]                  = "Gear score",
    ["One number out of 100 for how well put together your gear is."] =
        "Ett enda tal av 100 för hur välbyggt ditt gear är.",
    ["It starts at 100 and loses points for empty slots, missing enchants, empty gem holes, wearing the wrong type of armor, and pieces that are far behind the rest of your set."] =
        "Den börjar på 100 och tappar poäng för tomma slots, saknade enchants, tomma gem-hål, fel sorts armor, och delar som ligger långt efter resten av setet.",
    ["It does not measure how rare your items are. It measures how much free power you are leaving on the table."] =
        "Den mäter inte hur sällsynta dina föremål är. Den mäter hur mycket gratis power du lämnar kvar på bordet.",

    ["Nothing equipped here."]      = "Ingenting utrustat här.",
    ["Enchant: this slot cannot take one."] = "Enchant: den här sloten kan inte ta någon.",
    ["Enchant: yes, this item is enchanted."] = "Enchant: ja, det här föremålet är enchantat.",
    ["Enchant: missing, and that is fine for now. Enchants start being worth the gold at level %d."] =
        "Enchant: saknas, och det är helt okej så länge. Enchants börjar vara värda guldet vid level %d.",
    ["Enchant: missing. Free stats you are not getting."] =
        "Enchant: saknas. Gratis stats som du går miste om.",
    ["Gems: this item has no gem holes."] = "Gems: det här föremålet har inga gem-hål.",
    ["Gems: %d of %d holes filled."] = "Gems: %d av %d hål fyllda.",

    ["The upgrade finder is not loaded in this build."] =
        "Uppgraderingssökaren är inte laddad i den här versionen.",
    ["The enchanting guide is not loaded in this build."] =
        "Enchanting-guiden är inte laddad i den här versionen.",
    ["Rotation tracking is not loaded in this build."] =
        "Rotationsspårningen är inte laddad i den här versionen.",

    ["Left click to open the gear and rotation coach."] =
        "Vänsterklicka för att öppna gear- och rotationscoachen.",
    ["Right click to open the officer console."] =
        "Högerklicka för att öppna officerskonsolen.",
    ["Drag to move this button."]   = "Dra för att flytta knappen.",

    -- -----------------------------------------------------------------------
    -- slash command output
    -- -----------------------------------------------------------------------
    ["Score %d (%s), %d issue."]    = "Score %d (%s), %d problem.",
    ["Score %d (%s), %d issues."]   = "Score %d (%s), %d problem.",
    ["Language set to %s."]         = "Språket är satt till %s.",
    ["Language: %s. Use /gearscout lang en or /gearscout lang sv."] =
        "Språk: %s. Använd /gearscout lang en eller /gearscout lang sv.",
    ["Skin set to %s. Type /reload to see it."] =
        "Skin satt till %s. Skriv /reload för att se det.",
    ["Current skin: %s. Use /gearscout skin obsidian or /gearscout skin slate."] =
        "Nuvarande skin: %s. Använd /gearscout skin obsidian eller /gearscout skin slate.",
    ["Nothing scanned yet. Try /gearscout scan first."] =
        "Inget skannat än. Testa /gearscout scan först.",
    ["No equipped items to compare."] = "Inga utrustade föremål att jämföra med.",
    ["Nothing known that beats your %s at item level %d in dungeons near your level. The loot table only covers dungeons and raids, so quest rewards will not appear here."] =
        "Inget känt som slår din %s på item level %d i dungeons nära din level. Loot-tabellen täcker bara dungeons och raids, så questbelöningar dyker inte upp här.",
    ["Upgrades for your %s, currently item level %d:"] =
        "Uppgraderingar till din %s, just nu item level %d:",
    ["  %s (item level %d) from %s in %s"] = "  %s (item level %d) från %s i %s",
    ["1 more candidate is still loading from the server. Run this again in a moment for the complete answer."] =
        "1 kandidat till laddas fortfarande från servern. Kör kommandot igen om en stund för hela svaret.",
    ["%d more candidates are still loading from the server. Run this again in a moment for the complete answer."] =
        "%d kandidater till laddas fortfarande från servern. Kör kommandot igen om en stund för hela svaret.",
    ["Item evaluation is not loaded."] = "Item-utvärderingen är inte laddad.",
    ["No stat weight data for your class and spec yet."] =
        "Ingen stat weight-data för din klass och spec än.",
    ["Stat caps, data confidence %s:"] = "Stat caps, datasäkerhet %s:",
    ["met"]                         = "uppnått",
    ["NOT met, %s"]                 = "INTE uppnått, %s",
    ["Shift click an item into chat after the command, like /gearscout score [item]."] =
        "Shift-klicka in ett föremål i chatten efter kommandot, till exempel /gearscout score [item].",
    ["Score difference against what you are wearing: %+.1f"] =
        "Score-skillnad mot det du har på dig: %+.1f",
    ["No comparison available."]    = "Ingen jämförelse tillgänglig.",
    ["Rotation data source set to %s. Run /gearscout rot to see what it resolved."] =
        "Rotationens datakälla satt till %s. Kör /gearscout rot för att se vad den landade i.",
    ["Rotation data source: %s, currently using %s. Switch with /gearscout data research or /gearscout data builtin."] =
        "Rotationens datakälla: %s, använder just nu %s. Byt med /gearscout data research eller /gearscout data builtin.",
    ["WeakAuras: ready made import strings and copy paste snippets are in WEAKAURA.md, in the GearScout folder you downloaded."] =
        "WeakAuras: färdiga import-strängar och snuttar att kopiera finns i WEAKAURA.md, i GearScout-mappen du laddade ner.",
    ["  Fastest way: /wa, click Import, paste the string from the top of that file."] =
        "  Snabbaste vägen: /wa, klicka Import, klistra in strängen högst upp i den filen.",
    ["  Missing group buffs right now: %d%s"] = "  Gruppbuffar du saknar just nu: %d%s",
    [" (you are not in a group, so there is nobody to ask)"] =
        " (du är inte i en grupp, så det finns ingen att fråga)",
    ["Diagnostic failed: %s"]       = "Diagnostiken misslyckades: %s",
    ["The rotation module did not load at all."] = "Rotationsmodulen laddades inte alls.",
    ["Level %d %s  |  GearScout %s"] = "Level %d %s  |  GearScout %s",

    -- -----------------------------------------------------------------------
    -- the gear advice, Rules.lua
    -- -----------------------------------------------------------------------
    [" and "]                       = " och ",
    ["%s, %s, %s and %d more"]      = "%s, %s, %s och %d till",
    ["character"]                   = "karaktär",
    ["heavier armor"]               = "tyngre armor",
    ["your armor type"]             = "din armor-typ",
    ["your class stats"]            = "stats för din klass",

    ["You are wearing nothing on your %s"] = "Du har ingenting på %s",
    ["This slot is completely empty, so it gives you no armor and no stats at all."] =
        "Den här sloten är helt tom, så den ger dig ingen armor och inga stats alls.",
    ["Put anything in it. Look in your bags first, then any town vendor. At your level a plain green costs silver, not gold."] =
        "Sätt vad som helst i den. Kolla väskorna först, sedan vilken vendor som helst i en by. På din level kostar ett vanligt grönt silver, inte guld.",
    ["Put anything in it. Even a cheap auction house item beats an empty slot. Check your bags first, you may already own something."] =
        "Sätt vad som helst i den. Även ett billigt föremål från auction house slår en tom slot. Kolla väskorna först, du kanske redan äger något.",
    ["You are wearing nothing on %d slots: %s"] = "Du har ingenting på %d slots: %s",
    ["These slots are completely empty, so together they give you no armor and no stats at all."] =
        "De här slotsen är helt tomma, så tillsammans ger de dig ingen armor och inga stats alls.",
    ["Put anything in each of them. Look in your bags first, then any town vendor. At your level plain greens cost silver, not gold."] =
        "Sätt vad som helst i var och en av dem. Kolla väskorna först, sedan vilken vendor som helst i en by. På din level kostar vanliga gröna silver, inte guld.",
    ["Put anything in each of them. Even a cheap auction house item beats an empty slot. Check your bags first, you may already own some of these."] =
        "Sätt vad som helst i var och en av dem. Även ett billigt föremål från auction house slår en tom slot. Kolla väskorna först, du kanske redan äger några av dem.",

    ["No enchant on your %s"]       = "Ingen enchant på %s",
    ["An enchant is a permanent bonus added on top of an item. This one has none, so you are missing free stats."] =
        "En enchant är en permanent bonus ovanpå ett föremål. Det här har ingen, så du går miste om gratis stats.",
    ["Ask an enchanter to add a permanent enchant to this slot."] =
        "Be en enchanter lägga en permanent enchant på den här sloten.",
    ["No enchant on %d slots: %s"]  = "Ingen enchant på %d slots: %s",
    ["An enchant is a permanent bonus added on top of an item. None of these have one, so you are missing free stats on every one of them."] =
        "En enchant är en permanent bonus ovanpå ett föremål. Ingen av de här har någon, så du går miste om gratis stats på varenda en.",
    ["Start with your %s: %s%s"]    = "Börja med %s: %s%s",
    [" Then do the rest when you can afford it: %s."] = " Ta sedan resten när du har råd: %s.",

    ["1 empty gem slot on your %s"] = "1 tomt gem-hål på %s",
    ["%d empty gem slots on your %s"] = "%d tomma gem-hål på %s",
    ["This item has %d gem holes and only %d of them have a gem in. Empty holes give you nothing."] =
        "Det här föremålet har %d gem-hål och bara %d av dem har en gem i. Tomma hål ger dig ingenting.",
    ["Gems drop in dungeons and sell for a few silver at the auction house. Right click a gem, then click the item, and it snaps in. Even the cheapest gem beats an empty hole."] =
        "Gems droppar i dungeons och säljs för några silver på auction house. Högerklicka på en gem, klicka sedan på föremålet, så åker den i. Även den billigaste gemmen slår ett tomt hål.",
    ["1 empty gem slot across %d items: %s"] = "1 tomt gem-hål fördelat på %d föremål: %s",
    ["%d empty gem slots across %d items: %s"] = "%d tomma gem-hål fördelat på %d föremål: %s",
    ["These items have %d gem holes between them and only %d of them have a gem in. Empty holes give you nothing."] =
        "De här föremålen har %d gem-hål tillsammans och bara %d av dem har en gem i. Tomma hål ger dig ingenting.",

    ["Your %s is the wrong kind of armor"] = "Föremålet på %s är fel sorts armor",
    ["You are wearing %s here, but from level 40 a %s can wear %s, which has far more armor on it."] =
        "Du har %s här, men från level 40 kan en %s bära %s, som har mycket mer armor på sig.",
    ["Look for %s instead. You are giving away a large amount of protection for nothing."] =
        "Leta efter %s istället. Du ger bort en stor mängd skydd helt i onödan.",

    ["Your %s is a low quality item"] = "Föremålet på %s håller låg kvalitet",
    ["%s is a green or white item and you are level %d. Items are colour coded, and green is the second weakest tier."] =
        "%s är ett grönt eller vitt föremål och du är level %d. Föremål är färgkodade, och grönt är näst sämst.",
    ["Blue items from normal and heroic dungeons are a large step up and cost nothing but time. Crafted gear and reputation rewards work too."] =
        "Blå föremål från normal och heroic dungeons är ett stort kliv upp och kostar inget annat än tid. Craftat gear och reputation-belöningar fungerar också.",
    ["%d of your items are low quality: %s"] = "%d av dina föremål håller låg kvalitet: %s",
    ["These are green or white items and you are level %d. Green is the second weakest quality tier."] =
        "Det här är gröna eller vita föremål och du är level %d. Grönt är näst sämsta kvalitetsnivån.",

    ["Your %s is the weakest thing you are wearing"] = "Föremålet på %s är det svagaste du har på dig",
    ["Item level is a simple power number printed on every item. This one is %d, while the rest of your gear averages %d."] =
        "Item level är ett enkelt styrketal som står på varje föremål. Det här ligger på %d, medan resten av ditt gear snittar %d.",
    ["Because it is so far behind everything else, replacing this one piece helps you more than upgrading anything else right now."] =
        "Eftersom den ligger så långt efter allt annat hjälper det dig mer att byta ut just den delen än att uppgradera något annat just nu.",
    ["%s drops the %s at item level %d, and GearScout knows of %d more for this slot at your level."] =
        "%s droppar %s på item level %d, och GearScout känner till %d till för den här sloten på din level.",
    ["%s drops an upgrade at item level %d, and GearScout knows of %d more for this slot at your level."] =
        "%s droppar en uppgradering på item level %d, och GearScout känner till %d till för den här sloten på din level.",
    ["%s drops the %s at item level %d, which would replace this."] =
        "%s droppar %s på item level %d, vilket skulle ersätta det här.",
    ["%s drops an upgrade at item level %d, which would replace this."] =
        "%s droppar en uppgradering på item level %d, vilket skulle ersätta det här.",

    ["Your %s is out of date"]      = "Föremålet på %s är föråldrat",
    ["It is item level %d. At level %d you should be wearing something around item level %d."] =
        "Det är item level %d. På level %d borde du ha på dig något runt item level %d.",
    ["Almost any quest reward or dungeon drop in the zone you are questing in right now will be better than this."] =
        "Nästan vilken questbelöning eller dungeon-drop som helst i zonen du questar i just nu är bättre än det här.",
    ["%d of your items are out of date: %s"] = "%d av dina föremål är föråldrade: %s",
    ["Their item levels run from %d to %d. At level %d you should be wearing something around item level %d."] =
        "Deras item levels går från %d till %d. På level %d borde du ha på dig något runt item level %d.",
    ["Almost any quest reward or dungeon drop in the zone you are questing in right now will be better than these."] =
        "Nästan vilken questbelöning eller dungeon-drop som helst i zonen du questar i just nu är bättre än de här.",

    ["Your %s has stats a %s cannot use"] = "Föremålet på %s har stats som en %s inte kan använda",
    ["It gives %s %d. A %s gets no benefit at all from %s, so that part of the item is doing nothing for you."] =
        "Det ger %s %d. En %s har ingen nytta alls av %s, så den delen av föremålet gör ingenting för dig.",
    ["Not urgent on its own. It does mean that when you find a piece with %s on it, that piece will be a clear upgrade."] =
        "Inte akut i sig. Men det betyder att när du hittar en del med %s på så är den delen en tydlig uppgradering.",
    ["%d of your items have stats a %s cannot use: %s"] =
        "%d av dina föremål har stats som en %s inte kan använda: %s",
    ["Between them these items give %s. A %s gets no benefit from any of that, so that part of each item is doing nothing for you."] =
        "Tillsammans ger de här föremålen %s. En %s har ingen nytta alls av det, så den delen av varje föremål gör ingenting för dig.",
    ["Not urgent on its own. It does mean that when you find pieces with %s on them, those pieces will be a clear upgrade."] =
        "Inte akut i sig. Men det betyder att när du hittar delar med %s på så är de delarna en tydlig uppgradering.",

    ["Your %s is broken"]           = "Föremålet på %s är trasigt",
    ["Durability is at %d percent. A broken item gives zero armor and zero stats until it is fixed."] =
        "Durability ligger på %d procent. Ett trasigt föremål ger noll armor och noll stats tills det är lagat.",
    ["Visit any repair vendor, the ones with a small anvil icon on the map, and click the repair all button."] =
        "Gå till vilken repair vendor som helst, de med en liten städ-ikon på kartan, och klicka på repair all-knappen.",

    ["Cannot check the enchant on your %s right now"] = "Går inte att kolla enchanten på %s just nu",
    ["A temporary buff such as a sharpening stone, an oil or a poison is on this weapon, and it hides the permanent enchant underneath."] =
        "En tillfällig buff, till exempel en sharpening stone, en oil eller en poison, sitter på vapnet och döljer den permanenta enchanten under.",
    ["Nothing to do. GearScout will check this slot again once the temporary buff wears off."] =
        "Inget att göra. GearScout kollar sloten igen när den tillfälliga buffen gått ut.",

    ["You have no bow, gun or crossbow"] = "Du har ingen bow, gun eller crossbow",
    ["A hunter does most of their damage at range. With this slot empty, your auto shot and every shot ability are unusable."] =
        "En hunter gör större delen av sin damage på avstånd. Med den här sloten tom går varken auto shot eller någon shot-ability att använda.",
    ["Equip a ranged weapon right now. Any vendor in a starting town sells a basic one for silver."] =
        "Sätt på ett ranged-vapen på en gång. Vilken vendor som helst i en startby säljer ett enkelt för några silver.",

    ["Enchants and gems are being skipped on purpose"] = "Enchants och gems hoppas över med flit",
    ["At level %d your gear gets replaced every few levels, so an enchant bought now is thrown away almost immediately."] =
        "På level %d byts ditt gear ut varannan eller var tredje level, så en enchant du köper nu slängs bort nästan direkt.",
    ["Spend the gold on bags, riding skill and your class trainer instead. GearScout starts checking enchants at level %d, when Outland gear lasts long enough to deserve one."] =
        "Lägg guldet på bags, riding skill och din class trainer istället. GearScout börjar kolla enchants vid level %d, när Outland-gear sitter kvar tillräckligt länge för att förtjäna en.",
    ["Where your next upgrades come from at level %d"] = "Var dina nästa uppgraderingar kommer ifrån på level %d",
    ["Item level is the number GearScout compares. Anything with a higher one is an upgrade for that slot."] =
        "Item level är siffran GearScout jämför. Allt med en högre siffra är en uppgradering för den sloten.",

    -- how to get each enchant, from Rules.lua's ENCHANT_SOURCE
    ["Head enchants are bought once from a reputation vendor and last forever. Ask in guild chat which one suits your class."] =
        "Head-enchants köps en gång av en reputation-vendor och sitter kvar för alltid. Fråga i guildchatten vilken som passar din klass.",
    ["Shoulder enchants are sold by the Aldor or the Scryers in Shattrath once you have earned enough standing with them."] =
        "Shoulder-enchants säljs av Aldor eller Scryers i Shattrath när du har tillräckligt med standing hos dem.",
    ["Any enchanter can enchant a cloak. It is cheap, it is permanent, and you only pay once."] =
        "Vilken enchanter som helst kan enchanta en cloak. Det är billigt, det är permanent, och du betalar bara en gång.",
    ["Ask any enchanter for plus six to all stats on your chest. It is one of the cheapest upgrades in the whole game."] =
        "Be vilken enchanter som helst om plus sex till alla stats på ditt chest. Det är en av de billigaste uppgraderingarna i hela spelet.",
    ["Any enchanter can add stats to bracers for very little gold."] =
        "Vilken enchanter som helst kan lägga stats på bracers för väldigt lite guld.",
    ["Any enchanter can enchant gloves. If you are an engineer you can also fit a glove gadget instead."] =
        "Vilken enchanter som helst kan enchanta gloves. Är du engineer kan du sätta en glove-gadget istället.",
    ["Leg armor comes from a tailor as spellthread, or from a leatherworker as an armor kit. One of them lasts forever."] =
        "Leg armor kommer från en tailor som spellthread, eller från en leatherworker som ett armor kit. Den sitter kvar för alltid.",
    ["Boots can take extra movement speed or extra stats from an enchanter. Movement speed is never wasted."] =
        "Boots kan få extra movement speed eller extra stats av en enchanter. Movement speed är aldrig bortkastat.",
    ["A weapon enchant is the single largest enchant in the game. Get one from an enchanter as soon as you can afford it."] =
        "En weapon-enchant är den enskilt största enchanten i spelet. Skaffa en av en enchanter så fort du har råd.",
    ["Your off hand can take a weapon enchant, or a shield enchant, from an enchanter."] =
        "Din off hand kan ta en weapon-enchant, eller en shield-enchant, av en enchanter.",
    ["An engineer can fit a scope to a bow, gun or crossbow. It adds flat damage to every single shot you fire."] =
        "En engineer kan sätta en scope på en bow, gun eller crossbow. Den lägger på fast damage på varje enskilt skott du skjuter.",
    ["You are an enchanter, and only enchanters may enchant their own rings. Both of yours are bare."] =
        "Du är enchanter, och bara enchanters får enchanta sina egna ringar. Båda dina är bara.",

    -- where the upgrades are, by level bracket. Zone and dungeon names are
    -- the client's own and are left exactly as they are.
    ["Quest rewards. At this level they beat anything you can buy, and you get them for free just by questing."] =
        "Questbelöningar. På den här nivån slår de allt du kan köpa, och du får dem gratis bara genom att questa.",
    ["Quest rewards, plus your first dungeons: Ragefire Chasm, Wailing Caverns, Deadmines and Shadowfang Keep."] =
        "Questbelöningar, plus dina första dungeons: Ragefire Chasm, Wailing Caverns, Deadmines och Shadowfang Keep.",
    ["Blackfathom Deeps, the Stockade and Razorfen Kraul. Every blue that drops there is a big jump at your level."] =
        "Blackfathom Deeps, the Stockade och Razorfen Kraul. Varje blå som droppar där är ett stort kliv på din level.",
    ["Gnomeregan and Scarlet Monastery. The Monastery wings are the best gear per hour in this bracket by a wide margin."] =
        "Gnomeregan och Scarlet Monastery. Monastery-vingarna ger överlägset mest gear per timme i det här spannet.",
    ["Scarlet Monastery Cathedral, Razorfen Downs and Uldaman."] =
        "Scarlet Monastery Cathedral, Razorfen Downs och Uldaman.",
    ["Zul'Farrak and Maraudon. Also worth buying a few crafted blues from the auction house around now."] =
        "Zul'Farrak och Maraudon. Nu är det också värt att köpa några craftade blå på auction house.",
    ["Sunken Temple and the upper parts of Blackrock Depths."] =
        "Sunken Temple och de övre delarna av Blackrock Depths.",
    ["Blackrock Depths, Lower Blackrock Spire, Stratholme and Scholomance."] =
        "Blackrock Depths, Lower Blackrock Spire, Stratholme och Scholomance.",
    ["Head to Outland. The first green quest rewards in Hellfire Peninsula beat level 60 raid gear, so replace everything fast."] =
        "Ge dig av till Outland. De första gröna questbelöningarna i Hellfire Peninsula slår level 60-raidgear, så byt ut allt snabbt.",
    ["Auchenai Crypts, Sethekk Halls, Mana-Tombs and the Steamvault. Do the quests inside them for the rewards too."] =
        "Auchenai Crypts, Sethekk Halls, Mana-Tombs och the Steamvault. Gör questsen inuti dem för belöningarna också.",
    ["Heroic dungeons for badges, Karazhan, reputation rewards and crafted epics. Now is the point where enchants and gems are worth real gold."] =
        "Heroic dungeons för badges, Karazhan, reputation-belöningar och craftade epics. Nu är läget där enchants och gems är värda riktigt guld.",

    -- what each class actually wants instead. The stat names are the client's,
    -- only the connective moves.
    ["Strength, Stamina and Critical Strike"] = "Strength, Stamina och Critical Strike",
    ["Agility, Attack Power and Stamina"]     = "Agility, Attack Power och Stamina",
    ["Intellect, Spell Damage and Stamina"]   = "Intellect, Spell Damage och Stamina",
    ["Intellect, Spirit and Spell Power"]     = "Intellect, Spirit och Spell Power",

    -- -----------------------------------------------------------------------
    -- bag upgrades, Bags.lua
    -- -----------------------------------------------------------------------
    ["This item"]                   = "Det här föremålet",
    ["an item"]                     = "ett föremål",
    ["the best one"]                = "den bästa",
    ["you have nothing equipped in that slot at all"] =
        "du har ingenting alls i den sloten",
    ["its stats are worth about %d%% more to your spec than what you have on"] =
        "dess stats är värda ungefär %d%% mer för din spec än det du har på dig",
    ["it is item level %d against the item level %d you have on now"] =
        "den är item level %d mot item level %d som du har på dig nu",
    ["You are carrying an upgrade for your %s in your bags"] =
        "Du har en uppgradering till %s liggande i väskorna",
    ["%s is worth putting on: %s."] = "%s är värd att ta på: %s.",
    ["Open your bags, right click %s, and put it on."] =
        "Öppna väskorna, högerklicka på %s, och ta på den.",
    ["Open your bags, right click the item, and put it on."] =
        "Öppna väskorna, högerklicka på föremålet, och ta på det.",
    [" It is in your bank, so you need to be at the bank to reach it."] =
        " Den ligger i banken, så du måste stå vid banken för att komma åt den.",
    ["You are carrying %d upgrades in your bags"] = "Du bär på %d uppgraderingar i väskorna",
    ["The best one is %s for your %s: %s. There is 1 more upgrade sitting in your bags."] =
        "Den bästa är %s till %s: %s. Det ligger 1 uppgradering till i väskorna.",
    ["The best one is %s for your %s: %s. There are %d more upgrades sitting in your bags."] =
        "Den bästa är %s till %s: %s. Det ligger %d uppgraderingar till i väskorna.",
    ["Start with %s for your %s. Open your bags and right click it to equip it."] =
        "Börja med %s till %s. Öppna väskorna och högerklicka på den för att ta på den.",
    [" Some of these are in your bank, so you need to be there to reach all of them."] =
        " Några av dem ligger i banken, så du måste dit för att komma åt allihop.",

    -- -----------------------------------------------------------------------
    -- upgrades page, Upgrades.lua
    -- -----------------------------------------------------------------------
    ["GEAR SLOTS"]                  = "GEAR-SLOTS",
    ["EQUIPPED NOW"]                = "UTRUSTAT NU",
    ["EARNED, THINGS YOU GO AND GET"] = "INTJÄNAT, SÅNT DU HÄMTAR SJÄLV",
    ["BOUGHT, FROM THE AUCTION HOUSE"] = "KÖPT, FRÅN AUCTION HOUSE",
    ["ALREADY YOURS"]               = "REDAN DINA",
    ["no effort at all"]            = "ingen ansträngning alls",
    ["QUEST REWARDS"]               = "QUESTBELÖNINGAR",
    ["already in your log"]         = "redan i din logg",
    ["one run at your level"]       = "en run på din level",
    ["a grind worth planning before you start"] = "en grind värd att planera innan du börjar",
    ["OTHER"]                       = "ÖVRIGT",
    ["%d upgrade"]                  = "%d uppgradering",
    ["%d upgrades"]                 = "%d uppgraderingar",
    ["Equipped item"]               = "Utrustat föremål",
    ["Not used with your two hander."] = "Används inte med ditt two hander.",
    ["Nothing equipped."]           = "Ingenting utrustat.",
    ["Unknown item"]                = "Okänt föremål",
    ["Item level %d, up from %d."]  = "Item level %d, upp från %d.",
    ["Item level %d, and that slot is empty right now."] =
        "Item level %d, och den sloten är tom just nu.",
    ["It is not soulbound, so you can buy it instead of farming it."] =
        "Den är inte soulbound, så du kan köpa den istället för att farma den.",
    ["GearScout has no researched stat weights for your spec yet."] =
        "GearScout har inga researchade stat weights för din spec än.",
    ["Auction house price: %s"]     = "Pris på auction house: %s",
    ["not known"]                   = "okänt",
    ["%d gold"]                     = "%d guld",
    ["%d copper"]                   = "%d koppar",
    ["Already sitting in your bags."] = "Ligger redan i dina väskor.",
    ["Already sitting in your bank."] = "Ligger redan i din bank.",
    ["Quest reward from %s."]       = "Questbelöning från %s.",
    ["Quest reward from %s (one of the reward choices)."] =
        "Questbelöning från %s (ett av belöningsvalen).",
    ["a quest"]                     = "en quest",
    ["Drops in %s."]                = "Droppar i %s.",
    ["a dungeon"]                   = "en dungeon",
    ["Reputation reward. Reach %s standing with %s and buy it from their quartermaster."] =
        "Reputation-belöning. Nå %s standing hos %s och köp den av deras quartermaster.",
    ["Your gear has not been scanned yet. Open the Gear tab once so GearScout can read what you have equipped, then come back here."] =
        "Ditt gear har inte skannats än. Öppna Gear-fliken en gång så att GearScout kan läsa av vad du har på dig, och kom sedan tillbaka hit.",
    ["You have a two handed weapon equipped, so nothing goes in your off hand right now."] =
        "Du har ett tvåhandsvapen utrustat, så inget går i din off hand just nu.",
    ["GearScout could not score this item for your spec yet, comparing by item level only."] =
        "GearScout kunde inte poängsätta det här föremålet för din spec än, så jämförelsen görs bara på item level.",
    ["GearScout has no researched stat weights for your spec yet. Anything below showing an item level figure instead of a score is ranked by item level only, not by how much it actually helps."] =
        "GearScout har inga researchade stat weights för din spec än. Allt nedanför som visar en item level-siffra istället för ett score är rangordnat bara på item level, inte på hur mycket det faktiskt hjälper.",
    ["1 more item is still loading from the server. Reopen this tab in a moment to see it."] =
        "1 föremål till laddas fortfarande från servern. Öppna fliken igen om en stund för att se det.",
    ["%d more items are still loading from the server. Reopen this tab in a moment to see them."] =
        "%d föremål till laddas fortfarande från servern. Öppna fliken igen om en stund för att se dem.",
    ["Nothing found yet that beats what you have equipped there."] =
        "Inget hittat än som slår det du har utrustat där.",
    ["Nothing found yet for this empty slot."] = "Inget hittat än till den här tomma sloten.",
    ["Nothing for this slot can be bought. Quest and reputation rewards are soulbound, and so is everything above that a boss has to drop for you personally."] =
        "Inget till den här sloten går att köpa. Quest- och reputation-belöningar är soulbound, och det är även allt ovanför som en boss måste droppa till dig personligen.",

    -- -----------------------------------------------------------------------
    -- enchanting page, Enchants.lua
    -- -----------------------------------------------------------------------
    ["YOUR ENCHANTING"]             = "DIN ENCHANTING",
    ["WHAT TO PUT ON THIS SLOT, BEST FIRST"] = "VAD DU BÖR SÄTTA PÅ SLOTEN, BÄST FÖRST",
    ["WHAT TO PUT ON THIS SLOT, WHAT YOU CAN USE FIRST"] =
        "VAD DU BÖR SÄTTA PÅ SLOTEN, DET DU KAN ANVÄNDA FÖRST",
    ["WHAT GOES ON THIS SLOT"]      = "VAD SOM GÅR PÅ DEN HÄR SLOTEN",
    ["YOU CAN USE THESE NOW"]       = "DE HÄR KAN DU ANVÄNDA NU",
    ["NOT YET, BUT CLOSE"]          = "INTE ÄN, MEN NÄRA",
    ["A LONG WAY OFF"]              = "LÅNGT BORT",
    ["Nothing readable stands between you and any of these."] =
        "Det står inget läsbart hinder mellan dig och någon av de här.",
    ["A little more character or a little more gear and these open up."] =
        "Lite mer level eller lite bättre gear, så öppnar de här upp sig.",
    ["These are here so you know they exist, not because they are worth planning around today."] =
        "De här står med så att du vet att de finns, inte för att de är värda att planera runt idag.",
    ["%s  |  This one and the %d below it have names that do not say what they do, so GearScout will not pretend to rank them."] =
        "%s  |  Den här och de %d under den har namn som inte säger vad de gör, så GearScout låtsas inte rangordna dem.",

    ["Nothing equipped"]            = "Inget utrustat",
    ["Takes no enchant"]            = "Tar ingen enchant",
    ["Already enchanted"]           = "Redan enchantad",
    ["You can do this one now"]     = "Den här kan du göra nu",
    ["Nothing in reach yet"]        = "Inget inom räckhåll än",
    ["Bought with reputation"]      = "Köps med reputation",
    ["Leatherworker or tailor"]     = "Leatherworker eller tailor",
    ["Engineer fits a scope"]       = "Engineer sätter på en scope",
    ["Bare, recipe not known"]      = "Bar, receptet är okänt",
    ["Bare"]                        = "Bar",

    ["Nothing equipped here right now."] = "Ingenting utrustat här just nu.",
    ["There is already an enchant on this one. GearScout cannot read which enchant it is, only that something is on there, so check the item tooltip before paying for a replacement."] =
        "Det sitter redan en enchant på den här. GearScout kan inte läsa vilken, bara att något sitter där, så kolla föremålets tooltip innan du betalar för ett byte.",
    ["Nothing to choose here."]     = "Inget att välja på här.",
    ["GearScout has no enchant data for this slot."] =
        "GearScout har ingen enchant-data för den här sloten.",
    ["Nothing is equipped here, so there is nothing to enchant yet."] =
        "Det sitter ingenting här, så det finns inget att enchanta än.",
    ["Only an enchanter can enchant a ring, and this character is not one. It is the one enchant nobody can do for you."] =
        "Bara en enchanter kan enchanta en ring, och den här karaktären är ingen. Det är den enda enchanten ingen annan kan göra åt dig.",
    ["A scope only fits a bow, a gun or a crossbow. What is in this slot cannot take one."] =
        "En scope passar bara på en bow, en gun eller en crossbow. Det som sitter i den här sloten kan inte ta någon.",
    ["This slot does not take a permanent enchant in this version of the game."] =
        "Den här sloten tar ingen permanent enchant i den här versionen av spelet.",
    ["You are holding a two hander, so these are the two hand weapon enchants."] =
        "Du håller i ett two hander, så det här är enchants för tvåhandsvapen.",
    ["Nothing on this list is usable at level %d yet. Everything below says what it is waiting on."] =
        "Inget på den här listan går att använda på level %d än. Allt nedanför säger vad det väntar på.",
    ["Nothing on this list is usable yet. Everything below says what it is waiting on."] =
        "Inget på den här listan går att använda än. Allt nedanför säger vad det väntar på.",

    ["Needs level %d and you are %d, so it is 1 level away."] =
        "Kräver level %d och du är %d, så det är 1 level kvar.",
    ["Needs level %d and you are %d, so it is %d levels away."] =
        "Kräver level %d och du är %d, så det är %d levels kvar.",
    ["You are already %s with %s."] = "Du är redan %s med %s.",
    ["You already have the standing with %s."] = "Du har redan standingen hos %s.",
    ["Costs %s standing with %s and you are %s with them."] =
        "Kostar %s standing hos %s, och du är %s med dem.",
    ["Costs %s standing with %s, which has to be earned before any of it is for sale."] =
        "Kostar %s standing hos %s, och den måste grindas fram innan något av det går att köpa.",
    ["Only goes on an item of level %d or higher, and the one you are wearing is level %d."] =
        "Går bara på ett föremål av level %d eller högre, och det du har på dig är level %d.",

    ["The name says this one gives %s. GearScout could not get the exact numbers from the client."] =
        "Namnet säger att den här ger %s. GearScout fick inte ut de exakta siffrorna från klienten.",
    ["GearScout cannot tell what this one gives. The name does not say and the client would not describe it."] =
        "GearScout kan inte se vad den här ger. Namnet säger inget och klienten ville inte beskriva den.",
    ["GearScout could not read what this one gives. Hover it to see the game's own tooltip."] =
        "GearScout kunde inte läsa vad den här ger. Håll muspekaren över den för spelets egen tooltip.",
    ["Still loading from the server. Reopen this tab in a moment."] =
        "Laddas fortfarande från servern. Öppna fliken igen om en stund.",

    ["You are not an enchanter, so somebody else applies this one. Buy the materials, hand them over with the item, and tip for the work."] =
        "Du är inte enchanter, så någon annan applicerar den här. Köp materialen, lämna över dem med föremålet, och ge dricks för jobbet.",
    ["You can do this one yourself right now. Read from %s."] =
        "Den här kan du göra själv på en gång. Avläst från %s.",
    ["You do not know this recipe yet, according to %s. Enchanting recipes come from your trainer or from a formula that drops, is sold, or is a reputation reward."] =
        "Du kan inte det här receptet än, enligt %s. Enchanting-recept kommer från din trainer eller från en formula som droppar, säljs, eller är en reputation-belöning.",
    ["GearScout could not read which recipes you know. Open your enchanting window once and it will read them, along with what each one costs in materials."] =
        "GearScout kunde inte läsa vilka recept du kan. Öppna ditt enchanting-fönster en gång, så läser den av dem och vad var och en kostar i material.",
    ["Materials: %s"]               = "Material: %s",
    ["Open your enchanting window once so GearScout can read what this one costs in materials."] =
        "Öppna ditt enchanting-fönster en gång så att GearScout kan läsa vad den här kostar i material.",
    ["GearScout only gets a material list for recipes you already know, because that is all the client will hand an addon."] =
        "GearScout får bara materiallistan för recept du redan kan, för det är allt klienten lämnar ut till ett addon.",
    ["Ask the enchanter which materials they need. The client only tells GearScout the materials for recipes you know yourself."] =
        "Fråga enchantern vilka material de behöver. Klienten berättar bara materialen för recept som du själv kan.",
    ["Needs %d enchanting skill. You have %d."] = "Kräver %d i enchanting skill. Du har %d.",
    ["Needs %d enchanting skill and you have %d, so you are %d short."] =
        "Kräver %d i enchanting skill och du har %d, så du saknar %d.",
    ["Needs %d enchanting skill."]  = "Kräver %d i enchanting skill.",

    ["Bought once from %s%s quartermaster at %s standing. You apply it yourself, no enchanter involved."] =
        "Köps en gång hos %s%s quartermaster vid %s standing. Du applicerar den själv, ingen enchanter inblandad.",
    ["Costs reputation and a little gold, and it never wears off."] =
        "Kostar reputation och lite guld, och den försvinner aldrig.",
    ["A %s makes this. It is an item, so you can buy one off the auction house and apply it yourself."] =
        "En %s gör den här. Det är ett föremål, så du kan köpa en på auction house och applicera den själv.",
    ["Buy the finished item, or bring the materials to a crafter. This one is not an enchanting job."] =
        "Köp det färdiga föremålet, eller ta med materialen till en crafter. Det här är inget enchanting-jobb.",
    ["An engineer makes this. It is an item, so you can buy one and attach it yourself."] =
        "En engineer gör den här. Det är ett föremål, så du kan köpa en och sätta på den själv.",
    ["Buy the finished scope, or ask an engineer. This one is not an enchanting job."] =
        "Köp den färdiga scopen, eller fråga en engineer. Det här är inget enchanting-jobb.",

    ["Every one of these needs"]    = "Varenda en av de här kräver",
    ["%d of these need"]            = "%d av de här kräver",
    ["%s level %d or higher, and you are %d."] = "%s level %d eller högre, och du är %d.",
    ["%s level %d or higher."]      = "%s level %d eller högre.",
    ["They are bought with faction standing, which is a grind worth planning before you start rather than something you pick up on the way past."] =
        "De köps med faction standing, vilket är en grind värd att planera innan du börjar snarare än något du plockar upp på vägen förbi.",
    ["%d of them are bought with faction standing."] = "%d av dem köps med faction standing.",
    ["also "]                       = "också ",
    ["They %swant a better item in this slot than the one you are wearing."] =
        "De vill %sha ett bättre föremål i den här sloten än det du har på dig.",
    ["%d of them %swant a better item in this slot than the one you are wearing."] =
        "%d av dem vill %sha ett bättre föremål i den här sloten än det du har på dig.",

    ["Enchanting %d of %d, read from %s."] = "Enchanting %d av %d, avläst från %s.",
    ["Enchanting %d, read from %s."] = "Enchanting %d, avläst från %s.",
    ["You are an enchanter. GearScout could not read your skill number on this client, so it will not guess one."] =
        "Du är enchanter. GearScout kunde inte läsa av din skill-siffra på den här klienten, så den gissar inte.",
    ["It knows %d of your recipes and what they cost, read from your enchanting window."] =
        "Den känner till %d av dina recept och vad de kostar, avläst från ditt enchanting-fönster.",
    ["Open your enchanting window once and GearScout will read which recipes you know and what each one costs in materials."] =
        "Öppna ditt enchanting-fönster en gång, så läser GearScout av vilka recept du kan och vad var och en kostar i material.",
    ["You are not an enchanter, so every enchant here is somebody else's work. What you can do is buy the materials and hand them over with the item."] =
        "Du är inte enchanter, så varje enchant här är någon annans jobb. Det du kan göra är att köpa materialen och lämna över dem tillsammans med föremålet.",
    ["%d of your 1 bare slot has an enchant you already know how to apply."] =
        "%d av din enda bara slot har en enchant som du redan kan applicera.",
    ["%d of your %d bare slots have an enchant you already know how to apply."] =
        "%d av dina %d bara slots har en enchant som du redan kan applicera.",
    ["1 slot is carrying no enchant."] = "1 slot saknar enchant.",
    ["%d slots are carrying no enchant."] = "%d slots saknar enchant.",
    ["%d of those have nothing in reach at level %d, and each one says what it is waiting on."] =
        "%d av dem har ingenting inom räckhåll på level %d, och var och en säger vad den väntar på.",
    ["%d of those have nothing in reach yet, and each one says what it is waiting on."] =
        "%d av dem har ingenting inom räckhåll än, och var och en säger vad den väntar på.",
    ["Every slot that can take an enchant already has one."] =
        "Alla slots som kan ta en enchant har redan en.",

    ["Ranked with GearScout's researched stat weights for %s."] =
        "Rangordnat med GearScouts researchade stat weights för %s.",
    ["Your talents are too thin to name a spec, so this is ranked with the weights for %s and is a guide rather than an answer. Every option for this slot is listed below, not just the top one."] =
        "Dina talents är för tunna för att sätta namn på en spec, så det här är rangordnat med vikterna för %s och är en vägledning snarare än ett svar. Alla alternativ för den här sloten listas nedanför, inte bara det bästa.",
    ["GearScout has no researched stat weights for your spec, so this is ranked by what a %s generally wants. That is a preference, not research."] =
        "GearScout har inga researchade stat weights för din spec, så det här rangordnas efter vad en %s brukar vilja ha. Det är en tumregel, inte research.",
    ["GearScout has neither researched stat weights for your spec nor a confident read on your role, so this ordering is a rough one. Read the options rather than trusting the order."] =
        "GearScout har varken researchade stat weights för din spec eller en säker läsning av din roll, så ordningen här är grov. Läs alternativen istället för att lita på ordningen.",
    ["the tree you have most points in"] = "det träd du har flest poäng i",
    ["your spec"]                   = "din spec",
    ["your own recipes"]            = "dina egna recept",
    ["the client"]                  = "klienten",
    ["the faction"]                 = "factionen",
    ["the required"]                = "den nödvändiga",
    -- English puts an article in front of a faction name and Swedish does not,
    -- so the slot the article goes in is simply left empty here.
    ["the "]                        = "",

    -- where a skill number or a recipe list was read from
    ["your enchanting window"]      = "ditt enchanting-fönster",
    ["your profession list"]        = "din yrkeslista",
    ["your skill list"]             = "din skill-lista",
    ["your spellbook"]              = "din spellbook",
    ["remembered from the last time GearScout saw it"] =
        "ihågkommet från senaste gången GearScout såg det",

    -- plain words for what an enchant gives, where the word is not a stat name
    ["all five stats"]              = "alla fem stats",
    ["less threat"]                 = "mindre threat",
    ["one school of resistance"]    = "en sorts resistance",
    ["a gathering profession, not a combat stat"] =
        "ett gathering-yrke, inte en combat-stat",
    ["a bonus against one kind of enemy only"] = "en bonus mot bara en sorts fiende",

    -- -----------------------------------------------------------------------
    -- group buffs, Buffs.lua
    -- -----------------------------------------------------------------------
    ["You are missing 1 group buff"] = "Du saknar 1 gruppbuff",
    ["You are missing %d group buffs"] = "Du saknar %d gruppbuffar",
    ["You can put %s on yourself right now. %s"] = "Du kan lägga %s på dig själv direkt. %s",
    ["%s is in your group and can give you %s. %s"] = "%s är i din grupp och kan ge dig %s. %s",
    ["Your group can give you %d buffs you do not have: %s."] =
        "Din grupp kan ge dig %d buffar som du inte har: %s.",
    ["Buffs are free, they last a long time, and they are the cheapest power you will ever get."] =
        "Buffar är gratis, de håller länge, och det är den billigaste power du någonsin får.",
    ["Cast them on yourself."]      = "Casta dem på dig själv.",
    ["Ask %s for them, and cast the rest on yourself. %s"] =
        "Be %s om dem, och casta resten på dig själv. %s",
    ["Ask %s for them. %s"]         = "Be %s om dem. %s",

    ["Extra health. There is no reason to fight without it."] =
        "Extra health. Det finns ingen anledning att slåss utan den.",
    ["Regenerates your mana faster between casts."] =
        "Regenererar din mana snabbare mellan casts.",
    ["Shadow resistance. Worth asking for on a fight that throws shadow damage at you and worth nothing on any other."] =
        "Shadow resistance. Värd att be om på en fight som kastar shadow damage på dig, och värdelös på alla andra.",
    ["More mana, and more chance to land a critical spell."] =
        "Mer mana, och större chans att landa en critical spell.",
    ["Raises every one of your stats and your resistances at once."] =
        "Höjer alla dina stats och dina resistances på en gång.",
    ["Hurts anything that hits you, which helps whoever is tanking hold a group and does nothing for anyone else."] =
        "Skadar allt som slår dig, vilket hjälper den som tankar att hålla en grupp och gör ingenting för någon annan.",
    ["Critical strike chance for the druid's party, if they are feral and have spent the talent point."] =
        "Critical strike-chans för druidens party, om den är feral och har lagt talangpoängen.",
    ["Spell critical strike chance for the druid's party, if they are balance and standing in moonkin form."] =
        "Spell critical strike-chans för druidens party, om den är balance och står i moonkin form.",
    ["Straight attack power, so every hit lands harder."] =
        "Ren attack power, så varje träff slår hårdare.",
    ["Gives mana back steadily, even while you are casting."] =
        "Ger tillbaka mana jämnt, även medan du castar.",
    ["Ten percent to every stat you have, which is the best blessing in the game for almost everybody. The paladin has to have spent the talent point on it."] =
        "Tio procent på varje stat du har, vilket är den bästa blessingen i spelet för nästan alla. Paladinen måste ha lagt talangpoängen på den.",
    ["Cuts the threat you make, so you can hit harder without pulling things off the tank. Never ask for it while you are the one tanking."] =
        "Sänker threaten du bygger, så du kan slå hårdare utan att dra saker av tanken. Be aldrig om den när det är du som tankar.",
    ["Makes a paladin's heals land on you for more. A tanking blessing and nothing to anybody else."] =
        "Gör att en paladins heals landar för mer på dig. En tank-blessing och ingenting för någon annan.",
    ["Less damage taken, and some of it thrown back. A tanking blessing, and it needs a talent point."] =
        "Mindre damage tagen, och en del av den kastas tillbaka. En tank-blessing, och den kräver en talangpoäng.",
    ["A paladin runs one aura at a time and it only reaches their own party. Any of them beats standing there with none."] =
        "En paladin kör en aura i taget och den når bara det egna partyt. Vilken som helst av dem slår att stå där utan någon.",
    ["Attack power for everyone standing near the warrior."] =
        "Attack power för alla som står nära warriorn.",
    ["Extra health for the warrior's party, and it stacks with a priest's Fortitude."] =
        "Extra health för warriorns party, och den stackar med en priests Fortitude.",
    ["Extra health from the warlock's imp, for as long as the imp is the demon they have out."] =
        "Extra health från warlockens imp, så länge impen är demonen de har ute.",
    ["Attack power for the hunter's party, if they are marksmanship and have spent the talent point."] =
        "Attack power för hunterns party, om den är marksmanship och har lagt talangpoängen.",
    ["Strength for the shaman's party, out of a totem that has to stay planted near you."] =
        "Strength för shamanens party, ur en totem som måste stå kvar nära dig.",
    ["Armor instead of strength out of the earth slot. A tanking choice."] =
        "Armor istället för strength ur earth-sloten. Ett tankval.",
    ["Extra windfury hits on weapon swings. It does nothing at all for a bow, a gun or a spell."] =
        "Extra windfury-träffar på vapensvingar. Den gör ingenting alls för en bow, en gun eller en spell.",
    ["Agility for the shaman's party, which is attack power and crit for anyone who scales off it."] =
        "Agility för shamanens party, vilket är attack power och crit för alla som skalar på det.",
    ["Spell damage and healing for the shaman's party."] =
        "Spell damage och healing för shamanens party.",
    ["A steady trickle of mana back to everyone near the totem."] =
        "Ett jämnt flöde av mana tillbaka till alla nära totemen.",
    ["A small heal every few seconds to the shaman's party, instead of the mana one."] =
        "En liten heal med några sekunders mellanrum till shamanens party, istället för mana-varianten.",
    ["Spell crit and spell hit for the party, from an elemental shaman deep enough in the tree to have it."] =
        "Spell crit och spell hit för partyt, från en elemental shaman som är djupt nog i trädet för att ha den.",

    -- -----------------------------------------------------------------------
    -- readiness gaps, Gaps.lua
    -- -----------------------------------------------------------------------
    ["You have 1 unspent talent point"] = "Du har 1 olagd talent point",
    ["You have %d unspent talent points"] = "Du har %d olagda talent points",
    ["Talent points make your character permanently stronger and cost nothing to spend. Right now they are sitting unused and doing nothing for you."] =
        "Talent points gör din karaktär permanent starkare och kostar ingenting att lägga. Just nu ligger de oanvända och gör ingenting för dig.",
    ["Open your talents from the main menu, or press the default key N, and click a point into any tree you like. You can move points around again later for a fee."] =
        "Öppna dina talents från huvudmenyn, eller tryck på standardknappen N, och klicka in en poäng i vilket träd du vill. Du kan flytta om poängen senare mot en avgift.",
    ["You have no ammo loaded"]     = "Du har ingen ammo laddad",
    ["Your bow, crossbow or gun needs arrows or bullets sitting in your ammo slot to fire at all. That slot is empty right now, so you cannot attack at range."] =
        "Din bow, crossbow eller gun behöver arrows eller bullets i ammo-sloten för att över huvud taget kunna skjuta. Den sloten är tom just nu, så du kan inte attackera på avstånd.",
    ["Buy arrows or bullets from any vendor that sells weapons, whichever your weapon uses, then right click the stack to load it into your ammo slot."] =
        "Köp arrows eller bullets av en vendor som säljer vapen, beroende på vad ditt vapen använder, och högerklicka sedan på stacken för att ladda den i ammo-sloten.",
    ["Your ammo is far below your level"] = "Din ammo ligger långt under din level",
    ["Your current ammo"]           = "Din nuvarande ammo",
    ["%s is old ammo, meant for characters level %d and under. Ammo damage scales with the ammo itself, so this is doing noticeably less damage than ammo made for where you are now."] =
        "%s är gammal ammo, gjord för karaktärer level %d och under. Ammo-damage skalar med själva ammon, så det här gör märkbart mindre damage än ammo gjord för din nivå.",
    ["Buy the newest arrows or bullets a weapons vendor near your level sells, and load those instead."] =
        "Köp de nyaste arrows eller bullets en vapenvendor nära din level säljer, och ladda dem istället.",
    ["You are low on ammo: %d left"] = "Du börjar få slut på ammo: %d kvar",
    ["Ammo is used up on every shot. Running out in the middle of a fight leaves you with no ranged attack at all until you restock."] =
        "Ammo går åt vid varje skott. Tar den slut mitt i en fight står du helt utan ranged attack tills du fyllt på.",
    ["Buy a full stack from any vendor that sells ammo before you head back out to quest."] =
        "Köp en full stack av vilken vendor som helst som säljer ammo innan du ger dig ut och questar igen.",
    ["You do not have a quiver"]    = "Du har ingen quiver",
    ["You do not have an ammo pouch"] = "Du har ingen ammo pouch",
    ["A %s holds your ammo and makes you shoot noticeably faster. Without one, your shooting speed is stuck at its slowest for no reason."] =
        "En %s håller din ammo och gör att du skjuter märkbart snabbare. Utan en sitter din skjuthastighet fast på det långsammaste helt i onödan.",
    ["Buy a %s from a leatherworker, the auction house, or a vendor near your class trainer, then drag it onto any empty bag slot. It works from there without doing anything else."] =
        "Köp en %s av en leatherworker, på auction house, eller av en vendor nära din class trainer, och dra den sedan till en tom bag-slot. Den fungerar därifrån utan att du gör något mer.",
    ["You can learn to ride but have not"] = "Du kan lära dig att rida men har inte gjort det",
    ["From level 40 you can train riding, which lets you buy a mount. A mount moves much faster than running everywhere on foot."] =
        "Från level 40 kan du träna riding, vilket låter dig köpa en mount. En mount är mycket snabbare än att springa överallt till fots.",
    ["Find a riding trainer in any major city, pay for riding training, then buy a mount from the stable master standing nearby."] =
        "Leta upp en riding trainer i valfri storstad, betala för riding-träningen, och köp sedan en mount av stable mastern som står bredvid.",
    ["You can learn expert riding but have not"] = "Du kan lära dig expert riding men har inte gjort det",
    ["From level 60 you can train expert riding, which is what allows you to fly once you reach Outland."] =
        "Från level 60 kan du träna expert riding, vilket är det som gör att du kan flyga när du kommer till Outland.",
    ["Find a riding trainer, pay for expert riding training, then buy a flying mount once you are in Outland."] =
        "Leta upp en riding trainer, betala för expert riding, och köp sedan en flying mount när du är i Outland.",
    ["Your ranged slot is empty"]   = "Din ranged-slot är tom",
    ["A cheap thrown weapon or a bow in that slot lets you damage an enemy before it reaches you, which is how most players start a fight on their own terms instead of the enemy's."] =
        "Ett billigt kastvapen eller en bow i den sloten låter dig skada en fiende innan den når fram, vilket är så de flesta startar en fight på sina egna villkor istället för fiendens.",
    ["Buy a throwing weapon or a bow from any vendor that sells weapons and equip it in your ranged slot. It does not need to be good, it only needs to be there."] =
        "Köp ett kastvapen eller en bow av en vendor som säljer vapen och sätt den i din ranged-slot. Den behöver inte vara bra, den behöver bara finnas där.",
    ["a poison"]                    = "en poison",
    ["a sharpening stone or weightstone"] = "en sharpening stone eller weightstone",
    ["No temporary buff on your main hand weapon"] = "Ingen tillfällig buff på ditt main hand-vapen",
    ["%s applied to your weapon adds real damage for a while, and keeping one active is standard practice for a %s."] =
        "%s på ditt vapen ger riktig extra damage en stund, och att alltid ha en aktiv är standard för en %s.",
    ["Buy %s from a vendor or the auction house, right click it, then click your main hand weapon to apply it."] =
        "Köp %s av en vendor eller på auction house, högerklicka på den, och klicka sedan på ditt main hand-vapen för att applicera den.",
    ["You are still using only your starting backpack"] = "Du använder fortfarande bara din start-backpack",
    ["With no extra bags equipped you have very little room to carry quest items, gear you pick up, or anything worth selling, so you have to stop and empty your bags far more often than you need to."] =
        "Utan extra bags har du väldigt lite plats för quest-föremål, gear du plockar upp, eller något värt att sälja, så du måste stanna och tömma väskorna mycket oftare än du behöver.",
    ["Buy any bag from a vendor, even a small cheap one, and drag it onto an empty slot in your backpack. Every extra bag helps."] =
        "Köp vilken bag som helst av en vendor, även en liten billig, och dra den till en tom plats i din backpack. Varje extra bag hjälper.",
    ["Your bags are completely full"] = "Dina väskor är helt fulla",
    ["With zero free slots you cannot pick up quest items, loot, or anything else until you make room."] =
        "Med noll lediga platser kan du inte plocka upp quest-föremål, loot, eller något annat förrän du gör plats.",
    ["Sell or delete anything you do not need at a vendor, or mail items to another character, before you keep playing."] =
        "Sälj eller släng det du inte behöver hos en vendor, eller maila föremål till en annan karaktär, innan du spelar vidare.",

    -- -----------------------------------------------------------------------
    -- quest rewards, Quests.lua
    -- -----------------------------------------------------------------------
    ["Turn in %s for a better %s"]  = "Lämna in %s för en bättre %s",
    ["%s is already in your quest log, so you have done the work for it. Its %s reward is item level %d, better than the item level %d you have equipped there now."] =
        "%s ligger redan i din questlogg, så jobbet är redan gjort. Belöningen till %s är item level %d, bättre än item level %d som du har där nu.",
    [" There is 1 more quest reward in your log that would also be an upgrade."] =
        " Det finns 1 questbelöning till i loggen som också vore en uppgradering.",
    [" There are %d more quest rewards in your log that would also be an upgrade."] =
        " Det finns %d questbelöningar till i loggen som också vore en uppgradering.",
    ["Hand in %s. The reward is a straight upgrade over what you have equipped, and you already finished the quest."] =
        "Lämna in %s. Belöningen är en ren uppgradering mot det du har på dig, och questen är redan klar.",

    -- -----------------------------------------------------------------------
    -- deaths, Deaths.lua
    -- -----------------------------------------------------------------------
    ["Fall damage"]                 = "Fallskada",
    ["Drowning"]                    = "Drunkning",
    ["Exhaustion"]                  = "Utmattning",
    ["Fire"]                        = "Eld",
    ["Slime"]                       = "Slem",
    ["Environmental damage"]        = "Miljöskada",
    ["Unknown"]                     = "Okänd",
    ["an unknown zone"]             = "en okänd zon",
    ["You have died to %s %d times"] = "Du har dött till %s %d gånger",
    ["Out of your last %d deaths, %s alone accounts for %d of them. That is a pattern, not bad luck."] =
        "Av dina senaste %d dödsfall står %s ensam för %d av dem. Det är ett mönster, inte otur.",
    ["Before you fight it again, bring more health consumables, ask for help, or look up what makes that particular enemy dangerous."] =
        "Innan du möter den igen: ta med mer healing-consumables, be om hjälp, eller läs på om vad som gör just den fienden farlig.",
    ["You died with a healing item still in your bags"] = "Du dog med ett healing-föremål kvar i väskorna",
    ["When %s killed you, you still had a healing potion or bandage on you. It was never used."] =
        "När %s dödade dig hade du fortfarande en healing potion eller ett bandage på dig. Den användes aldrig.",
    ["Keybind your healing potion or bandage and use it around half health, not after the fight has already gone wrong."] =
        "Lägg din healing potion eller ditt bandage på en knapp och använd den runt halva health, inte efter att fighten redan gått åt skogen.",
    ["%s was available when you died"] = "%s var tillgänglig när du dog",
    ["Your %s was off cooldown when %s killed you, so it was ready to be used."] =
        "Din %s var av cooldown när %s dödade dig, så den var redo att användas.",
    ["Use a defensive cooldown earlier, around half health, rather than waiting to see if you will need it."] =
        "Använd en defensiv cooldown tidigare, runt halva health, istället för att vänta och se om du behöver den.",
    [" You lasted about %s."]       = " Du höll dig vid liv i ungefär %s.",
    [" Your last hit took roughly %d percent of your health."] =
        " Den sista träffen tog ungefär %d procent av din health.",
    [" Your last %d hits took roughly %d percent of your health."] =
        " Dina sista %d träffar tog ungefär %d procent av din health.",
    ["You last died to %s"]         = "Du dog senast till %s",
    ["This happened in %s.%s%s"]    = "Det hände i %s.%s%s",
    ["Nothing to fix yet. GearScout will start pointing out patterns once it has seen a few more deaths."] =
        "Inget att fixa än. GearScout börjar peka ut mönster när den sett några dödsfall till.",

    -- -----------------------------------------------------------------------
    -- rotation findings, Rotation.lua
    -- -----------------------------------------------------------------------
    ["RECENT FIGHTS"]               = "SENASTE FIGHTS",
    ["IDLE TIME"]                   = "IDLE-TID",
    ["Current fight"]               = "Pågående fight",
    ["%s  |  %d casts  |  happening now"] = "%s  |  %d casts  |  pågår nu",
    ["fight in progress"]           = "fight pågår",
    ["shared fight"]                = "delad fight",
    ["This player"]                 = "Den här spelaren",
    ["  |  pet out %d%%"]           = "  |  pet ute %d%%",
    ["No fights recorded yet. Pull something for at least five seconds and it will show up here."] =
        "Inga fights inspelade än. Pulla något i minst fem sekunder så dyker det upp här.",
    ["%s has not shared any fights yet. They need to fight something with rotation sharing turned on."] =
        "%s har inte delat några fights än. De behöver slåss mot något med rotationsdelning påslagen.",
    ["Nothing wrong so far. Keep going."] = "Inget fel hittills. Kör på.",
    ["Clean fight. Nothing stood out."] = "Ren fight. Inget stack ut.",

    ["once"]                        = "en gång",
    ["twice"]                       = "två gånger",
    ["%d times"]                    = "%d gånger",
    ["missed"]                      = "missade",
    ["dodged"]                      = "dodgades",
    ["parried"]                     = "parerades",
    ["blocked"]                     = "blockades",
    ["resisted"]                    = "resistades",
    ["deflected"]                   = "deflektades",
    ["evaded"]                      = "evadades",
    ["reflected"]                   = "reflekterades",
    ["absorbed"]                    = "absorberades",
    ["on you"]                      = "på dig",
    ["on your target"]              = "på ditt mål",

    ["%s was never up"]             = "%s var aldrig uppe",
    ["It was not %s at any point after you started attacking (%s)."] =
        "Den var inte %s vid någon tidpunkt efter att du började attackera (%s).",
    ["This is a keep it up button. Apply it at the start and refresh it when it drops."] =
        "Det här är en håll-den-uppe-knapp. Lägg den i början och refresha när den faller av.",
    ["%s did not stick"]            = "%s satt inte kvar",
    ["You cast it once, but it %s, so it had little chance to be up."] =
        "Du castade den en gång, men den %s, så den fick liten chans att ligga uppe.",
    ["You cast it %d times, but it %s, so it had little chance to be up."] =
        "Du castade den %d gånger, men den %s, så den fick liten chans att ligga uppe.",
    ["You cast it once but it was not %s for long."] =
        "Du castade den en gång men den var inte %s särskilt länge.",
    ["You cast it %d times but it was not %s for long."] =
        "Du castade den %d gånger men den var inte %s särskilt länge.",
    ["Check you are not overwriting it with a weaker application, or refresh it the moment it drops."] =
        "Kolla att du inte skriver över den med en svagare version, eller refresha den så fort den faller av.",
    ["Present %s for roughly %s of the %s since you started attacking."] =
        "Uppe %s ungefär %s av de %s som gått sedan du började attackera.",
    [" %d of %d casts were %s, not missed presses."] =
        " %d av %d casts blev %s, inte missade knapptryck.",
    ["%s up only %d percent of the time"] = "%s uppe bara %d procent av tiden",
    ["Refresh it as soon as it falls off. Every second it is missing is damage you simply do not do."] =
        "Refresha den så fort den faller av. Varje sekund den saknas är damage du helt enkelt inte gör.",
    ["%s up %d percent of the time"] = "%s uppe %d procent av tiden",
    ["Close, but it dropped %s during the fight."] = "Nära, men den föll av %s under fighten.",
    ["Refresh a moment earlier and this becomes full uptime."] =
        "Refresha en aning tidigare så blir det full uptime.",

    ["%s was never used"]           = "%s användes aldrig",
    ["It was available the whole fight and never pressed."] =
        "Den var tillgänglig hela fighten och trycktes aldrig.",
    ["That is free damage or healing sitting unused on your bars."] =
        "Det är gratis damage eller healing som ligger oanvänd på dina bars.",
    ["A %d second cooldown across %s allows roughly %d casts."] =
        "En cooldown på %d sekunder över %s räcker till ungefär %d casts.",
    [" You also spent about %d percent of the fight without %s to cast."] =
        " Du låg dessutom ungefär %d procent av fighten utan %s att casta med.",
    ["%s used %d of about %d times"] = "%s använd %d av ungefär %d gånger",
    ["Press it again as soon as it comes back up."] = "Tryck den igen så fort den är uppe.",
    ["%s was never pressed"]        = "%s trycktes aldrig",
    ["Your spec treats this as a main button and it saw zero casts."] =
        "Din spec räknar den här som en huvudknapp och den fick noll casts.",
    ["Check your action bars and your keybinds."] = "Kolla dina action bars och dina keybinds.",

    ["Started the fight at %d percent %s"] = "Startade fighten på %d procent %s",
    ["Starting a fight low on this means running dry partway through it."] =
        "Att starta en fight lågt på det här betyder att du får slut halvvägs in.",
    ["Drink or eat before you pull. A few seconds spent topping up costs far less than the fight does."] =
        "Drick eller ät innan du pullar. Några sekunder på att fylla på kostar långt mindre än fighten gör.",
    ["Out of %s for about %d percent of the fight"] = "Slut på %s ungefär %d procent av fighten",
    ["The bar was at or near empty for a real share of the fight, time you physically could not cast."] =
        "Baren låg på eller nära noll under en rejäl del av fighten, tid då du fysiskt inte kunde casta.",
    ["This is a resource problem, not a rotation problem. A fuller bar at the pull and a lighter rotation once it gets low both help."] =
        "Det är ett resursproblem, inte ett rotationsproblem. En fullare bar vid pullen och en lättare rotation när den börjar ta slut hjälper båda.",

    ["You fought without a pet"]    = "Du slogs utan pet",
    ["Your pet was out for %d percent of the fight."] = "Din pet var ute %d procent av fighten.",
    ["A hunter pet is a large slice of your damage and it holds things off you. Call it before you pull, and revive it when it dies."] =
        "En hunter-pet är en stor del av din damage och håller saker borta från dig. Kalla på den innan du pullar, och återuppliva den när den dör.",
    ["Your demon is a large slice of your damage. Summon one before you pull."] =
        "Din demon är en stor del av din damage. Summona en innan du pullar.",
    ["Your pet was only out %d percent of the fight"] = "Din pet var bara ute %d procent av fighten",
    ["It either died partway through or was called late."] =
        "Den dog antingen halvvägs in eller kallades på för sent.",
    ["Keep it alive and keep it on the target. Mend Pet while it is tanking."] =
        "Håll den vid liv och håll den på målet. Mend Pet medan den tankar.",
    ["Your pet never used an ability"] = "Din pet använde aldrig någon ability",
    ["It was out the whole fight but never cast anything of its own."] =
        "Den var ute hela fighten men castade aldrig något eget.",
    ["Open the pet spellbook and set Claw or Bite to autocast. Free damage that costs you nothing."] =
        "Öppna pet-spellbooken och sätt Claw eller Bite på autocast. Gratis damage som inte kostar dig något.",
    ["You let your pet open the fight"] = "Du lät din pet öppna fighten",
    ["Your pet was already in combat for %s before your first cast."] =
        "Din pet hade redan varit i combat i %s innan din första cast.",
    ["That is good play. It gives your pet time to build threat and take the hit instead of you."] =
        "Det är bra spelat. Det ger din pet tid att bygga threat och ta smällen istället för dig.",

    ["%d percent of the fight with nothing cast"] = "%d procent av fighten utan att något castades",
    ["%d gaps longer than %.0f seconds, %s in total."] =
        "%d luckor längre än %.0f sekunder, %s totalt.",
    ["Moving, swapping targets and running dry all land here. Something instant is almost always better than standing still."] =
        "Att röra på sig, byta mål och få slut på resurser hamnar alla här. Något instant är nästan alltid bättre än att stå still.",
    ["%d percent idle time"]        = "%d procent idle-tid",
    ["%d gaps longer than %.0f seconds."] = "%d luckor längre än %.0f sekunder.",
    ["Some of this cannot be helped. The rest is free damage."] =
        "En del av det går inte att göra något åt. Resten är gratis damage.",
    ["Long fight, log truncated"]   = "Lång fight, loggen kapades",
    ["Only the most recent %d casts were kept."] = "Bara de %d senaste casten sparades.",
    ["The percentages above still describe the recorded part."] =
        "Procenten ovanför beskriver fortfarande den inspelade delen.",

    -- -----------------------------------------------------------------------
    -- findings that need the Details damage meter, DetailsBridge.lua
    -- -----------------------------------------------------------------------
    ["Your pet dealt no damage"]    = "Din pet gjorde ingen damage",
    ["It was out for the whole fight but Details recorded nothing from it."] =
        "Den var ute hela fighten men Details registrerade ingenting från den.",
    ["It is probably passive, or it never reached the target. Set it to defensive, and make sure Claw or Bite is on autocast in the pet spellbook."] =
        "Den står antagligen på passive, eller så nådde den aldrig fram till målet. Sätt den på defensive, och se till att Claw eller Bite ligger på autocast i pet-spellbooken.",
    ["%d percent of your melee swings were avoided"] =
        "%d procent av dina melee-svingar undveks",
    ["%d of %d swings were dodged, parried or missed outright."] =
        "%d av %d svingar dodgades, parerades eller missade helt.",
    ["This usually means you are standing in front of the target. Move to its side or back when you can, most enemies cannot dodge or parry an attack from there."] =
        "Det betyder oftast att du står framför målet. Ställ dig vid sidan eller bakom när du kan, de flesta fiender kan varken dodga eller parera en attack därifrån.",
    ["%d percent of your damage was plain auto attack"] =
        "%d procent av din damage var ren auto attack",
    ["Auto attack is the swing that happens by itself when you stand next to something. Everything else on your bars is what you add on top."] =
        "Auto attack är svingen som sker av sig själv när du står bredvid något. Allt annat på dina bars är det du lägger till ovanpå.",
    ["You are barely using your abilities. Pick the three or four buttons your spec cares about, put them somewhere easy to reach, and press them whenever they are ready."] =
        "Du använder knappt dina abilities. Välj ut de tre eller fyra knappar din spec bryr sig om, lägg dem lättåtkomligt, och tryck på dem så fort de är redo.",

    -- -----------------------------------------------------------------------
    -- the one popup GearScout shows, Comm.lua
    -- -----------------------------------------------------------------------
    ["%s wants to see your gear through GearScout. Share it?"] =
        "%s vill se ditt gear via GearScout. Dela det?",
    ["Share"]                       = "Dela",
    ["Decline"]                     = "Neka",
    ["Always share with them"]      = "Dela alltid med den här personen",

    ["Tooltip additions turned off after repeated errors: %s"] =
        "GearScout-raderna i tooltips stängdes av efter upprepade fel: %s",
}

-- ---------------------------------------------------------------------------
-- the lookup
--
-- Misses fall through to __index, which answers with the key itself, so an
-- untranslated string renders as the English it already was. The answer is
-- then cached straight into the table, which means the metamethod runs once
-- per distinct string per language and every later read is a plain hash
-- lookup rather than a function call. Switching language empties the cache.
-- ---------------------------------------------------------------------------
local active = nil     -- nil means English, i.e. the keys themselves

local L = setmetatable({}, {
    __index = function(t, key)
        -- Guarded, and it returns before writing anything, because a caller
        -- doing L[SOME_TABLE[x]] on a missing x hands this a nil key, and
        -- assigning to a nil key is an error while reading one is not.
        if type(key) ~= "string" then return key end
        local s = active and active[key]
        if s == nil or s == "" then s = key end
        t[key] = s     -- plain rawset, there is no __newindex
        return s
    end,
})
ns.L = L

-- format(L[fmt], ...) in one call, for the places that only need it once.
local format = string.format
function ns.Lf(fmt, ...)
    return format(L[fmt], ...)
end

ns.locale = "enUS"

-- Returns true when the language actually changed, so a caller can decide
-- whether anything needs redrawing. Anything unknown resolves to English
-- rather than to an empty screen.
function ns.SetLocale(name)
    if type(name) ~= "string" or (name ~= "enUS" and not translations[name]) then
        name = "enUS"
    end
    if name == ns.locale then return false end

    active = (name ~= "enUS") and translations[name] or nil
    ns.locale = name

    -- Drop the cached answers. Clearing in place matters: every file captured
    -- this exact table when it loaded, the same way they all captured ns.T,
    -- so it must never be replaced.
    for k in pairs(L) do L[k] = nil end

    ns:Emit("LOCALE_CHANGED", name)
    return true
end

-- Applied as soon as the saved variables exist. Locale.lua subscribes before
-- any UI file does, because it loads before them, so every screen built after
-- this point is built in the right language from the start.
ns:Sub("DB_READY", function()
    ns.SetLocale(ns.db and ns.db.locale)
end)
