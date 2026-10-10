-- Etiquetas del chat: quien tiene un pase con "chatTag" (Config.Gamepasses, p. ej. el VIP) escribe con esa etiqueta
-- delante del nombre, del color del pase. Lo pinta cada cliente al recibir el mensaje, leyendo los atributos
-- "Pass_<clave>" de quien lo escribe (los publica server/Passes), así que no se puede poner uno mismo la etiqueta.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Stats = require(ReplicatedStorage.Shared.Stats)

local ChatTags = {}

-- Etiquetas de ese jugador, en el orden de la tienda.
local function tags(speaker: Player): string
	local text = ""
	for _, key in Config.GamepassOrder do
		local pass = Config.Gamepasses[key]
		if pass.chatTag and Stats.pass(speaker, key) then
			text ..= `<font color="#{pass.color:ToHex()}"><b>[{pass.chatTag}]</b></font> `
		end
	end
	return text
end

function ChatTags.start()
	TextChatService.OnIncomingMessage = function(message: TextChatMessage)
		local source = message.TextSource
		local speaker = source and Players:GetPlayerByUserId(source.UserId)
		local prefix = speaker and tags(speaker)
		if not prefix or prefix == "" then
			return nil
		end
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = prefix .. message.PrefixText
		return properties
	end
end

return ChatTags
