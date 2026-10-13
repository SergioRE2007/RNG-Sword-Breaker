// Arregla un mp3 y lo guarda como WAV: le quita el silencio del principio y, si se pide, le suaviza la entrada
// (las grabaciones de ElevenLabs a veces empiezan con un golpe saturado). El pico se queda como estaba, salvo que
// pase de 1, que se baja a 0,98.
// Uso: node tools/sonidos/recortar.mjs <entrada.mp3> <salida.wav> [segundos de entrada suave] [volumen al empezar, 0 a 1]
// (necesita `npm install` en tools/sonidos)
import fs from "node:fs";
import { MPEGDecoder } from "mpg123-decoder";

const [input, output, softText, floorText] = process.argv.slice(2);
const soft = Number(softText ?? 0);
const floor = Number(floorText ?? 0.3);
const SILENCE = 0.01; // por debajo de esto (de 0 a 1) se da por silencio

const decoder = new MPEGDecoder();
await decoder.ready;
const { channelData, samplesDecoded, sampleRate } = decoder.decode(new Uint8Array(fs.readFileSync(input)));
decoder.free();
const channels = [channelData[0], channelData[1] ?? channelData[0]];

let start = 0;
while (start < samplesDecoded && Math.abs(channels[0][start]) < SILENCE && Math.abs(channels[1][start]) < SILENCE) start++;
start = Math.max(0, start - Math.round(sampleRate * 0.005)); // 5 ms de margen para no cortar el ataque
const length = samplesDecoded - start;

// Entrada suave: el volumen sube de `floor` a 1 a lo largo de `soft` segundos.
const ramp = Math.round(soft * sampleRate);
let peak = 0;
const out = channels.map((channel) => {
	const data = new Float32Array(length);
	for (let i = 0; i < length; i++) {
		const gain = i < ramp ? floor + (1 - floor) * (i / ramp) ** 2 : 1;
		data[i] = channel[start + i] * gain;
		peak = Math.max(peak, Math.abs(data[i]));
	}
	return data;
});
const scale = peak > 0.98 ? 0.98 / peak : 1;

const bytes = Buffer.alloc(44 + length * 4);
bytes.write("RIFF", 0);
bytes.writeUInt32LE(36 + length * 4, 4);
bytes.write("WAVEfmt ", 8);
bytes.writeUInt32LE(16, 16);
bytes.writeUInt16LE(1, 20); // PCM
bytes.writeUInt16LE(2, 22);
bytes.writeUInt32LE(sampleRate, 24);
bytes.writeUInt32LE(sampleRate * 4, 28);
bytes.writeUInt16LE(4, 32);
bytes.writeUInt16LE(16, 34);
bytes.write("data", 36);
bytes.writeUInt32LE(length * 4, 40);
for (let i = 0; i < length; i++) {
	for (let c = 0; c < 2; c++) {
		bytes.writeInt16LE(Math.round(Math.max(-1, Math.min(1, out[c][i] * scale)) * 32767), 44 + i * 4 + c * 2);
	}
}
fs.writeFileSync(output, bytes);
console.log(`${output}: quitados ${(start / sampleRate).toFixed(3)} s, quedan ${(length / sampleRate).toFixed(2)} s, pico ${(peak * scale).toFixed(2)}`);
