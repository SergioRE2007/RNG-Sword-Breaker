// Genera candidatos de efectos de sonido con ElevenLabs y una página para escucharlos.
// Uso: node generar.mjs <carpeta de salida> [versiones] [solo este sonido]
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const out = process.argv[2];
const versions = Number(process.argv[3] ?? 3);
const only = process.argv[4];

// La clave sale de la variable de entorno o de la configuración del MCP de ElevenLabs en Claude Code.
function apiKey() {
	if (process.env.ELEVENLABS_API_KEY) return process.env.ELEVENLABS_API_KEY;
	const config = JSON.parse(fs.readFileSync(path.join(os.homedir(), ".claude.json"), "utf8"));
	for (const project of Object.values(config.projects ?? {})) {
		const key = project.mcpServers?.elevenlabs?.env?.ELEVENLABS_API_KEY;
		if (key) return key;
	}
	throw new Error("No encuentro la clave de ElevenLabs");
}

// nombre, segundos, descripción (en español, para la página), texto para ElevenLabs
const SOUNDS = [
	["swing_sword", 0.5, "Espadazo: espada", "Single fast sword swing whoosh, sharp blade slicing through air, punchy game sound effect, dry, no reverb"],
	["swing_dual", 0.5, "Espadazo: espadas dobles", "Single very quick light blade swish, thin and sharp, fast dagger slash through air, game sound effect, dry, no reverb"],
	["swing_spear", 0.5, "Espadazo: lanza", "Single spear thrust whoosh, quick forward stab through air, tight and focused, game sound effect, dry, no reverb"],
	["swing_axe", 0.6, "Espadazo: hacha", "Single heavy axe swing whoosh, wide powerful arc, deep and weighty, game sound effect, dry, no reverb"],
	["swing_hammer", 0.7, "Espadazo: martillo", "Single massive war hammer swing, slow heavy low whoosh, huge weight moving through air, game sound effect, dry, no reverb"],
	["hit_wood", 0.5, "Golpe: madera (caja, barril)", "Single sword hit on a wooden crate, short punchy wood thunk, satisfying game impact sound effect, dry"],
	["hit_stone", 0.5, "Golpe: piedra (roca, pilar, monolito)", "Single metal blade striking solid rock, short hard stone clank with a small chip, game impact sound effect, dry"],
	["hit_crystal", 0.5, "Golpe: cristal", "Single blade hit on a crystal, short bright glassy ting with a tiny sparkle, game impact sound effect, dry"],
	["hit_energy", 0.5, "Golpe: energía (núcleo, estrella...)", "Single blade hit on a magical energy orb, short electric zap impact with a soft synth thump, game sound effect, dry"],
	["hit_enemy", 0.5, "Golpe: enemigo de mazmorra", "Single sword slash hitting a cartoon monster, short meaty punchy impact, no voice, game sound effect, dry"],
	["break_wood", 1.0, "Rotura: madera", "Wooden crate smashed to pieces, short crunchy wood break with splinters scattering, satisfying cartoon game sound effect"],
	["break_stone", 1.2, "Rotura: piedra", "Rock shattering into rubble, short heavy stone crack and crumble, satisfying game sound effect"],
	["break_crystal", 1.2, "Rotura: cristal", "Crystal shattering into sparkling shards, bright glassy burst with shimmer, satisfying game sound effect"],
	["break_energy", 1.2, "Rotura: energía", "Magical energy core bursting, short sci-fi magic explosion with a shimmering sparkle tail, satisfying game sound effect"],
	["break_enemy", 0.8, "Rotura: enemigo derrotado", "Cartoon monster defeated, short soft poof burst with a small pop, no voice, game sound effect"],
	["coin_break", 0.5, "Moneda", "Single coin pickup, one bright clean metallic chime note, very short, arcade game sound effect"],
	["gem_break", 0.7, "Gema", "Single gem pickup, one sparkling crystalline chime, magical, very short, game sound effect"],
];

fs.mkdirSync(out, { recursive: true });
const key = apiKey();
let made = 0;
let failed = 0;

for (const [name, seconds, , text] of SOUNDS) {
	if (only && only !== name) continue;
	for (let version = 1; version <= versions; version++) {
		const file = path.join(out, `${name}_${version}.mp3`);
		if (fs.existsSync(file)) continue;
		const response = await fetch("https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128", {
			method: "POST",
			headers: { "xi-api-key": key, "Content-Type": "application/json" },
			body: JSON.stringify({ text, duration_seconds: seconds, prompt_influence: 0.6 }),
		});
		if (!response.ok) {
			failed++;
			console.log(`FALLO ${name}_${version}: ${response.status} ${(await response.text()).slice(0, 300)}`);
			continue;
		}
		const bytes = Buffer.from(await response.arrayBuffer());
		fs.writeFileSync(file, bytes);
		made++;
		console.log(`${name}_${version}.mp3  ${bytes.length} bytes`);
	}
}

// Página para escucharlos: un botón por versión, agrupados por sonido.
const rows = SOUNDS.map(([name, , label]) => {
	const buttons = [];
	for (let version = 1; fs.existsSync(path.join(out, `${name}_${version}.mp3`)); version++) {
		buttons.push(`<button data-src="${name}_${version}.mp3">${version}</button>`);
	}
	return `<tr><td><b>${label}</b><br><code>${name}</code></td><td>${buttons.join(" ")}</td></tr>`;
}).join("\n");
fs.writeFileSync(path.join(out, "escuchar.html"), `<!doctype html>
<html lang="es"><meta charset="utf-8"><title>Sonidos del juego</title>
<style>
body { font-family: system-ui, sans-serif; background: #1b1d24; color: #eee; max-width: 760px; margin: 24px auto; padding: 0 16px; }
td { padding: 8px 12px; border-bottom: 1px solid #333; vertical-align: middle; }
code { color: #8ab; font-size: 12px; }
button { font-size: 18px; width: 52px; height: 44px; margin-right: 6px; border-radius: 8px; border: 2px solid #000; background: #3a7bd5; color: #fff; cursor: pointer; }
button.last { background: #e2a03f; }
p { color: #aab; }
</style>
<h2>Sonidos del juego: elige una versión de cada uno</h2>
<p>Pulsa un número para oír esa versión (el último que has pulsado se queda en naranja). Dile a Claude cuál te gusta de cada fila, o cuáles hay que repetir.</p>
<table>
${rows}
</table>
<script>
let last;
for (const button of document.querySelectorAll("button")) {
	button.onclick = () => {
		new Audio(button.dataset.src).play();
		if (last) last.classList.remove("last");
		last = button;
		button.classList.add("last");
	};
}
</script>
</html>
`);
console.log(`Hechos ${made}, fallos ${failed}. Carpeta: ${out}`);
