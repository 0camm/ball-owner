local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local owning = false
local PLAYER_INPUT_THRESHOLD = 0.2
local hidden = false
local lastInputTime = tick()
local AFK_TIMEOUT = 5
local BALL_RADIUS = 20
local tickCount = 0
local THROTTLE = 3

UserInputService.InputBegan:Connect(function()
	lastInputTime = tick()
end)

UserInputService.InputChanged:Connect(function()
	lastInputTime = tick()
end)

local function isAFK()
	return tick() - lastInputTime > AFK_TIMEOUT
end

local function findBall()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local nearest, nearestDist

	for _, v in pairs(workspace:GetDescendants()) do
		local candidate

		if v:IsA("Tool") and (v.Name == "Ball" or v.Name == "Basketball") then
			for _, c in pairs(v:GetDescendants()) do
				if c:IsA("BasePart") then
					candidate = c
					break
				end
			end
		elseif v:IsA("BasePart") and (v.Name == "Ball" or v.Name == "Basketball") then
			candidate = v
		end

		if candidate and hrp then
			local d = (candidate.Position - hrp.Position).Magnitude
			if d <= BALL_RADIUS and (not nearestDist or d < nearestDist) then
				nearest = candidate
				nearestDist = d
			end
		end
	end

	return nearest
end

local function hasBall()
	local char = LocalPlayer.Character
	if not char then return false end
	for _, v in pairs(char:GetDescendants()) do
		if (v:IsA("Tool") or v:IsA("BasePart")) and (v.Name == "Ball" or v.Name == "Basketball") then
			return true
		end
	end
	return false
end

-- UI
local coreGui = game:GetService("CoreGui")

local existing = coreGui:FindFirstChild("__hud")
if existing then existing:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "__hud"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.Parent = coreGui

-- pill indicator (always visible, tiny)
local pill = Instance.new("Frame")
pill.Size = UDim2.new(0, 6, 0, 6)
pill.Position = UDim2.new(1, -14, 0, 14)
pill.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
pill.BorderSizePixel = 0
pill.Parent = gui

local pillCorner = Instance.new("UICorner")
pillCorner.CornerRadius = UDim.new(1, 0)
pillCorner.Parent = pill

local pillBtn = Instance.new("TextButton")
pillBtn.Size = UDim2.new(0, 24, 0, 24)
pillBtn.Position = UDim2.new(1, -26, 0, 6)
pillBtn.BackgroundTransparency = 1
pillBtn.Text = ""
pillBtn.Parent = gui

-- panel
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 160, 0, 72)
panel.Position = UDim2.new(1, -172, 0, 36)
panel.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
panel.BackgroundTransparency = 0.15
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true
panel.Visible = true
panel.Parent = gui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 8)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(255, 255, 255)
panelStroke.Transparency = 0.9
panelStroke.Thickness = 1
panelStroke.Parent = panel

-- status row
local dot = Instance.new("Frame")
dot.Size = UDim2.new(0, 6, 0, 6)
dot.Position = UDim2.new(0, 12, 0, 14)
dot.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
dot.BorderSizePixel = 0
dot.Parent = panel

local dotCorner2 = Instance.new("UICorner")
dotCorner2.CornerRadius = UDim.new(1, 0)
dotCorner2.Parent = dot

local statusLbl = Instance.new("TextLabel")
statusLbl.Size = UDim2.new(1, -28, 0, 20)
statusLbl.Position = UDim2.new(0, 24, 0, 6)
statusLbl.BackgroundTransparency = 1
statusLbl.Text = "off"
statusLbl.TextColor3 = Color3.fromRGB(100, 100, 100)
statusLbl.Font = Enum.Font.Gotham
statusLbl.TextSize = 11
statusLbl.TextXAlignment = Enum.TextXAlignment.Left
statusLbl.Parent = panel

-- toggle
local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(1, -24, 0, 28)
toggle.Position = UDim2.new(0, 12, 1, -38)
toggle.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
toggle.BorderSizePixel = 0
toggle.Text = "activate"
toggle.TextColor3 = Color3.fromRGB(160, 160, 160)
toggle.Font = Enum.Font.Gotham
toggle.TextSize = 11
toggle.Parent = panel

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 6)
toggleCorner.Parent = toggle

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = Color3.fromRGB(255, 255, 255)
toggleStroke.Transparency = 0.92
toggleStroke.Thickness = 1
toggleStroke.Parent = toggle

local function setStatus(text, dotColor, textColor)
	statusLbl.Text = text
	statusLbl.TextColor3 = textColor or dotColor
	dot.BackgroundColor3 = dotColor
	pill.BackgroundColor3 = dotColor
end

local function setState(state)
	owning = state
	if state then
		setStatus("active", Color3.fromRGB(100, 220, 100), Color3.fromRGB(140, 240, 140))
		toggle.Text = "deactivate"
		toggle.TextColor3 = Color3.fromRGB(120, 220, 120)
		toggleStroke.Color = Color3.fromRGB(80, 180, 80)
		toggleStroke.Transparency = 0.6
	else
		setStatus("off", Color3.fromRGB(80, 80, 80), Color3.fromRGB(100, 100, 100))
		toggle.Text = "activate"
		toggle.TextColor3 = Color3.fromRGB(160, 160, 160)
		toggleStroke.Color = Color3.fromRGB(255, 255, 255)
		toggleStroke.Transparency = 0.92
	end
end

pillBtn.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

toggle.MouseButton1Click:Connect(function()
	setState(not owning)
end)

RunService.Heartbeat:Connect(function()
	if not owning then return end

	tickCount = tickCount + 1
	if tickCount % THROTTLE ~= 0 then return end

	if isAFK() then
		setStatus("afk", Color3.fromRGB(220, 140, 40), Color3.fromRGB(220, 160, 80))
		return
	end

	if hasBall() then
		setStatus("holding", Color3.fromRGB(220, 200, 60), Color3.fromRGB(240, 220, 80))
		return
	end

	local character = LocalPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local myHRP = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not myHRP then return end

	local ball = findBall()
	if not ball then
		setStatus("waiting", Color3.fromRGB(80, 80, 80), Color3.fromRGB(100, 100, 100))
		return
	end

	setStatus("active", Color3.fromRGB(100, 220, 100), Color3.fromRGB(140, 240, 140))

	local moveDir = humanoid.MoveDirection
	if moveDir and moveDir.Magnitude > PLAYER_INPUT_THRESHOLD then return end

	local right = myHRP.CFrame.RightVector
	local localOffset = (ball.Position - myHRP.Position):Dot(right)
	local targetPos = myHRP.Position + right * localOffset

	humanoid:MoveTo(targetPos)
end)

setState(false)
