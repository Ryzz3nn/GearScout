-- GearScout / Comm.lua
-- Transport plus the responder. This file can SEND your own gear and it can
-- register handlers for incoming opcodes, but it contains no code that stores
-- or displays another player's gear. That lives in GearScout_Lead.
--
-- Every ask ends with a pop-up the player has to click. Nothing is ever sent
-- on its own, whether the ask came as a broadcast to the party or raid, or as
-- a whisper naming this one player. The only automatic reply is a decline.
--
-- Blizzard gives every addon message prefix an allowance of 10 messages that
-- refills at 1 per second. Going over it drops messages silently, so every
-- send goes through a token bucket sized just under that budget, and replies
-- are jittered so twenty five raiders do not answer in the same frame.

local ADDON, ns = ...

local C_ChatInfo = C_ChatInfo
local SendAddonMessage = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or _G.SendAddonMessage
local RegisterPrefix = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or _G.RegisterAddonMessagePrefix
local GetTime, C_Timer = GetTime, C_Timer
local format, strsplit, tonumber = string.format, strsplit, tonumber
local floor, min, random = math.floor, math.min, math.random
local tinsert, tremove, ipairs = table.insert, table.remove, ipairs

local PREFIX = ns.PREFIX
local SEP = "~"                 -- envelope separator, deliberately not a pipe
local MAX_BODY = 240            -- hard client limit is 255
local CHUNK = 200

local Comm = {}
ns.Comm = Comm
Comm.SEP = SEP

-- ---------------------------------------------------------------------------
-- outbound token bucket
-- ---------------------------------------------------------------------------
local BUCKET_MAX = 8            -- two under the real allowance, as headroom
local tokens = BUCKET_MAX
local lastRefill = GetTime()
local queue = {}
local ticker

local function Pump()
    local now = GetTime()
    local elapsed = now - lastRefill
    if elapsed >= 1 then
        local gained = floor(elapsed)
        tokens = min(BUCKET_MAX, tokens + gained)
        lastRefill = lastRefill + gained
    end

    while tokens > 0 and #queue > 0 do
        local m = tremove(queue, 1)
        SendAddonMessage(PREFIX, m.body, m.channel, m.target)
        tokens = tokens - 1
    end

    if #queue == 0 and ticker then
        ticker:Cancel()
        ticker = nil
    end
end

-- No permanent timer. The ticker only exists while something is waiting.
function Comm.Send(body, channel, target)
    if #body > MAX_BODY then return false end
    queue[#queue + 1] = { body = body, channel = channel, target = target }
    Pump()
    if #queue > 0 and not ticker then
        ticker = C_Timer.NewTicker(0.5, Pump)
    end
    return true
end

function Comm.SendChunked(op, nonce, payload, channel, target)
    local total = math.ceil(#payload / CHUNK)
    if total == 0 then total = 1 end
    for i = 1, total do
        local piece = payload:sub((i - 1) * CHUNK + 1, i * CHUNK)
        Comm.Send(table.concat({ op, nonce, i, total, piece }, SEP), channel, target)
    end
end

-- ---------------------------------------------------------------------------
-- inbound dispatch
-- An opcode with no registered handler is ignored. The base addon only ever
-- registers "q", so a plain member never even parses gear data.
-- ---------------------------------------------------------------------------
local ops = {}

function Comm.RegisterOp(op, fn)
    ops[op] = fn
end

ns:On("CHAT_MSG_ADDON", function(prefix, message, channel, sender)
    if prefix ~= PREFIX or not message then return end
    if sender == ns.playerFull or sender == ns.playerName then return end
    local op, rest = message:match("^(%a)" .. SEP .. "(.*)$")
    if not op then return end
    local fn = ops[op]
    if fn then fn(rest, channel, sender) end
end)

ns:On("PLAYER_LOGIN", function()
    if RegisterPrefix then RegisterPrefix(PREFIX) end
end)

-- ---------------------------------------------------------------------------
-- payload
-- One compact line per equipped slot. The lead rebuilds a real item link from
-- these numbers, so tooltips work without sending any strings.
-- ---------------------------------------------------------------------------
local function BuildPayload()
    -- Refresh if the cached scan is stale.
    if not ns.lastReport or not ns.lastScan
       or (GetTime() - (ns.lastScan.scannedAt or 0)) > 60 then
        ns.Evaluate()
    end
    local scan, report = ns.lastScan, ns.lastReport
    if not scan or not report then return nil end

    local parts = {}
    parts[1] = table.concat({
        "h",
        scan.level or 0,
        scan.class or "",
        report.score or 0,
        ns.Round((report.avgIlvl or 0) * 10),
        report.counts.missingEnchants or 0,
        report.counts.emptySockets or 0,
        report.counts.emptySlots or 0,
    }, ":")

    for i = 1, #scan.slots do
        local r = scan.slots[i]
        if not r.empty then
            local g = r.gems or { 0, 0, 0, 0 }
            parts[#parts + 1] = table.concat({
                r.slotID, r.itemID or 0, r.ilvl or 0, r.enchantID or 0,
                g[1] or 0, g[2] or 0, g[3] or 0, g[4] or 0, r.sockets or 0,
            }, ":")
        end
    end

    if ns.db and ns.db.shareRotation then
        local fights = ns.GetFights and ns.GetFights() or nil
        local f = fights and fights[1]
        if f then
            local crit = 0
            for _, x in ipairs(f.findings) do
                if x.sev == ns.SEVERITY.CRITICAL then crit = crit + 1 end
            end
            parts[#parts + 1] = table.concat({
                "r", f.spec or "", ns.Round((f.deadPct or 0) * 100),
                ns.Round(f.cpm or 0), crit, ns.Round(f.dur or 0),
            }, ":")
        end
    end

    return table.concat(parts, ";")
end
ns.BuildPayload = BuildPayload

-- ---------------------------------------------------------------------------
-- who is allowed to be asked
-- ns.db.respondTo still gates everything, but it no longer decides whether to
-- answer automatically, only whether this sender is even allowed to make the
-- pop-up appear. "nobody" is turned away before any of this runs, since that
-- setting means the question was already answered.
--
-- Guild channel used to be trusted on its own, since only guild members can
-- post there. A targeted ask now always arrives by whisper instead, so guild
-- membership is checked by name against the roster the same way either way.
-- ---------------------------------------------------------------------------
local function Short(n)
    if not n then return nil end
    return n:match("^[^%-]+") or n
end

local function IsGuildmate(shortSender)
    if not (IsInGuild and IsInGuild()) then return false end
    local total = GetNumGuildMembers and GetNumGuildMembers() or 0
    for i = 1, total do
        local name = GetGuildRosterInfo(i)
        if name and Short(name) == shortSender then return true end
    end
    return false
end

-- Called only for modes that are not "nobody"; the responder turns that one
-- away before this ever runs.
local function MayAsk(sender, mode)
    if mode == "anyone" then return true end

    -- Unit functions match a plain character name. CHAT_MSG_ADDON hands us
    -- "Name-Realm", which never matches a same realm unit, so every check
    -- below silently answered false until this was stripped.
    local who = Short(sender)

    if mode == "leaders" then
        local inGroup = UnitInRaid(who) or UnitInParty(who)
        if not inGroup then return false, "they are not in your group" end
        if UnitIsGroupLeader(who)
           or (UnitIsGroupAssistant and UnitIsGroupAssistant(who)) then
            return true
        end
        return false, "they are not the group leader, and you only answer leaders"
    end

    if mode == "guild" then
        if IsGuildmate(who) then return true end
        return false, "not sharing with guild"
    end

    return false, "not sharing"
end

-- ---------------------------------------------------------------------------
-- consent prompt
-- The one pop-up GearScout ever shows. "Always share with them" remembers
-- the asker by short name in ns.db.trustedRequesters, a plain table that is
-- created the first time it is needed and saved the same way ns.db.window is.
-- ---------------------------------------------------------------------------
local pending = nil   -- { nonce, sender }, the one request currently on screen

local function DeclineSilently(nonce, sender, reason)
    Comm.Send(table.concat({ "x", nonce, reason or "declined" }, SEP), "WHISPER", sender)
end

local function AcceptAndSend(nonce, sender)
    -- Spread the answers out. Without this a whole raid clicking "Share" at
    -- once replies in the same frame and most of it is dropped by the throttle.
    C_Timer.After(random() * 2.5, function()
        local payload = BuildPayload()
        if not payload then return end
        Comm.SendChunked("d", nonce, payload, "WHISPER", sender)
    end)
end

StaticPopupDialogs["GEARSCOUT_SHARE_REQUEST"] = {
    text = "%s wants to see your gear through GearScout. Share it?",
    button1 = "Share",
    button2 = "Decline",
    button3 = "Always share with them",
    OnAccept = function(self)
        local d = self.data
        if d then AcceptAndSend(d.nonce, d.sender) end
    end,
    OnCancel = function(self)
        local d = self.data
        if d then DeclineSilently(d.nonce, d.sender, "declined") end
    end,
    OnAlt = function(self)
        local d = self.data
        if not d then return end
        if ns.db then
            ns.db.trustedRequesters = ns.db.trustedRequesters or {}
            ns.db.trustedRequesters[Short(d.sender)] = true
        end
        AcceptAndSend(d.nonce, d.sender)
    end,
    OnHide = function(self)
        local d = self.data
        if pending and d and pending.nonce == d.nonce and pending.sender == d.sender then
            pending = nil
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    showAlert = true,
    preferredIndex = 3,
}

-- ---------------------------------------------------------------------------
-- responder
-- Every ask ends in exactly one of three things: an instant "x" (nobody, or
-- this sender does not qualify under respondTo), an instant "d" (this sender
-- is on the trusted list), or the pop-up above. Nothing ever goes out on its
-- own past this point.
-- ---------------------------------------------------------------------------
Comm.RegisterOp("q", function(rest, channel, sender)
    local nonce = strsplit(SEP, rest)
    if not nonce then return end

    local mode = (ns.db and ns.db.respondTo) or "leaders"
    if mode == "nobody" then
        DeclineSilently(nonce, sender, "declined")
        return
    end

    -- The same request arriving twice, for example a dropped ack, should not
    -- flicker the pop-up that is already on screen for it.
    if pending and pending.nonce == nonce and pending.sender == sender then
        return
    end

    local short = Short(sender)
    local trusted = ns.db and ns.db.trustedRequesters and ns.db.trustedRequesters[short]

    if not trusted then
        local allowed, reason = MayAsk(sender, mode)
        if not allowed then
            DeclineSilently(nonce, sender, reason)
            return
        end
    end

    if trusted then
        AcceptAndSend(nonce, sender)
        return
    end

    -- One open decision at a time. If a second, different ask arrives before
    -- the player answers the first, the first asker is told plainly instead
    -- of being left waiting forever with no reply.
    if pending then
        local old = pending
        pending = nil
        StaticPopup_Hide("GEARSCOUT_SHARE_REQUEST")
        DeclineSilently(old.nonce, old.sender, "replaced by a newer request")
    end

    pending = { nonce = nonce, sender = sender }
    StaticPopup_Show("GEARSCOUT_SHARE_REQUEST", short, nil, pending)
end)

-- ---------------------------------------------------------------------------
-- shared decoder, used by the lead addon
-- Kept here so both sides always agree on the format, but it is a pure parser:
-- it stores nothing and shows nothing.
-- ---------------------------------------------------------------------------
function Comm.DecodePayload(payload)
    local out = { slots = {}, bySlotID = {} }
    for record in payload:gmatch("[^;]+") do
        local kind = record:sub(1, 1)
        if kind == "h" then
            local _, level, class, score, ilvl10, ench, sockets, empty = strsplit(":", record)
            out.level = tonumber(level) or 0
            out.class = class
            out.score = tonumber(score) or 0
            out.avgIlvl = (tonumber(ilvl10) or 0) / 10
            out.missingEnchants = tonumber(ench) or 0
            out.emptySockets = tonumber(sockets) or 0
            out.emptySlots = tonumber(empty) or 0
        elseif kind == "r" then
            local _, spec, dead, cpm, crit, dur = strsplit(":", record)
            out.rotation = {
                spec = spec,
                deadPct = (tonumber(dead) or 0) / 100,
                cpm = tonumber(cpm) or 0,
                crit = tonumber(crit) or 0,
                dur = tonumber(dur) or 0,
            }
        else
            local slotID, itemID, ilvl, ench, g1, g2, g3, g4, sockets = strsplit(":", record)
            slotID = tonumber(slotID)
            if slotID then
                local gemsFilled = 0
                for _, g in ipairs({ g1, g2, g3, g4 }) do
                    if (tonumber(g) or 0) ~= 0 then gemsFilled = gemsFilled + 1 end
                end
                local rec = {
                    slotID  = slotID,
                    itemID  = tonumber(itemID) or 0,
                    ilvl    = tonumber(ilvl) or 0,
                    enchantID = tonumber(ench) or 0,
                    sockets = tonumber(sockets) or 0,
                    gemsFilled = gemsFilled,
                    link = format("item:%s:%s:%s:%s:%s:%s",
                                  itemID, ench, g1 or 0, g2 or 0, g3 or 0, g4 or 0),
                }
                rec.emptySockets = math.max(0, rec.sockets - gemsFilled)
                out.slots[#out.slots + 1] = rec
                out.bySlotID[slotID] = rec
            end
        end
    end
    return out
end
