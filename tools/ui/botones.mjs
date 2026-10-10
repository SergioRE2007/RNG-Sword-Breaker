// Dibuja las imágenes de fondo de los botones del menú (client/MenuTile), sin dependencias:
//   node tools/ui/botones.mjs
// Salen en assets/logos, en blanco con transparencia, para que el juego las tiña del color de cada botón:
//   boton_patron.png   rombos en mosaico (dos periodos por lado)
//   boton_rayos.png    rayos que salen del centro y se apagan hacia el borde (giran detrás del logo)
//   boton_destello.png estrella de cuatro puntas (los destellos al pasar el ratón)
// Después se suben a Roblox como los logos y su id va en Ui.IMAGES.
import { writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { crc32, deflateSync } from "node:zlib";

const OUT = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "assets", "logos");
const SAMPLES = 4; // muestras por lado en cada píxel, para que los bordes no salgan a dientes

function chunk(type, data) {
	const body = Buffer.concat([Buffer.from(type, "ascii"), data]);
	const head = Buffer.alloc(4);
	head.writeUInt32BE(data.length);
	const tail = Buffer.alloc(4);
	tail.writeUInt32BE(crc32(body));
	return Buffer.concat([head, body, tail]);
}

// `alphaAt(x, y)` devuelve la opacidad (0 a 1) del punto; la imagen es blanca entera.
function draw(name, size, alphaAt) {
	const row = size * 4 + 1;
	const raw = Buffer.alloc(row * size);
	for (let y = 0; y < size; y++) {
		for (let x = 0; x < size; x++) {
			let sum = 0;
			for (let j = 0; j < SAMPLES; j++) {
				for (let i = 0; i < SAMPLES; i++) {
					sum += alphaAt(x + (i + 0.5) / SAMPLES, y + (j + 0.5) / SAMPLES);
				}
			}
			const at = y * row + 1 + x * 4;
			raw[at] = raw[at + 1] = raw[at + 2] = 255;
			raw[at + 3] = Math.round((Math.min(Math.max(sum / (SAMPLES * SAMPLES), 0), 1)) * 255);
		}
	}
	const header = Buffer.alloc(13);
	header.writeUInt32BE(size, 0);
	header.writeUInt32BE(size, 4);
	header.set([8, 6, 0, 0, 0], 8); // 8 bits, RGBA
	const file = Buffer.concat([
		Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
		chunk("IHDR", header),
		chunk("IDAT", deflateSync(raw, { level: 9 })),
		chunk("IEND", Buffer.alloc(0)),
	]);
	writeFileSync(join(OUT, name), file);
	console.log(name, size + " px", file.length + " bytes");
}

const smooth = (from, to, value) => {
	const t = Math.min(Math.max((value - from) / (to - from), 0), 1);
	return t * t * (3 - 2 * t);
};

// Rombos alternos, unos claros y otros casi apagados, cada uno con su degradado (parecen tallados).
const PERIOD = 256;
draw("boton_patron.png", PERIOD * 2, (x, y) => {
	const u = (x + y) / PERIOD;
	const v = (x - y) / PERIOD;
	const along = u - Math.floor(u);
	const bright = (Math.floor(u) + Math.floor(v)) & 1;
	return bright ? 1 - 0.55 * along : 0.3 * (1 - along);
});

// Doce rayos. Enteros hasta el 70 % del radio y apagados del todo antes del borde: la imagen gira sin recorte.
const RAYS = 12;
draw("boton_rayos.png", 512, (x, y) => {
	const dx = x - 256;
	const dy = y - 256;
	const radius = Math.hypot(dx, dy) / 256;
	if (radius >= 1 || Math.sin(Math.atan2(dy, dx) * RAYS) < 0) {
		return 0;
	}
	return 1 - smooth(0.7, 0.98, radius);
});

// Estrella de cuatro puntas con los lados hundidos.
draw("boton_destello.png", 128, (x, y) => {
	const px = Math.abs(x - 64) / 62;
	const py = Math.abs(y - 64) / 62;
	return px ** 0.55 + py ** 0.55 <= 1 ? 1 : 0;
});
