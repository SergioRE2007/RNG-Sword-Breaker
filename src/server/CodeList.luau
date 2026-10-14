-- Lista de códigos de regalo (los canjea server/Codes). Vive en el servidor y no en Config: lo de shared/ lo puede leer
-- cualquier cliente con trampas, y un código con pocos usos se lo llevaría quien mirara la lista.
-- La clave es el código, en mayúsculas y sin espacios. rewards = lista de { coins = N }, { gems = N } o
-- { item = clave de Config.Items, amount = N }. Opcionales: maxUses = cuántos jugadores en total lo pueden canjear
-- (contador global) y expires = "AAAA-MM-DD" (último día que vale, hora UTC). Cada jugador canjea cada uno una sola vez.
-- Un código nuevo es una línea aquí y publicar el juego.
return {
	RELEASE = { rewards = { { item = "luckClover", amount = 1 }, { item = "potion_coins_5", amount = 1 } } },
	-- 5467 tickets = lo que cuestan en tickets los ocho pases juntos (Stats.ticketPrice). Para 10 jugadores.
	["FUNDADOR-K7Q4X9"] = { maxUses = 10, rewards = { { item = "missionToken", amount = 5467 } } },
}
