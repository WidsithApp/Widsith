// Draws the glow behind the recorder's icon (Save.lua) when a save is due: a soft warm-gold
// halo, 64×64 TGA, each pixel the average of 8×8 samples.
//
//   node tools/build-glow.mjs [preview.png]      (from the addon's folder; tools/previews is ignored)
//
// Writes media/glow.tga. Save.lua draws it at 1.45× the icon, centred, behind the ring:
// 42 px ring → 61 px glow, so the ring's edge (radius 21) is at about 22 texels and the halo
// fades out over the next 10.

import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import { fileURLToPath } from 'node:url';

const SIZE = 64;
const SS = 8;
const C = SIZE / 2;
const GOLD = [1, 0.82, 0.36];

const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
const smooth = (e0, e1, x) => {
	const t = clamp((x - e0) / (e1 - e0));
	return t * t * (3 - 2 * t);
};

// Premultiplied colour and alpha at a point: full under the ring, fading to nothing past it.
function sample(x, y) {
	const d = Math.hypot(x - C, y - C);
	const a = 0.75 * (1 - smooth(19, 31.5, d));
	return [GOLD[0] * a, GOLD[1] * a, GOLD[2] * a, a];
}

function render() {
	const out = new Float64Array(SIZE * SIZE * 4);
	for (let y = 0; y < SIZE; y++) {
		for (let x = 0; x < SIZE; x++) {
			const acc = [0, 0, 0, 0];
			for (let sy = 0; sy < SS; sy++) {
				for (let sx = 0; sx < SS; sx++) {
					const p = sample(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS);
					for (let i = 0; i < 4; i++) acc[i] += p[i];
				}
			}
			const o = (y * SIZE + x) * 4;
			for (let i = 0; i < 4; i++) out[o + i] = acc[i] / (SS * SS);
		}
	}
	return out;
}

const byte = (v) => Math.round(clamp(v) * 255);

// Straight alpha, as the game expects.
function straight(px, o) {
	const a = px[o + 3];
	if (a <= 0) return [0, 0, 0, 0];
	return [byte(px[o] / a), byte(px[o + 1] / a), byte(px[o + 2] / a), byte(a)];
}

// Uncompressed 32-bit TGA, bottom-left origin (rows written bottom up), BGRA.
function tga(px) {
	const header = Buffer.alloc(18);
	header[2] = 2;
	header.writeUInt16LE(SIZE, 12);
	header.writeUInt16LE(SIZE, 14);
	header[16] = 32;
	header[17] = 8;
	const body = Buffer.alloc(SIZE * SIZE * 4);
	let k = 0;
	for (let y = SIZE - 1; y >= 0; y--) {
		for (let x = 0; x < SIZE; x++) {
			const [r, g, b, a] = straight(px, (y * SIZE + x) * 4);
			body[k++] = b;
			body[k++] = g;
			body[k++] = r;
			body[k++] = a;
		}
	}
	return Buffer.concat([header, body]);
}

// A preview over a dark background, 4× size.
function preview(px, file) {
	const S = 4, W = SIZE * S, bg = [30, 30, 34];
	const raw = Buffer.alloc((W * 3 + 1) * W);
	for (let y = 0; y < W; y++) {
		raw[y * (W * 3 + 1)] = 0;
		for (let x = 0; x < W; x++) {
			const o = (Math.floor(y / S) * SIZE + Math.floor(x / S)) * 4;
			for (let i = 0; i < 3; i++) raw[y * (W * 3 + 1) + 1 + x * 3 + i] = byte(px[o + i] + (bg[i] / 255) * (1 - px[o + 3]));
		}
	}
	const CRC = new Int32Array(256).map((_, n) => {
		let c = n;
		for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
		return c;
	});
	const crc32 = (buf) => {
		let c = -1;
		for (const b of buf) c = CRC[(c ^ b) & 0xff] ^ (c >>> 8);
		return (c ^ -1) >>> 0;
	};
	const chunk = (type, data) => {
		const len = Buffer.alloc(4);
		len.writeUInt32BE(data.length);
		const td = Buffer.concat([Buffer.from(type), data]);
		const crc = Buffer.alloc(4);
		crc.writeUInt32BE(crc32(td));
		return Buffer.concat([len, td, crc]);
	};
	const ihdr = Buffer.alloc(13);
	ihdr.writeUInt32BE(W, 0);
	ihdr.writeUInt32BE(W, 4);
	ihdr[8] = 8;
	ihdr[9] = 2;
	fs.writeFileSync(file, Buffer.concat([
		Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
		chunk('IHDR', ihdr),
		chunk('IDAT', zlib.deflateSync(raw)),
		chunk('IEND', Buffer.alloc(0))
	]));
}

const here = path.dirname(fileURLToPath(import.meta.url));
const media = path.join(here, '..', 'media');
fs.mkdirSync(media, { recursive: true });
const px = render();
fs.writeFileSync(path.join(media, 'glow.tga'), tga(px));
console.log('wrote media/glow.tga');
if (process.argv[2]) {
	preview(px, process.argv[2]);
	console.log('preview', process.argv[2]);
}
