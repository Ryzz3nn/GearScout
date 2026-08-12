#!/usr/bin/env node
// tools/build-installer.mjs
//
// Bundles the multi file GearScoutInstaller (installer/*.ps1, *.xaml, lib/*.ps1,
// README.txt) plus the public addon zip (dist/GearScout-*.zip, never the Lead
// zip) into ONE self contained Windows batch file: dist/GearScoutInstaller.bat.
//
// That single .bat is what gets handed out. It is double clickable (no right
// click, no unblocking, no execution policy prompt) because it invokes
// PowerShell itself with -NoProfile -ExecutionPolicy Bypass. Everything it
// needs travels inside it, after a ":PAYLOAD" marker line, as base64 text
// decoding to a plain ZIP archive. On run it extracts that archive to a fresh
// folder under %TEMP%, launches the installer GUI from there, and removes the
// temp folder again once the GUI closes.
//
// Run with: node tools/build-installer.mjs

import { readFileSync, writeFileSync, mkdirSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import zlib from 'node:zlib';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const INSTALLER_DIR = path.join(ROOT, 'installer');
const DIST_DIR = path.join(ROOT, 'dist');
const OUTPUT_PATH = path.join(DIST_DIR, 'GearScoutInstaller.bat');

const PAYLOAD_MARKER = ':PAYLOAD';
const BASE64_LINE_WIDTH = 100;

// ---------------------------------------------------------------------------
// Pick the public addon zip out of dist/. Matches "GearScout-<version>.zip"
// and deliberately excludes "GearScout_Lead-*.zip": that one is the officer
// console, handed out privately, and must never end up in the public
// installer. If several match, the most recently built one wins.
// ---------------------------------------------------------------------------
function findAddonZip() {
    const candidates = readdirSync(DIST_DIR)
        .filter((name) => /^GearScout-.*\.zip$/i.test(name))
        .map((name) => {
            const full = path.join(DIST_DIR, name);
            return { name, full, mtime: statSync(full).mtimeMs };
        })
        .sort((a, b) => b.mtime - a.mtime);

    if (candidates.length === 0) {
        throw new Error(
            `No public addon zip found in ${DIST_DIR} (expected something like GearScout-<version>.zip).`
        );
    }
    return candidates[0];
}

// ---------------------------------------------------------------------------
// Minimal ZIP writer. Every entry is stored (no compression): the ps1/xaml/
// txt sources are small, and the addon zip is already compressed, so storing
// it raw means its bytes travel through unchanged rather than being
// decompressed and recompressed. That also means the addon zip's own
// forward slash entry paths are carried through as-is, never rebuilt.
// ---------------------------------------------------------------------------
function dosDateTime(date) {
    const dosTime =
        ((date.getHours() & 0x1f) << 11) |
        ((date.getMinutes() & 0x3f) << 5) |
        ((Math.floor(date.getSeconds() / 2)) & 0x1f);
    const dosDate =
        (((date.getFullYear() - 1980) & 0x7f) << 9) |
        (((date.getMonth() + 1) & 0xf) << 5) |
        (date.getDate() & 0x1f);
    return { dosTime, dosDate };
}

function buildZip(entries) {
    const { dosTime, dosDate } = dosDateTime(new Date());
    const localParts = [];
    const centralParts = [];
    let offset = 0;

    for (const entry of entries) {
        const nameBuf = Buffer.from(entry.name, 'utf8');
        const data = entry.data;
        const crc = zlib.crc32(data) >>> 0;
        const size = data.length;

        const localHeader = Buffer.alloc(30);
        localHeader.writeUInt32LE(0x04034b50, 0);
        localHeader.writeUInt16LE(20, 4); // version needed to extract
        localHeader.writeUInt16LE(0x0800, 6); // flags: UTF-8 name
        localHeader.writeUInt16LE(0, 8); // method: store
        localHeader.writeUInt16LE(dosTime, 10);
        localHeader.writeUInt16LE(dosDate, 12);
        localHeader.writeUInt32LE(crc, 14);
        localHeader.writeUInt32LE(size, 18); // compressed size
        localHeader.writeUInt32LE(size, 22); // uncompressed size
        localHeader.writeUInt16LE(nameBuf.length, 26);
        localHeader.writeUInt16LE(0, 28); // extra field length

        localParts.push(localHeader, nameBuf, data);

        const centralHeader = Buffer.alloc(46);
        centralHeader.writeUInt32LE(0x02014b50, 0);
        centralHeader.writeUInt16LE(20, 4); // version made by
        centralHeader.writeUInt16LE(20, 6); // version needed to extract
        centralHeader.writeUInt16LE(0x0800, 8); // flags
        centralHeader.writeUInt16LE(0, 10); // method: store
        centralHeader.writeUInt16LE(dosTime, 12);
        centralHeader.writeUInt16LE(dosDate, 14);
        centralHeader.writeUInt32LE(crc, 16);
        centralHeader.writeUInt32LE(size, 20);
        centralHeader.writeUInt32LE(size, 24);
        centralHeader.writeUInt16LE(nameBuf.length, 28);
        centralHeader.writeUInt16LE(0, 30); // extra field length
        centralHeader.writeUInt16LE(0, 32); // comment length
        centralHeader.writeUInt16LE(0, 34); // disk number start
        centralHeader.writeUInt16LE(0, 36); // internal attributes
        centralHeader.writeUInt32LE(0, 38); // external attributes
        centralHeader.writeUInt32LE(offset, 42); // relative offset of local header

        centralParts.push(centralHeader, nameBuf);

        offset += localHeader.length + nameBuf.length + data.length;
    }

    const centralDirStart = offset;
    const centralDirBuf = Buffer.concat(centralParts);

    const eocd = Buffer.alloc(22);
    eocd.writeUInt32LE(0x06054b50, 0);
    eocd.writeUInt16LE(0, 4); // this disk
    eocd.writeUInt16LE(0, 6); // disk with central dir start
    eocd.writeUInt16LE(entries.length, 8); // entries on this disk
    eocd.writeUInt16LE(entries.length, 10); // entries total
    eocd.writeUInt32LE(centralDirBuf.length, 12);
    eocd.writeUInt32LE(centralDirStart, 16);
    eocd.writeUInt16LE(0, 20); // comment length

    return Buffer.concat([...localParts, centralDirBuf, eocd]);
}

// ---------------------------------------------------------------------------
// The batch header. Kept deliberately simple: one PowerShell -Command call,
// only single quoted PS string literals (so nothing inside it needs a
// literal double quote, which would break out of the quoted cmd argument),
// and the self path / temp path handed in through environment variables
// instead of %~f0 substitution inside the PowerShell text, so spaces in
// either path never have to survive cmd's own parsing twice.
// ---------------------------------------------------------------------------
function buildBatchHeader() {
    const psCommand = [
        `$ErrorActionPreference='Stop'`,
        `$self=$env:GSI_SELF`,
        `$dest=$env:GSI_TEMP`,
        `New-Item -ItemType Directory -Force -Path $dest | Out-Null`,
        `$marker=':PAYLOAD'`,
        `$raw=Get-Content -LiteralPath $self -Raw`,
        // LastIndexOf, not IndexOf: the marker text also appears once earlier,
        // inside this very command line (where it names what to search for).
        // ':' never appears in base64, so the real label line is always the
        // last occurrence in the file, guaranteed unambiguous.
        `$idx=$raw.LastIndexOf($marker)`,
        `if ($idx -lt 0) { throw 'Payload marker not found in this file.' }`,
        `$b64=$raw.Substring($idx+$marker.Length)`,
        `$b64=($b64 -replace '\\s','')`,
        `$bytes=[Convert]::FromBase64String($b64)`,
        `$zipPath=Join-Path $dest 'payload.zip'`,
        `[IO.File]::WriteAllBytes($zipPath,$bytes)`,
        `Add-Type -AssemblyName System.IO.Compression.FileSystem`,
        `[IO.Compression.ZipFile]::ExtractToDirectory($zipPath,$dest)`,
        `Remove-Item -LiteralPath $zipPath -Force`,
        `& (Join-Path $dest 'GearScoutInstaller.ps1')`,
    ].join('; ');

    const lines = [
        '@echo off',
        'rem GearScout Installer, single file edition.',
        'rem Generated by tools/build-installer.mjs. Do not edit this file by hand,',
        'rem edit the sources under installer\\ and rebuild instead.',
        'rem',
        'rem Double click this file. It unpacks itself into a fresh folder under',
        'rem %TEMP%, runs the installer app from there, and deletes that folder',
        'rem again once the app window closes. Nothing else on this computer is',
        'rem touched except the WoW AddOns folder you pick inside the app.',
        'setlocal',
        'set "GSI_SELF=%~f0"',
        'set "GSI_TEMP=%TEMP%\\GearScoutInstaller_%RANDOM%%RANDOM%"',
        '',
        `powershell -NoProfile -ExecutionPolicy Bypass -Command "${psCommand}"`,
        'set "GSI_ERR=%ERRORLEVEL%"',
        '',
        'if exist "%GSI_TEMP%" rmdir /s /q "%GSI_TEMP%"',
        '',
        'if not "%GSI_ERR%"=="0" (',
        '    echo.',
        '    echo GearScout Installer closed with an error. See above for details.',
        '    pause',
        ')',
        '',
        'exit /b %GSI_ERR%',
        '',
        PAYLOAD_MARKER,
    ];

    return lines.join('\r\n') + '\r\n';
}

function wrapBase64(b64, width) {
    const out = [];
    for (let i = 0; i < b64.length; i += width) {
        out.push(b64.slice(i, i + width));
    }
    return out.join('\r\n');
}

function main() {
    const addonZip = findAddonZip();

    const sourceFiles = [
        { src: path.join(INSTALLER_DIR, 'GearScoutInstaller.ps1'), entry: 'GearScoutInstaller.ps1' },
        { src: path.join(INSTALLER_DIR, 'GearScoutInstaller.xaml'), entry: 'GearScoutInstaller.xaml' },
        { src: path.join(INSTALLER_DIR, 'README.txt'), entry: 'README.txt' },
        { src: path.join(INSTALLER_DIR, 'lib', 'Detect.ps1'), entry: 'lib/Detect.ps1' },
        { src: path.join(INSTALLER_DIR, 'lib', 'InstallLogic.ps1'), entry: 'lib/InstallLogic.ps1' },
        { src: addonZip.full, entry: addonZip.name },
    ];

    const entries = sourceFiles.map(({ src, entry }) => ({
        name: entry,
        data: readFileSync(src),
    }));

    const zipBuf = buildZip(entries);
    const b64 = zipBuf.toString('base64');

    const header = buildBatchHeader();
    const payload = wrapBase64(b64, BASE64_LINE_WIDTH);

    const batchText = header + payload + '\r\n';

    mkdirSync(DIST_DIR, { recursive: true });
    writeFileSync(OUTPUT_PATH, batchText, { encoding: 'ascii' });

    const outSize = statSync(OUTPUT_PATH).size;
    console.log(`Bundled ${entries.length} files (addon zip: ${addonZip.name}, ${addonZip.name.includes('Lead') ? 'LEAD, WRONG' : 'public'}).`);
    console.log(`Inner zip: ${zipBuf.length} bytes -> base64: ${b64.length} bytes.`);
    console.log(`Wrote ${OUTPUT_PATH} (${outSize} bytes).`);
}

main();
