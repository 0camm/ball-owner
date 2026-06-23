local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local CFG = {
	AFK_TIMEOUT      = 3,
	BALL_RADIUS      = 25,
	INPUT_THRESHOLD  = 0.15,
	MOVE_HZ          = 1/20,
	JITTER_SMOOTH    = 0.18,
	PRESSURE_DIST    = 5,
	PRESSURE_SPEED   = 0.5,
	SENSITIVITY      = 1.0,
	REACTION_DELAY   = 0,
	HUMANIZE         = true,
	BALL_NAMES       = {Ball = true, Basketball = true},
}

local owning         = false
local lastInputTime  = tick()
local lastMoveTime   = 0
local smoothBallPos  = nil
local lastRawBallPos = nil
local ballVel        = Vector3.new()
local cachedBall     = nil
local ballConnection = nil
local reactionTimer  = 0
local humanizeOffset = Vector3.new()
local humanizeTimer  = 0

local function clearBallCache()
	cachedBall = nil
	if ballConnection then ballConnection:Disconnect() ballConnection = nil end
end

local function watchBall(part)
	cachedBall   = part
	smoothBallPos   = part.Position
	lastRawBallPos  = part.Position
	ballVel      = Vector3.new()
	if ballConnection then ballConnection:Disconnect() end
	ballConnection = part.AncestryChanged:Connect(function()
		if not part or not part.Parent then clearBallCache() end
	end)
end

local function findBall()
	local char = LocalPlayer.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local hrpPos = hrp.Position
	local best, bestD

	for _, v in next, workspace:GetDescendants() do
		local part
		if v:IsA("BasePart") and CFG.BALL_NAMES[v.Name] then
			local anc, ours = v.Parent, false
			while anc do
				if anc == char then ours = true break end
				anc = anc.Parent
			end
			if not ours then part = v end
		end
		if part then
			local d = (part.Position - hrpPos).Magnitude
			if d <= CFG.BALL_RADIUS and (not bestD or d < bestD) then
				best, bestD = part, d
			end
		end
	end

	if best then watchBall(best) end
end

local function hasBall()
	local char = LocalPlayer.Character
	if not char then return false end
	for _, v in next, char:GetDescendants() do
		if CFG.BALL_NAMES[v.Name] then return true end
	end
	return false
end

local function isAFK()
	return tick() - lastInputTime > CFG.AFK_TIMEOUT
end

local function randomOffset()
	return Vector3.new(
		(math.random() - 0.5) * 0.6,
		0,
		(math.random() - 0.5) * 0.6
	)
end

UserInputService.InputBegan:Connect(function() lastInputTime = tick() end)
UserInputService.InputChanged:Connect(function() lastInputTime = tick() end)

-- UI
local cg  = game:GetService("CoreGui")
local old = cg:FindFirstChild("__overlay")
if old then old:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name           = "__overlay"
sg.ResetOnSpawn   = false
sg.DisplayOrder   = 999
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent         = cg

local dot = Instance.new("Frame", sg)
dot.Size             = UDim2.new(0,7,0,7)
dot.Position         = UDim2.new(1,-16,0,16)
dot.BackgroundColor3 = Color3.fromRGB(70,70,70)
dot.BorderSizePixel  = 0
Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0)

local dotBtn = Instance.new("TextButton", sg)
dotBtn.Size                = UDim2.new(0,28,0,28)
dotBtn.Position            = UDim2.new(1,-30,0,8)
dotBtn.BackgroundTransparency = 1
dotBtn.Text                = ""

local panel = Instance.new("Frame", sg)
panel.Name               = "panel"
panel.Size               = UDim2.new(0,182,0,260)
panel.Position           = UDim2.new(1,-198,0,38)
panel.BackgroundColor3   = Color3.fromRGB(8,8,8)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel    = 0
panel.Active             = true
panel.Draggable          = true
Instance.new("UICorner", panel).CornerRadius = UDim.new(0,10)

local pStroke = Instance.new("UIStroke", panel)
pStroke.Color        = Color3.fromRGB(255,255,255)
pStroke.Transparency = 0.88
pStroke.Thickness    = 1

local bar = Instance.new("Frame", panel)
bar.Size             = UDim2.new(1,0,0,30)
bar.BackgroundColor3 = Color3.fromRGB(14,14,14)
bar.BorderSizePixel  = 0
Instance.new("UICorner", bar).CornerRadius = UDim.new(0,10)
local barFix = Instance.new("Frame", bar)
barFix.Size             = UDim2.new(1,0,0.5,0)
barFix.Position         = UDim2.new(0,0,0.5,0)
barFix.BackgroundColor3 = Color3.fromRGB(14,14,14)
barFix.BorderSizePixel  = 0

local titleDot = Instance.new("Frame", bar)
titleDot.Size             = UDim2.new(0,5,0,5)
titleDot.Position         = UDim2.new(0,12,0.5,-2)
titleDot.BackgroundColor3 = Color3.fromRGB(70,70,70)
titleDot.BorderSizePixel  = 0
Instance.new("UICorner", titleDot).CornerRadius = UDim.new(1,0)

local titleLbl = Instance.new("TextLabel", bar)
titleLbl.Size               = UDim2.new(1,-24,1,0)
titleLbl.Position           = UDim2.new(0,24,0,0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text               = "assist"
titleLbl.TextColor3         = Color3.fromRGB(70,70,70)
titleLbl.Font               = Enum.Font.Gotham
titleLbl.TextSize           = 10
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left

local statusDot = Instance.new("Frame", panel)
statusDot.Size             = UDim2.new(0,6,0,6)
statusDot.Position         = UDim2.new(0,14,0,40)
statusDot.BackgroundColor3 = Color3.fromRGB(70,70,70)
statusDot.BorderSizePixel  = 0
Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1,0)

local statusLbl = Instance.new("TextLabel", panel)
statusLbl.Size               = UDim2.new(1,-30,0,18)
statusLbl.Position           = UDim2.new(0,26,0,34)
statusLbl.BackgroundTransparency = 1
statusLbl.Text               = "inactive"
statusLbl.TextColor3         = Color3.fromRGB(60,60,60)
statusLbl.Font               = Enum.Font.Gotham
statusLbl.TextSize           = 10
statusLbl.TextXAlignment     = Enum.TextXAlignment.Left

local function makeDivider(yPos)
	local d = Instance.new("Frame", panel)
	d.Size               = UDim2.new(1,-24,0,1)
	d.Position           = UDim2.new(0,12,0,yPos)
	d.BackgroundColor3   = Color3.fromRGB(255,255,255)
	d.BackgroundTransparency = 0.93
	d.BorderSizePixel    = 0
end

makeDivider(58)
makeDivider(132)
makeDivider(196)

local function makeRow(label, yPos)
	local lbl = Instance.new("TextLabel", panel)
	lbl.Size               = UDim2.new(0,80,0,18)
	lbl.Position           = UDim2.new(0,14,0,yPos)
	lbl.BackgroundTransparency = 1
	lbl.Text               = label
	lbl.TextColor3         = Color3.fromRGB(55,55,55)
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 9
	lbl.TextXAlignment     = Enum.TextXAlignment.Left

	local val = Instance.new("TextLabel", panel)
	val.Size               = UDim2.new(0,40,0,18)
	val.Position           = UDim2.new(0,90,0,yPos)
	val.BackgroundTransparency = 1
	val.Text               = ""
	val.TextColor3         = Color3.fromRGB(110,110,110)
	val.Font               = Enum.Font.GothamBold
	val.TextSize           = 9
	val.TextXAlignment     = Enum.TextXAlignment.Right

	local minus = Instance.new("TextButton", panel)
	minus.Size             = UDim2.new(0,18,0,15)
	minus.Position         = UDim2.new(1,-42,0,yPos+1)
	minus.BackgroundColor3 = Color3.fromRGB(20,20,20)
	minus.BorderSizePixel  = 0
	minus.Text             = "−"
	minus.TextColor3       = Color3.fromRGB(110,110,110)
	minus.Font             = Enum.Font.GothamBold
	minus.TextSize         = 10
	Instance.new("UICorner", minus).CornerRadius = UDim.new(0,4)

	local plus = Instance.new("TextButton", panel)
	plus.Size              = UDim2.new(0,18,0,15)
	plus.Position          = UDim2.new(1,-21,0,yPos+1)
	plus.BackgroundColor3  = Color3.fromRGB(20,20,20)
	plus.BorderSizePixel   = 0
	plus.Text              = "+"
	plus.TextColor3        = Color3.fromRGB(110,110,110)
	plus.Font              = Enum.Font.GothamBold
	plus.TextSize          = 10
	Instance.new("UICorner", plus).CornerRadius = UDim.new(0,4)

	return val, minus, plus
end

local radVal, radMinus, radPlus       = makeRow("radius",    66)
local senVal, senMinus, senPlus       = makeRow("sensitivity", 88)
local delVal, delMinus, delPlus       = makeRow("delay",     110)
local afkVal, afkMinus, afkPlus       = makeRow("afk after", 140)
local spdVal, spdMinus, spdPlus       = makeRow("pressure",  162)
local smVal,  smMinus,  smPlus        = makeRow("smoothing", 184)

local function makeToggleRow(label, yPos, initVal, onChange)
	local lbl = Instance.new("TextLabel", panel)
	lbl.Size               = UDim2.new(0,110,0,18)
	lbl.Position           = UDim2.new(0,14,0,yPos)
	lbl.BackgroundTransparency = 1
	lbl.Text               = label
	lbl.TextColor3         = Color3.fromRGB(55,55,55)
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 9
	lbl.TextXAlignment     = Enum.TextXAlignment.Left

	local state = initVal
	local btn = Instance.new("TextButton", panel)
	btn.Size               = UDim2.new(0,38,0,15)
	btn.Position           = UDim2.new(1,-50,0,yPos+1)
	btn.BackgroundColor3   = state and Color3.fromRGB(30,80,30) or Color3.fromRGB(20,20,20)
	btn.BorderSizePixel    = 0
	btn.Text               = state and "on" or "off"
	btn.TextColor3         = state and Color3.fromRGB(90,200,90) or Color3.fromRGB(80,80,80)
	btn.Font               = Enum.Font.Gotham
	btn.TextSize           = 9
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0,4)

	btn.MouseButton1Click:Connect(function()
		state = not state
		btn.BackgroundColor3 = state and Color3.fromRGB(30,80,30) or Color3.fromRGB(20,20,20)
		btn.Text             = state and "on" or "off"
		btn.TextColor3       = state and Color3.fromRGB(90,200,90) or Color3.fromRGB(80,80,80)
		onChange(state)
	end)
end

makeToggleRow("humanize", 204, CFG.HUMANIZE, function(v) CFG.HUMANIZE = v end)
makeToggleRow("pressure", 220, true, function(v) CFG.PRESSURE_SPEED = v and 0.5 or 0 end)

-- wire up controls
local function wireRow(minBtn, plusBtn, valLbl, key, min, max, step, fmt)
	local function refresh()
		valLbl.Text = fmt and fmt(CFG[key]) or tostring(CFG[key])
	end
	refresh()
	minBtn.MouseButton1Click:Connect(function()
		CFG[key] = math.max(min, math.floor((CFG[key] - step) * 100 + 0.5) / 100)
		if key == "BALL_RADIUS" then clearBallCache() end
		refresh()
	end)
	plusBtn.MouseButton1Click:Connect(function()
		CFG[key] = math.min(max, math.floor((CFG[key] + step) * 100 + 0.5) / 100)
		refresh()
	end)
end

wireRow(radMinus, radPlus, radVal, "BALL_RADIUS",    5,  60,  5,    function(v) return v.."st" end)
wireRow(senMinus, senPlus, senVal, "SENSITIVITY",    0.1, 2.0, 0.1, function(v) return math.floor(v*100).."%"end)
wireRow(delMinus, delPlus, delVal, "REACTION_DELAY", 0,  1.0, 0.05, function(v) return v.."s" end)
wireRow(afkMinus, afkPlus, afkVal, "AFK_TIMEOUT",   2,  30,  1,    function(v) return v.."s" end)
wireRow(spdMinus, spdPlus, spdVal, "PRESSURE_SPEED",0,  2.0, 0.1,  function(v) return tostring(v) end)
wireRow(smMinus,  smPlus,  smVal,  "JITTER_SMOOTH", 0.02,0.5, 0.02, function(v) return tostring(v) end)

local toggleBtn = Instance.new("TextButton", panel)
toggleBtn.Size             = UDim2.new(1,-24,0,26)
toggleBtn.Position         = UDim2.new(0,12,1,-34)
toggleBtn.BackgroundColor3 = Color3.fromRGB(18,18,18)
toggleBtn.BorderSizePixel  = 0
toggleBtn.Text             = "activate"
toggleBtn.TextColor3       = Color3.fromRGB(120,120,120)
toggleBtn.Font             = Enum.Font.Gotham
toggleBtn.TextSize         = 10
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0,6)

local tStroke = Instance.new("UIStroke", toggleBtn)
tStroke.Color        = Color3.fromRGB(255,255,255)
tStroke.Transparency = 0.92
tStroke.Thickness    = 1

local function setStatus(text, color)
	statusLbl.Text             = text
	statusLbl.TextColor3       = color
	statusDot.BackgroundColor3 = color
	titleDot.BackgroundColor3  = color
	dot.BackgroundColor3       = color
end

local function setState(state)
	owning       = state
	smoothBallPos  = nil
	lastRawBallPos = nil
	ballVel      = Vector3.new()
	reactionTimer  = 0
	if not state then clearBallCache() end
	if state then
		setStatus("active", Color3.fromRGB(85,205,85))
		toggleBtn.Text       = "deactivate"
		toggleBtn.TextColor3 = Color3.fromRGB(85,195,85)
		tStroke.Color        = Color3.fromRGB(55,150,55)
		tStroke.Transparency = 0.55
	else
		setStatus("inactive", Color3.fromRGB(55,55,55))
		toggleBtn.Text       = "activate"
		toggleBtn.TextColor3 = Color3.fromRGB(120,120,120)
		tStroke.Color        = Color3.fromRGB(255,255,255)
		tStroke.Transparency = 0.92
	end
end

dotBtn.MouseButton1Click:Connect(function() panel.Visible = not panel.Visible end)
toggleBtn.MouseButton1Click:Connect(function() setState(not owning) end)

RunService.Heartbeat:Connect(function()
	if not owning then return end

	local now = tick()
	if now - lastMoveTime < CFG.MOVE_HZ then return end
	lastMoveTime = now

	if isAFK() then
		setStatus("afk", Color3.fromRGB(205,135,40))
		return
	end
	if hasBall() then
		setStatus("holding", Color3.fromRGB(205,185,50))
		return
	end

	local char = LocalPlayer.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local myHRP    = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not myHRP then return end

	if not cachedBall or not cachedBall.Parent then findBall() end

	local ball = cachedBall
	if not ball or not ball.Parent then
		setStatus("scanning", Color3.fromRGB(55,55,55))
		return
	end

	local rawPos = ball.Position

	if not smoothBallPos then
		smoothBallPos  = rawPos
		lastRawBallPos = rawPos
	else
		local rawDelta = rawPos - lastRawBallPos
		ballVel        = ballVel:Lerp(rawDelta, 0.25)
		lastRawBallPos = rawPos
		local predicted = rawPos + ballVel * 3
		smoothBallPos   = smoothBallPos:Lerp(predicted, CFG.JITTER_SMOOTH)
	end

	-- reaction delay
	if CFG.REACTION_DELAY > 0 then
		reactionTimer = reactionTimer + CFG.MOVE_HZ
		if reactionTimer < CFG.REACTION_DELAY then
			setStatus("active", Color3.fromRGB(85,205,85))
			return
		end
		reactionTimer = 0
	end

	setStatus("active", Color3.fromRGB(85,205,85))

	local moveDir = humanoid.MoveDirection
	if moveDir and moveDir.Magnitude > CFG.INPUT_THRESHOLD then return end

	local myPos  = myHRP.Position
	local right  = myHRP.CFrame.RightVector
	local fwd    = myHRP.CFrame.LookVector
	local delta  = smoothBallPos - myPos
	local latOff = delta:Dot(right) * CFG.SENSITIVITY
	local fwdOff = delta:Dot(fwd)
	local speed  = ballVel.Magnitude

	-- humanize: drift a tiny random offset periodically
	if CFG.HUMANIZE then
		humanizeTimer = humanizeTimer + CFG.MOVE_HZ
		if humanizeTimer > 0.8 then
			humanizeOffset = randomOffset()
			humanizeTimer  = 0
		end
	else
		humanizeOffset = Vector3.new()
	end

	local target
	if speed < 0.04 then
		local flat = Vector3.new(delta.X, 0, delta.Z)
		if flat.Magnitude > CFG.PRESSURE_DIST then
			target = myPos + flat.Unit * CFG.PRESSURE_SPEED + humanizeOffset
		else
			target = myPos + right * latOff + humanizeOffset
		end
	else
		target = myPos + right * latOff + fwd * (fwdOff * 0.12) + humanizeOffset
	end

	humanoid:MoveTo(target)
end)

setState(false)
