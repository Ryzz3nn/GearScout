# GearScout WeakAuras

GearScout already works out which group buffs you are missing. It knows your
spec, it only counts classes that are actually in your group, and it respects
the Burning Crusade rules, so one paladin means one blessing and a totem only
counts when the shaman is in your own subgroup. A Beast Mastery hunter is told
about Blessing of Might and is never told about Blessing of Wisdom.

This file turns that into a WeakAura.

There are two ways to get there. The import strings are the fast one. The
recipe further down builds the same thing by hand, one box at a time, if you
would rather see how it works or want to change it.

Every piece of code in this file checks that GearScout is loaded before it does
anything. If you paste one of these with the addon disabled you get an aura
that shows nothing, not an error.

---

## What changed: both auras are plainer now

Same information, less furniture. If you are new here you can skip this
section. If you imported an earlier version, this is what moved.

- The icons are smaller, 28 pixels instead of 40, and zoomed slightly so you
  get a clean square instead of the carved border the game art comes with.
- No border, no background, no glow element, and the swipe overlay is off.
- The name of whoever can cast the buff is now small white text sitting to the
  right of the icon, instead of a larger gold `Ask Bob` caption underneath it.
- The icons stack downwards as a list rather than sideways as a row. That is
  what lets the names sit in clear space. In a row they overlapped each other
  as soon as two people owed you something.
- The text line dropped its `Missing 2:` counter and is smaller and white. It
  now reads `Blessing of Might (Bob), Battle Shout (Carl)`.
- The two auras start well apart on screen instead of nearly on top of each
  other.

Both auras kept their names and their internal ids, so pasting a new string
does not give you a second copy. WeakAuras recognises it as the same aura and
offers to update the one you already have. If you had customised the old one,
look at the change list it shows you before you accept.

---

## The fast way: import a ready made aura

1. Type `/wa` in game and press Enter. The WeakAuras window opens.
2. Click **Import** at the bottom left.
3. Copy one of the strings below and paste it into the box, then press Enter.
4. WeakAuras shows you what it is about to add. Click **Import**.
5. Drag it where you want it.

Nothing appears straight away, and that is correct. Both auras are quiet until
you are in a party or a raid and something is actually missing.

Pick one. They say the same thing in two shapes, and running both just puts the
same information on screen twice.

### Aura 1: GearScout Party Buffs

A short vertical list. One small icon per missing buff, best first, with the
name of the person who can cast it beside it. So a missing Blessing of Might
that Bob can cast shows the Blessing of Might icon with `Bob` next to it.

Imports as a dynamic group called `GearScout Party Buffs` with one icon inside
it called `GearScout Buff Icon`. Starts a little above the centre of your
screen.

```
!WA:2!1zv3UTXXv4it4621Xfo0XUfQgnduAmSlCiSDrcGVixWvIKMP0Iu7sjzdxdQz3DwUt8Yz2mZSIIkWxeHGcFTEe4JabYlGEcgiu0ha9gu9e0Zm7skr529I9NZ5Bo)nNZ3SRSt1Wv)WxnLgYz(8Cri5(FI4GUXXsIALz4OFixQirVeFW1U4dk7AIjlGWct4IECktfSEJn73W70qopnIpM5pMMrsoz(NnIgssCnoAVJuc6WHeHC1hikF9F7QMKrccbxWhnR4XaJOzsfwrYZIG7tJib5XX9bXIx0OtVMB3XJSpbC9li4uvIhdpIiDCZzuvqwkEcrCKmJKM2os6eyrkZQ3QrDp)17UD)bUB3SP)GT7Tr9(n2a1Rt9x3WBGnjAVzRb721RZgOwED3U3aVU(G0sONjZlmMpem0dMny96(9h43VUxFVWes4703zbKEccaXZVxJoD0)(dQSrColur5ShIttTPM8XilYh5GGRV(RrDzeKvdcst0iQuszdrMeVgQDmQfbl8d55kevIyCfkLJJirwRiMuUsQCU1KJPkiOIq84yeMfHujeeoxGrs6OSuybj8XwdLaUPMDzP8qCkcNrrF3LCNzXl(Qw9ETVewbjJluaCZImaHN1AruUqu7vO7)P0h(ihRvI5c0Ghpp4zOmmviVOe9iue3IZCzfvZe2G)IXPsYvufMGzdHm(7qkrEHsclQWr0yBnRmEHAbdExLlywSxGZeqM0)Ppg9LfGRnFN4sHsrYha4wgZBOVDbMfjXBcQ9oYK3cG)PfkTbDrMy8)JxsXY5XY6Ye8HcIuAMfaaRzCbnCTLbTponNytILeR4kiQ)iXuwe5aqmDzXMzkqAqTuCaj9klbMMT6mVCLGhdKfcRYybFecQNRDLWBCYeREZZRO(9lVRDPTihq45f8d7GfuCqkrM9Zfv0f(8NqruPHaWuA2nHdAywTiQAThJulkAcyZAn07lCSjoGRpA5tqt45OXy2))L)(JZzLmzoNdCHebdNUdWWbt6)65VJqYQderHkpyxINCSKKgB5m13a40Kyi7GoKKPaRHhziSg5QF4UzvvKdudKjyG(8vLeUhBLzUj(QI0n72xc268uU47xzLvQCwH05oYTtJM9ZUJviohkEM2LDPrQe36WNNBvamvKiRWF(0cI9xx62tS6nhaqJNORnvWnT09bHUB2DZg6BjGq3GPmOlwDzq)7MALfAJTkWvrseZzQSB3uqpeTvoocQayu)(lzG5U)uRSXCr0UcC2r7w(YPlSJ9ibGsVt7nBSuDBrcuyWbzMIXmajWM71U1l6FHn8PhsU7Plf5L59(ujf6Z2liHqhMOEURHYTzamfb823ZBuEQI64A2GVNUTJxykwknV5kbtAEzQWURAIsTZXyg1u(5SV1dgBfQMNqWsIVsqydvj3qFlxgNronY0uaOShdkKeyelsEKbQ1oB5octzn19GfO3s7P9191BfetzuzYvfpJYagTcV6Ck0aa5y3mZxWbJGHJPdDCpKZh1RYtQ93oVOi0uaJ(gFf4VUxJgBovXd3VON(32B11Orz35IthmC6O2GPey75BYVv31rVJJlepkNzXgBbPiSjxXBSPf75Ex0q8SCA0SwsJnAhYEYtH5kJJijzvZLK1l)dIxYJG5hYEzF(8)PW0aUbvAibI2BQParlYPJMJi5S5mLf)EZF9(FY1QoQAu1Op8e3Hc(y3n6U7MNfaDueHlo8DrcEw2TDtPhEiweH6d2rrZ0xBf91)p6FJ(gZkGEXGMNmdhsUUEqzcR3ZrFZvFG(t)N6ptxvFlpZHTpt)hD0)j9913t)h0)z9xOVJ(Z131r)LoZGQq(iMVXivce4iAU8x(u9de972ZmZ6HtPdz6AcOvXqVSI(Ho6wn1VW0xP)E79)U9EhZ9tdkZH1NxCn7OFZXdf0Ij7BkkA)ij6)YV6jHZVivMgsmuwMT6164fuKHjtlEA(VTSpZ)hZXccQzEAkA3eQIOF5jrtGZgOHqvmpReSzg66Us4Oq9whzjjGTJv0VYr)ANJb2QS6SHPKV4myRcYhMQj0SWfbE13O92(6nHs4v7C1B)rs25QsoPW5LSnGFhxuo1VTSp9Ux0N2dg4My7wLhzkk2K2BdnUI(n6)HxkDevDt98UXwISN80JGEWog5jhJfHDStP)Y9Mgd1I1PIqGyqtD076u2A0MbrrLQYGVP2ZEATNxD))1R(Vd
```

### Aura 2: GearScout Missing Buffs

One line of text, on screen only while something is missing, for example
`Blessing of Might (Bob), Battle Shout (Carl)`. Imports as a single text aura
called `GearScout Missing Buffs`. Starts a little below the centre of your
screen.

```
!WA:2!Twv0Unsnuuf2hkBeGwLvQi2NmbTOwP2rTvIvIhkszstYwiBsyMe6UcHI8m2tgdo2d2EAtxe8qepWd8u)eYNqK4hGVGrvi(a2pH9lGR9mnDxGv8cJIY456Z9CV3JTVUw3gZBqAq(LpujZnCMGQgozC)th05ACUjvQgMzysHU(ActNXXxoMUW08HIR1PyI8INnmjrtn1wJfXa4rsMWe1UZGXDcYUxCU2iNBDysgbBOb0ZPcZlaELZXgw8zmIj1Vf8Pch7IYJc0gSYupkHjy606(Wlt9LgfB2mQs)Gpwvn8p9nxMrJkJW6YxtDMacm56I7VO2rj5chT74I7U1rWZ(7JANsXzuTb995W)W8OEuSkmgQFumwGWc9fuLhkGAYvcncJe5ZJOQ9qyoxgdfI(gQestktmdMrqqmnkbZ1u0fPubYKsrycbyhSd4qCjMqjEoxT0Wr4mg64xj4ws28LxRrN6WYsCUBblv3m0Rh18eMwdb3ppjPTmxySHuGuUSUktOcIJJkJVbh3zx0NHoOoaU4UrpMI5M0abEouM(5G(hzx2PQvLQ8ayIfV1(B02QfKnQRFoJt0UY)IujNIS7P2dPLotvBIqsb)sKGsbKpu8)OMyRPaAMu96QrZMBKIYWOkXC8)0VD29MiuIXl2PThFm6G)nkFfoZGDUAGYF4hDgtGmZwlhUh6JQOAEPWJishIBDncW96y(A23SbdKlrEjk5CNAun8No2Mc2mAdo7JljaNbcJ844ikh55HAI2PP9DLVwl72CJFuyRY)bj3ITsg3u7vYHbhXPGwjGZh748Fput43U2TvrUdG6Sw960kiSn0GzQ)KUDdNoz0jTg35e0O(TEwNGPU(gNoO30Zgg0)euVGHtgnnyyiyTc6sDgLZpLORheNsJ)UI7(cDEj9HWsiBX6PTBfoEA44wbJ3m1iffMkiCuN(9xrOraYXqVc1J70Fu3j9VcwGl3fVDX9Z0VH2gdTBzbtkOKXqWj3EoVYBeosEofPXms55p32(ugXUMdDbauPgVxt1u5uRa9sOTjvjW8Vc6YbH(3Ust5jUUPfB5NifMS71vXEo6lZXef2GrJhVcQUa6mxZzFBZLUrgmhY4TdMNZnS6(GwfVDXbGuXXATDKVM9CQDWslNHWhFqvJ8Nw1iFLYrPvE8nqN7LxivKZu4SLNvnqTOcQ6BHgcSKll2ALrgFEzM)2JEqtgj79V9eCv3gK9iMoiwYLQp)oWZ6ef0kj0ylN78YY7p6AnzJDuy7GoDgSc2qryLxaDuoJSUN2sZ4fMdouDzzE8RBfbOsyZQVUSuA7crTA1UZkyvNsCxZ8ZVZAMaosAV4rkQFfwWkh(OI3T7VtXABMqfZmPBv0Wxif0Rj5khc39kkn1Ml6LwO2mSOV)Cmt0T4lahk6x8KIbfdH3V3F3sdD0N4D0HEFAJZ)JN(xp
```

---

## The recipe: build it yourself

Both variants use the same idea. GearScout fires a custom event called
`GEARSCOUT_BUFFS_UPDATED` when the answer changes, and the WeakAura reads the
answer back out of `GearScout.API` when it hears it.

### Variant A: one small icon per missing buff

This is the dynamic group version. You create two things: a dynamic group to
hold the icons, and one icon aura inside it that clones itself once per missing
buff.

**Step 1.** In `/wa`, click **New**, choose **Dynamic Group**, and name it
whatever you like. On its **Group** tab set **Align** to `Left`. Leave
everything else alone. **Grow** is already `Down` and **Space** is already `2`,
which is exactly what this layout wants.

**Step 2.** Click **New** again, choose **Icon**, and drag it into the dynamic
group in the list on the left.

**Step 3.** Open the icon's **Trigger** tab and set:

- **Type**: `Custom`
- **Event Type**: `Trigger State Updater (Advanced)`
- **Check On...**: `Event(s)`
- **Event(s)**: paste this line

```
GEARSCOUT_BUFFS_UPDATED PLAYER_ENTERING_WORLD GROUP_ROSTER_UPDATE
```

**Step 4.** In the **Custom Trigger** box, paste this. Delete anything already
in the box first.

```lua
function(allstates, event)
    -- One state per missing buff. If GearScout is not loaded, every state is
    -- switched off and the aura simply shows nothing.
    local api = GearScout and GearScout.API
    local report = api and api.GetBuffReport and api.GetBuffReport()

    for _, state in pairs(allstates) do
        state.show = false
        state.changed = true
    end

    if not report then return true end

    for i = 1, #report.missing do
        local b = report.missing[i]
        allstates[b.key] = {
            show = true,
            changed = true,
            progressType = "static",
            value = 1,
            total = 1,
            index = i,
            name = b.label,
            icon = b.icon,
            caster = b.from or "",
            why = b.why or "",
        }
    end

    return true
end
```

**Step 5.** In the **Custom Variables** box, paste this. This box is optional.
It exists so the extra fields show up in the dropdowns on the Conditions tab
later, and it changes nothing about how the aura looks.

```lua
{
    caster = { display = "Who can cast it", type = "string" },
    why    = { display = "Why you want it", type = "string" },
}
```

**Step 6.** Open the icon's **Display** tab and make it small and plain:

- Leave **Icon Source** on `Automatic`, which is the default and means "use
  whatever icon the trigger hands over".
- Set **Width** and **Height** to `28`.
- Set **Zoom** to `30%`. This crops the carved edge off the game's icon art and
  leaves a clean square.
- Under **Swipe Overlay Settings**, untick **Enable Swipe**. Nothing here is on
  a timer, so the radial overlay has nothing to say.

**Step 7.** Still on the **Display** tab, scroll down to **Sub Elements**,
click the small plus button beside that heading, and choose **Text**. Set:

- **Display Text**: `%caster`
- **Size**: `10`
- **Anchor**: `Left`
- **To Frame's**: `Outer` / `Right`
- **X Offset**: `4`

That puts the name of whoever owes you the buff just to the right of that
buff's icon, with a small gap.

That is the whole thing. Every missing buff becomes one row in the list, best
first, and the list empties itself when you are fully buffed.

Other text you can use in that box, or anywhere else the aura takes text:

| Type this | You get |
| --- | --- |
| `%n` | the buff name, for example `Blessing of Might` |
| `%i` | the buff icon |
| `%caster` | `Bob`, whoever in the group can cast it |
| `%why` | the one line reason, for example `Straight attack power, so every hit lands harder.` |

Plain words mix in with those, so if you liked the old wording better, type
`Ask %caster` and you get `Ask Bob` back.

### Variant B: one line of text, only when something is missing

This is the cheap version. It asks one question, gets back one number, and
never builds a list unless there is something to say.

**Step 1.** In `/wa`, click **New** and choose **Text**.

**Step 2.** On the **Trigger** tab set:

- **Type**: `Custom`
- **Event Type**: `Status`
- **Check On...**: `Event(s)`
- **Event(s)**: paste the same line as before

```
GEARSCOUT_BUFFS_UPDATED PLAYER_ENTERING_WORLD GROUP_ROSTER_UPDATE
```

**Step 3.** In the **Custom Trigger** box:

```lua
function(event)
    -- Cheapest question GearScout can answer. Returns a number, allocates
    -- nothing, and is false when the addon is not loaded.
    local api = GearScout and GearScout.API
    if not api or not api.GetMissingBuffCount then return false end
    return api.GetMissingBuffCount() > 0
end
```

**Step 4.** In the **Custom Untrigger** box:

```lua
function(event)
    -- Only ever reached when the trigger above said false, so hiding is right.
    return true
end
```

**Step 5.** Scroll down to the **Name Info** box and paste this. It builds the
whole sentence, so the display only has to print one thing.

```lua
function(trigger)
    -- Builds the whole line, so the display only needs %n.
    local api = GearScout and GearScout.API
    if not api or not api.GetBuffReport then return "" end
    local report = api.GetBuffReport()
    if report.count == 0 then return "" end

    local parts = {}
    for i = 1, #report.missing do
        local b = report.missing[i]
        if b.from and b.from ~= "" then
            parts[i] = b.label .. " (" .. b.from .. ")"
        else
            parts[i] = b.label
        end
    end

    return table.concat(parts, ", ")
end
```

**Step 6.** On the **Display** tab, set **Display Text** to:

```
%n
```

Then set **Size** to `12`, and set **Shadow X Offset** and **Shadow Y Offset**
to `0`. The outline already keeps the text readable over a bright floor, so the
drop shadow underneath it is just extra ink.

Done. The aura appears when something is missing and disappears when it is not.

If you want the count back at the front of the line, change the last line of
step 5 to this:

```lua
return "Missing " .. report.count .. ": " .. table.concat(parts, ", ")
```

And if you only want a count and no names at all, skip step 5 entirely and use
this as the display text instead, which needs no code beyond the trigger:

```
Buffs missing
```

---

## Three things worth knowing

**Which trigger type to pick.** `Trigger State Updater (Advanced)` is the one
that can show several things at once, so it is what the icon variant needs. It
hands you a table of states and you fill it in. `Status` is the simple one that
is either on or off, which is all the text variant needs. Do not use `Event`
for either of these, because `Event` is for things that happen and then stop
being true, and a missing buff stays missing until somebody casts it.

**Why Check On must not be Every Frame.** `Every Frame (High CPU usage)` runs
your code sixty or more times a second forever. There is no reason to. GearScout
already tells you the moment the answer changes, so setting **Check On...** to
`Event(s)` means your aura sits at zero cost until something actually happens.

**Why GetBuffStamp exists.** `GearScout.API.GetBuffStamp()` returns a single
number that only counts up when the set of missing buffs really changes. If you
are writing something of your own that has to poll, poll that number and only
rebuild your display when it moves. It is far cheaper than comparing lists, and
it is the same value GearScout uses internally to decide whether to fire the
event at all.

```lua
function()
    local api = GearScout and GearScout.API
    return api and api.GetBuffStamp and api.GetBuffStamp() or 0
end
```

---

## Extras

**A custom text function**, if you want to build the label yourself rather than
using `%caster`. Put `%c` in the display text and paste this into the function
box that appears:

```lua
function()
    local s = aura_env.state
    if not s then return "" end
    return s.caster or ""
end
```

**Conditions.** Because of the Custom Variables box in step 5, `caster` and
`why` appear in the property dropdown on the aura's **Conditions** tab
alongside the built in ones. So you can, for example, colour the icon
differently when the person who owes you the buff is you.

**Grow sideways instead.** If you would rather have a row than a list, set the
group's **Grow** to `Right`. Do that and the names will run into each other as
soon as two buffs are missing, so move the text sub element to **To Frame's**
`Outer` / `Bottom` with **Anchor** `Top` and **X Offset** `0` first, which puts
each name under its own icon.

**The optional list.** Anything that hangs on a talent, or on the fight being
the right one, is deliberately kept off the main answer and put on a second
list you get from `GearScout.API.GetOptionalBuffs()`. Kings and Sanctuary are
there because nothing outside the paladin can see whether they ever spent the
talent point. Salvation, Thorns and Shadow Protection are there because they
are right on some fights and wrong on others. If you want those on screen too,
copy the icon aura and, in its Custom Trigger, swap both mentions of
`report.missing` for a list you fetch once:

```lua
local list = api and api.GetOptionalBuffs and api.GetOptionalBuffs() or {}
```

The entries are exactly the same shape, so nothing else in the trigger changes.

---

## If nothing shows up

Work down this list in order.

1. **Are you in a group?** Both auras are empty on your own, on purpose. There
   is nobody to ask.
2. **Is GearScout loaded?** Type `/gearscout` and see if the window opens. If
   nothing happens the addon is not running, and every snippet here is written
   to stay silent rather than error in that case.
3. **Are you actually missing anything?** Type `/gearscout wa` and it prints the
   current count on the last line. If it says zero, the aura is right and you
   are buffed.
4. **Did the event name get mangled?** It is `GEARSCOUT_BUFFS_UPDATED`, all
   capitals, no spaces. A typo there means the aura never hears anything.
5. **Is Check On still set to Every Frame?** Then the **Event(s)** box is hidden
   and ignored. Set it back to `Event(s)`.
6. **Icons but no names?** The names hang outside the icons, off to the right,
   and the group only measures the icons. Drag the list too close to the right
   edge of your screen and the names go over it. Pull it left.
7. **Still nothing after a reload?** Leave and rejoin the group, or cast
   anything on yourself. That forces GearScout to recompute and fire the event.

---

## The API, in short

Everything above is built on four calls. They are read only, they hand back
fresh tables, and nothing a WeakAura does to what it is given can affect the
addon.

| Call | Gives you |
| --- | --- |
| `GearScout.API.GetBuffReport()` | everything: count, the missing list, the optional list, your spec and role |
| `GearScout.API.GetMissingBuffCount()` | one number, allocates nothing, safe to call often |
| `GearScout.API.GetBuffStamp()` | one number that only moves when the answer moves |
| `GearScout.API.GetOptionalBuffs()` | the talent gated and fight dependent ones |

The full shape of every field is documented in the comment block at the top of
`GearScout/API.lua`. In game, `/gearscout wa` prints the short version.
