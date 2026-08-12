-- GearScout / tools/schema.sql
-- Turso (libsql/SQLite) table definitions for what Collector.lua gathers.
-- Every table is keyed by the natural key of the fact it stores, so
-- re-running export-session.mjs against the same or an overlapping session
-- is idempotent: it upserts existing rows rather than duplicating them.
--
-- Applied by hand or by export-session.mjs; nothing here runs itself.

-- Item id seen dropping from a creature in a zone.
CREATE TABLE IF NOT EXISTS item_drops (
    item_id     INTEGER NOT NULL,
    npc_id      INTEGER NOT NULL,
    zone_id     INTEGER,
    zone_name   TEXT,
    seen_at     INTEGER NOT NULL,   -- unix epoch of the most recent sighting
    PRIMARY KEY (item_id, npc_id)
);

-- An item id resolved to its item level, quality, equip slot and required
-- level. One row per item id, refreshed on every re-upload that saw it.
CREATE TABLE IF NOT EXISTS item_meta (
    item_id     INTEGER PRIMARY KEY,
    ilvl        INTEGER,
    quality     INTEGER,
    equip_loc   TEXT,
    req_level   INTEGER,
    seen_at     INTEGER NOT NULL
);

-- Item ids seen as a reward (choice or guaranteed) on a quest's turn in
-- screen, keyed by quest id.
CREATE TABLE IF NOT EXISTS quest_rewards (
    quest_id    INTEGER NOT NULL,
    item_id     INTEGER NOT NULL,
    seen_at     INTEGER NOT NULL,
    PRIMARY KEY (quest_id, item_id)
);

-- Vendor price seen for an item while a merchant window was open. npc_id 0
-- means the merchant's creature id could not be resolved at the time (no
-- valid creature GUID on the open target); the price is still worth having.
CREATE TABLE IF NOT EXISTS vendor_prices (
    item_id       INTEGER NOT NULL,
    npc_id        INTEGER NOT NULL,
    price_copper  INTEGER NOT NULL,
    seen_at       INTEGER NOT NULL,
    PRIMARY KEY (item_id, npc_id)
);

-- Spell rank to level mappings, read off a class trainer window.
-- This table exists because the data is not obtainable any other way: AtlasLoot
-- ships no spell data, and Wowhead's rank tables are JavaScript rendered and so
-- cannot be fetched. A trainer window hands the client every spell it offers
-- with the level it unlocks at, which is exactly this mapping, gathered for
-- free while a player is standing at a trainer anyway.
--
-- spell_name rather than a spell id because the trainer window gives names, and
-- the addon matches spells by name so that every rank of a spell counts as the
-- same button. Names are localized, so client_locale keeps two languages from
-- overwriting each other.
CREATE TABLE IF NOT EXISTS trainer_spells (
    class_file    TEXT    NOT NULL,
    spell_name    TEXT    NOT NULL,
    rank          INTEGER NOT NULL,
    level_req     INTEGER NOT NULL,
    client_locale TEXT    NOT NULL DEFAULT 'enUS',
    seen_at       INTEGER NOT NULL,
    PRIMARY KEY (class_file, spell_name, rank, client_locale)
);
