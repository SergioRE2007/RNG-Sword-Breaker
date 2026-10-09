// Genera candidatos de efectos de sonido con ElevenLabs y, por tanda, una página para escucharlos.
// Uso: node tools/sonidos/generar.mjs <carpeta base> [tanda...]   (sin tandas, todas)
// Cada tanda va a <carpeta base>/<tanda>/<nombre>_<versión>.mp3; lo que ya existe no se repite.
// La clave sale de ELEVENLABS_API_KEY o de la configuración del MCP "elevenlabs" de Claude Code.
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const [base, ...wanted] = process.argv.slice(2);

function apiKey() {
	if (process.env.ELEVENLABS_API_KEY) return process.env.ELEVENLABS_API_KEY;
	const config = JSON.parse(fs.readFileSync(path.join(os.homedir(), ".claude.json"), "utf8"));
	for (const project of Object.values(config.projects ?? {})) {
		const key = project.mcpServers?.elevenlabs?.env?.ELEVENLABS_API_KEY;
		if (key) return key;
	}
	throw new Error("No encuentro la clave de ElevenLabs");
}

// Un sonido: nombre (el del evento de client/Sfx), segundos, descripción para la página, texto para ElevenLabs,
// cuántas versiones y si es un bucle (ambiente que se repite sin corte).
const s = (name, seconds, label, text, versions = 3, loop = false) => ({ name, seconds, label, text, versions, loop });
const DRY = "game sound effect, dry, no reverb";
const LOOP = "seamless ambient loop";

const BATCHES = {
	golpe: [
		s("swing_sword", 0.5, "Espadazo: espada", `Single fast sword swing whoosh, sharp blade slicing through air, punchy ${DRY}`),
		s("swing_dual", 0.5, "Espadazo: espadas dobles", `Single very quick light blade swish, thin and sharp, fast dagger slash through air, ${DRY}`),
		s("swing_spear", 0.5, "Espadazo: lanza", `Single spear thrust whoosh, quick forward stab through air, tight and focused, ${DRY}`),
		s("swing_axe", 0.6, "Espadazo: hacha", `Single heavy axe swing whoosh, wide powerful arc, deep and weighty, ${DRY}`),
		s("swing_hammer", 0.7, "Espadazo: martillo", `Single massive war hammer swing, slow heavy low whoosh, huge weight moving through air, ${DRY}`),
		s("hit_wood", 0.5, "Golpe: madera (caja, barril)", "Single sword hit on a wooden crate, short punchy wood thunk, satisfying game impact sound effect, dry"),
		s("hit_stone", 0.5, "Golpe: piedra (roca, pilar, monolito)", "Single metal blade striking solid rock, short hard stone clank with a small chip, game impact sound effect, dry"),
		s("hit_crystal", 0.5, "Golpe: cristal", "Single blade hit on a crystal, short bright glassy ting with a tiny sparkle, game impact sound effect, dry"),
		s("hit_energy", 0.5, "Golpe: energía (núcleo, estrella...)", "Single blade hit on a magical energy orb, short electric zap impact with a soft synth thump, game sound effect, dry"),
		s("hit_enemy", 0.5, "Golpe: enemigo de mazmorra", "Single sword slash hitting a cartoon monster, short meaty punchy impact, no voice, game sound effect, dry"),
		s("break_wood", 1.0, "Rotura: madera", "Wooden crate smashed to pieces, short crunchy wood break with splinters scattering, satisfying cartoon game sound effect"),
		s("break_stone", 1.2, "Rotura: piedra", "Rock shattering into rubble, short heavy stone crack and crumble, satisfying game sound effect"),
		s("break_crystal", 1.2, "Rotura: cristal", "Crystal shattering into sparkling shards, bright glassy burst with shimmer, satisfying game sound effect"),
		s("break_energy", 1.2, "Rotura: energía", "Magical energy core bursting, short sci-fi magic explosion with a shimmering sparkle tail, satisfying game sound effect"),
		s("break_enemy", 0.8, "Rotura: enemigo derrotado", "Cartoon monster defeated, short soft poof burst with a small pop, no voice, game sound effect"),
		s("coin_break", 0.5, "Moneda", "Single coin pickup, one bright clean metallic chime note, very short, arcade game sound effect"),
		s("gem_break", 0.7, "Gema", "Single gem pickup, one sparkling crystalline chime, magical, very short, game sound effect"),
	],
	interfaz: [
		s("click", 0.5, "Pulsar un botón", "UI button click, soft bubbly pop, clean and satisfying, cartoon game interface sound, very short, dry", 2),
		s("hover", 0.5, "Pasar el ratón por un botón", "UI hover, very soft subtle light tap, tiny and quiet, game interface sound, very short, dry", 2),
		s("tick", 0.5, "Tic de cuenta atrás", "Single countdown tick, short clean wooden clock tick, game interface sound, very short, dry", 2),
		s("open", 0.5, "Abrir una ventana", "UI window opening, quick soft whoosh up with a light pop, game menu sound, short, dry", 2),
		s("close", 0.5, "Cerrar una ventana", "UI window closing, quick soft whoosh down, game menu sound, short, dry", 2),
		s("toast", 0.7, "Aviso", "Notification chime, two soft bright marimba notes, friendly game notification sound, short", 2),
		s("error", 0.5, "Error / no se puede", "Error sound, short low soft negative double thud, game interface denied sound, not harsh, dry", 2),
		s("buy", 0.8, "Compra", "Purchase confirmed, satisfying cash register cha-ching with a soft pop, cartoon game sound, short", 2),
		s("buyPing", 0.6, "Mejora comprada", "Upgrade bought, single bright rising sparkle chime, cartoon game reward sound, very short", 2),
		s("equip", 0.5, "Equipar algo", "Equipping an item, quick leather and metal clasp snap, game inventory sound, short, dry", 2),
		s("sell", 0.9, "Vender armas", "Selling items, quick burst of several coins dropping into a pile, cartoon game sound, short", 2),
		s("teleport", 1.0, "Teletransporte", "Magic teleport, quick swirling warp whoosh ending in a sparkle pop, fantasy game sound, short", 2),
		s("potion", 1.0, "Beber una poción", "Drinking a magic potion, quick gulp with bubbly fizz and a sparkle, cartoon game sound, short", 2),
		s("rebirth", 3.0, "Renacer", "Epic rebirth ascension, rising magical swell ending in a bright triumphant burst with choir shimmer, game reward sound", 2),
	],
	// Opciones para el sonido de pasar el ratón por un botón (el usuario elige una).
	raton: [
		s("hover_madera", 0.5, "Madera: toque suave", "UI hover sound, one tiny soft wooden tick, muted and warm, very short, dry", 2),
		s("hover_burbuja", 0.5, "Burbuja", "UI hover sound, one tiny soft bubble blip, round and gentle, very short, dry", 2),
		s("hover_papel", 0.5, "Papel: una carta que se mueve", "UI hover sound, one light paper card flick, soft and airy, very short, dry", 2),
		s("hover_digital", 0.5, "Digital: pitido limpio", "UI hover sound, one soft clean high sine blip, minimal and modern, very short, dry", 2),
		s("hover_kalimba", 0.5, "Kalimba: una nota suave", "UI hover sound, one gentle muted kalimba pluck, soft single note, very short, dry", 2),
		s("hover_aire", 0.5, "Aire: un soplo", "UI hover sound, one subtle soft air swish, barely audible whiff, very short, dry", 2),
		s("hover_cristal", 0.5, "Cristal: un tintineo", "UI hover sound, one tiny delicate glass ting, soft and bright, very short, dry", 2),
		s("hover_tambor", 0.5, "Tambor: golpe sordo", "UI hover sound, one soft low muted thump, tiny felt drum tap, very short, dry", 2),
	],
	// Opciones para el sonido de teletransporte (el usuario elige una).
	teleporte: [
		s("teleport_magia", 1.0, "Magia: remolino de destellos", "Magic teleport, quick shimmering sparkle swirl, bright and airy, fantasy game sound, short", 2),
		s("teleport_warp", 1.0, "Warp: energía que sube y pop", "Sci-fi warp teleport, fast rising energy zip ending in a soft pop, game sound, short", 2),
		s("teleport_viento", 0.8, "Viento: ráfaga rápida", "Quick wind dash whoosh, fast airy swoosh passing by, ninja dash, game sound, short, dry", 2),
		s("teleport_humo", 0.9, "Humo: bomba de humo ninja", "Ninja smoke bomb vanish, soft poof with a quick airy whoosh, game sound, short", 2),
		s("teleport_campana", 1.2, "Campana: tono de templo", "Mystical teleport chime, soft temple bell tone with a quick shimmering whoosh, japanese fantasy game sound, short", 2),
		s("teleport_portal", 1.2, "Portal: grave y resonante", "Portal opening and closing, quick deep whoosh with a resonant low hum, fantasy game sound, short", 2),
		s("teleport_destello", 0.6, "Destello: parpadeo corto", "Quick bright flash zap, short sparkling blink, light and clean, game sound, very short", 2),
		s("teleport_burbuja", 0.8, "Burbuja: blup que sube", "Soft bubbly warp, quick watery bloop with a rising pitch, cute cartoon game sound, short", 2),
	],
	tiradas: [
		s("orb", 0.5, "Aparece el orbe de una tirada", "Magic orb appearing, soft bubbly energy pop with a quick shimmer, fantasy game sound, short, dry", 2),
		s("charge", 0.5, "El orbe se carga (cada pulso)", "Energy charging pulse, single short rising magical hum blip, building tension, game sound, dry", 2),
		s("reveal_1", 0.5, "Tirada: Normal", "Common item reveal, small soft sparkle pop, light and quick, game reward sound, very short", 2),
		s("reveal_2", 0.8, "Tirada: Buena", "Good item reveal, bright two-note sparkle chime, pleasant game reward sound, short", 2),
		s("reveal_3", 1.3, "Tirada: Genial", "Great item reveal, rising magical sparkle ending in a bright impact, exciting game reward sting", 2),
		s("reveal_4", 2.0, "Tirada: Increíble", "Epic item reveal, powerful magical impact with a shimmering choir swell, dramatic game reward sting", 2),
		s("reveal_5", 3.5, "Tirada: Premio gordo", "Legendary jackpot reveal, huge magical explosion followed by a triumphant orchestral fanfare with sparkles, epic game reward sound", 2),
		s("collect", 0.5, "El arma llega al jugador", "Item collected, quick soft whoosh into a bright blip, game pickup sound, very short", 2),
		s("roll", 0.7, "Empieza una tirada de rasgo o grado", "Starting a lucky spin, quick mechanical whirr with a magical shimmer, game roll sound, short", 2),
		s("rare", 1.2, "Sale algo raro", "Rare find sting, deep impact with a bright magical shimmer, dramatic short game reward sound", 2),
		s("win", 2.0, "Sale algo muy bueno", "Victory jingle, short triumphant brass fanfare with sparkles, cartoon game win sound", 2),
		s("forge_hit", 0.7, "Forja: martillazo", "Blacksmith hammer striking hot metal on an anvil, single heavy metallic clang with sparks, punchy, short", 3),
		s("forge_super", 1.5, "Forja: súper martillazo", "Massive blacksmith hammer strike on an anvil, huge ringing metallic clang with a magical burst of sparks, epic, short", 2),
	],
	mazmorra: [
		s("wave", 1.2, "Empieza una oleada", "Enemy wave incoming, short dramatic war drum hit with a low horn stab, game alert sound", 2),
		s("hurt", 0.5, "Te hacen daño", "Player taking damage, short blunt punch impact with a soft thud, cartoon game hit sound, no voice, dry", 3),
		s("dungeon_win", 3.0, "Mazmorra superada", "Dungeon cleared victory fanfare, short triumphant orchestral brass with a final cymbal, heroic game sound", 2),
		s("dungeon_lose", 2.0, "Mazmorra perdida", "Defeat sound, short descending sad brass notes with a low drum, game over sting", 2),
	],
	// Ambiente de fondo de cada zona y de las estaciones del hub (client/Soundscape), y detalles del mundo.
	ambiente: [
		s("amb_day", 20, "Superficie, de día", `Peaceful japanese garden daytime ambience, gentle breeze through trees, soft birdsong, distant trickling water, calm, ${LOOP}`, 1, true),
		s("amb_night", 20, "Superficie, de noche", `Calm night ambience in a japanese garden, crickets chirping, soft night breeze, peaceful, ${LOOP}`, 1, true),
		s("amb_lobby", 20, "Lobby de las mazmorras", `Underground cavern ambience, deep airy echoing space, slow water drips, faint low wind, mysterious, ${LOOP}`, 1, true),
		s("amb_dungeon", 20, "Dentro de una mazmorra", `Dark dungeon ambience, low ominous drone, distant rumbles and faint echoes, tense, ${LOOP}`, 1, true),
		s("st_forge", 10, "Forja de grados", `Blacksmith forge ambience, crackling fire and soft roaring bellows, warm, ${LOOP}`, 1, true),
		s("st_enchant", 10, "Mesa de encantamiento", `Magical enchanting table ambience, soft mystical hum with gentle twinkling chimes, ${LOOP}`, 1, true),
		s("slam", 0.9, "Golpe épico contra el suelo", "Massive weapon slamming into the ground, deep heavy boom with a burst of debris, powerful, short", 3),
		s("unsheath", 0.6, "Sacar el arma", "Sword being drawn from its scabbard, quick metallic blade slide with a ring, short, dry", 2),
		s("sheath", 0.6, "Guardar el arma", "Sword sliding back into its scabbard, quick blade slide ending in a soft click, short, dry", 2),
	],
	clima: [
		s("w_rain", 10, "Lluvia", `Steady gentle rain falling on leaves and ground, soft and calm, ${LOOP}`, 1, true),
		s("w_petals", 10, "Pétalos", `Gentle warm spring breeze through cherry trees, soft rustling leaves, calm, ${LOOP}`, 1, true),
		s("w_fog", 10, "Niebla", `Quiet eerie foggy ambience, very soft low wind, distant muffled air, calm, ${LOOP}`, 1, true),
		s("w_snow", 10, "Nieve", `Soft cold winter wind with a gentle snowfall hush, quiet, ${LOOP}`, 1, true),
		s("w_storm", 10, "Tormenta", `Heavy thunderstorm rain with strong gusting wind, intense downpour, no thunder, ${LOOP}`, 1, true),
		s("w_golden", 10, "Lluvia dorada", `Magical golden rain, soft rain mixed with gentle shimmering chimes and sparkles, enchanting, ${LOOP}`, 1, true),
		s("w_volcanic", 10, "Volcán", `Volcanic eruption ambience, deep rumbling earth, crackling lava and distant roaring fire, ${LOOP}`, 1, true),
		s("w_aurora", 10, "Aurora", `Ethereal aurora ambience, soft airy shimmering pad with gentle crystalline twinkles, peaceful, ${LOOP}`, 1, true),
		s("w_bloodmoon", 10, "Luna de sangre", `Ominous blood moon ambience, low dark drone with eerie distant howling wind, tense, ${LOOP}`, 1, true),
		s("w_eclipse", 10, "Eclipse", `Solar eclipse ambience, deep dark sub drone with a faint mysterious hum, heavy and still, ${LOOP}`, 1, true),
		s("w_cosmic", 10, "Cósmico", `Cosmic space ambience, deep slow evolving hum with soft distant shimmering tones, vast, ${LOOP}`, 1, true),
		s("w_starfall", 10, "Lluvia de estrellas", `Magical starry night ambience, soft airy pad with gentle twinkling sparkles, dreamy, ${LOOP}`, 1, true),
		s("thunder", 3.5, "Trueno", "Thunder crack followed by a deep rolling rumble, powerful, natural", 3),
		s("meteor", 1.5, "Cae un meteorito", "Fiery meteor impact, heavy explosive ground hit with crackling fire debris, short", 2),
		s("star", 1.5, "Cae una estrella", "Falling star impact, magical sparkling burst with a soft boom, short", 2),
	],
};

const key = apiKey();
try {
	const info = await (await fetch("https://api.elevenlabs.io/v1/user/subscription", { headers: { "xi-api-key": key } })).json();
	console.log(`Créditos: usados ${info.character_count} de ${info.character_limit} (plan ${info.tier})`);
} catch {
	console.log("No he podido leer los créditos");
}

let made = 0;
let failed = 0;
let stop = false;
for (const batch of wanted.length > 0 ? wanted : Object.keys(BATCHES)) {
	const sounds = BATCHES[batch];
	if (!sounds) {
		console.log(`No existe la tanda ${batch}`);
		continue;
	}
	const out = path.join(base, batch);
	fs.mkdirSync(out, { recursive: true });
	for (const sound of sounds) {
		for (let version = 1; version <= sound.versions && !stop; version++) {
			const file = path.join(out, `${sound.name}_${version}.mp3`);
			if (fs.existsSync(file)) continue;
			const body = { text: sound.text, duration_seconds: sound.seconds, prompt_influence: 0.6 };
			if (sound.loop) body.loop = true;
			const response = await fetch("https://api.elevenlabs.io/v1/sound-generation?output_format=mp3_44100_128", {
				method: "POST",
				headers: { "xi-api-key": key, "Content-Type": "application/json" },
				body: JSON.stringify(body),
			});
			if (!response.ok) {
				failed++;
				console.log(`FALLO ${batch}/${sound.name}_${version}: ${response.status} ${(await response.text()).slice(0, 300)}`);
				stop = response.status === 401 || response.status === 402; // clave o créditos: no seguir
				continue;
			}
			fs.writeFileSync(file, Buffer.from(await response.arrayBuffer()));
			made++;
			console.log(`${batch}/${sound.name}_${version}.mp3`);
		}
	}

	// Página para escucharlos: un botón por versión, una fila por sonido.
	const rows = sounds.map((sound) => {
		const buttons = [];
		for (let version = 1; fs.existsSync(path.join(out, `${sound.name}_${version}.mp3`)); version++) {
			buttons.push(`<button data-src="${sound.name}_${version}.mp3">${version}</button>`);
		}
		return `<tr><td><b>${sound.label}</b><br><code>${sound.name}</code></td><td>${buttons.join(" ")}</td></tr>`;
	}).join("\n");
	fs.writeFileSync(path.join(out, "escuchar.html"), `<!doctype html>
<html lang="es"><meta charset="utf-8"><title>Sonidos: ${batch}</title>
<style>
body { font-family: system-ui, sans-serif; background: #1b1d24; color: #eee; max-width: 760px; margin: 24px auto; padding: 0 16px; }
td { padding: 8px 12px; border-bottom: 1px solid #333; vertical-align: middle; }
code { color: #8ab; font-size: 12px; }
button { font-size: 18px; width: 52px; height: 44px; margin-right: 6px; border-radius: 8px; border: 2px solid #000; background: #3a7bd5; color: #fff; cursor: pointer; }
button.last { background: #e2a03f; }
p { color: #aab; }
</style>
<h2>Sonidos del juego: ${batch}</h2>
<p>Pulsa un número para oír esa versión (el último que has pulsado se queda en naranja; al pulsar otro se corta el anterior).</p>
<table>
${rows}
</table>
<script>
let last, audio;
for (const button of document.querySelectorAll("button")) {
	button.onclick = () => {
		if (audio) audio.pause();
		audio = new Audio(button.dataset.src);
		audio.play();
		if (last) last.classList.remove("last");
		last = button;
		button.classList.add("last");
	};
}
</script>
</html>
`);
}
console.log(`Hechos ${made}, fallos ${failed}. Carpeta: ${base}`);
