-- assist v2 — clean UI rebuild

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer      = Players.LocalPlayer

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

-- ─── Core Logic ───────────────────────────────────────────────────────────────

local function clearBallCache()
	cachedBall = nil
	if ballConnection then ballConnection:Disconnect(); ballConnection = nil end
end

local function watchBall(part)
	cachedBall     = part
	smoothBallPos  = part.Position
	lastRawBallPos = part.Position
	ballVel        = Vector3.new()
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
				if anc == char then ours = true; break end
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

-- ─── Unload (declared early for UI reference) ─────────────────────────────────

local function unload()
	owning = false
	clearBallCache()
	if heartbeatConn then heartbeatConn:Disconnect(); heartbeatConn = nil end
	for _, c in next, inputConns do c:Disconnect() end
	inputConns = {}
	local cg  = game:GetService("CoreGui")
	local old = cg:FindFirstChild("__assist_gui")
	if old then old:Destroy() end
end

-- ─── Input Tracking ───────────────────────────────────────────────────────────

table.insert(inputConns, UserInputService.InputBegan:Connect(function()  lastInputTime = tick() end))
table.insert(inputConns, UserInputService.InputChanged:Connect(function() lastInputTime = tick() end))

-- ─── UI ───────────────────────────────────────────────────────────────────────

local cg  = game:GetService("CoreGui")
local old = cg:FindFirstChild("__assist_gui")
if old then old:Destroy() end

local sg = Instance.new("ScreenGui")
sg.Name           = "__assist_gui"
sg.ResetOnSpawn   = false
sg.DisplayOrder   = 999
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent         = cg

-- ── Palette ──
local C = {
	bg       = Color3.fromRGB(10, 10, 10),
	surface  = Color3.fromRGB(16, 16, 16),
	surface2 = Color3.fromRGB(22, 22, 22),
	border   = Color3.fromRGB(38, 38, 38),
	text     = Color3.fromRGB(180, 180, 180),
	muted    = Color3.fromRGB(70, 70, 70),
	dim      = Color3.fromRGB(45, 45, 45),
	green    = Color3.fromRGB(80, 210, 100),
	greenDim = Color3.fromRGB(25, 60, 30),
	amber    = Color3.fromRGB(220, 160, 50),
	red      = Color3.fromRGB(200, 70, 70),
	white    = Color3.fromRGB(255, 255, 255),
}

-- ── Stealth dot (always visible, top-right) ──
local DOT_SIZE = 8
local DOT_PAD  = 14

local dotFrame = Instance.new("Frame", sg)
dotFrame.Size             = UDim2.new(0, DOT_SIZE, 0, DOT_SIZE)
dotFrame.Position         = UDim2.new(1, -(DOT_PAD + DOT_SIZE), 0, DOT_PAD)
dotFrame.BackgroundColor3 = C.dim
dotFrame.BorderSizePixel  = 0
dotFrame.ZIndex           = 20
Instance.new("UICorner", dotFrame).CornerRadius = UDim.new(1, 0)

-- invisible hit area around the dot
local dotBtn = Instance.new("TextButton", sg)
dotBtn.Size                   = UDim2.new(0, 28, 0, 28)
dotBtn.Position               = UDim2.new(1, -(DOT_PAD + DOT_SIZE + 10), 0, DOT_PAD - 10)
dotBtn.BackgroundTransparency = 1
dotBtn.Text                   = ""
dotBtn.ZIndex                 = 21

-- ── Root panel ──
local PANEL_W = 200

local panel = Instance.new("Frame", sg)
panel.Name               = "panel"
panel.Size               = UDim2.new(0, PANEL_W, 0, 10) -- height driven by layout
panel.Position           = UDim2.new(1, -(PANEL_W + 14), 0, 14)
panel.BackgroundColor3   = C.bg
panel.BorderSizePixel    = 0
panel.Active             = true
panel.Draggable          = true
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 10)

-- subtle border
local panelStroke = Instance.new("UIStroke", panel)
panelStroke.Color       = C.border
panelStroke.Transparency = 0
panelStroke.Thickness   = 1

-- list layout drives all height
local rootLayout = Instance.new("UIListLayout", panel)
rootLayout.FillDirection       = Enum.FillDirection.Vertical
rootLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
rootLayout.SortOrder           = Enum.SortOrder.LayoutOrder
rootLayout.Padding             = UDim.new(0, 0)

rootLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	panel.Size = UDim2.new(0, PANEL_W, 0, rootLayout.AbsoluteContentSize.Y)
end)

-- ── Header ──
local header = Instance.new("Frame", panel)
header.LayoutOrder          = 0
header.Size                 = UDim2.new(1, 0, 0, 38)
header.BackgroundColor3     = C.surface
header.BorderSizePixel      = 0
Instance.new("UICorner", header).CornerRadius = UDim.new(0, 10)

-- square off bottom corners
local headerFill = Instance.new("Frame", header)
headerFill.Size             = UDim2.new(1, 0, 0, 10)
headerFill.Position         = UDim2.new(0, 0, 1, -10)
headerFill.BackgroundColor3 = C.surface
headerFill.BorderSizePixel  = 0

local titleLbl = Instance.new("TextLabel", header)
titleLbl.Size               = UDim2.new(1, -16, 1, 0)
titleLbl.Position           = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text               = "AG"
titleLbl.TextColor3         = C.muted
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextSize           = 11
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left

-- status badge (right side of header)
local badge = Instance.new("Frame", header)
badge.Size             = UDim2.new(0, 60, 0, 18)
badge.Position         = UDim2.new(1, -72, 0.5, -9)
badge.BackgroundColor3 = C.surface2
badge.BorderSizePixel  = 0
Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 6)

local badgeStroke = Instance.new("UIStroke", badge)
badgeStroke.Color        = C.border
badgeStroke.Transparency = 0
badgeStroke.Thickness    = 1

local badgeLbl = Instance.new("TextLabel", badge)
badgeLbl.Size               = UDim2.new(1, 0, 1, 0)
badgeLbl.BackgroundTransparency = 1
badgeLbl.Text               = "off"
badgeLbl.TextColor3         = C.dim
badgeLbl.Font               = Enum.Font.Gotham
badgeLbl.TextSize           = 9
badgeLbl.TextXAlignment     = Enum.TextXAlignment.Center

-- ── Divider helper ──
local divOrder = 1
local function makeDivider(order)
	local d = Instance.new("Frame", panel)
	d.LayoutOrder          = order
	d.Size                 = UDim2.new(1, -28, 0, 1)
	d.BackgroundColor3     = C.border
	d.BackgroundTransparency = 0
	d.BorderSizePixel      = 0
	return d
end

-- ── Section label ──
local function makeSectionLabel(text, order)
	local f = Instance.new("Frame", panel)
	f.LayoutOrder          = order
	f.Size                 = UDim2.new(1, 0, 0, 22)
	f.BackgroundTransparency = 1
	f.BorderSizePixel      = 0

	local lbl = Instance.new("TextLabel", f)
	lbl.Size               = UDim2.new(1, -28, 1, 0)
	lbl.Position           = UDim2.new(0, 14, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text               = string.upper(text)
	lbl.TextColor3         = C.dim
	lbl.Font               = Enum.Font.GothamBold
	lbl.TextSize           = 8
	lbl.TextXAlignment     = Enum.TextXAlignment.Left
end

-- ── Row builders ──
local rowCount = 10 -- start after header/dividers

local function makeValueRow(label, valStr, onMinus, onPlus)
	local sec = Instance.new("Frame", panel)
	sec.LayoutOrder          = rowCount
	rowCount                 = rowCount + 1
	sec.Size                 = UDim2.new(1, 0, 0, 30)
	sec.BackgroundTransparency = 1
	sec.BorderSizePixel      = 0

	local lbl = Instance.new("TextLabel", sec)
	lbl.Size               = UDim2.new(0, 90, 1, 0)
	lbl.Position           = UDim2.new(0, 14, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text               = label
	lbl.TextColor3         = C.text
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 10
	lbl.TextXAlignment     = Enum.TextXAlignment.Left

	local val = Instance.new("TextLabel", sec)
	val.Size               = UDim2.new(0, 36, 1, 0)
	val.Position           = UDim2.new(0, 102, 0, 0)
	val.BackgroundTransparency = 1
	val.Text               = valStr
	val.TextColor3         = C.muted
	val.Font               = Enum.Font.GothamBold
	val.TextSize           = 10
	val.TextXAlignment     = Enum.TextXAlignment.Center

	local function makeBtn(xOff, label2)
		local b = Instance.new("TextButton", sec)
		b.Size             = UDim2.new(0, 20, 0, 20)
		b.Position         = UDim2.new(1, xOff, 0.5, -10)
		b.BackgroundColor3 = C.surface2
		b.BorderSizePixel  = 0
		b.Text             = label2
		b.TextColor3       = C.muted
		b.Font             = Enum.Font.GothamBold
		b.TextSize         = 12
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
		local s = Instance.new("UIStroke", b)
		s.Color        = C.border
		s.Transparency = 0
		s.Thickness    = 1
		return b
	end

	local minusBtn = makeBtn(-44, "−")
	local plusBtn  = makeBtn(-21, "+")

	minusBtn.MouseButton1Click:Connect(onMinus)
	plusBtn.MouseButton1Click:Connect(onPlus)

	return val
end

local function makeToggleRow(label, init, onChange)
	local sec = Instance.new("Frame", panel)
	sec.LayoutOrder          = rowCount
	rowCount                 = rowCount + 1
	sec.Size                 = UDim2.new(1, 0, 0, 30)
	sec.BackgroundTransparency = 1
	sec.BorderSizePixel      = 0

	local lbl = Instance.new("TextLabel", sec)
	lbl.Size               = UDim2.new(0, 130, 1, 0)
	lbl.Position           = UDim2.new(0, 14, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text               = label
	lbl.TextColor3         = C.text
	lbl.Font               = Enum.Font.Gotham
	lbl.TextSize           = 10
	lbl.TextXAlignment     = Enum.TextXAlignment.Left

	local state = init

	local track = Instance.new("Frame", sec)
	track.Size             = UDim2.new(0, 32, 0, 16)
	track.Position         = UDim2.new(1, -46, 0.5, -8)
	track.BackgroundColor3 = state and C.greenDim or C.surface2
	track.BorderSizePixel  = 0
	Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
	local ts = Instance.new("UIStroke", track)
	ts.Color = state and C.green or C.border; ts.Transparency = state and 0.7 or 0; ts.Thickness = 1

	local knob = Instance.new("Frame", track)
	knob.Size             = UDim2.new(0, 10, 0, 10)
	knob.Position         = state and UDim2.new(1, -13, 0.5, -5) or UDim2.new(0, 3, 0.5, -5)
	knob.BackgroundColor3 = state and C.green or C.muted
	knob.BorderSizePixel  = 0
	Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

	local hitbox = Instance.new("TextButton", sec)
	hitbox.Size             = UDim2.new(0, 36, 0, 24)
	hitbox.Position         = UDim2.new(1, -48, 0.5, -12)
	hitbox.BackgroundTransparency = 1
	hitbox.Text             = ""

	hitbox.MouseButton1Click:Connect(function()
		state = not state
		track.BackgroundColor3 = state and C.greenDim or C.surface2
		ts.Color               = state and C.green or C.border
		ts.Transparency        = state and 0.7 or 0
		knob.Position          = state and UDim2.new(1,-13,0.5,-5) or UDim2.new(0,3,0.5,-5)
		knob.BackgroundColor3  = state and C.green or C.muted
		onChange(state)
	end)
end

local function wireRow(label, key, min2, max2, step, fmt)
	local function fmtVal() return fmt(CFG[key]) end
	local valLbl = makeValueRow(label, fmtVal(),
		function()
			CFG[key] = math.max(min2, math.floor((CFG[key]-step)*1000+0.5)/1000)
			if key == "BALL_RADIUS" then clearBallCache() end
			valLbl.Text = fmtVal()
		end,
		function()
			CFG[key] = math.min(max2, math.floor((CFG[key]+step)*1000+0.5)/1000)
			valLbl.Text = fmtVal()
		end
	)
end

-- ── Build layout ──

makeDivider(1)
makeSectionLabel("detection", 2)
wireRow("radius",       "BALL_RADIUS",     5,   60,  5,    function(v) return v.."st" end)
wireRow("sensitivity",  "SENSITIVITY",     0.1, 2.0, 0.1,  function(v) return math.floor(v*100).."%" end)
wireRow("delay",        "REACTION_DELAY",  0,   1.0, 0.05, function(v) return v.."s" end)

makeDivider(rowCount) rowCount = rowCount + 1
makeSectionLabel("smoothing", rowCount) rowCount = rowCount + 1
wireRow("jitter",       "JITTER_SMOOTH",   0.02, 0.5, 0.02, function(v) return v end)

makeDivider(rowCount) rowCount = rowCount + 1
makeSectionLabel("pressure", rowCount) rowCount = rowCount + 1
wireRow("speed",        "PRESSURE_SPEED",  0,   2.0, 0.1,  function(v) return v end)
wireRow("afk after",    "AFK_TIMEOUT",     2,   30,  1,    function(v) return v.."s" end)

makeDivider(rowCount) rowCount = rowCount + 1
makeSectionLabel("options", rowCount) rowCount = rowCount + 1
makeToggleRow("humanize",   CFG.HUMANIZE,    function(v) CFG.HUMANIZE    = v end)
makeToggleRow("pressure",   CFG.PRESSURE_ON, function(v) CFG.PRESSURE_ON = v end)

makeDivider(rowCount) rowCount = rowCount + 1

-- ── Activate button ──
local activeSec = Instance.new("Frame", panel)
activeSec.LayoutOrder          = rowCount
rowCount                       = rowCount + 1
activeSec.Size                 = UDim2.new(1, 0, 0, 44)
activeSec.BackgroundTransparency = 1
activeSec.BorderSizePixel      = 0

local toggleBtn = Instance.new("TextButton", activeSec)
toggleBtn.Size             = UDim2.new(1, -28, 0, 28)
toggleBtn.Position         = UDim2.new(0, 14, 0.5, -14)
toggleBtn.BackgroundColor3 = C.surface2
toggleBtn.BorderSizePixel  = 0
toggleBtn.Text             = "activate"
toggleBtn.TextColor3       = C.muted
toggleBtn.Font             = Enum.Font.GothamBold
toggleBtn.TextSize         = 10
Instance.new("UICorner", toggleBtn).CornerRadius = UDim.new(0, 7)
local tStroke = Instance.new("UIStroke", toggleBtn)
tStroke.Color        = C.border
tStroke.Transparency = 0
tStroke.Thickness    = 1

-- ── Unload button ──
local unloadSec = Instance.new("Frame", panel)
unloadSec.LayoutOrder          = rowCount
unloadSec.Size                 = UDim2.new(1, 0, 0, 34)
unloadSec.BackgroundTransparency = 1
unloadSec.BorderSizePixel      = 0

local unloadBtn = Instance.new("TextButton", unloadSec)
unloadBtn.Size             = UDim2.new(1, -28, 0, 22)
unloadBtn.Position         = UDim2.new(0, 14, 0, 6)
unloadBtn.BackgroundColor3 = C.bg
unloadBtn.BorderSizePixel  = 0
unloadBtn.Text             = "unload script"
unloadBtn.TextColor3       = Color3.fromRGB(90, 50, 50)
unloadBtn.Font             = Enum.Font.Gotham
unloadBtn.TextSize         = 9
Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 6)
local uStroke = Instance.new("UIStroke", unloadBtn)
uStroke.Color        = Color3.fromRGB(70, 35, 35)
uStroke.Transparency = 0
uStroke.Thickness    = 1

-- ── Status logic ──

dotBtn.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

local function setStatus(text, color)
	badgeLbl.Text             = text
	badgeLbl.TextColor3       = color
	badgeStroke.Color         = color
	badgeStroke.Transparency  = 0.6
	dotFrame.BackgroundColor3 = color  -- dot mirrors status at a glance
end

local function setState(state)
	owning         = state
	smoothBallPos  = nil
	lastRawBallPos = nil
	ballVel        = Vector3.new()
	reactionTimer  = 0
	if not state then clearBallCache() end
	if state then
		setStatus("active", C.green)
		toggleBtn.Text             = "deactivate"
		toggleBtn.TextColor3       = C.green
		toggleBtn.BackgroundColor3 = C.greenDim
		tStroke.Color              = C.green
		tStroke.Transparency       = 0.6
	else
		setStatus("off", C.dim)
		toggleBtn.Text             = "activate"
		toggleBtn.TextColor3       = C.muted
		toggleBtn.BackgroundColor3 = C.surface2
		tStroke.Color              = C.border
		tStroke.Transparency       = 0
	end
end

-- ── Button wiring ──

toggleBtn.MouseButton1Click:Connect(function()  setState(not owning) end)
unloadBtn.MouseButton1Click:Connect(function()  unload() end)

-- ─── Main Loop ────────────────────────────────────────────────────────────────

heartbeatConn = RunService.Heartbeat:Connect(function()
	if not owning then return end
	local now = tick()
	if now - lastMoveTime < CFG.MOVE_HZ then return end
	lastMoveTime = now

	if isAFK() then setStatus("afk", C.amber); return end
	if hasBall() then setStatus("holding", Color3.fromRGB(200, 190, 60)); return end

	local char = LocalPlayer.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local myHRP    = char:FindFirstChild("HumanoidRootPart")
	if not humanoid or not myHRP then return end

	if not cachedBall or not cachedBall.Parent then findBall() end

	local ball = cachedBall
	if not ball or not ball.Parent then
		setStatus("scanning", C.dim)
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
			setStatus("active", C.green)
			return
		end
		reactionTimer = 0
	end

	setStatus("active", C.green)

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
