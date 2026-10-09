// Iguala el volumen de los audios de una carpeta para poder compararlos de oído: de cada mp3 saca una copia
// `previas/<nombre>.wav` con el mismo pico (0,3 si no se dice otro) y deja la página `escuchar.html` apuntando a
// esas copias. Ojo: no vale para ambientes casi mudos; subirlos tanto los rompe (ver `medir.mjs`).
// (Las grabaciones salen de ElevenLabs a niveles muy distintos; en el juego las iguala la ganancia de cada una.)
// Uso: node tools/sonidos/previas.mjs <carpeta> [pico]   (necesita `npm install` en tools/sonidos)
import fs from "node:fs";
import path from "node:path";
import { MPEGDecoder } from "mpg123-decoder";

const folder = process.argv[2];
const target = Number(process.argv[3] ?? 0.3);
const out = path.join(folder, "previas");
fs.mkdirSync(out, { recursive: true });

const decoder = new MPEGDecoder();
await decoder.ready;
let made = 0;
for (const file of fs.readdirSync(folder).filter((name) => name.endsWith(".mp3")).sort()) {
	await decoder.reset();
	const { channelData, samplesDecoded, sampleRate } = decoder.decode(new Uint8Array(fs.readFileSync(path.join(folder, file))));
	let peak = 0;
	for (const channel of channelData) {
		for (let i = 0; i < samplesDecoded; i++) peak = Math.max(peak, Math.abs(channel[i]));
	}
	const gain = target / Math.max(peak, 0.001);
	const channels = channelData.length;
	const data = Buffer.alloc(samplesDecoded * channels * 2);
	for (let i = 0; i < samplesDecoded; i++) {
		for (let c = 0; c < channels; c++) {
			const sample = Math.max(-1, Math.min(1, channelData[c][i] * gain));
			data.writeInt16LE(Math.round(sample * 32767), (i * channels + c) * 2);
		}
	}
	// Cabecera WAV de PCM de 16 bits.
	const header = Buffer.alloc(44);
	header.write("RIFF", 0);
	header.writeUInt32LE(36 + data.length, 4);
	header.write("WAVEfmt ", 8);
	header.writeUInt32LE(16, 16);
	header.writeUInt16LE(1, 20);
	header.writeUInt16LE(channels, 22);
	header.writeUInt32LE(sampleRate, 24);
	header.writeUInt32LE(sampleRate * channels * 2, 28);
	header.writeUInt16LE(channels * 2, 32);
	header.writeUInt16LE(16, 34);
	header.write("data", 36);
	header.writeUInt32LE(data.length, 40);
	fs.writeFileSync(path.join(out, path.basename(file, ".mp3") + ".wav"), Buffer.concat([header, data]));
	made++;
}
decoder.free();

const page = path.join(folder, "escuchar.html");
if (fs.existsSync(page)) {
	const html = fs.readFileSync(page, "utf8").replace(/data-src="([^"/]+)\.mp3"/g, 'data-src="previas/$1.wav"');
	fs.writeFileSync(page, html);
}
console.log(`Copias igualadas: ${made} en ${out}`);
