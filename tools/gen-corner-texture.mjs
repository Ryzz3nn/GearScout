// GearScout / tools/gen-corner-texture.mjs
// Plain Node script, no dependencies. Generates a 64x64 uncompressed 32 bit
// TGA of a rounded rectangle that fills the whole image, corner radius 16px.
// White RGB everywhere, shape carried in the alpha channel so any panel can
// tint it at runtime with SetVertexColor. The edge is antialiased by
// supersampling each pixel and turning the inside/outside coverage ratio
// into an alpha value, so the curve is not jagged.
//
// Run with: node gen-corner-texture.mjs
// Output:   ../GearScout/media/roundrect.tga

import { writeFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const SIZE = 64;          // power of two, required by WoW
const RADIUS = 16;        // corner radius in pixels
const SUPERSAMPLE = 4;    // NxN subsamples per pixel for antialiasing

const HERE = path.dirname(fileURLToPath(import.meta.url));
const OUT_DIR = path.join(HERE, "..", "GearScout", "media");
const OUT_FILE = path.join(OUT_DIR, "roundrect.tga");

// True if the point (px, py), given relative to the rectangle centre, falls
// inside a rectangle of half extents (halfW, halfH) with corners rounded to
// radius r. The straight edges are a simple bounds check; the four corners
// each reduce to a circle test around the corner's own centre.
function insideRoundedRect(px, py, halfW, halfH, r) {
    const ax = Math.abs(px);
    const ay = Math.abs(py);
    if (ax > halfW || ay > halfH) return false;
    if (ax <= halfW - r || ay <= halfH - r) return true;
    const dx = ax - (halfW - r);
    const dy = ay - (halfH - r);
    return (dx * dx + dy * dy) <= r * r;
}

function coverageAt(x, y) {
    const halfW = SIZE / 2;
    const halfH = SIZE / 2;
    let hits = 0;
    const step = 1 / SUPERSAMPLE;
    const half = step / 2;
    for (let sy = 0; sy < SUPERSAMPLE; sy++) {
        for (let sx = 0; sx < SUPERSAMPLE; sx++) {
            const px = (x + sx * step + half) - halfW;
            const py = (y + sy * step + half) - halfH;
            if (insideRoundedRect(px, py, halfW, halfH, RADIUS)) hits++;
        }
    }
    return hits / (SUPERSAMPLE * SUPERSAMPLE);
}

// Pixel data, top row first (y = 0 is the top of the intended image). Paired
// with the top left origin bit in the TGA header below, this stores and
// reads back the same way so the image is not flipped.
const pixels = Buffer.alloc(SIZE * SIZE * 4);
let o = 0;
for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
        const coverage = coverageAt(x, y);
        const a = Math.round(coverage * 255);
        // TGA true colour pixels are stored B, G, R, A.
        pixels[o++] = 255; // B
        pixels[o++] = 255; // G
        pixels[o++] = 255; // R
        pixels[o++] = a;   // A
    }
}

// 18 byte TGA header.
const header = Buffer.alloc(18);
header[0] = 0;                 // ID length
header[1] = 0;                 // colour map type: none
header[2] = 2;                 // image type: uncompressed true colour
// bytes 3-7: colour map spec, unused, left zero
header.writeUInt16LE(0, 8);    // x origin
header.writeUInt16LE(0, 10);   // y origin
header.writeUInt16LE(SIZE, 12); // width
header.writeUInt16LE(SIZE, 14); // height
header[16] = 32;               // bits per pixel
// image descriptor: bits 0-3 alpha depth (8), bit 5 set = top left origin
header[17] = 0x08 | 0x20;

const tga = Buffer.concat([header, pixels]);

mkdirSync(OUT_DIR, { recursive: true });
writeFileSync(OUT_FILE, tga);

console.log(`wrote ${OUT_FILE} (${tga.length} bytes, ${SIZE}x${SIZE}, 32bpp)`);
