--!strict
-- Una sola línea de texto: estado del vuelo y, si ShowDebug, los valores internos para ajustar el feeling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Glider.GliderConfig)

local StatusLabel = {}

local gui = Instance.new("ScreenGui")
gui.Name = "GliderStatus"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true

local label = Instance.new("TextLabel")
label.AnchorPoint = Vector2.new(0.5, 0)
label.Position = UDim2.new(0.5, 0, 0, 46)
label.Size = UDim2.new(0.9, 0, 0, 44)
label.BackgroundTransparency = 1
label.Font = Enum.Font.GothamMedium
label.TextSize = 16
label.TextColor3 = Color3.new(1, 1, 1)
label.TextStrokeTransparency = 0.4
label.Text = ""
label.Parent = gui
gui.Parent = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui")

local function number(glider: Model, name: string): number
	local value = glider:GetAttribute(name)
	return if type(value) == "number" then value else 0
end

function StatusLabel.update(glider: Model?, side: number)
	if not glider or side == 0 then
		label.Text = ""
		return
	end
	local state = glider:GetAttribute("State")
	local sideText = if side < 0 then "PLAYER 1" else "PLAYER 2"
	local status
	if state == "Idle" then
		status = "Waiting for your partner"
	elseif state == "Countdown" then
		local checkpoint = number(glider, "Checkpoint")
		status = string.format("Takeoff in %d", math.ceil(number(glider, "Countdown")))
		if checkpoint > 0 then
			status ..= string.format(" · from checkpoint %d", checkpoint)
		end
	elseif state == "Ended" then
		if glider:GetAttribute("Completed") then
			status = "Finish! Returning to the lobby"
		elseif number(glider, "Checkpoint") > 0 then
			status = string.format("Crash! Back to checkpoint %d", number(glider, "Checkpoint"))
		else
			status = "Crash! Back to the start"
		end
	else
		status = "Flying"
	end

	local text = string.format("%s · %s · A/D to slide along the bar", sideText, status)
	if Config.ShowDebug then
		text ..= string.format(
			"\nP1 %+.2f  P2 %+.2f  |  Lift %.2f  Balance %+.2f  |  Vy %+.1f  Roll %+.0f°  Turn %+.0f°/s  |  Alt %.0f",
			number(glider, "LeftPosition"),
			number(glider, "RightPosition"),
			number(glider, "LiftInput"),
			number(glider, "BalanceInput"),
			number(glider, "VerticalSpeed"),
			number(glider, "Roll"),
			number(glider, "TurnRate"),
			number(glider, "Altitude")
		)
	end
	label.Text = text
end

return StatusLabel
