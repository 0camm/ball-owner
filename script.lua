local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local CFG = {
	AFK_TIMEOUT     = 2.5,
	BALL_RADIUS     = 25,
	INPUT_THRESHOLD = 0.15,
	MOVE_HZ         = 1/20,
	JITTER_SMOOTH   = 0.18,
	PRESSURE_DIST   = 5,
	PRESSURE_SPEED  = 0.5,
	SENSITIVITY     = 1.0,
	REACTION_DELAY  = 0,
	HUMANIZE        = true,
	PRESSURE_ON     = true,
	BALL_NAMES      = {Ball = true, Basketball = true},
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
local heartbeatConn  = nil
local inputConns     = {}

local function clearBallCache()
	cachedBall = nil
	if ballConnection then ballConnection:Disconnect() ballConnection = nil end
end

local function watchBall(part)
	cachedBall      = part
	smoothBallPos   = part.Position
	lastRawBallPos  = part.Position
	ballVel         = Vector3.new()
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
	return Vector3.new((math.random()-0.5)*0.6, 0, (math.random()-0.5)*0.6)
end

-- unload function declared early so UI can reference it
local function unload()
	owning = false
	clearBallCache()
	if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
	for _, c in next, inputConns do c:Disconnect() end
	inputConns = {}
	local cg  = game:GetService("CoreGui")
	local old = cg:FindFirstChild("__overlay")
	if old then old:Destroy() end
end

table.insert(inputConns, UserInputService.InputBegan:Connect(function() lastInputTime = tick() end))
table.insert(inputConns, UserInputService.InputChanged:Connect(function() lastInputTime = tick() end))

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

-- corner dot
local dot = Instance.new("Frame", sg)
dot.Size             = UDim2.new(0,7,0,7)
dot.Position         = UDim2.new(1,-16,0,16)
dot.BackgroundColor3 = Color3.fromRGB(70,70,70)
dot.BorderSizePixel  = 0
Instance.new("UICorner", dot).CornerRadius = UDim.new(1,0)

local dotBtn = Instance.new("TextButton", sg)
dotBtn.Size                  = UDim2.new(0,28,0,28)
dotBtn.Position              = UDim2.new(1,-30,0,6)
dotBtn.BackgroundTransparency= 1
dotBtn.Text                  = ""

-- panel
local PANEL_W = 186
local panel = Instance.new("Frame", sg)
panel.Name               = "panel"
panel.Size               = UDim2.new(0,PANEL_W,0,10) -- height set by layout
panel.Position           = UDim2.new(1,-(PANEL_W+12),0,38)
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

-- use UIListLayout so nothing ever overlaps
local layout = Instance.new("UIListLayout", panel)
layout.FillDirection  = Enum.FillDirection.Vertical
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder      = Enum.SortOrder.LayoutOrder
layout.Padding        = UDim.new(0,0)

local padding = Instance.new("UIPadding", panel)
padding.PaddingTop    = UDim.new(0,0)
padding.PaddingBottom = UDim.new(0,8)
padding.PaddingLeft   = UDim.new(0,0)
padding.PaddingRight  = UDim.new(0,0)

-- auto-resize panel height
layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	panel.Size = UDim2.new(0,PANEL_W,0,layout.AbsoluteContentSize.Y+8)
end)

local function makeSection(h)
	local f = Instance.new("Frame", panel)
	f.Size             = UDim2.new(1,0,0,h)
	f.BackgroundTransparency = 1
	f.BorderSizePixel  = 0
	return f
end

-- title bar
local titleSec = makeSection(32)
titleSec.LayoutOrder = 0
titleSec.BackgroundColor3 = Color3.fromRGB(14,14,14)
titleSec.BackgroundTransparency = 0

local titleCorner = Instance.new("UICorner", titleSec)
titleCorner.CornerRadius = UDim.new(0,10)
local titleFix = Instance.new("Frame", titleSec)
titleFix.Size             = UDim2.new(1,0,0.5,0)
titleFix.Position         = UDim2.new(0,0,0.5,0)
titleFix.BackgroundColor3 = Color3.fromRGB(14,14,14)
titleFix.BorderSizePixel  = 0

local titleDot = Instance.new("Frame", titleSec)
titleDot.Size             = UDim2.new(0,5,0,5)
titleDot.Position         = UDim2.new(0,12,0.5,-2)
titleDot.BackgroundColor3 = Color3.fromRGB(70,70,70)
titleDot.BorderSizePixel  = 0
Instance.new("UICorner", titleDot).CornerRadius = UDim.new(1,0)

local titleLbl = Instance.new("TextLabel", titleSec)
titleLbl.Size               = UDim2.new(1,-24,1,0)
titleLbl.Position           = UDim2.new(0,24,0,0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text               = "assist"
titleLbl.TextColor3         = Color3.fromRGB(70,70,70)
titleLbl.Font               = Enum.Font.Gotham
titleLbl.TextSize           = 10
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left

-- status row
local statusSec = makeSection(30)
statusSec.LayoutOrder = 1

local statusDot = Instance.new("Frame", statusSec)
statusDot.Size             = UDim2.new(0,6,0,6)
statusDot.Position         = UDim2.new(0,14,0.5,-3)
statusDot.BackgroundColor3 = Color3.fromRGB(70,70,70)
statusDot.BorderSizePixel  = 0
Instance.new("UICorner", statusDot).CornerRadius = UDim.new(1,0)

local statusLbl = Instance.new("TextLabel", statusSec)
statusLbl.Size               = UDim2.new(1,-30,1,0)
statusLbl.Position           = UDim2.new(0,26,0,0)
statusLbl.BackgroundTransparency = 1
statusLbl.Text               = "inactive"
statusLbl.TextColor3         = Color3.fromRGB(60,60,60)
statusLbl.Font               = Enum.Font.Gotham
statusLbl.TextSize           = 10
statusLbl.TextXAlignment     = Enum.TextXAlignment.Left

local function makeDividerSec(order)
	local s = makeSection(1)
	s.LayoutOrder        = order
	s.BackgroundColor3   = Color3.fromRGB(255,255,255)
	s.BackgroundTransparency = 0.93
end

makeDividerSec(2)

-- row builder using layout sections
local rowOrder = 3
local function makeRow(label, valStr, onMinus, onPlus)
	local sec = makeSection(28)
	sec.LayoutOrder = rowOrder
	rowOrder = rowOrder + 1

	local lbl = Instance.new("TextLabel", sec)
	lbl.Size               = UDim2.new(0,88,1,0)
	lbl.Position           = UDim2.new(0,14,0,0)
	lbl.BackgroundTransparency = 1
	lbl.Text               = label
	lbl.TextColor3         = Color3.fromRGB(55,55,55)
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 9
	lbl.TextXAlignment     = Enum.TextXAlignment.Left

	local val = Instance.new("TextLabel", sec)
	val.Size               = UDim2.new(0,38,1,0)
	val.Position           = UDim2.new(0,94,0,0)
	val.BackgroundTransparency = 1
	val.Text               = valStr
	val.TextColor3         = Color3.fromRGB(110,110,110)
	val.Font               = Enum.Font.GothamBold
	val.TextSize           = 9
	val.TextXAlignment     = Enum.TextXAlignment.Right

	local minus = Instance.new("TextButton", sec)
	minus.Size             = UDim2.new(0,18,0,16)
	minus.Position         = UDim2.new(1,-40,0.5,-8)
	minus.BackgroundColor3 = Color3.fromRGB(20,20,20)
	minus.BorderSizePixel  = 0
	minus.Text             = "−"
	minus.TextColor3       = Color3.fromRGB(110,110,110)
	minus.Font             = Enum.Font.GothamBold
	minus.TextSize         = 10
	Instance.new("UICorner", minus).CornerRadius = UDim.new(0,4)

	local plus = Instance.new("TextButton", sec)
	plus.Size              = UDim2.new(0,18,0,16)
	plus.Position          = UDim2.new(1,-19,0.5,-8)
	plus.BackgroundColor3  = Color3.fromRGB(20,20,20)
	plus.BorderSizePixel   = 0
	plus.Text              = "+"
	plus.TextColor3        = Color3.fromRGB(110,110,110)
	plus.Font              = Enum.Font.GothamBold
	plus.TextSize          = 10
	Instance.new("UICorner", plus).CornerRadius = UDim.new(0,4)

	minus.MouseButton1Click:Connect(onMinus)
	plus.MouseButton1Click:Connect(onPlus)

	return val
end

local function makeToggleRow(label, init, onChange)
	local sec = makeSection(28)
	sec.LayoutOrder = rowOrder
	rowOrder = rowOrder + 1

	local lbl = Instance.new("TextLabel", sec)
	lbl.Size               = UDim2.new(0,120,1,0)
	lbl.Position           = UDim2.new(0,14,0,0)
	lbl.BackgroundTransparency = 1
	lbl.Text               = label
	lbl.TextColor3         = Color3.fromRGB(55,55,55)
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 9
	lbl.TextXAlignment     = Enum.TextXAlignment.Left

	local state = init
	local btn = Instance.new("TextButton", sec)
	btn.Size               = UDim2.new(0,40,0,16)
	btn.Position           = UDim2.new(1,-52,0.5,-8)
	btn.BackgroundColor3   = state and Color3.fromRGB(25,70,25) or Color3.fromRGB(20,20,20)
	btn.BorderSizePixel    = 0
	btn.Text               = state and "on" or "off"
	btn.TextColor3         = state and Color3.fromRGB(85,200,85) or Color3.fromRGB(75,75,75)
	btn.Font               = Enum.Font.Gotham
	btn.TextSize           = 9
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0,4)

	btn.MouseButton1Click:Connect(function()
		state = not state
		btn.BackgroundColor3 = state and Color3.fromRGB(25,70,25) or Color3.fromRGB(20,20,20)
		btn.Text             = state and "on" or "off"
		btn.TextColor3       = state and Color3.fromRGB(85,200,85) or Color3.fromRGB(75,75,75)
		onChange(state)
	end)
end

local function wireRow(label, key, min, max, step, fmt)
	local function fmtVal() return fmt(CFG[key]) end
	local valLbl = makeRow(label, fmtVal(),
		function()
			CFG[key] = math.max(min, math.floor((CFG[key]-step)*1000+0.5)/1000)
			if key == "BALL_RADIUS" then clearBallCache() end
			valLbl.Text = fmtVal()
		end,
		function()
			CFG[key] = math.min(max, math.floor((CFG[key]+step)*1000+0.5)/1000)
			valLbl.Text = fmtVal()
		end
	)
end

wireRow("radius",      "BALL_RADIUS",     5,   60,  5,    function(v) return v.."st" end)
wireRow("sensitivity", "SENSITIVITY",     0.1, 2.0, 0.1,  function(v) return math.floor(v*100).."%"end)
wireRow("delay",       "REACTION_DELAY",  0,   1.0, 0.05, function(v) return v.."s" end)
wireRow("smoothing",   "JITTER_SMOOTH",   0.02,0.5, 0.02, function(v) return v end)
wireRow("pressure spd","PRESSURE_SPEED",  0,   2.0, 0.1,  function(v) return v end)
wireRow("afk after",   "AFK_TIMEOUT",     2,   30,  1,    function(v) return v.."s" end)

makeDividerSec(rowOrder) rowOrder = rowOrder + 1

makeToggleRow("humanize",        CFG.HUMANIZE,     function(v) CFG.HUMANIZE    = v end)
makeToggleRow("pressure",        CFG.PRESSURE_ON,  function(v) CFG.PRESSURE_ON = v end)

makeDividerSec(rowOrder) rowOrder = rowOrder + 1

-- activate button
local activeSec = makeSection(38)
activeSec.LayoutOrder = rowOrder
rowOrder = rowOrder + 1

local toggleBtn = Instance.new("TextButton", activeSec)
toggleBtn.Size             = UDim2.new(1,-24,0,26)
toggleBtn.Position         = UDim2.new(0,12,0.5,-13)
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

-- unload button
local unloadSec = makeSection(30)
unloadSec.LayoutOrder = rowOrder

local unloadBtn = Instance.new("TextButton", unloadSec)
unloadBtn.Size             = UDim2.new(1,-24,0,20)
unloadBtn.Position         = UDim2.new(0,12,0.5,-10)
unloadBtn.BackgroundColor3 = Color3.fromRGB(14,14,14)
unloadBtn.BorderSizePixel  = 0
unloadBtn.Text             = "unload"
unloadBtn.TextColor3       = Color3.fromRGB(80,40,40)
unloadBtn.Font             = Enum.Font.Gotham
unloadBtn.TextSize         = 9
Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0,6)
local uStroke = Instance.new("UIStroke", unloadBtn)
uStroke.Color        = Color3.fromRGB(120,40,40)
uStroke.Transparency = 0.7
uStroke.Thickness    = 1

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
unloadBtn.MouseButton1Click:Connect(function() unload() end)

heartbeatConn = RunService.Heartbeat:Connect(function()
	if not owning then return end
	local now = tick()
	if now - lastMoveTime < CFG.MOVE_HZ then return end
	lastMoveTime = now

	if isAFK() then setStatus("afk", Color3.fromRGB(205,135,40)) return end
	if hasBall() then setStatus("holding", Color3.fromRGB(205,185,50)) return end

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
		smoothBallPos  = smoothBallPos:Lerp(rawPos + ballVel*3, CFG.JITTER_SMOOTH)
	end

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
	if speed < 0.04 and CFG.PRESSURE_ON then
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
