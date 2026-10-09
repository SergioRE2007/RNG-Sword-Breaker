// Compone un ambiente en bucle a partir de piezas sueltas: una brisa de fondo hecha por código y sonidos
// colocados en su momento, cada uno con su volumen, su lado y lo apagado que suena. Así el ambiente queda
// limpio y con huecos; pedido de una vez a ElevenLabs sale casi mudo y todo siseo.
// Uso: node tools/sonidos/componer.mjs <receta.json> <carpeta de piezas> <salida.wav> [fondo: 1 normal, 0 sin brisa]
// (necesita `npm install` en tools/sonidos)
//
// Receta: { seconds, cutoff (corte final de agudos, Hz), bed: { level (nivel medio, 0 a 1), cutoff, depth, seed },
//   events: [{ file, at (s), gain (pico con el que entra), pan (-1 izquierda a 1 derecha), cutoff (opcional) }] }
// Lo que se sale por el final entra por el principio, para que el bucle no tenga corte.
import fs from "node:fs";
import path from "node:path";
import { MPEGDecoder } from "mpg123-decoder";

const [specFile, pieces, output, bedText] = process.argv.slice(2);
const spec = JSON.parse(fs.readFileSync(specFile, "utf8"));
const bedScale = bedText === undefined ? 1 : Number(bedText);
const RATE = 44100;
const length = Math.round(spec.seconds * RATE);
const mix = [new Float32Array(length), new Float32Array(length)];

// Paso bajo de un polo, las veces que se pida.
function lowpass(samples, cutoff, passes = 2) {
	const alpha = 1 - Math.exp((-2 * Math.PI * cutoff) / RATE);
	for (let pass = 0; pass < passes; pass++) {
		let state = 0;
		for (let i = 0; i < samples.length; i++) {
			state += alpha * (samples[i] - state);
			samples[i] = state;
		}
	}
}

// Brisa de fondo: ruido sin agudos que sube y baja despacio, distinto en cada oído, con el final fundido en el principio.
if (spec.bed && bedScale > 0) {
	let seed = spec.bed.seed ?? 1;
	const random = () => {
		seed = (seed + 0x6d2b79f5) | 0;
		let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
		t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
	const overlap = 2 * RATE;
	for (let channel = 0; channel < 2; channel++) {
		const noise = new Float32Array(length + overlap);
		for (let i = 0; i < noise.length; i++) noise[i] = random() * 2 - 1;
		lowpass(noise, spec.bed.cutoff, 2);
		const rumble = Float32Array.from(noise);
		lowpass(rumble, 90, 1);
		for (let i = 0; i < noise.length; i++) noise[i] -= rumble[i]; // sin el zumbido más grave
		const bed = new Float32Array(length);
		for (let i = 0; i < length; i++) {
			const fade = i < overlap ? i / overlap : 1;
			bed[i] = noise[i] * fade + (i < overlap ? noise[length + i] * (1 - fade) : 0);
		}
		let energy = 0;
		for (let i = 0; i < length; i++) {
			const t = i / length;
			const swell = 1 - spec.bed.depth * (0.5 + 0.3 * Math.sin(2 * Math.PI * (2 * t + channel * 0.13)) + 0.2 * Math.sin(2 * Math.PI * (3 * t + 0.4)));
			bed[i] *= swell;
			energy += bed[i] * bed[i];
		}
		const gain = (spec.bed.level * bedScale) / Math.max(Math.sqrt(energy / length), 1e-9);
		for (let i = 0; i < length; i++) mix[channel][i] += bed[i] * gain;
	}
}

// Las piezas.
const decoder = new MPEGDecoder();
await decoder.ready;
const cache = new Map();
for (const event of spec.events) {
	if (!cache.has(event.file)) {
		await decoder.reset();
		const { channelData, samplesDecoded } = decoder.decode(new Uint8Array(fs.readFileSync(path.join(pieces, event.file))));
		const mono = new Float32Array(samplesDecoded);
		for (let i = 0; i < samplesDecoded; i++) mono[i] = (channelData[0][i] + (channelData[1] ?? channelData[0])[i]) / 2;
		cache.set(event.file, mono);
	}
	const sound = Float32Array.from(cache.get(event.file));
	if (event.cutoff) lowpass(sound, event.cutoff, 2);
	let peak = 0;
	for (let i = 0; i < sound.length; i++) peak = Math.max(peak, Math.abs(sound[i]));
	const gain = event.gain / Math.max(peak, 0.001);
	const angle = (((event.pan ?? 0) + 1) * Math.PI) / 4;
	const left = Math.cos(angle) * Math.SQRT2;
	const right = Math.sin(angle) * Math.SQRT2;
	const edge = Math.round(0.01 * RATE);
	const start = Math.round(event.at * RATE);
	for (let i = 0; i < sound.length; i++) {
		const fade = Math.min(1, i / edge, (sound.length - 1 - i) / edge);
		const at = (start + i) % length;
		mix[0][at] += sound[i] * gain * fade * left;
		mix[1][at] += sound[i] * gain * fade * right;
	}
}
decoder.free();

// Corte final de agudos, dando dos vueltas para que el final enlace con el principio.
if (spec.cutoff) {
	const alpha = 1 - Math.exp((-2 * Math.PI * spec.cutoff) / RATE);
	for (const channel of mix) {
		let state = 0;
		for (let lap = 0; lap < 2; lap++) {
			for (let i = 0; i < length; i++) {
				state += alpha * (channel[i] - state);
				if (lap === 1) channel[i] = state;
			}
		}
	}
}

let peak = 0;
let energy = 0;
let crossings = 0;
for (const channel of mix) {
	for (let i = 0; i < length; i++) {
		peak = Math.max(peak, Math.abs(channel[i]));
		energy += channel[i] * channel[i];
		if (i > 0 && channel[i] >= 0 !== channel[i - 1] >= 0) crossings++;
	}
}
const data = Buffer.alloc(length * 4);
for (let i = 0; i < length; i++) {
	data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mix[0][i])) * 32767), i * 4);
	data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mix[1][i])) * 32767), i * 4 + 2);
}
const header = Buffer.alloc(44);
header.write("RIFF", 0);
header.writeUInt32LE(36 + data.length, 4);
header.write("WAVEfmt ", 8);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20);
header.writeUInt16LE(2, 22);
header.writeUInt32LE(RATE, 24);
header.writeUInt32LE(RATE * 4, 28);
header.writeUInt16LE(4, 32);
header.writeUInt16LE(16, 34);
header.write("data", 36);
header.writeUInt32LE(data.length, 40);
fs.writeFileSync(output, Buffer.concat([header, data]));
const rms = Math.sqrt(energy / (length * 2));
console.log(`${path.basename(output)}: ${spec.seconds} s, pico ${peak.toFixed(2)}, nivel medio ${(20 * Math.log10(Math.max(rms, 1e-6))).toFixed(1)} dB, cruces por cero ${Math.round(crossings / 2 / spec.seconds)}/s`);
