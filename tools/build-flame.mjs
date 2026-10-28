// Draws the recorder's icon (Save.lua): the Widsith flame on a midnight disc, inside the game's
// own ring. The flame is the Widsith mark: one asymmetric flame with two tongues, drawn four
// times inward from its base, dark to light; three layers under 24 px. In game each layer is its
// own texture, so the addon can scale it (the flame shrinks as unsaved play grows), tint it (lit,
// dimming, or out) and animate it (breathing, and the halo when recording starts). The layers are
// therefore shipped WHITE, as alpha shapes, and coloured in Lua with SetVertexColor; one strip
// holds every layer at its scale.
//
//   node tools/build-flame.mjs [previewDir]      (from the addon's folder; tools/previews is ignored)
//
// Writes to media/:
//   flame.tga        512×64, eight 64 px cells in a row (two spare): the outline at scales
//                    1, 0.8, 0.58, 0.34 (the four-layer flame) then 0.72, 0.42 (the inner two of
//                    the three-layer flame, which shares the outer). Small and Medium.
//   flame-large.tga  1024×128, the same at 128 px cells. Large.
//   disc.tga         64×64, the midnight plate under the flame, shaded toward the rim so it seats
//                    under the ring.
//   emblem.tga       64×64, the addon list's icon (TOC IconTexture): the disc with the lit
//                    four-layer flame on it.
// Every cell is rendered at 8× and shrunk with a Lanczos filter, so its edges are already smooth;
// a texture close to its size on screen stays smooth where a much larger one sampled small is
// jaggy. Renders with sharp, the one dependency in tools/package.json (run `npm install` in
// tools/ first).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = path.dirname(fileURLToPath(import.meta.url));

const SUPER = 8;

/** The flame's outline in a 64-unit box; every layer is this, scaled about the base centre (32, 61). */
const OUTLINE =
	'M39 3 C42 14 53 22 53 38 C53 51 44 61 32 61 C20 61 11 52 11 41 C11 32 15 27 19 19 C20.5 25 23 29 27 31 C25.5 21 30 12 39 3 Z';
/** The cells of the strip: the four-layer flame's scales, then the three-layer flame's inner two. */
const CELLS = [1, 0.8, 0.58, 0.34, 0.72, 0.42];
const STRIP_CELLS = 8;
/** The lit colours, outer to heart, for the addon list's icon (the game tints the strip itself). */
const LIT = ['#b9521a', '#e08a2b', '#f4b04a', '#fff4d6'];
const MIDNIGHT = '#141829';

function layer(scale, fill) {
	return `<path d="${OUTLINE}" fill="${fill}" transform="translate(32 61) scale(${scale}) translate(-32 -61)"/>`;
}

/** The strip: one white flame per cell, each at its scale, in a row. */
function strip(cell) {
	const w = cell * STRIP_CELLS;
	const cells = CELLS.map((s, i) => `<g transform="translate(${i * 64} 0)">${layer(s, '#fff')}</g>`).join('');
	return `<svg xmlns="http://www.w3.org/2000/svg" width="${w * SUPER}" height="${cell * SUPER}" viewBox="0 0 ${64 * STRIP_CELLS} 64">${cells}</svg>`;
}

/** The midnight plate: a disc darker toward the rim, lit a little high and left as the game's discs are. */
function disc(mark) {
	return `
<svg xmlns="http://www.w3.org/2000/svg" width="${64 * SUPER}" height="${64 * SUPER}" viewBox="0 0 64 64">
  <defs>
    <radialGradient id="plate" cx="42%" cy="36%" r="70%">
      <stop offset="0%" stop-color="#2a3050"/><stop offset="100%" stop-color="${MIDNIGHT}"/>
    </radialGradient>
    <radialGradient id="rim" cx="50%" cy="50%" r="50%">
      <stop offset="74%" stop-color="#000" stop-opacity="0"/><stop offset="100%" stop-color="#000" stop-opacity="0.55"/>
    </radialGradient>
    <clipPath id="disc"><circle cx="32" cy="32" r="32"/></clipPath>
  </defs>
  <g clip-path="url(#disc)">
    <circle cx="32" cy="32" r="32" fill="url(#plate)"/>
    ${mark}
    <circle cx="32" cy="32" r="32" fill="url(#rim)"/>
  </g>
</svg>`;
}

/** The flame as the icon draws it on the disc: the 64 box scaled to FLAME of the disc, its bottom at
 *  BOTTOM of the disc's height from the top, so the base stands just clear of the rim's shadow.
 *  Save.lua lays the layers out the same way. */
const FLAME = 0.8;
const BOTTOM = 0.88;
function flameOnDisc() {
	const k = FLAME;
	const layers = LIT.map((fill, i) => layer(CELLS[i], fill)).join('');
	return `<g transform="translate(${32 - 32 * k} ${64 * BOTTOM - 64 * k}) scale(${k})">${layers}</g>`;
}

// Uncompressed 32-bit TGA, bottom-left origin (rows written bottom up), BGRA, straight alpha.
function tga(rgba, width, height) {
	const header = Buffer.alloc(18);
	header[2] = 2;
	header.writeUInt16LE(width, 12);
	header.writeUInt16LE(height, 14);
	header[16] = 32;
	header[17] = 8;
	const body = Buffer.alloc(width * height * 4);
	let k = 0;
	for (let y = height - 1; y >= 0; y--) {
		for (let x = 0; x < width; x++) {
			const o = (y * width + x) * 4;
			body[k++] = rgba[o + 2];
			body[k++] = rgba[o + 1];
			body[k++] = rgba[o];
			body[k++] = rgba[o + 3];
		}
	}
	return Buffer.concat([header, body]);
}

const TEXTURES = [
	{ file: 'flame', svg: strip(64), width: 64 * STRIP_CELLS, height: 64 },
	{ file: 'flame-large', svg: strip(128), width: 128 * STRIP_CELLS, height: 128 },
	{ file: 'disc', svg: disc(''), width: 64, height: 64 },
	{ file: 'emblem', svg: disc(flameOnDisc()), width: 64, height: 64 }
];

const media = path.join(here, '..', 'media');
fs.mkdirSync(media, { recursive: true });
const previewDir = process.argv[2];
if (previewDir) fs.mkdirSync(previewDir, { recursive: true });
for (const { file, svg, width, height } of TEXTURES) {
	const big = await sharp(Buffer.from(svg)).png().toBuffer();
	const small = sharp(big).resize(width, height, { kernel: 'lanczos3' }).ensureAlpha();
	const { data } = await small.clone().raw().toBuffer({ resolveWithObject: true });
	fs.writeFileSync(path.join(media, `${file}.tga`), tga(data, width, height));
	console.log(`wrote media/${file}.tga (${width}×${height})`);
	if (previewDir) {
		await small
			.clone()
			.flatten({ background: '#3a3a44' })
			.resize(width * 4, height * 4, { kernel: 'nearest' })
			.png()
			.toFile(path.join(previewDir, `${file}.png`));
	}
}

// A preview of the icon as the game composes it at Small: the disc at 33 px with the strip's
// layers tinted and stood on the base, lit, burnt down, and out.
if (previewDir) {
	const SIZE = 33;
	const base = (await sharp(Buffer.from(disc(''))).png().resize(SIZE, SIZE, { kernel: 'lanczos3' }).toBuffer());
	const strip64 = await sharp(Buffer.from(strip(64))).png().resize(64 * STRIP_CELLS, 64, { kernel: 'lanczos3' }).toBuffer();
	const states = [
		{ name: 'lit', gauge: 1, layers: [0, 4, 5], colours: ['#b9521a', '#f4b04a', '#fff4d6'] },
		{ name: 'half', gauge: 0.55, layers: [0, 4, 5], colours: ['#b9521a', '#f4b04a', '#fff4d6'] },
		{ name: 'ember', gauge: 0.2, layers: [0, 4, 5], colours: ['#b9521a', '#f4b04a', '#fff4d6'] },
		{ name: 'out', gauge: 1, layers: [0, 4], colours: ['#6f6a72', '#4d4954'] }
	];
	const tiles = [];
	for (const s of states) {
		const flame = Math.round(SIZE * FLAME * s.gauge);
		const comps = [];
		for (let i = 0; i < s.layers.length; i++) {
			const cell = s.layers[i];
			const tint = s.colours[i];
			// Tinted as the game tints a white texture: the colour under the shape's alpha.
			const alpha = await sharp(strip64)
				.extract({ left: cell * 64, top: 0, width: 64, height: 64 })
				.resize(Math.max(1, flame), Math.max(1, flame), { kernel: 'lanczos3' })
				.extractChannel('alpha')
				.toBuffer();
			const shape = await sharp({ create: { width: Math.max(1, flame), height: Math.max(1, flame), channels: 3, background: tint } })
				.joinChannel(alpha)
				.png()
				.toBuffer();
			comps.push({ input: shape, left: Math.round((SIZE - flame) / 2), top: Math.round(SIZE * BOTTOM - flame) });
		}
		tiles.push(await sharp(base).composite(comps).png().toBuffer());
	}
	// Composited first, then enlarged: sharp resizes before it composites whatever the order of calls.
	const sheet = await sharp({ create: { width: (SIZE + 8) * tiles.length + 8, height: SIZE + 16, channels: 4, background: '#3a3a44' } })
		.composite(tiles.map((input, i) => ({ input, left: 8 + i * (SIZE + 8), top: 8 })))
		.png()
		.toBuffer();
	await sharp(sheet).resize(((SIZE + 8) * tiles.length + 8) * 6, (SIZE + 16) * 6, { kernel: 'nearest' }).toFile(path.join(previewDir, 'icon-states.png'));
	console.log('preview', path.join(previewDir, 'icon-states.png'));
}
