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

## The fast way: import a ready made aura

1. Type `/wa` in game and press Enter. The WeakAuras window opens.
2. Click **Import** at the bottom left.
3. Copy one of the strings below and paste it into the box, then press Enter.
4. WeakAuras shows you what it is about to add. Click **Import**.
5. Drag it where you want it. Both start in the middle of your screen.

Nothing appears straight away, and that is correct. Both auras are quiet until
you are in a party or a raid and something is actually missing.

### Aura 1: GearScout Party Buffs

A row of icons, one per missing buff, each with the buff's own icon and the
name of the person who can cast it underneath. Imports as a dynamic group
called `GearScout Party Buffs` with one icon inside it called
`GearScout Buff Icon`.

```
!WA:2!1zv3UTXXv4qZM621Xf2sXofUgnduAmSduiKfGnAVixWvIuMb0I0lPSSRRk1S7ol3PA5mBMzwtrz4lkrqHVwpc8rGa5IEREcgquKha9iONGEMzjPePt2l2FoNV583CMVZw4LReCVp81JObCwlEMiGC)prCCJOijrvymo8FLjvKWNJp(Ax(bLDnXG5qybXCrtoLP83QYUTR4njGZtc59zT6ttjhE2SpRe2Le7AC0HdvcA3UeH8Epqm91F2vniL4haUG3BC(JogrJLkSIKLgc3hfs8ZIIAdIfpRs9Mv3RUh5TeW1pJGtuXEmCpI0XnJrv(Pj4beXqzkjjPwO0X3IuMwENkL9ATvJ9A3XDVQvB1zVMBxUDLTrnRx(1v86ytIA7UtN9B4vFB0oEn2RzhVgTaPtHEUml3yTGGHE84oBvUv7oTAx2RTxqmj4i9QZH0uqaiETAwPED9F44IVlkJfOOC2dXjj2utUoYI8roi46B)wudgbz1GG0e1JkLuwxKjXlHQfH2HGfTc4zkevIyCfkHJdjHwRigmDLu5mRj7tvqqfI4rrimlePIjiCMaJK0EPjWcI59TgkgCtj7Ys4b4eeoLI(UR4oZIN)vPYnRDfScskxOa4MfzacplTdr5crTxUUFrPp8rowReXfOoRpl4zOumviVSe9iui3IZCzfvYe2G)IWjsYsQcIXSUqg)DiLilxjHfM7iAKTMnnEHAbdExLjywSxIZeqM0)XRJ(QCWLMTtCLqjp59bClI5n0dMJzEs8g)shrgCaa(DZvAd68mX4)1xqXI5XI6sf8UcIuAolaawZ4cAWAlc6T4KmInjwqSIRGO(JetzHKJbX0ffBotbs9lLG9jjlTe40SvN5LLcEmqwiSkJe8EiOEU2sHhwE0L6nThpCTYGO1qLknv6J(Lww)4b2LzEUK63V4M9v2zDaHxKtR8sSGI9tiY0)B(gX8q9DOqQ0WByQO7hZbnmRwevT26i18ATa2Jxd9(ChBsd4APLBYKekJ8RVot8)XRBFq6aEgQpM9R723FAgBkXPZfa1lrWWjVeiubILF6IJiK0YaVxGYdAk4XNkjjrwkA91bkujgQkqdz8iGKYJ0fwJ8B(WQPROihR6iJXaB9RMYVFQvM5M7xd5z6TUcMT4jCX3xOqHINNlDMx2SDJMPRALHZGcUPZCFAOk2Tm85fwfaPij0k8FpjFgYRN6YZS6nZAOrdGawWnNEABcHDBSBf9nfqyBWmYcmWgffB(B2O0FDZcfZd4iotLERQc6jOxKHdHSfJA3EHmCM7MyL1Nlc3xGthU)0xMm3o2PnW0I612TYz5HANutAEgieMj42OD7gp)s8TONq(IP50RwiNElvsH(Ud)5jDt49Rki)qgHfmWe6B(K88YO4SmjzNKP134HgrMyyIFMsXznawEOvzKrCDcRRk(oJnVplFoT7SL(9fHlRUzHHR5JylIwaXfPOnqAhtdoIbCjfTAQdnTYBBTVlumiIy)ycTBS6fUMjnv9bYdyC1D96LLOOoUMgT7Q3ZXliblLM3CLqjW8YiHT7Ye9ANtXmQPvGZEQhWwjuvpJGLKwkHnlUU(MUmoJmj00CcOSt)fscWSekhAGATZbU9Wuwv9)awG(a9)u3rFO(a)ikJkJxw8ykdiYZ9QZeOze2tAKA(c(FaWWr0UoUNW59kCr(gwvbW2z8JFRT8Quz3rkEWBZpx97AEV1OHPRE5arZymunWmcSDKU8P634O9DCHyr5moYyli9GMVIE9nT6VWly(gZMz0WX7in2OwaBJhdNTnoIeNUcS)V10FA658q4mm5W0pF2VrzoiSnvAiWcJhzko088z4meXNpB4q(F09n3)tU2k9wjCLWpSHBxbVVNxTDEw7Z9T7UU4GJcf800B5Mqp5eSie1gmKIMQVwb9N(JFM(3QV(4CSxEI3tMIdi3uF00uwN4OVX9EG(Z(p6BRxrFtpZFySP(p6O)t67RVR(l0)z9xQxv)5674O)kNXqDiRhRLXif9f4qAMe80d0L8Wj0Um91fqlIHERG(Ho6wv1Tn9t6xAVVV9(Rm3N4pn8N3X3S4gLEYPDf0C2LBiYB7iX6)Yp5jTD9JcigktZ28A198ZZT4r5pn)MA6TB9dzybbvnljbTFmvr0V(SWbWOqAaubZsNc2Cw)tDLWKF9bdTevWwrbDOJM4CkmujTmRBc5lph2MG8HPQcnkCHVx5TRTxl9FhkEl3XQXFKe)LLCwUZZpu)7b)2pVqQPt7rVZL9OnHdAdSDQYHMIInP92w3ROURo2lH2JQUHoDAN4oI0nE8qO)RUrE8PyrqohZpE3rrqTylQiaiW0zo6aNPnf1yquuCfP)tkT5Jl93w5T)Vx9))d
```

### Aura 2: GearScout Missing Buffs

One line of text that is only on screen while something is missing, for example
`Missing 2: Blessing of Might (Bob), Battle Shout (Carl)`. Imports as a single
text aura called `GearScout Missing Buffs`.

```
!WA:2!Twv0UnoruucDLw2iaTkRurAfpmBqlQvQRvBLyfGurkonjBrPjbBh6UcHIg7zC8aoZyMzCB6IGhI4bEUFc5tis8dWxGvfIpG9ty)c4oJDtBbwXlevvp(oN75EVhFN7uRBJznini)6JKICDkJtLdhh0)ObDUeNRteYHzAMGRQVIWuzP4ZdOZ1nFm)svcMio7fdJJvu9h(wRW8ia9ibJRdB3zqqhVS7hLR0IzgpgNrWAQh9ukx)kGyXmSMfDcJOtCBbVkXr2W8upLgl11dJzCMkPUl8qxFHwYMoLkvp8JLvl)tx95z0WYiSQ8XeRjGaDUQ4bZRTFCo3s7w24UDDe87jpb1oHIZOkn6hYH)d7J6rXs)iqaqryocZvNrLoipQoxYvimINplKk3bHttfrqHOUIkUqNW4tHD4eetHIXPkk6SekhPtOimHaSd2bCOubMqjowxn0KIWzm0b3i4gsw)MtRrhzXYITUBalKxT0PhvFmtPGG7Mhh3wKZ1MqYrsBwxLjuoXYrLX3GJBTn6lq7whaxCVWNrXP6epoEguMU5G(hA(UtLllv5bWgZFB)1AB1hK1QRBolLOSL)zjIukY0uTdsjSMQ6IqcE65ioLciFm))rnXutE0mH82QrZMRLIYWilXCW)0VT2(QiuIXjYQThCaA3)nkVbNzqNRcO8h)jRXyiZm1YE7G(OkQMvk8iIWI4AxdbC3gZ3W(21yGCj0jwkMzvJQL)8bMuWKrRXz(ztcWzGWqNuCinf54GAI2QP5zLVglB3CTFuOv5)GKRXwjJRR9RKJQMkKno3s6mr7ZlTRXHPuWmhofTLnk7GAc)TTP5l0EmvL1QxNwE(TH5qtCh3TR)KXJoSvqNdrJ636fD8MyNUC0GEtozOx)dr98goE0eVH(G1kOluz000JiQ6Erj0OVV4EVsLxsVp8HMnF1K2T8dM4h0Yly9wJKuylp)rD63FjHgcidGjkYN1P)OUJ7FbulL96Bw8Gm1By4YqtJnyscAagco56PbvEJWHItPifMrkpLApCKWig1dMvaOs0o3uB1YCQrGEnmCLk540VgMfcH(3UqrtJlN56omiy4XUXcUo7(DLSxI(QCmrI1yuqWsOe9OtTdYDnZH6gQXPqAVP3S8unRUliyrBwShOxPyLYSYvXEj1SyHHtF4Lhvn0)5Ld93yP0sPrJC1Wq(fNjKKtK4SfNuTqoVeAn53bZoyXNxC3LAr0PLP)7m6HnzKSp46d7x1dzonQ8IePc5xUXO7SRZNUFTnwflHrp(AtnTXRlVVPRXKjbc9B71PZGLqRfHvEJ1(5mYQEkdxbZ17UN88YK5o1dbuXSP1xvwpTTXPwTABSe((tj2RL(L3DfJdhHnxuj41VaZzLlFAX7193PyLjtO8P6K7w0WLl40lj5slc79qsf1KlQfgOMmS4y3zygVBrFWHIJlgumSye889)7wAOc)eN93Z5ZAC6F88)k
```

---

## The recipe: build it yourself

Both variants use the same idea. GearScout fires a custom event called
`GEARSCOUT_BUFFS_UPDATED` when the answer changes, and the WeakAura reads the
answer back out of `GearScout.API` when it hears it.

### Variant A: one icon per missing buff

This is the dynamic group version. You create two things: a dynamic group to
hold the icons, and one icon aura inside it that clones itself once per missing
buff.

**Step 1.** In `/wa`, click **New**, choose **Dynamic Group**, and name it
whatever you like. On its **Group** tab set **Grow** to `Right` if you want a
row, or `Down` if you want a column. Leave everything else alone.

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
            ask = b.from and ("Ask " .. b.from) or "",
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
    ask    = { display = "Ask line", type = "string" },
    why    = { display = "Why you want it", type = "string" },
}
```

**Step 6.** Open the icon's **Display** tab. Leave **Icon** / **Source** on
`Automatic`, which is the default and means "use whatever icon the trigger hands
over". Then scroll down to **Sub Elements**, click the small plus button beside
that heading, and choose **Text**. Set the new text's **Display Text** to

```
%ask
```

and set its **To Region's** anchor to `Outer` / `Bottom` so it sits under the
icon. That prints `Ask Bob` under the icon of the buff Bob owes you.

That is the whole thing. Every missing buff becomes one icon in the group, best
first, and the group empties itself when you are fully buffed.

Other text you can use in that box, or anywhere else the aura takes text:

| Type this | You get |
| --- | --- |
| `%n` | the buff name, for example `Blessing of Might` |
| `%i` | the buff icon |
| `%ask` | `Ask Bob` |
| `%caster` | `Bob` |
| `%why` | the one line reason, for example `Straight attack power, so every hit lands harder.` |

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

    return "Missing " .. report.count .. ": " .. table.concat(parts, ", ")
end
```

**Step 6.** On the **Display** tab, set **Display Text** to:

```
%n
```

Done. The aura appears when something is missing and disappears when it is not.

If you only want a count and no names, skip step 5 and use this as the display
text instead, which needs no code at all beyond the trigger:

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
using `%ask`. Put `%c` in the display text and paste this into the function box
that appears:

```lua
function()
    local s = aura_env.state
    if not s then return "" end
    return s.ask or ""
end
```

**Conditions.** Because of the Custom Variables box in step 5, `caster`, `ask`
and `why` appear in the property dropdown on the aura's **Conditions** tab
alongside the built in ones. So you can, for example, colour the icon
differently when the person who owes you the buff is you.

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
6. **Still nothing after a reload?** Leave and rejoin the group, or cast
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
