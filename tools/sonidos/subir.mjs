// Sube a Roblox los mp3 de una carpeta (Open Cloud, API de recursos) y apunta el id de cada uno en ids.json.
// Uso: node tools/sonidos/subir.mjs <carpeta> <userId> <archivo con la clave de API> [expresión regular]
// Con la expresión solo sube los archivos cuyo nombre (sin .mp3) encaja: "_1$" sube la primera versión de cada uno.
import fs from "node:fs";
import path from "node:path";

const [folder, userId, keyFile, only] = process.argv.slice(2);
const key = fs.readFileSync(keyFile, "utf8").trim();
const idsFile = path.join(folder, "ids.json");
const ids = fs.existsSync(idsFile) ? JSON.parse(fs.readFileSync(idsFile, "utf8")) : {};
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

let made = 0;
let failed = 0;
for (const file of fs.readdirSync(folder).filter((name) => name.endsWith(".mp3")).sort()) {
	const name = path.basename(file, ".mp3");
	if (ids[name] || (only && !new RegExp(only).test(name))) continue;

	const form = new FormData();
	form.append("request", JSON.stringify({
		assetType: "Audio",
		displayName: name,
		description: "Efecto de sonido del juego",
		creationContext: { creator: { userId: String(userId) } },
	}));
	form.append("fileContent", new Blob([fs.readFileSync(path.join(folder, file))], { type: "audio/mpeg" }), file);
	const response = await fetch("https://apis.roblox.com/assets/v1/assets", { method: "POST", headers: { "x-api-key": key }, body: form });
	if (!response.ok) {
		failed++;
		console.log(`FALLO ${name}: ${response.status} ${(await response.text()).slice(0, 300)}`);
		if (response.status === 401 || response.status === 403 || response.status === 429) break; // clave, permiso o tope: no seguir
		continue;
	}
	let operation = await response.json();
	// La subida se procesa aparte: se pregunta hasta que termina.
	for (let attempt = 0; attempt < 30 && !operation.done; attempt++) {
		await sleep(1500);
		const poll = await fetch(`https://apis.roblox.com/assets/v1/operations/${operation.operationId ?? operation.path.split("/").pop()}`, { headers: { "x-api-key": key } });
		if (poll.ok) operation = await poll.json();
	}
	const assetId = operation.response?.assetId;
	if (!assetId) {
		failed++;
		console.log(`FALLO ${name}: sin id ${JSON.stringify(operation).slice(0, 300)}`);
		continue;
	}
	ids[name] = Number(assetId);
	fs.writeFileSync(idsFile, JSON.stringify(ids, null, "\t"));
	made++;
	console.log(`${name} = ${assetId}  (${operation.response?.moderationResult?.moderationState ?? "?"})`);
}
console.log(`Subidos ${made}, fallos ${failed}, en total ${Object.keys(ids).length} ids en ${idsFile}`);
