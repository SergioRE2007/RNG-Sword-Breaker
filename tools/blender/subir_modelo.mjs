// Sube un .fbx a Roblox como modelo del grupo (Open Cloud, API de recursos) y escribe su id.
// Uso: node tools/blender/subir_modelo.mjs <archivo.fbx> <archivo con la clave de API> [grupo]
// Luego, en Studio (modo Edit): game:GetObjects("rbxassetid://<id>") trae el modelo con sus MeshParts ya subidas.
import fs from "node:fs";
import path from "node:path";

const [file, keyFile, group = "1002188803"] = process.argv.slice(2);
const key = fs.readFileSync(keyFile, "utf8").trim();
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

const form = new FormData();
form.append("request", JSON.stringify({
	assetType: "Model",
	displayName: path.basename(file, ".fbx"),
	description: "Modelo del juego",
	creationContext: { creator: { groupId: group } },
}));
form.append("fileContent", new Blob([fs.readFileSync(file)], { type: "model/fbx" }), path.basename(file));
const response = await fetch("https://apis.roblox.com/assets/v1/assets", { method: "POST", headers: { "x-api-key": key }, body: form });
if (!response.ok) {
	console.log(`FALLO: ${response.status} ${(await response.text()).slice(0, 500)}`);
	process.exit(1);
}
let operation = await response.json();
// La subida se procesa aparte: se pregunta hasta que termina (los modelos tardan más que los audios).
for (let attempt = 0; attempt < 80 && !operation.done; attempt++) {
	await sleep(3000);
	const poll = await fetch(`https://apis.roblox.com/assets/v1/operations/${operation.operationId ?? operation.path.split("/").pop()}`, { headers: { "x-api-key": key } });
	if (poll.ok) operation = await poll.json();
}
const assetId = operation.response?.assetId;
if (!assetId) {
	console.log(`FALLO: sin id ${JSON.stringify(operation).slice(0, 500)}`);
	process.exit(1);
}
console.log(`${path.basename(file)} = ${assetId}  (${operation.response?.moderationResult?.moderationState ?? "?"})`);
