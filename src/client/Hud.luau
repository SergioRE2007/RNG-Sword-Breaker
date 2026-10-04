-- Interfaz fija: contadores, línea de estadísticas, menú y avisos.
-- La mochila está en Backpack, las mejoras en SkillTree, el gacha en GachaRoll y el estilo en Ui.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

local Config = require(ReplicatedStorage.Shared.Config)
local Format = require(ReplicatedStorage.Shared.Format)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Stats = require(ReplicatedStorage.Shared.Stats)
local Ui = require(script.Parent.Ui)

local Hud = {}

local player = Players.LocalPlayer
local BLACK = Color3.new(0, 0, 0)

local function counter(gui: Instance, offset: number, color: Color3): TextLabel
	local text = Ui.label(gui, 26)
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.new(0.5, offset, 0, 12)
	text.Size = UDim2.fromOffset(250, 50)
	text.BackgroundTransparency = 0
	text.BackgroundColor3 = color
	Ui.round(text, 14)
	Ui.bevel(text)
	Ui.stroke(text, BLACK, 3)
	return text
end

function Hud.start()
	local gui = Ui.screen()

	local coins = counter(gui, -132, Ui.COLORS.coins)
	local gems = counter(gui, 132, Ui.COLORS.purple)

	local stats = Ui.label(gui, 16)
	stats.Name = "Stats"
	stats.AnchorPoint = Vector2.new(0.5, 0)
	stats.Position = UDim2.new(0.5, 0, 0, 68)
	stats.Size = UDim2.fromOffset(514, 30)
	stats.BackgroundTransparency = 0.1
	stats.BackgroundColor3 = Ui.COLORS.panel
	Ui.round(stats, 10)
	Ui.stroke(stats, BLACK, 2)

	-- Menú
	local menu = Instance.new("Frame")
	menu.Name = "Menu"
	menu.AnchorPoint = Vector2.new(0, 0.5)
	menu.Position = UDim2.new(0, 14, 0.5, 0)
	menu.Size = UDim2.fromOffset(140, 0)
	menu.AutomaticSize = Enum.AutomaticSize.Y
	menu.BackgroundTransparency = 1
	menu.Parent = gui
	local menuLayout = Instance.new("UIListLayout")
	menuLayout.Padding = UDim.new(0, 12)
	menuLayout.SortOrder = Enum.SortOrder.LayoutOrder
	menuLayout.Parent = menu

	for order, entry in { { "Backpack", "Mochila", Ui.COLORS.blue }, { "Upgrades", "Mejoras", Ui.COLORS.green } } do
		local item = Ui.button(menu, entry[2], entry[3])
		item.Name = entry[1]
		item.LayoutOrder = order
		item.Size = UDim2.new(1, 0, 0, 60)
		item.TextSize = 24
		item.Activated:Connect(function()
			Ui.toggle(entry[1])
		end)
	end

	local function refresh()
		local amount = player:GetAttribute("Coins") or 0
		local gemAmount = player:GetAttribute("Gems") or 0

		coins.Text = "Monedas: " .. Format.short(amount)
		gems.Text = "Gemas: " .. Format.short(gemAmount)
		stats.Text = `Daño {Format.multiplier(Stats.damage(player))}  ·  Suerte x{Format.multiplier(Stats.luck(player))}  ·  Suerte de gacha x{Format.multiplier(Stats.gachaLuck(player))}`
	end

	player.AttributeChanged:Connect(refresh)
	refresh()

	Remotes.SwordObtained.OnClientEvent:Connect(function(index: number, kept: boolean, source: string)
		local sword = Config.Swords[index]
		local origin = if source == "roca" then "¡La roca de armas soltó" else "¡Te ha salido"
		local detail = if kept
			then `1 entre {Format.short(sword.rarity or 1)} · daño {Format.short(sword.damage)}`
			else `Vendida sola: +{Config.Gacha.SellValue} gemas`
		Ui.toast(`{origin} {sword.name}!\n{detail}`, sword.color)
	end)

	Remotes.Notice.OnClientEvent:Connect(Ui.toast)

	-- Avisos de cosas muy raras: al chat, o al aviso de pantalla si no hay chat.
	Remotes.Announce.OnClientEvent:Connect(function(text: string, color: Color3)
		local channels = TextChatService:FindFirstChild("TextChannels")
		local channel = channels and channels:FindFirstChild("RBXGeneral")
		if channel then
			channel:DisplaySystemMessage(`<font color="#{color:ToHex()}"><b>{text}</b></font>`)
		else
			Ui.toast(text, color)
		end
	end)
end

return Hud
