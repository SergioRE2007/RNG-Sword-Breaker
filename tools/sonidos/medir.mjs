// Mide el silencio del principio de cada mp3: en qué segundo empieza a sonar de verdad.
// Uso: node medir.mjs <carpeta> [carpeta...]   (necesita `npm install mpg123-decoder` en la carpeta de este archivo)
// Escribe por pantalla una línea por archivo y, al final, la tabla `START` lista para pegar en client/Sfx
// (solo los que tienen id en el ids.json de su carpeta).
import fs from "node:fs";
import path from "node:path";
import { MPEGDecoder } from "mpg123-decoder";

const THRESHOLD = 0.05; // empieza donde la onda pasa del 5 % de su pico
const PREROLL = 0.01; // y se deja este margen antes, para no comerse el ataque

const decoder = new MPEGDecoder();
await decoder.ready;

const rows = [];
for (const folder of process.argv.slice(2)) {
	const idsFile = path.join(folder, "ids.json");
	const ids = fs.existsSync(idsFile) ? JSON.parse(fs.readFileSync(idsFile, "utf8")) : {};
	for (const file of fs.readdirSync(folder).filter((name) => name.endsWith(".mp3")).sort()) {
		const name = path.basename(file, ".mp3");
		await decoder.reset();
		const { channelData, samplesDecoded, sampleRate } = decoder.decode(new Uint8Array(fs.readFileSync(path.join(folder, file))));
		let peak = 0;
		for (const channel of channelData) {
			for (let i = 0; i < samplesDecoded; i++) peak = Math.max(peak, Math.abs(channel[i]));
		}
		let onset = 0;
		search: for (let i = 0; i < samplesDecoded; i++) {
			for (const channel of channelData) {
				if (Math.abs(channel[i]) > Math.max(peak * THRESHOLD, 0.003)) {
					onset = i;
					break search;
				}
			}
		}
		const start = Math.max(0, onset / sampleRate - PREROLL);
		// Hasta dónde suena de verdad: la última muestra por encima del umbral.
		let last = samplesDecoded - 1;
		tail: for (; last > onset; last--) {
			for (const channel of channelData) {
				if (Math.abs(channel[last]) > Math.max(peak * THRESHOLD, 0.003)) break tail;
			}
		}
		rows.push({ batch: path.basename(folder), name, id: ids[name], start, length: (last - onset) / sampleRate, peak });
	}
}
decoder.free();

for (const row of rows) {
	console.log(`${row.batch}/${row.name}  empieza ${row.start.toFixed(3)} s de ${row.length.toFixed(2)} s  pico ${row.peak.toFixed(2)}${row.id ? "" : "  (sin subir)"}`);
}
// Cuánto hay que subir cada grabación para que su pico llegue a 1: la tabla GAIN de client/Sfx.
console.log("\nlocal GAIN = {");
for (const row of rows) {
	const gain = 1 / Math.max(row.peak, 0.001);
	if (row.id && Math.abs(gain - 1) > 0.1) console.log(`\t[${row.id}] = ${gain.toFixed(2)}, -- ${row.name}`);
}
console.log("}");
