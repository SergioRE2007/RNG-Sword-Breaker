-- Avisos entre servidores del juego (MessagingService), para las órdenes de admin que valen "en todos los servidores"
-- (server/AdminCommands y server/AdminEvents). Librería con start():
--   Broadcast.on("clave", function(datos) ... end)   qué hacer al llegar un aviso de esa clase
--   Broadcast.send("clave", datos)                   lo hace ya en este servidor y lo manda a los demás
-- Solo los servidores del juego pueden publicar aquí, así que lo que llega viene de otro servidor nuestro; aun así,
-- quien lo recibe comprueba los datos como si no. Cada aviso lleva un id: el que vuelve a su propio servidor, o uno
-- repetido, no se hace dos veces (importa en los regalos). Los datos tienen que ser pequeños (menos de 1 KB) y de los
-- que caben en JSON: nada de Color3 ni instancias. En Studio no hay más servidores: el aviso se queda en este.
local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")

local Broadcast = {}

local TOPIC = "AdminGlobal"
local KEEP = 600 -- segundos que se recuerda el id de un aviso ya hecho

local handlers: { [string]: (any) -> () } = {}
local seen: { [string]: number } = {}

local function run(id: unknown, kind: unknown, data: unknown)
	if type(id) ~= "string" or type(kind) ~= "string" or seen[id] then
		return
	end
	local now = os.clock()
	for old, at in seen do
		if now - at > KEEP then
			seen[old] = nil
		end
	end
	seen[id] = now
	local handler = handlers[kind]
	if handler then
		task.spawn(handler, data)
	end
end

function Broadcast.on(kind: string, handler: (any) -> ())
	handlers[kind] = handler
end

-- Devuelve si el aviso ha salido hacia los demás servidores (aquí se hace siempre).
function Broadcast.send(kind: string, data: any): boolean
	local id = HttpService:GenerateGUID(false)
	run(id, kind, data)
	local ok, problem = pcall(function()
		MessagingService:PublishAsync(TOPIC, { id = id, kind = kind, data = data })
	end)
	if not ok then
		warn("[Broadcast] Publish failed: " .. tostring(problem))
	end
	return ok
end

function Broadcast.start()
	-- En su hilo: suscribirse espera a la red y, sin ella (Studio sin acceso), falla.
	task.spawn(function()
		local ok, problem = pcall(function()
			MessagingService:SubscribeAsync(TOPIC, function(message)
				local body = message.Data
				if type(body) == "table" then
					run(body.id, body.kind, body.data)
				end
			end)
		end)
		if not ok then
			warn("[Broadcast] Subscribe failed: " .. tostring(problem))
		end
	end)
end

return Broadcast
