// Mezcla varios mp3 en un solo audio y lo suaviza: cada capa se iguala a su pico y entra con su peso, se
// quitan los agudos por encima de un corte (lo que hace que un ambiente suene áspero o recargado) y el
// resultado sale como WAV con el pico que se pida. Con una sola capa sirve para suavizar un audio.
// Los bucles siguen siendo bucles: el filtro se pasa dos veces seguidas y se guarda la segunda vuelta.
// Uso: node tools/sonidos/mezclar.mjs <salida.wav> <corte en Hz> <pico de 0 a 1> <archivo.mp3:peso>...
// (necesita `npm install` en tools/sonidos)
import fs from "node:fs";
import { MPEGDecoder } from "mpg123-decoder";

const [output, cutoffText, peakText, ...layers] = process.argv.slice(2);
const cutoff = Number(cutoffText);
const target = Number(peakText);

const decoder = new MPEGDecoder();
await decoder.ready;
let rate = 44100;
let length = Infinity;
const tracks = [];
for (const layer of layers) {
	const split = layer.lastIndexOf(":");
	const file = layer.slice(0, split);
	const weight = Number(layer.slice(split + 1));
	await decoder.reset();
	const { channelData, samplesDecoded, sampleRate } = decoder.decode(new Uint8Array(fs.readFileSync(file)));
	rate = sampleRate;
	const left = channelData[0];
	const right = channelData[1] ?? channelData[0];
	let peak = 0;
	for (let i = 0; i < samplesDecoded; i++) peak = Math.max(peak, Math.abs(left[i]), Math.abs(right[i]));
	tracks.push({ left, right, gain: weight / Math.max(peak, 0.001) });
	length = Math.min(length, samplesDecoded);
}
decoder.free();

const mix = [new Float32Array(length), new Float32Array(length)];
for (const track of tracks) {
	for (let i = 0; i < length; i++) {
		mix[0][i] += track.left[i] * track.gain;
		mix[1][i] += track.right[i] * track.gain;
	}
}

// Paso bajo de dos polos (dos pasadas de uno), dando dos vueltas al audio para que el final enlace con el principio.
const alpha = 1 - Math.exp((-2 * Math.PI * cutoff) / rate);
for (const channel of mix) {
	for (let pass = 0; pass < 2; pass++) {
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
for (const channel of mix) {
	for (let i = 0; i < length; i++) {
		peak = Math.max(peak, Math.abs(channel[i]));
		energy += channel[i] * channel[i];
	}
}
const gain = target / Math.max(peak, 0.001);
const data = Buffer.alloc(length * 4);
for (let i = 0; i < length; i++) {
	data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mix[0][i] * gain)) * 32767), i * 4);
	data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, mix[1][i] * gain)) * 32767), i * 4 + 2);
}
const header = Buffer.alloc(44);
header.write("RIFF", 0);
header.writeUInt32LE(36 + data.length, 4);
header.write("WAVEfmt ", 8);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20);
header.writeUInt16LE(2, 22);
header.writeUInt32LE(rate, 24);
header.writeUInt32LE(rate * 4, 28);
header.writeUInt16LE(4, 32);
header.writeUInt16LE(16, 34);
header.write("data", 36);
header.writeUInt32LE(data.length, 40);
fs.writeFileSync(output, Buffer.concat([header, data]));
const rms = Math.sqrt(energy / (length * 2)) * gain;
console.log(`${output}: ${(length / rate).toFixed(2)} s, pico ${target}, nivel medio ${(20 * Math.log10(Math.max(rms, 1e-6))).toFixed(1)} dB`);
