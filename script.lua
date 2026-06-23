local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local owning = false
local PLAYER_INPUT_THRESHOLD = 0.2
local hidden = false
local lastInputTime = tick()
local AFK_TIMEOUT = 5

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

		if candidate then
			if hrp then
				local d = (candidate.Position - hrp.Position).Magnitude
				if not nearestDist or d < nearestDist then
					nearest = candidate
					nearestDist = d
				end
			elseif not nearest then
				nearest = candidate
			end
		end
	end

	return nearest, nearestDist
end

local function hasBall()
	local char = LocalPlayer.Character
	if not char then return false end
	for _, v in pairs(char:GetDescendants()) do
		if v:IsA("Tool") and (v.Name == "Ball" or v.Name == "Basketball") then
			return true
		end
		if v:IsA("BasePart") and (v.Name == "Ball" or v.Name == "Basketball") then
			return true
		end
	end
	return false
end

local gui = Instance.new("ScreenGui")
gui.ResetOnSpawn = false
gui.Name = "OwnerGui"
gui.Parent = game:GetService("CoreGui")

local main = Instance.new("Frame")
main.Name = "Main"
main.Parent = gui
main.Size = UDim2.new(0, 220, 0, 110)
main.Position = UDim2.new(0, 20, 0.5, -55)
main.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
main.BorderSizePixel = 0
main.Active = true
main.Draggable = true

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = main

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(60, 60, 60)
stroke.Thickness = 1.2
stroke.Parent = main

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
titleBar.BorderSizePixel = 0
titleBar.Parent = main

local titleCorner = Instance.new("UICorner")
titleCorner.CornerRadius = UDim.new(0, 10)
titleCorner.Parent = titleBar

local titleFix = Instance.new("Frame")
titleFix.Size = UDim2.new(1, 0, 0.5, 0)
titleFix.Position = UDim2.new(0, 0, 0.5, 0)
titleFix.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
titleFix.BorderSizePixel = 0
titleFix.Parent = titleBar

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -40, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "Ball Owner"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar

local hideBtn = Instance.new("TextButton")
hideBtn.Size = UDim2.new(0, 28, 0, 22)
hideBtn.Position = UDim2.new(1, -32, 0, 5)
hideBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
hideBtn.BorderSizePixel = 0
hideBtn.Text = "−"
hideBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
hideBtn.Font = Enum.Font.GothamBold
hideBtn.TextSize = 16
hideBtn.Parent = titleBar

local hideBtnCorner = Instance.new("UICorner")
hideBtnCorner.CornerRadius = UDim.new(0, 6)
hideBtnCorner.Parent = hideBtn

local content = Instance.new("Frame")
content.Name = "Content"
content.Size = UDim2.new(1, 0, 1, -32)
content.Position = UDim2.new(0, 0, 0, 32)
content.BackgroundTransparency = 1
content.Parent = main

local statusDot = Instance.new("Frame")
statusDot.Size = UDim2.new(0, 10, 0, 10)
statusDot.Position = UDim2.new(0, 16, 0, 18)
statusDot.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
statusDot.BorderSizePixel = 0
statusDot.Parent = content

local dotCorner = Instance.new("UICorner")
dotCorner.CornerRadius = UDim.new(1, 0)
dotCorner.Parent = statusDot

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -36, 0, 26)
statusLabel.Position = UDim2.new(0, 32, 0, 12)
statusLabel.BackgroundTransparency = 1
statusLabel.Text = "Inactive"
statusLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
statusLabel.Font = Enum.Font.Gotham
statusLabel.TextSize = 13
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Parent = content

local toggleBtn = Instance.new("TextButton")
toggleBtn.Size = UDim2.new(1, -24, 0, 34)
toggleBtn.Position = UDim2.new(0, 12, 1, -44)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
toggleBtn.BorderSizePixel = 0
toggleBtn.Text = "Enable"
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.TextSize = 14
toggleBtn.Parent = content

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleBtn

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = Color3.fromRGB(60, 60, 60)
toggleStroke.Thickness = 1
toggleStroke.Parent = toggleBtn

local tabBtn = Instance.new("TextButton")
tabBtn.Size = UDim2.new(0, 28, 0, 22)
tabBtn.Position = UDim2.new(0, 20, 0.5, -11)
tabBtn.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
tabBtn.BorderSizePixel = 0
tabBtn.Text = "●"
tabBtn.TextColor3 = Color3.fromRGB(100, 100, 100)
tabBtn.Font = Enum.Font.GothamBold
tabBtn.TextSize = 12
tabBtn.Visible = false
tabBtn.Parent = gui

local tabCorner = Instance.new("UICorner")
tabCorner.CornerRadius = UDim.new(0, 6)
tabCorner.Parent = tabBtn

local tabStroke = Instance.new("UIStroke")
tabStroke.Color = Color3.fromRGB(60, 60, 60)
tabStroke.Thickness = 1
tabStroke.Parent = tabBtn

local function setStatus(text, color)
	statusLabel.Text = text
	statusLabel.TextColor3 = color
	statusDot.BackgroundColor3 = color
end

local function setState(state)
	owning = state
	if state then
		setStatus("Active", Color3.fromRGB(30, 200, 30))
		toggleBtn.Text = "Disable"
		toggleBtn.BackgroundColor3 = Color3.fromRGB(30, 100, 30)
		toggleStroke.Color = Color3.fromRGB(30, 160, 30)
	else
		setStatus("Inactive", Color3.fromRGB(160, 160, 160))
		toggleBtn.Text = "Enable"
		toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
		toggleStroke.Color = Color3.fromRGB(60, 60, 60)
	end
end

hideBtn.MouseButton1Click:Connect(function()
	hidden = true
	main.Visible = false
	tabBtn.Visible = true
end)

tabBtn.MouseButton1Click:Connect(function()
	hidden = false
	main.Visible = true
	tabBtn.Visible = false
end)

toggleBtn.MouseButton1Click:Connect(function()
	setState(not owning)
end)

RunService.RenderStepped:Connect(function()
	if not owning then return end

	if isAFK() then
		setStatus("AFK", Color3.fromRGB(255, 165, 0))
		return
	end

	if hasBall() then
		setStatus("Has Ball", Color3.fromRGB(255, 215, 0))
		return
	end

	setStatus("Active", Color3.fromRGB(30, 200, 30))

	local character = LocalPlayer.Character
	if not character then return end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local myHRP = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not myHRP then return end

	local ball, _ = findBall()
	if not ball then return end

	local moveDir = humanoid.MoveDirection
	if moveDir and moveDir.Magnitude > PLAYER_INPUT_THRESHOLD then return end

	local right = myHRP.CFrame.RightVector
	local localOffset = (ball.Position - myHRP.Position):Dot(right)
	local targetPos = myHRP.Position + right * localOffset

	humanoid:MoveTo(targetPos)
end)

setState(false)
