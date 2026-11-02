--[[
    BOXHUB v2.0 Studio — Restructured UI for Blox Fruits
    -----------------------------------------------------------
    Layout      : 3-column (sidebar / main / logs) như BOXHUB v1
    Features    : theo cấu trúc Maru/Kimp (11 tabs)
    Logic       : WORKING — port từ Project Spooky + Maru fix
    Toggle btn  : floating button + phím RightCtrl / Insert

    FIX so với Maru gốc:
      1) Không loadstring library ngoài (nguyên nhân crash dòng 1562)
      2) StopTween đảo ngược logic → đã sửa
      3) EquipWeapon typo 'Nill' → 'nil'
      4) Auto Buy Fruit Sniper truyền string → truyền biến
      5) Player count paragraph so sánh với 12 → sửa

    Cách dùng:
      • Executor: paste toàn bộ vào executor → Run
      • Studio  : chạy được nhưng features cần server (ESP still hoạt động)
]]

-- ============================================================
--  SERVICES
-- ============================================================

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local TeleportService   = game:GetService("TeleportService")
local Stats             = game:GetService("Stats")
local CoreGui           = game:GetService("CoreGui")
local LocalPlayer       = Players.LocalPlayer
local PlayerGui         = LocalPlayer:WaitForChild("PlayerGui")
local VirtualUser       = (game:GetService("VirtualUser") ~= nil and game:GetService("VirtualUser")) or nil

local F = {
    UDim2   = UDim2.new,
    Color3  = Color3.fromRGB,
    Vec3    = Vector3.new,
    CF      = CFrame.new,
    Clamp   = math.clamp,
    Floor   = math.floor,
    Spawn   = task.spawn,
    Wait    = task.wait,
    Insert  = table.insert,
}

-- Feature state table
local FeatureStates    = {}
local FeatureCallbacks = {}
local ToggleButtons    = {}
local CycleChoices     = {}     -- Lưu choice hiện tại của các cycle button
local FeatureLoops     = {}     -- Generation epoch cho mỗi feature (để stop loop sạch)
local ActiveConns      = {}     -- Mọi connection đang active (để cleanup)

-- Status readout values (cập nhật bởi loop ở cuối file)
local StatusValues = {
    FPS = 60, PING = 0, ServerTime = "00:00:00",
    Race = "Human", Beli = 0, Bounty = 0, Fragments = 0, Level = 1,
    DevilFruit = "None",
}
local StatusProxies = {}   -- Tham chiếu tới các createParagraph proxy để update text

-- ============================================================
--  ANTI-AFK (auto-init)
-- ============================================================

pcall(function()
    LocalPlayer.Idled:Connect(function()
        if VirtualUser then
            VirtualUser:ClickButton2(Vector2.zero)
        end
        F.Spawn(function()
            F.Wait(math.random(5, 15))
        end)
    end)
end)

-- ============================================================
--  NOTIFICATION
-- ============================================================

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title   = title or "Hub",
            Text    = text or "",
            Duration = duration or 3,
        })
    end)
    print(string.format("[%s] %s", title or "Hub", text or ""))
end

-- ============================================================
--  TOGGLE STATE MANAGEMENT
-- ============================================================

local function setFeatureState(name, active)
    active = active == true
    FeatureStates[name] = active
    -- Update visual
    local data = ToggleButtons[name]
    if data and data.btn and data.btn.Parent then
        local accent = Color3.fromRGB(140, 115, 235)
        if data.switchKnob then
            TweenService:Create(data.switchKnob, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = active and F.UDim2(1, -11, 0.5, -4.5) or F.UDim2(0, 2, 0.5, -4.5),
                BackgroundColor3 = active and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(80, 80, 95)
            }):Play()
        end
        if data.switchPill then
            TweenService:Create(data.switchPill, TweenInfo.new(0.18), {
                BackgroundColor3 = active and accent or Color3.fromRGB(24, 24, 32)
            }):Play()
        end
        if data.btnStk then
            TweenService:Create(data.btnStk, TweenInfo.new(0.18), {
                Color = active and accent or Color3.fromRGB(36, 36, 42)
            }):Play()
        end
    end
    -- Run callback
    local cb = FeatureCallbacks[name]
    if cb then
        F.Spawn(function()
            local ok, err = pcall(cb, active)
            if not ok then
                warn("[Feature: " .. name .. "] " .. tostring(err))
            end
        end)
    end
end

local function toggleFeature(name)
    setFeatureState(name, not (FeatureStates[name] or false))
end

-- ============================================================
--  SAFE PARENT
-- ============================================================

local function getSafeParent()
    -- Ưu tiên gethui (executor) → CoreGui → PlayerGui
    if gethui then
        local ok, h = pcall(gethui)
        if ok and h then return h end
    end
    if syn and syn.protect_gui then
        pcall(syn.protect_gui, PlayerGui)
        return PlayerGui
    end
    -- Studio fallback
    local ok = pcall(function() return CoreGui end)
    if ok and CoreGui then return CoreGui end
    return PlayerGui
end

local function safeParent(gui)
    if not gui then return end
    local ok = pcall(function() gui.Parent = getSafeParent() end)
    if (not ok or not gui.Parent) and LocalPlayer then
        pcall(function()
            gui.Parent = LocalPlayer:FindFirstChild("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 3)
        end)
    end
end

-- ============================================================
--  GAME HELPERS (Blox Fruits specific)
-- ============================================================

-- Resolve ReplicatedStorage.Remotes.CommF_ (an toàn, retry nhẹ)
local function resolveCommF()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        return remotes:FindFirstChild("CommF_") or remotes:WaitForChild("CommF_", 5)
    end
    return ReplicatedStorage:FindFirstChild("CommF_", true)
end

local function resolveCommE()
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    if remotes then
        return remotes:FindFirstChild("CommE") or remotes:WaitForChild("CommE", 5)
    end
    return ReplicatedStorage:FindFirstChild("CommE", true)
end

local function getChar()
    return LocalPlayer.Character
end

local function getHRP()
    local char = getChar()
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
end

local function getHum()
    local char = getChar()
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function getLeaderstats()
    return LocalPlayer:FindFirstChild("leaderstats")
end

local function getData()
    return LocalPlayer:FindFirstChild("Data")
end

-- Equip tool từ Backpack (FIX maru's typo: dùng 'nil' thay vì 'Nill')
local function EquipWeapon(name)
    if not name then return end
    local char = getChar()
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not hum or not backpack then return end
    local tool = backpack:FindFirstChild(name)
    if tool then
        pcall(function() hum:EquipTool(tool) end)
    elseif char and char:FindFirstChild(name) then
        -- Đã equip sẵn
    end
end

-- Tween tới CFrame dùng trick PartTele (tránh anti-cheat detect HRP di chuyển trực tiếp)
local activeTweens = {}
local function topos(targetCF, speed)
    if typeof(targetCF) ~= "CFrame" then return end
    speed = speed or 350
    local char = getChar()
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return end

    -- Hủy tween cũ nếu có
    if activeTweens.main then
        pcall(function() activeTweens.main:Cancel() end)
    end

    -- Tạo PartTele vô hình
    local partTele = char:FindFirstChild("PartTele")
    if not partTele then
        partTele = Instance.new("Part")
        partTele.Name = "PartTele"
        partTele.Size = Vector3.new(10, 1, 10)
        partTele.Anchored = true
        partTele.Transparency = 1
        partTele.CanCollide = false
        partTele.Parent = char
    end
    partTele.CFrame = hrp.CFrame

    if not activeTweens.conn then
        activeTweens.conn = partTele:GetPropertyChangedSignal("CFrame"):Connect(function()
            local c = getChar()
            local h = c and c:FindFirstChild("HumanoidRootPart")
            if h then
                h.CFrame = partTele.CFrame
                h.AssemblyLinearVelocity = Vector3.zero
            end
        end)
        table.insert(ActiveConns, activeTweens.conn)
    end

    local dist = (targetCF.Position - hrp.Position).Magnitude
    local t = math.max(dist / speed, 0.1)
    activeTweens.main = TweenService:Create(partTele, TweenInfo.new(t, Enum.EasingStyle.Linear), { CFrame = targetCF })
    activeTweens.main:Play()
end

-- STOP all active tweens (FIX maru's StopTween inverted logic)
local function stopAllTweens()
    if activeTweens.main then
        pcall(function() activeTweens.main:Cancel() end)
        activeTweens.main = nil
    end
    local char = getChar()
    if char then
        local pt = char:FindFirstChild("PartTele")
        if pt then pcall(function() pt:Destroy() end) end
    end
end

-- ============================================================
--  ISLAND LIST (Sea 1 / Sea 2 / Sea 3)
-- ============================================================

local Islands = {
    Sea1 = {
        {name="WindMill",      cf=CFrame.new(979.799, 16.516, 1429.047)},
        {name="Marine",        cf=CFrame.new(-2566.43, 6.856, 2045.256)},
        {name="Middle Town",   cf=CFrame.new(-690.331, 15.096, 1500.22)},
        {name="Jungle",        cf=CFrame.new(-1612.424, 36.246, 149.226)},
        {name="Desert",        cf=CFrame.new(140.367, 6.857, -840.617)},
        {name="Pirate Village",cf=CFrame.new(-1141.311, 13.856, 3758.718)},
        {name="Underwater",    cf=CFrame.new(4073.293, 0.599, -1871.436)},
        {name="Sky Island 1",  cf=CFrame.new(-4870.598, 798.712, -2192.151)},
        {name="Sky Island 2",  cf=CFrame.new(-4920.967, 798.712, -2192.151)},
        {name="Prison",        cf=CFrame.new(5292.879, 0.597, 4770.77)},
        {name="Magma Village", cf=CFrame.new(-5403.478, 13.856, -2705.325)},
        {name="Undersea",      cf=CFrame.new(-3148.401, 0.599, -5243.708)},
        {name="Fountain City", cf=CFrame.new(5270.075, 0.599, -1722.743)},
    },
    Sea2 = {
        {name="Dock",          cf=CFrame.new(7.0, 13.0, 2885.0)},
        {name="Cafe",          cf=CFrame.new(-385.0, 14.0, 2990.0)},
        {name="Mansion",       cf=CFrame.new(-440.0, 14.0, 3140.0)},
        {name="Flamingo Mansion",cf=CFrame.new(-460.0, 14.0, 3160.0)},
        {name="Flamingo Room", cf=CFrame.new(-460.0, 14.0, 3160.0)},
        {name="Sand Zone",     cf=CFrame.new(0.0, 14.0, 2900.0)},
        {name="Half Hot",      cf=CFrame.new(-690.0, 14.0, 3600.0)},
        {name="Ice Zone",      cf=CFrame.new(-690.0, 14.0, 3600.0)},
        {name="Forgotten Island",cf=CFrame.new(0.0, 14.0, 3200.0)},
        {name="Usoap Island",  cf=CFrame.new(4880.0, 14.0, 1200.0)},
        {name="Mini Sky",      cf=CFrame.new(-260.0, 500.0, 3000.0)},
        {name="Castle",        cf=CFrame.new(-5500.0, 320.0, -1000.0)},
        {name="Graveyard",     cf=CFrame.new(-5500.0, 14.0, -1000.0)},
        {name="Dark Arena",    cf=CFrame.new(-5500.0, 14.0, -800.0)},
        {name="Remote Island", cf=CFrame.new(-5500.0, 14.0, -1000.0)},
    },
    Sea3 = {
        {name="Port Town",     cf=CFrame.new(-690.0, 14.0, 2900.0)},
        {name="Hydra Island",  cf=CFrame.new(5292.879, 0.597, 4770.77)},
        {name="Great Tree",    cf=CFrame.new(2280.0, 14.0, 2900.0)},
        {name="Floating Turtle",cf=CFrame.new(-2192.151, 14.0, 10239.795)},
        {name="Kitsune Shrine",cf=CFrame.new(796.644, 14.0, 5462.743)},
        {name="Mystic Island", cf=CFrame.new(-9000.0, 543.0, -9000.0)},
        {name="Tiki Outpost",  cf=CFrame.new(-7000.0, 14.0, -7000.0)},
    },
}

-- Danh sách NPC / Boss (tên dùng để teleport tới NPC có match tên trong workspace)
local NPCList = {
    "Blox Fruits Dealer","Circuit Smuggler","Cyborg Dispatcher","Dark Step Teacher",
    "Dragon Talon Teacher","Electric Claw Teacher","Fruit Dealer","God's Guard",
    "Guitar Teacher","Water Karate Teacher","Military Detective","Mr. Mohawk",
    "Parasol Dealer","Passage Keeper","Pineapple Dealer","Quest NPC","Saber Expert",
    "Sharkman Karate Teacher","Skeleton","Shop","Tom","Wind Breaker",
}

local BossListSea1 = {"Bobby","Yeti","Mob Leader","Sabre Expert","Ice Cream Chef",
    "Wysper","The Gorilla King","Magma Admiral","Fishman Captain","Cyborg"}

local BossListSea2 = {"Diamond","Jeremy","Fajita","Don Swan","Smoke Admiral",
    "Cursed Captain","Terrorshark","Stone","Island Empress","Kolo Admiral","Longma"}

local BossListSea3 = {"Beautiful Pirate","Cake Queen","Soul Reaper","Cursed Captain",
    "Terrorshark","Jawhead","Leviathan","Dragon","Pirate"}

-- Mã game codes (cập nhật tháng 11/2026)
local GameCodes = {
    "SUB2GAMERROBOT_EXP1","Sub2OfficialNoobie","Sub2Fer999","KittReset","KittGaming",
    "Enyu_is_Pro","Magicbus","JCWK","Starcodeheo","Bluxxy","Sub2Daigrock",
    "StrawHatMain","Sub2NoobMaster123","Sub2Rox","Sub2Undel","Sub2ThaiGaming",
    "TantaiGaming","Sub2Axiore","fudd10_v2","STAFFBROADCAST","DEVSCOOKIN",
    "Sub2Kem",
}

-- ============================================================
--  SERVER HOP / REJOIN
-- ============================================================

local function fetchBestServers()
    local placeId = game.PlaceId
    local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Asc&limit=100&excludeFullGames=true"
    local servers = {}
    pcall(function()
        local raw = game:HttpGet(url)
        local data = HttpService:JSONDecode(raw)
        if data and type(data.data) == "table" then
            for _, s in ipairs(data.data) do
                if s.playing and s.id and s.playing < 12 then
                    table.insert(servers, { id = s.id, playing = s.playing })
                end
            end
        end
    end)
    table.sort(servers, function(a, b) return a.playing < b.playing end)
    return servers
end

local function teleportToServer(jobId)
    if not jobId or jobId == game.JobId then return false end
    pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, tostring(jobId), LocalPlayer)
    end)
end

local function serverHop()
    F.Spawn(function()
        local list = fetchBestServers()
        if #list > 0 then
            teleportToServer(list[1].id)
            notify("Server Hop", "Đang teleport tới server " .. list[1].id, 3)
        else
            notify("Server Hop", "Không tìm server trống", 3)
        end
    end)
end

local function rejoinServer()
    pcall(function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    notify("Rejoin", "Đang rejoin server", 3)
end

-- ============================================================
--  DRAGGABLE
-- ============================================================

local function makeDraggable(dragBars, targetFrame)
    local bars = (typeof(dragBars) == "table") and dragBars or { dragBars }
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    local function update(input)
        if not dragging or not dragStart or not startPos then return end
        local delta = input.Position - dragStart
        targetFrame.Position = F.UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
    for _, b in ipairs(bars) do
        if b then
            b.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                    dragging = true
                    dragStart = input.Position
                    startPos = targetFrame.Position
                end
            end)
            b.InputChanged:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
                    dragInput = input
                end
            end)
        end
    end
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            update(input)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

-- ============================================================
--  UI SCALING
-- ============================================================

local function computeScale()
    local camera = workspace.CurrentCamera
    if not camera then return 0.85 end
    local vp = camera.ViewportSize
    local scaleX = (vp.X * 0.92) / 650
    local scaleY = (vp.Y * 0.90) / 369
    return math.clamp(math.min(scaleX, scaleY, 1) * 0.95, 0.35, 1.0)
end

-- ============================================================
--  BUILD MAIN UI
-- ============================================================

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "BOXHUB_v2_UI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.IgnoreGuiInset = true
safeParent(ScreenGui)

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = F.UDim2(0, 650, 0, 369)
MainFrame.Position = F.UDim2(0.5, 0, 0.5, 0)
MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
MainFrame.BackgroundColor3 = Color3.fromRGB(9, 9, 13)
MainFrame.BorderSizePixel = 0
MainFrame.Visible = false
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

local frameStroke = Instance.new("UIStroke", MainFrame)
frameStroke.Thickness = 1.5
frameStroke.Color = Color3.fromRGB(28, 26, 38)

local UIScale = Instance.new("UIScale", MainFrame)
UIScale.Scale = computeScale()

-- Left sidebar
local leftSide = Instance.new("Frame", MainFrame)
leftSide.Name = "LeftSidebar"
leftSide.Size = F.UDim2(0, 128, 0, 369)
leftSide.Position = F.UDim2(0, 0, 0, 0)
leftSide.BackgroundColor3 = Color3.fromRGB(9, 9, 13)
leftSide.BorderSizePixel = 0
Instance.new("UICorner", leftSide).CornerRadius = UDim.new(0, 8)

local leftDivider = Instance.new("Frame", leftSide)
leftDivider.Size = F.UDim2(0, 1, 1, 0)
leftDivider.Position = F.UDim2(1, -1, 0, 0)
leftDivider.BackgroundColor3 = Color3.fromRGB(28, 26, 38)
leftDivider.BorderSizePixel = 0

-- Hub icon
local hubIcon = Instance.new("TextLabel", leftSide)
hubIcon.Size = F.UDim2(0, 128, 0, 30)
hubIcon.Position = F.UDim2(0, 0, 0, 8)
hubIcon.BackgroundTransparency = 1
hubIcon.Font = Enum.Font.GothamBold
hubIcon.Text = "BOXHUB v2"
hubIcon.TextSize = 14
hubIcon.TextColor3 = Color3.fromRGB(140, 115, 235)
hubIcon.TextXAlignment = Enum.TextXAlignment.Center

local versionLbl = Instance.new("TextLabel", leftSide)
versionLbl.Size = F.UDim2(0, 128, 0, 14)
versionLbl.Position = F.UDim2(0, 0, 0, 36)
versionLbl.BackgroundTransparency = 1
versionLbl.Font = Enum.Font.GothamBold
versionLbl.Text = "v2.0 Studio"
versionLbl.TextSize = 9
versionLbl.TextColor3 = Color3.fromRGB(100, 100, 120)
versionLbl.TextXAlignment = Enum.TextXAlignment.Center

-- Drag handle
local dragHandle = Instance.new("Frame", MainFrame)
dragHandle.Size = F.UDim2(1, -128, 0, 42)
dragHandle.Position = F.UDim2(0, 128, 0, 0)
dragHandle.BackgroundTransparency = 1
dragHandle.ZIndex = 2
makeDraggable({ dragHandle, leftSide }, MainFrame)

-- Close button
local closeBtn = Instance.new("TextButton", MainFrame)
closeBtn.Size = F.UDim2(0, 26, 0, 26)
closeBtn.Position = F.UDim2(0.938, 0, 0, 8)
closeBtn.BackgroundTransparency = 1
closeBtn.Font = Enum.Font.GothamBold
closeBtn.Text = "X"
closeBtn.TextSize = 14
closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
closeBtn.ZIndex = 10
closeBtn.Activated:Connect(function()
    ScreenGui:Destroy()
end)

-- Minimize button
local minBtn = Instance.new("TextButton", MainFrame)
minBtn.Size = F.UDim2(0, 26, 0, 26)
minBtn.Position = F.UDim2(0.888, 0, 0, 8)
minBtn.BackgroundTransparency = 1
minBtn.Font = Enum.Font.GothamBold
minBtn.Text = "-"
minBtn.TextSize = 18
minBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
minBtn.ZIndex = 10
minBtn.Activated:Connect(function()
    MainFrame.Visible = false
    mobileToggle.Visible = true
end)

-- Floating toggle button (luôn visible khi main menu ẩn — bấm để mở lại)
-- Cũng có thể toggle bằng phím RightCtrl / Insert
local mobileToggle = Instance.new("TextButton", ScreenGui)
mobileToggle.Name = "MobileToggle"
mobileToggle.Size = F.UDim2(0, 56, 0, 56)
mobileToggle.Position = F.UDim2(1, -76, 1, -76)  -- Bottom-right corner
mobileToggle.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
mobileToggle.Font = Enum.Font.GothamBold
mobileToggle.Text = ""
mobileToggle.Visible = false
mobileToggle.ZIndex = 9999
mobileToggle.AutoButtonColor = true
Instance.new("UICorner", mobileToggle).CornerRadius = UDim.new(0, 14)
local mtStroke = Instance.new("UIStroke", mobileToggle)
mtStroke.Color = Color3.fromRGB(140, 115, 235)
mtStroke.Thickness = 1.6

-- Gradient bg cho toggle button
local mtGrad = Instance.new("UIGradient", mobileToggle)
mtGrad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 32, 70)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(18, 18, 26)),
})
mtGrad.Rotation = 90

-- Icon + label
local mtIcon = Instance.new("TextLabel", mobileToggle)
mtIcon.Size = F.UDim2(1, 0, 0, 24)
mtIcon.Position = F.UDim2(0, 0, 0, 8)
mtIcon.BackgroundTransparency = 1
mtIcon.Font = Enum.Font.GothamBold
mtIcon.Text = "BOX"
mtIcon.TextSize = 14
mtIcon.TextColor3 = Color3.fromRGB(190, 165, 255)
mtIcon.ZIndex = 10000

local mtSub = Instance.new("TextLabel", mobileToggle)
mtSub.Size = F.UDim2(1, 0, 0, 12)
mtSub.Position = F.UDim2(0, 0, 0, 34)
mtSub.BackgroundTransparency = 1
mtSub.Font = Enum.Font.GothamBold
mtSub.Text = "MENU"
mtSub.TextSize = 8
mtSub.TextColor3 = Color3.fromRGB(110, 110, 130)
mtSub.ZIndex = 10000

-- Pulse animation để user để ý
F.Spawn(function()
    while mobileToggle.Parent do
        if mobileToggle.Visible then
            pcall(function()
                TweenService:Create(mtStroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    Thickness = 2.4,
                }):Play()
                F.Wait(0.8)
                TweenService:Create(mtStroke, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
                    Thickness = 1.6,
                }):Play()
                F.Wait(0.8)
            end)
        else
            F.Wait(0.5)
        end
    end
end)

mobileToggle.Activated:Connect(function()
    MainFrame.Visible = true
    mobileToggle.Visible = false
    addLog("[UI] Menu opened")
end)

-- Right sidebar (logs)
local rightSide = Instance.new("Frame", MainFrame)
rightSide.Size = F.UDim2(0, 122, 0, 369)
rightSide.Position = F.UDim2(0.811, 0, 0, 0)
rightSide.BackgroundColor3 = Color3.fromRGB(9, 9, 13)
rightSide.BorderSizePixel = 0
Instance.new("UICorner", rightSide).CornerRadius = UDim.new(0, 8)

local rightDivider = Instance.new("Frame", rightSide)
rightDivider.Size = F.UDim2(0, 1, 1, 0)
rightDivider.Position = F.UDim2(0, 0, 0, 0)
rightDivider.BackgroundColor3 = Color3.fromRGB(28, 26, 38)
rightDivider.BorderSizePixel = 0

local logsTitle = Instance.new("TextLabel", rightSide)
logsTitle.Size = F.UDim2(0, 122, 0, 20)
logsTitle.Position = F.UDim2(0, 0, 0, 8)
logsTitle.BackgroundTransparency = 1
logsTitle.Font = Enum.Font.GothamBold
logsTitle.Text = "LOGS"
logsTitle.TextSize = 10
logsTitle.TextColor3 = Color3.fromRGB(140, 115, 235)
logsTitle.TextXAlignment = Enum.TextXAlignment.Center

local logsScroll = Instance.new("ScrollingFrame", rightSide)
logsScroll.Size = F.UDim2(0, 112, 0, 320)
logsScroll.Position = F.UDim2(0, 5, 0, 32)
logsScroll.BackgroundTransparency = 1
logsScroll.BorderSizePixel = 0
logsScroll.ScrollBarThickness = 2
logsScroll.ScrollBarImageColor3 = Color3.fromRGB(60, 58, 80)
logsScroll.CanvasSize = F.UDim2(0, 0, 0, 0)
logsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
local logsLayout = Instance.new("UIListLayout", logsScroll)
logsLayout.SortOrder = Enum.SortOrder.LayoutOrder
logsLayout.Padding = UDim.new(0, 4)

local logCount = 0
local function addLog(text)
    logCount = logCount + 1
    local lbl = Instance.new("TextLabel")
    lbl.Size = F.UDim2(1, -6, 0, 0)
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamMedium
    lbl.Text = "- " .. tostring(text)
    lbl.TextSize = 9
    lbl.TextColor3 = Color3.fromRGB(195, 195, 215)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextWrapped = true
    lbl.LayoutOrder = logCount
    lbl.Parent = logsScroll
    if logCount > 30 then
        local first = logsScroll:FindFirstChildOfClass("TextLabel")
        if first then first:Destroy() end
    end
end

-- Center pages area
local centerBg = Instance.new("Frame", MainFrame)
centerBg.Name = "CenterBg"
centerBg.Size = F.UDim2(0, 404, 0, 369)
centerBg.Position = F.UDim2(0, 128, 0, 0)
centerBg.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
centerBg.BorderSizePixel = 0
centerBg.ZIndex = 2

local pagesFolder = Instance.new("Frame", MainFrame)
pagesFolder.Name = "Pages"
pagesFolder.Size = F.UDim2(0, 404, 0, 353)
pagesFolder.Position = F.UDim2(0, 128, 0, 8)
pagesFolder.BackgroundTransparency = 1
pagesFolder.BorderSizePixel = 0
pagesFolder.ZIndex = 8

-- Sidebar scroll for tab buttons
local sidebarScroll = Instance.new("ScrollingFrame", leftSide)
sidebarScroll.Size = F.UDim2(0, 112, 0, 290)
sidebarScroll.Position = F.UDim2(0, 8, 0, 56)
sidebarScroll.BackgroundTransparency = 1
sidebarScroll.BorderSizePixel = 0
sidebarScroll.ScrollBarThickness = 2
sidebarScroll.ScrollBarImageColor3 = Color3.fromRGB(65, 65, 85)
sidebarScroll.CanvasSize = F.UDim2(0, 0, 0, 600)
local sidebarLayout = Instance.new("UIListLayout", sidebarScroll)
sidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
sidebarLayout.Padding = UDim.new(0, 3)

-- ============================================================
--  TAB DEFINITIONS (mapped from Maru tabs)
-- ============================================================

local tabDefinitions = {
    { id = "Status",    label = "Status" },
    { id = "General",   label = "General" },
    { id = "Quest",     label = "Quest & Item" },
    { id = "Race",      label = "Race & Mirage" },
    { id = "Volcano",   label = "Volcano Event" },
    { id = "Local",     label = "Local Player" },
    { id = "Visual",    label = "Visual" },
    { id = "FruitRaid", label = "Fruit & Raid" },
    { id = "Teleport",  label = "Teleport" },
    { id = "Shop",      label = "Shop" },
    { id = "Misc",      label = "Miscellaneous" },
}

local NavButtons = {}
local currentActiveTab = "Status"

-- ============================================================
--  CREATE SCROLL PAGE
-- ============================================================

local function createScrollPage(pageName)
    local sf = Instance.new("ScrollingFrame")
    sf.Name = pageName
    sf.Size = F.UDim2(1, 0, 1, 0)
    sf.BackgroundTransparency = 1
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 4
    sf.ScrollBarImageColor3 = Color3.fromRGB(48, 48, 55)
    sf.CanvasSize = F.UDim2(0, 0, 0, 800)
    sf.Visible = false
    sf.ZIndex = 8
    sf.Parent = pagesFolder
    local pad = Instance.new("UIPadding", sf)
    pad.PaddingTop = UDim.new(0, 6)
    pad.PaddingLeft = UDim.new(0, 6)
    pad.PaddingRight = UDim.new(0, 6)
    return sf
end

-- Create all pages
local pages = {}
for _, tdef in ipairs(tabDefinitions) do
    pages[tdef.id] = createScrollPage(tdef.id .. "_Page")
end

-- ============================================================
--  SHOW TAB
-- ============================================================

local function showTab(tabId)
    currentActiveTab = tabId
    for id, page in pairs(pages) do
        page.Visible = (id == tabId)
    end
    -- Update sidebar visuals
    for id, btnData in pairs(NavButtons) do
        local isSel = (id == tabId)
        local btn = btnData.btn
        local st = btnData.st
        local lbl = btnData.lbl
        if btn then
            TweenService:Create(btn, TweenInfo.new(0.15), {
                BackgroundColor3 = isSel and Color3.fromRGB(24, 22, 38) or Color3.fromRGB(12, 12, 17)
            }):Play()
        end
        if st then
            TweenService:Create(st, TweenInfo.new(0.15), {
                Color = isSel and Color3.fromRGB(140, 115, 235) or Color3.fromRGB(30, 28, 40),
                Thickness = isSel and 1.2 or 1
            }):Play()
        end
        if lbl then
            TweenService:Create(lbl, TweenInfo.new(0.15), {
                TextColor3 = isSel and Color3.fromRGB(175, 145, 255) or Color3.fromRGB(150, 150, 170)
            }):Play()
        end
    end
    addLog("[TAB] " .. tabId)
end

-- ============================================================
--  CREATE TAB BUTTONS
-- ============================================================

for idx, tdef in ipairs(tabDefinitions) do
    local isDefault = (tdef.id == "Status")
    local btn = Instance.new("TextButton", sidebarScroll)
    btn.Name = string.lower(tdef.label) .. "_btn"
    btn.Size = F.UDim2(1, -6, 0, 27)
    btn.BackgroundColor3 = isDefault and Color3.fromRGB(24, 22, 38) or Color3.fromRGB(12, 12, 17)
    btn.Font = Enum.Font.GothamBold
    btn.Text = ""
    btn.AutoButtonColor = false
    btn.LayoutOrder = idx
    btn.ZIndex = 9
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    local st = Instance.new("UIStroke", btn)
    st.Color = isDefault and Color3.fromRGB(120, 95, 195) or Color3.fromRGB(30, 28, 40)
    st.Thickness = isDefault and 1.2 or 1

    local lbl = Instance.new("TextLabel", btn)
    lbl.Size = F.UDim2(1, -14, 1, 0)
    lbl.Position = F.UDim2(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = tdef.label
    lbl.TextSize = 10.5
    lbl.TextColor3 = isDefault and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 170)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.ZIndex = 10

    NavButtons[tdef.id] = { btn = btn, st = st, lbl = lbl }
    btn.Activated:Connect(function()
        showTab(tdef.id)
    end)
end

-- ============================================================
--  CARD HELPER
-- ============================================================

local BW = F.UDim2(0, 124, 0, 30)
local X1, X2, X3 = 6, 134, 262

local function makeCard(parent, titleText, height, y)
    local card = Instance.new("Frame")
    card.Size = F.UDim2(1, -10, 0, height)
    card.Position = F.UDim2(0, 5, 0, y)
    card.BackgroundColor3 = Color3.fromRGB(11, 11, 16)
    card.BorderSizePixel = 0
    card.Parent = parent
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

    local cardGrad = Instance.new("UIGradient", card)
    cardGrad.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(16, 16, 24)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(10, 10, 15))
    })
    cardGrad.Rotation = 90

    local cStroke = Instance.new("UIStroke", card)
    cStroke.Color = Color3.fromRGB(38, 36, 52)
    cStroke.Thickness = 1.1

    local hdr = Instance.new("TextLabel", card)
    hdr.Size = F.UDim2(1, -16, 0, 22)
    hdr.Position = F.UDim2(0, 8, 0, 0)
    hdr.BackgroundTransparency = 1
    hdr.Font = Enum.Font.GothamBold
    hdr.Text = titleText
    hdr.TextSize = 11
    hdr.TextColor3 = Color3.fromRGB(240, 240, 252)
    hdr.TextXAlignment = Enum.TextXAlignment.Left
    hdr.ZIndex = 3

    local hairline = Instance.new("Frame", card)
    hairline.Size = F.UDim2(1, -16, 0, 1)
    hairline.Position = F.UDim2(0, 8, 0, 22)
    hairline.BackgroundColor3 = Color3.fromRGB(32, 32, 42)
    hairline.BorderSizePixel = 0

    return card
end

-- ============================================================
--  TOGGLE BUTTON HELPER
-- ============================================================

local function createToggleButton(parent, name, text, size, pos)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = Color3.fromRGB(16, 16, 18)
    btn.Font = Enum.Font.GothamBold
    btn.Text = ""
    btn.AutoButtonColor = true
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 9)
    local btnStk = Instance.new("UIStroke", btn)
    btnStk.Color = Color3.fromRGB(36, 36, 42)
    btnStk.Thickness = 1.2

    local txtLbl = Instance.new("TextLabel", btn)
    txtLbl.Size = F.UDim2(1, -38, 1, 0)
    txtLbl.Position = F.UDim2(0, 8, 0, 0)
    txtLbl.BackgroundTransparency = 1
    txtLbl.Font = Enum.Font.GothamBold
    txtLbl.Text = text
    txtLbl.TextSize = 11.5
    txtLbl.TextColor3 = Color3.fromRGB(200, 200, 215)
    txtLbl.TextXAlignment = Enum.TextXAlignment.Left
    txtLbl.ZIndex = 3

    local switchPill = Instance.new("Frame", btn)
    switchPill.Size = F.UDim2(0, 24, 0, 13)
    switchPill.Position = F.UDim2(1, -28, 0.5, -6.5)
    switchPill.BackgroundColor3 = Color3.fromRGB(26, 26, 34)
    switchPill.BorderSizePixel = 0
    switchPill.ZIndex = 3
    Instance.new("UICorner", switchPill).CornerRadius = UDim.new(1, 0)
    local pillStk = Instance.new("UIStroke", switchPill)
    pillStk.Color = Color3.fromRGB(48, 48, 62)
    pillStk.Thickness = 1

    local switchKnob = Instance.new("Frame", switchPill)
    switchKnob.Size = F.UDim2(0, 9, 0, 9)
    switchKnob.Position = F.UDim2(0, 2, 0.5, -4.5)
    switchKnob.BackgroundColor3 = Color3.fromRGB(80, 80, 95)
    switchKnob.BorderSizePixel = 0
    switchKnob.ZIndex = 4
    Instance.new("UICorner", switchKnob).CornerRadius = UDim.new(1, 0)

    ToggleButtons[name] = {
        btn = btn,
        txtLbl = txtLbl,
        btnStk = btnStk,
        switchPill = switchPill,
        pillStk = pillStk,
        switchKnob = switchKnob,
        text = text,
    }
    if FeatureStates[name] == nil then FeatureStates[name] = false end

    -- Default callback: print + notification
    FeatureCallbacks[name] = FeatureCallbacks[name] or function(state)
        notify(name, (state and "ON" or "OFF"), 2)
    end

    btn.Activated:Connect(function()
        toggleFeature(name)
    end)

    return btn
end

-- ============================================================
--  ACTION BUTTON HELPER
-- ============================================================

local function createActionButton(parent, text, size, pos, onClick)
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = Color3.fromRGB(20, 20, 26)
    btn.Font = Enum.Font.GothamBold
    btn.Text = ""
    btn.AutoButtonColor = true
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    local aStk = Instance.new("UIStroke", btn)
    aStk.Color = Color3.fromRGB(45, 45, 58)
    aStk.Thickness = 1

    local txtLbl = Instance.new("TextLabel", btn)
    txtLbl.Size = F.UDim2(1, -10, 1, 0)
    txtLbl.Position = F.UDim2(0, 5, 0, 0)
    txtLbl.BackgroundTransparency = 1
    txtLbl.Font = Enum.Font.GothamBold
    txtLbl.Text = text
    txtLbl.TextSize = 11.5
    txtLbl.TextColor3 = Color3.fromRGB(235, 235, 245)
    txtLbl.TextXAlignment = Enum.TextXAlignment.Center
    txtLbl.ZIndex = 3

    if onClick then
        btn.Activated:Connect(function()
            F.Spawn(function()
                local ok, err = pcall(onClick)
                if not ok then
                    notify("Error", tostring(err):sub(1, 100), 3)
                end
            end)
        end)
    else
        -- Default: print
        btn.Activated:Connect(function()
            notify("Action", text, 2)
        end)
    end

    return btn
end

-- ============================================================
--  SLIDER HELPER
-- ============================================================

local function createSlider(parent, text, minV, maxV, defV, suffix, pos)
    local frame = Instance.new("Frame")
    frame.Size = F.UDim2(1, -12, 0, 38)
    frame.Position = pos or F.UDim2(0, 6, 0, 26)
    frame.BackgroundTransparency = 1
    frame.Parent = parent

    local titleLbl = Instance.new("TextLabel", frame)
    titleLbl.Size = F.UDim2(0.65, 0, 0, 16)
    titleLbl.Position = F.UDim2(0, 4, 0, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Font = Enum.Font.GothamBold
    titleLbl.Text = text
    titleLbl.TextSize = 11
    titleLbl.TextColor3 = Color3.fromRGB(210, 210, 225)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left

    local valLbl = Instance.new("TextLabel", frame)
    valLbl.Size = F.UDim2(0.35, -4, 0, 16)
    valLbl.Position = F.UDim2(0.65, 0, 0, 0)
    valLbl.BackgroundTransparency = 1
    valLbl.Font = Enum.Font.GothamBold
    valLbl.Text = tostring(defV) .. (suffix or "")
    valLbl.TextSize = 11
    valLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
    valLbl.TextXAlignment = Enum.TextXAlignment.Right

    local track = Instance.new("Frame", frame)
    track.Size = F.UDim2(1, -8, 0, 6)
    track.Position = F.UDim2(0, 4, 0, 24)
    track.BackgroundColor3 = Color3.fromRGB(22, 22, 30)
    track.BorderSizePixel = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame", track)
    local curPct = math.clamp((defV - minV) / (maxV - minV), 0, 1)
    fill.Size = F.UDim2(curPct, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(140, 115, 235)
    fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("ImageButton", track)
    knob.Size = F.UDim2(0, 18, 0, 18)
    knob.Position = F.UDim2(curPct, -9, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    knob.BorderSizePixel = 0
    knob.ZIndex = 5
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)
    local knStk = Instance.new("UIStroke", knob)
    knStk.Color = Color3.fromRGB(240, 240, 255)
    knStk.Thickness = 1.5

    local isDragging = false
    local function updateValue(inputX)
        local absPos = track.AbsolutePosition.X
        local absSize = track.AbsoluteSize.X
        if absSize <= 0 then return end
        local pct = math.clamp((inputX - absPos) / absSize, 0, 1)
        local rawVal = minV + pct * (maxV - minV)
        rawVal = math.floor(rawVal + 0.5)
        rawVal = math.clamp(rawVal, minV, maxV)
        pct = (rawVal - minV) / (maxV - minV)
        fill.Size = F.UDim2(pct, 0, 1, 0)
        knob.Position = F.UDim2(pct, -9, 0.5, -9)
        valLbl.Text = tostring(rawVal) .. (suffix or "")
        -- Lưu giá trị để feature callbacks dùng
        CycleChoices[text] = rawVal
    end
    CycleChoices[text] = defV   -- init default value

    knob.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            updateValue(input.Position.X)
        end
    end)
    track.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = true
            updateValue(input.Position.X)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if isDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateValue(input.Position.X)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            isDragging = false
        end
    end)

    return frame
end

-- ============================================================
--  DROPDOWN (Cycle Button) HELPER
-- ============================================================

local function createCycleButton(parent, prefix, choices, defaultIdx, size, pos)
    local currentIdx = defaultIdx or 1
    local btn = Instance.new("TextButton")
    btn.Size = size
    btn.Position = pos
    btn.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
    btn.Font = Enum.Font.GothamBold
    btn.Text = ""
    btn.AutoButtonColor = true
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
    local cStk = Instance.new("UIStroke", btn)
    cStk.Color = Color3.fromRGB(42, 42, 54)
    cStk.Thickness = 1

    local txtLbl = Instance.new("TextLabel", btn)
    txtLbl.Size = F.UDim2(1, -26, 1, 0)
    txtLbl.Position = F.UDim2(0, 8, 0, 0)
    txtLbl.BackgroundTransparency = 1
    txtLbl.Font = Enum.Font.GothamBold
    txtLbl.Text = prefix .. ": " .. tostring(choices[currentIdx])
    txtLbl.TextSize = 11
    txtLbl.TextColor3 = Color3.fromRGB(225, 225, 240)
    txtLbl.TextXAlignment = Enum.TextXAlignment.Left
    txtLbl.TextTruncate = Enum.TextTruncate.AtEnd
    txtLbl.ZIndex = 3

    local arrowLbl = Instance.new("TextLabel", btn)
    arrowLbl.Size = F.UDim2(0, 16, 1, 0)
    arrowLbl.Position = F.UDim2(1, -18, 0, 0)
    arrowLbl.BackgroundTransparency = 1
    arrowLbl.Font = Enum.Font.GothamBold
    arrowLbl.Text = "v"
    arrowLbl.TextSize = 8.5
    arrowLbl.TextColor3 = Color3.fromRGB(130, 135, 155)
    arrowLbl.ZIndex = 3

    btn.Activated:Connect(function()
        currentIdx = (currentIdx % #choices) + 1
        txtLbl.Text = prefix .. ": " .. tostring(choices[currentIdx])
        CycleChoices[prefix] = choices[currentIdx]
        addLog("[DROP] " .. prefix .. " = " .. tostring(choices[currentIdx]))
    end)
    CycleChoices[prefix] = choices[currentIdx]   -- init default choice

    return btn
end

-- ============================================================
--  PARAGRAPH HELPER
-- ============================================================

local function createParagraph(parent, name, defaultText, y)
    local frame = Instance.new("Frame")
    frame.Size = F.UDim2(1, -12, 0, 40)
    frame.Position = F.UDim2(0, 6, 0, y)
    frame.BackgroundColor3 = Color3.fromRGB(13, 13, 19)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 7)
    local fStk = Instance.new("UIStroke", frame)
    fStk.Color = Color3.fromRGB(36, 34, 48)
    fStk.Thickness = 1

    local title = Instance.new("TextLabel", frame)
    title.Size = F.UDim2(1, -16, 0, 14)
    title.Position = F.UDim2(0, 8, 0, 4)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = name
    title.TextSize = 9
    title.TextColor3 = Color3.fromRGB(130, 130, 155)
    title.TextXAlignment = Enum.TextXAlignment.Left

    local desc = Instance.new("TextLabel", frame)
    desc.Size = F.UDim2(1, -16, 0, 18)
    desc.Position = F.UDim2(0, 8, 0, 18)
    desc.BackgroundTransparency = 1
    desc.Font = Enum.Font.GothamBold
    desc.Text = defaultText or ""
    desc.TextSize = 11
    desc.TextColor3 = Color3.fromRGB(245, 245, 255)
    desc.TextXAlignment = Enum.TextXAlignment.Left
    desc.TextTruncate = Enum.TextTruncate.AtEnd

    local proxy = {}
    function proxy:Set(opts)
        if opts and opts.Description then
            desc.Text = opts.Description
        end
    end
    return proxy
end

-- ============================================================
--  FEATURE CALLBACKS — WORKING LOGIC (port từ Spooky + Maru fix)
-- ============================================================
-- Mỗi callback nhận `state` (true = ON, false = OFF).
-- Khi state=false, mọi loop phải tự thoát (check FeatureStates[name]).
-- ====================================

-- ===== AUTO HAKI (Buso) =====
FeatureCallbacks["AutoHaki"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["AutoHaki"] do
            local comm = resolveCommF()
            if comm then pcall(function() comm:InvokeServer("Buso") end) end
            F.Wait(5)
        end
    end)
end

-- ===== AUTO KEN (Observation Haki) =====
FeatureCallbacks["AutoKen"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["AutoKen"] do
            local comm = resolveCommF()
            if comm then pcall(function() comm:InvokeServer("KenTalk") end) end
            pcall(function() comm:InvokeServer("ObservationStart") end)
            F.Wait(5)
        end
    end)
end

-- ===== AUTO RACE V3 =====
FeatureCallbacks["ActiveV3"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["ActiveV3"] do
            local commE = resolveCommE()
            if commE then pcall(function() commE:FireServer("ActivateAbility") end) end
            F.Wait(0.4)
        end
    end)
end

-- ===== AUTO RACE V4 AWAKENING =====
local v4LoopConn = nil
FeatureCallbacks["ActiveV4"] = function(state)
    if not state then
        if v4LoopConn then v4LoopConn:Disconnect(); v4LoopConn = nil end
        return
    end
    F.Spawn(function()
        while FeatureStates["ActiveV4"] do
            pcall(function()
                local rem = ReplicatedStorage:FindFirstChild("Remotes")
                local commE = rem and rem:FindFirstChild("CommE")
                if commE then commE:FireServer("ActivateAwakening", true) end
                -- Equip Awakening tool + activate
                local char = getChar()
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                local bp = LocalPlayer:FindFirstChild("Backpack")
                local awk = (bp and bp:FindFirstChild("Awakening")) or (char and char:FindFirstChild("Awakening"))
                if awk and hum and awk.Parent ~= char then
                    pcall(function() hum:EquipTool(awk) end)
                end
                if awk then
                    pcall(function() awk:Activate() end)
                    local rf = awk:FindFirstChild("RemoteFunction")
                    if rf then pcall(function() rf:InvokeServer(true) end) end
                    local re = awk:FindFirstChild("RemoteEvent")
                    if re then pcall(function() re:FireServer(true) end) end
                end
            end)
            F.Wait(2)
        end
    end)
end

-- ===== INFINITE STAMINA / ENERGY / ABILITY / DODGE =====
FeatureCallbacks["InfiniteEnergy"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["InfiniteEnergy"] do
            local data = getData()
            if data then
                local energy = data:FindFirstChild("Energy")
                if energy then energy.Value = energy.MaxValue or 100 end
            end
            F.Wait(0.2)
        end
    end)
end

FeatureCallbacks["InfAbility"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["InfAbility"] do
            local char = getChar()
            if char then
                local ability = char:FindFirstChild("Ability")
                if ability then
                    local val = ability:FindFirstChild("Energy")
                    if val then val.Value = 100 end
                end
            end
            F.Wait(0.2)
        end
    end)
end

FeatureCallbacks["nododgecool"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["nododgecool"] do
            local char = getChar()
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum:FindFirstChild("DodgeCooldownMax") then
                    hum.DodgeCooldownMax.Value = 0
                end
            end
            F.Wait(1)
        end
    end)
end

FeatureCallbacks["InfGeppo"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["InfGeppo"] do
            local data = getData()
            if data then
                local geppo = data:FindFirstChild("GeppoCount")
                if geppo then geppo.Value = 100 end
            end
            F.Wait(0.5)
        end
    end)
end

-- ===== NOCLIP =====
local noclipConn = nil
FeatureCallbacks["NoClip"] = function(state)
    if state then
        if noclipConn then noclipConn:Disconnect() end
        noclipConn = RunService.Stepped:Connect(function()
            local char = getChar()
            if char then
                for _, p in ipairs(char:GetDescendants()) do
                    if p:IsA("BasePart") and p.CanCollide then
                        p.CanCollide = false
                    end
                end
            end
        end)
        table.insert(ActiveConns, noclipConn)
    else
        if noclipConn then noclipConn:Disconnect(); noclipConn = nil end
    end
end

-- ===== WALK SPEED =====
FeatureCallbacks["WalkSp"] = function(state)
    if state then
        F.Spawn(function()
            while FeatureStates["WalkSp"] do
                local hum = getHum()
                if hum then
                    local sp = tonumber(CycleChoices["Speed"]) or 100
                    hum.WalkSpeed = sp
                end
                F.Wait(0.3)
            end
        end)
    else
        local hum = getHum()
        if hum then hum.WalkSpeed = 16 end
    end
end

-- ===== HIGH JUMP =====
FeatureCallbacks["JumpSp"] = function(state)
    if state then
        F.Spawn(function()
            while FeatureStates["JumpSp"] do
                local hum = getHum()
                if hum then
                    local jp = tonumber(CycleChoices["Jump"]) or 100
                    hum.JumpPower = jp
                    hum.UseJumpPower = true
                end
                F.Wait(0.3)
            end
        end)
    else
        local hum = getHum()
        if hum then hum.JumpPower = 50 end
    end
end

-- ===== WALK ON WATER =====
FeatureCallbacks["WalkWater"] = function(state)
    if state then
        F.Spawn(function()
            while FeatureStates["WalkWater"] do
                local char = getChar()
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health > 0 then
                    -- Hold Y position above sea level
                    if hrp.Position.Y < 0 then
                        hrp.CFrame = hrp.CFrame + Vector3.new(0, 5, 0)
                    end
                end
                F.Wait(0.1)
            end
        end)
    end
end

-- ===== AUTO CLICK =====
FeatureCallbacks["AutoClick"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["AutoClick"] do
            local char = getChar()
            local tool = char and char:FindFirstChildOfClass("Tool")
            if tool then
                pcall(function() tool:Activate() end)
            end
            if VirtualUser then
                pcall(function() VirtualUser:Button1Down(Vector2.new()) end)
                F.Wait(0.05)
                pcall(function() VirtualUser:Button1Up(Vector2.new()) end)
            end
            F.Wait(0.05)
        end
    end)
end

-- ===== BRING MOB (tạo dummy target gần HRP cho farm) =====
FeatureCallbacks["BringMonster"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["BringMonster"] do
            local hrp = getHRP()
            if hrp then
                local enemies = workspace:FindFirstChild("Enemies")
                if enemies then
                    for _, mob in ipairs(enemies:GetChildren()) do
                        local mobHrp = mob:FindFirstChild("HumanoidRootPart") or mob:FindFirstChild("Torso")
                        local mobHum = mob:FindFirstChildOfClass("Humanoid")
                        if mobHrp and mobHum and mobHum.Health > 0 then
                            pcall(function()
                                mobHrp.CFrame = hrp.CFrame + Vector3.new(0, 5, -5)
                            end)
                        end
                    end
                end
            end
            F.Wait(0.2)
        end
    end)
end

-- ===== ESP PLAYER (BillboardGui + Highlight) =====
local espObjects = {}
local function removeESP(player)
    local data = espObjects[player]
    if data then
        if data.bill then pcall(function() data.bill:Destroy() end) end
        if data.hl  then pcall(function() data.hl:Destroy()  end) end
        espObjects[player] = nil
    end
end

local function createESP(player)
    if player == LocalPlayer then return end
    local char = player.Character
    local head = char and char:FindFirstChild("Head")
    if not char or not head then return end
    if espObjects[player] then removeESP(player) end

    local bill = Instance.new("BillboardGui")
    bill.Name = "ESP_" .. player.Name
    bill.Adornee = head
    bill.Size = UDim2.new(0, 220, 0, 60)
    bill.StudsOffset = Vector3.new(0, 3, 0)
    bill.AlwaysOnTop = true
    bill.MaxDistance = 1500
    bill.Parent = head

    local lbl = Instance.new("TextLabel", bill)
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 13
    lbl.TextColor3 = Color3.fromRGB(255, 80, 80)
    lbl.TextStrokeTransparency = 0.2
    lbl.RichText = true
    lbl.Text = ""

    local hl = Instance.new("Highlight")
    hl.FillColor = Color3.fromRGB(255, 80, 80)
    hl.OutlineColor = Color3.fromRGB(255, 255, 255)
    hl.FillTransparency = 0.7
    hl.OutlineTransparency = 0
    hl.Adornee = char
    hl.Parent = char

    espObjects[player] = { bill = bill, lbl = lbl, hl = hl, char = char }
end

local espConn = nil
FeatureCallbacks["ESPPlayer"] = function(state)
    if state then
        if espConn then espConn:Disconnect() end
        espConn = RunService.Heartbeat:Connect(function()
            local myHrp = getHRP()
            local myPos = myHrp and myHrp.Position or Vector3.zero
            for _, plr in ipairs(Players:GetPlayers()) do
                if plr ~= LocalPlayer then
                    local char = plr.Character
                    local head = char and char:FindFirstChild("Head")
                    if char and head then
                        local data = espObjects[plr]
                        if not data or data.char ~= char then
                            createESP(plr)
                            data = espObjects[plr]
                        end
                        if data and data.lbl then
                            local hum = char:FindFirstChildOfClass("Humanoid")
                            local root = char:FindFirstChild("HumanoidRootPart")
                            local ls = plr:FindFirstChild("leaderstats")
                            local lvl = ls and ls:FindFirstChild("Level")
                            local bty = ls and (ls:FindFirstChild("Bounty/Honor") or ls:FindFirstChild("Bounty"))
                            local dist = root and math.floor((root.Position - myPos).Magnitude) or 0
                            local hpTxt = hum and math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth) or "?"
                            local lvlTxt = lvl and ("Lv " .. lvl.Value) or ""
                            local btyTxt = bty and (tostring(bty.Value)) or ""
                            data.lbl.Text = string.format(
                                "<font color='#FFFFFF'>%s</font>  %s\n<font color='#FFC44A'>%s HP</font>  <font color='#9CFF8A'>%dm</font>\n<font color='#FFC0CB'>Bty %s</font>",
                                plr.DisplayName, lvlTxt, hpTxt, dist, btyTxt
                            )
                        end
                    else
                        if espObjects[plr] then removeESP(plr) end
                    end
                end
            end
        end)
        table.insert(ActiveConns, espConn)
    else
        if espConn then espConn:Disconnect(); espConn = nil end
        for plr, _ in pairs(espObjects) do removeESP(plr) end
    end
end

-- ===== ESP DEVIL FRUIT (scan workspace) =====
local fruitEspObjs = {}
local function clearFruitESP()
    for _, o in ipairs(fruitEspObjs) do pcall(function() o:Destroy() end) end
    fruitEspObjs = {}
end
FeatureCallbacks["DevilFruitESP"] = function(state)
    if state then
        F.Spawn(function()
            while FeatureStates["DevilFruitESP"] do
                clearFruitESP()
                for _, obj in ipairs(workspace:GetChildren()) do
                    if obj.Name and string.find(string.lower(obj.Name), "fruit") then
                        local handle = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
                        if handle then
                            local bill = Instance.new("BillboardGui")
                            bill.Adornee = handle
                            bill.Size = UDim2.new(0, 150, 0, 30)
                            bill.AlwaysOnTop = true
                            bill.Parent = handle
                            local lbl = Instance.new("TextLabel", bill)
                            lbl.Size = UDim2.new(1, 0, 1, 0)
                            lbl.BackgroundTransparency = 1
                            lbl.Font = Enum.Font.GothamBold
                            lbl.TextSize = 13
                            lbl.TextColor3 = Color3.fromRGB(80, 200, 255)
                            lbl.TextStrokeTransparency = 0.2
                            lbl.Text = "DEVIL FRUIT: " .. obj.Name
                            table.insert(fruitEspObjs, bill)
                            local hl = Instance.new("Highlight")
                            hl.FillColor = Color3.fromRGB(80, 200, 255)
                            hl.Adornee = obj
                            hl.Parent = obj
                            table.insert(fruitEspObjs, hl)
                        end
                    end
                end
                F.Wait(2)
            end
        end)
    else
        clearFruitESP()
    end
end

-- ===== ESP FLOWER (Blox Fruit spawning flowers) =====
FeatureCallbacks["FlowerESP"] = function(state)
    if state then
        F.Spawn(function()
            while FeatureStates["FlowerESP"] do
                for _, obj in ipairs(workspace:GetChildren()) do
                    if obj.Name == "Flower1" or obj.Name == "Flower2" then
                        if not obj:FindFirstChild("FlowerESP_Marker") then
                            local hl = Instance.new("Highlight")
                            hl.Name = "FlowerESP_Marker"
                            hl.FillColor = Color3.fromRGB(255, 100, 200)
                            hl.Adornee = obj
                            hl.Parent = obj
                        end
                    end
                end
                F.Wait(1)
            end
        end)
    else
        for _, obj in ipairs(workspace:GetChildren()) do
            if obj.Name == "Flower1" or obj.Name == "Flower2" then
                local m = obj:FindFirstChild("FlowerESP_Marker")
                if m then m:Destroy() end
            end
        end
    end
end

-- ===== STORE FRUIT (auto cất trái cây vào kho) =====
FeatureCallbacks["StoreFruit"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["StoreFruit"] do
            pcall(function()
                local char = getChar()
                local bp = LocalPlayer:FindFirstChild("Backpack")
                local comm = resolveCommF()
                if not comm then return end
                -- Tìm fruit tool trong backpack/char
                local fruitTool = nil
                if bp then
                    for _, tool in ipairs(bp:GetChildren()) do
                        if tool:IsA("Tool") and tool:FindFirstChild("OriginalName") then
                            fruitTool = tool
                            break
                        end
                    end
                end
                if not fruitTool and char then
                    for _, tool in ipairs(char:GetChildren()) do
                        if tool:IsA("Tool") and tool:FindFirstChild("OriginalName") then
                            fruitTool = tool
                            break
                        end
                    end
                end
                if fruitTool then
                    local orig = fruitTool:FindFirstChild("OriginalName")
                    local origName = orig and orig.Value or fruitTool.Name
                    comm:InvokeServer("StoreFruit", origName, fruitTool)
                    notify("Store Fruit", "Đã cất: " .. tostring(origName), 2)
                end
            end)
            F.Wait(3)
        end
    end)
end

-- ===== BRING / TWEEN TO FRUIT (lấy trái cây spawn trên map) =====
FeatureCallbacks["Grabfruit"] = function(state)
    if not state then
        stopAllTweens()
        return
    end
    F.Spawn(function()
        while FeatureStates["Grabfruit"] do
            local found = nil
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj.Name and string.find(string.lower(obj.Name), "fruit") then
                    local handle = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
                    if handle then found = handle break end
                end
            end
            if found then
                local hrp = getHRP()
                if hrp then
                    if firetouchinterest then
                        pcall(function()
                            firetouchinterest(hrp, found, 0)
                            F.Wait(0.1)
                            firetouchinterest(hrp, found, 1)
                        end)
                    else
                        topos(found.CFrame + Vector3.new(0, 5, 0))
                    end
                end
            end
            F.Wait(0.5)
        end
    end)
end

FeatureCallbacks["Tweenfruit"] = function(state)
    if not state then
        stopAllTweens()
        return
    end
    F.Spawn(function()
        while FeatureStates["Tweenfruit"] do
            local found = nil
            for _, obj in ipairs(workspace:GetChildren()) do
                if obj.Name and string.find(string.lower(obj.Name), "fruit") then
                    local handle = obj:FindFirstChild("Handle") or obj:FindFirstChildWhichIsA("BasePart")
                    if handle then found = handle break end
                end
            end
            if found then
                topos(found.CFrame + Vector3.new(0, 5, 0))
            end
            F.Wait(1)
        end
    end)
end

-- ===== AUTO BUY FRUIT SNIPER (FIX maru's bug: pass variable, not string) =====
FeatureCallbacks["BuyFruitSniper"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["BuyFruitSniper"] do
            pcall(function()
                local comm = resolveCommF()
                local fruitName = CycleChoices["Fruits Sniper"] or "Flame"
                if comm then
                    comm:InvokeServer("PurchaseRawFruit", fruitName, false)  -- FIX: truyền BIẾN, không phải string literal
                end
            end)
            F.Wait(2)
        end
    end)
end

-- ===== TELEPORT TO ISLAND (toggle) =====
FeatureCallbacks["TeleportIsland"] = function(state)
    if not state then
        stopAllTweens()
        return
    end
    F.Spawn(function()
        while FeatureStates["TeleportIsland"] do
            local islandName = CycleChoices["Select Island"] or "WindMill"
            local speed = tonumber(CycleChoices["Tween Speed"]) or 350
            -- Tìm island trong 3 sea
            for seaKey, seaList in pairs(Islands) do
                for _, isl in ipairs(seaList) do
                    if isl.name == islandName then
                        topos(isl.cf, speed)
                        break
                    end
                end
            end
            F.Wait(1)
        end
    end)
end

-- ===== TELEPORT FAST =====
FeatureCallbacks["TeleFast"] = function(state)
    if not state then
        stopAllTweens()
        return
    end
    F.Spawn(function()
        while FeatureStates["TeleFast"] do
            local name = CycleChoices["Select Fast"] or "Sky Island 1"
            for seaKey, seaList in pairs(Islands) do
                for _, isl in ipairs(seaList) do
                    if isl.name == name then
                        topos(isl.cf, 800)
                        break
                    end
                end
            end
            F.Wait(0.5)
        end
    end)
end

-- ===== SPECTATE PLAYER =====
local lastSpecTarget = nil
FeatureCallbacks["SpectatePlys"] = function(state)
    if state then
        F.Spawn(function()
            while FeatureStates["SpectatePlys"] do
                local targetName = CycleChoices["Select Player"]
                local target = nil
                if targetName then
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p.Name == targetName or p.DisplayName == targetName then
                            target = p; break
                        end
                    end
                end
                if target and target.Character then
                    local hum = target.Character:FindFirstChildOfClass("Humanoid")
                    if hum and lastSpecTarget ~= target then
                        workspace.CurrentCamera.CameraSubject = hum
                        lastSpecTarget = target
                    end
                end
                F.Wait(0.5)
            end
        end)
    else
        local char = getChar()
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if hum then workspace.CurrentCamera.CameraSubject = hum end
        lastSpecTarget = nil
    end
end

-- ===== REMOVE NOTIFICATIONS =====
FeatureCallbacks["Remove_trct"] = function(state)
    if state then
        pcall(function()
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            if pg then
                for _, gui in ipairs(pg:GetChildren()) do
                    if gui.Name == "Notification" or gui.Name == "Toast" then
                        gui.Enabled = false
                    end
                end
            end
        end)
    else
        pcall(function()
            local pg = LocalPlayer:FindFirstChild("PlayerGui")
            if pg then
                for _, gui in ipairs(pg:GetChildren()) do
                    if gui.Name == "Notification" or gui.Name == "Toast" then
                        gui.Enabled = true
                    end
                end
            end
        end)
    end
end

-- ===== WHITE SCREEN (Lighting manipulation) =====
FeatureCallbacks["WhiteScreen"] = function(state)
    if state then
        Lighting.FogEnd = 99999
        Lighting.FogColor = Color3.new(1, 1, 1)
        Lighting.Ambient = Color3.new(1, 1, 1)
        Lighting.Brightness = 5
    else
        Lighting.FogEnd = 100000
        Lighting.FogColor = Color3.new(0.7, 0.7, 0.7)
        Lighting.Ambient = Color3.new(0.5, 0.5, 0.5)
        Lighting.Brightness = 2
    end
end

-- ===== REMOVE FOG =====
FeatureCallbacks["RemoveFog"] = function(state)
    if state then
        Lighting.FogEnd = 99999
    else
        Lighting.FogEnd = 100000
    end
end

-- ===== HIDE MOBS (ẩn quái để giảm lag) =====
FeatureCallbacks["hadesinvis"] = function(state)
    if state then
        F.Spawn(function()
            while FeatureStates["hadesinvis"] do
                local enemies = workspace:FindFirstChild("Enemies")
                if enemies then
                    for _, m in ipairs(enemies:GetChildren()) do
                        if not m:FindFirstChild("HiddenFlag") then
                            for _, p in ipairs(m:GetDescendants()) do
                                if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                                    p.Transparency = 1
                                end
                            end
                            local flag = Instance.new("BoolValue")
                            flag.Name = "HiddenFlag"
                            flag.Parent = m
                        end
                    end
                end
                F.Wait(2)
            end
        end)
    else
        local enemies = workspace:FindFirstChild("Enemies")
        if enemies then
            for _, m in ipairs(enemies:GetChildren()) do
                local flag = m:FindFirstChild("HiddenFlag")
                if flag then flag:Destroy() end
                for _, p in ipairs(m:GetDescendants()) do
                    if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
                        p.Transparency = 0
                    end
                end
            end
        end
    end
end

-- ===== AUTO BUY GEAR (Race V4) =====
FeatureCallbacks["BuyGear"] = function(state)
    if not state then return end
    F.Spawn(function()
        while FeatureStates["BuyGear"] do
            local comm = resolveCommF()
            if comm then
                pcall(function() comm:InvokeServer("BuyGear") end)
            end
            F.Wait(2)
        end
    end)
end

-- ===== DUNGEON / AUTO RAID (simplified) =====
local dungeonConn = nil
FeatureCallbacks["Dungeon"] = function(state)
    if state then
        if dungeonConn then dungeonConn:Disconnect() end
        dungeonConn = F.Spawn(function()
            while FeatureStates["Dungeon"] do
                pcall(function()
                    local char = getChar()
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if not hrp then return end
                    -- Tìm enemy gần nhất trong workspace (raid dungeon)
                    local closest, dist = nil, math.huge
                    local enemies = workspace:FindFirstChild("Enemies")
                    if enemies then
                        for _, m in ipairs(enemies:GetChildren()) do
                            local mHrp = m:FindFirstChild("HumanoidRootPart") or m:FindFirstChild("Torso")
                            local mHum = m:FindFirstChildOfClass("Humanoid")
                            if mHrp and mHum and mHum.Health > 0 then
                                local d = (mHrp.Position - hrp.Position).Magnitude
                                if d < dist then dist = d; closest = mHrp end
                            end
                        end
                    end
                    if closest and dist < 200 then
                        hrp.CFrame = CFrame.new(closest.Position + Vector3.new(0, 25, 0), closest.Position)
                        hrp.AssemblyLinearVelocity = Vector3.zero
                        local tool = char:FindFirstChildOfClass("Tool")
                        if tool then tool:Activate() end
                        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
                        if remotes then
                            local regAttack = remotes:FindFirstChild("RegisterAttack")
                            local regHit = remotes:FindFirstChild("RegisterHit")
                            if regAttack then regAttack:FireServer(0) end
                            if regHit then regHit:FireServer(closest, {{closest.Parent, closest}}) end
                        end
                    else
                        -- Tìm ExitTeleporter để advance island
                        local map = workspace:FindFirstChild("Map")
                        if map and map:FindFirstChild("Dungeon") then
                            for _, tp in ipairs(map.Dungeon:GetChildren()) do
                                if tp.Name == "ExitTeleporter" and tp:FindFirstChildWhichIsA("BasePart") then
                                    if firetouchinterest then
                                        pcall(function()
                                            firetouchinterest(hrp, tp:FindFirstChildWhichIsA("BasePart"), 0)
                                            F.Wait(0.1)
                                            firetouchinterest(hrp, tp:FindFirstChildWhichIsA("BasePart"), 1)
                                        end)
                                    end
                                    break
                                end
                            end
                        end
                    end
                end)
                F.Wait(0.08)
            end
        end)
    else
        if dungeonConn then task.cancel(dungeonConn); dungeonConn = nil end
    end
end

-- ===== AIMBOT NEAREST (player) =====
local aimConn = nil
FeatureCallbacks["AimNearest"] = function(state)
    if state then
        if aimConn then aimConn:Disconnect() end
        aimConn = RunService.Heartbeat:Connect(function()
            local myHrp = getHRP()
            if not myHrp then return end
            local closest, dist = nil, math.huge
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer and p.Character then
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    local root = p.Character:FindFirstChild("HumanoidRootPart")
                    if hum and hum.Health > 0 and root then
                        local d = (root.Position - myHrp.Position).Magnitude
                        if d < dist and d < 1000 then dist = d; closest = root end
                    end
                end
            end
            if closest then
                local cam = workspace.CurrentCamera
                if cam then
                    cam.CFrame = CFrame.new(cam.CFrame.Position, closest.Position)
                end
            end
        end)
        table.insert(ActiveConns, aimConn)
    else
        if aimConn then aimConn:Disconnect(); aimConn = nil end
    end
end

-- ============================================================
--  BUILD PAGES WITH MARU FEATURES
-- ============================================================

-- === STATUS PAGE ===
local statusPage = pages["Status"]
local cStatus = makeCard(statusPage, "Server Status", 140, 2)
StatusProxies.ServerTime = createParagraph(cStatus, "Server Time", "00:00:00", 26)
StatusProxies.FPS = createParagraph(cStatus, "FPS", "60", 70)
StatusProxies.PING = createParagraph(cStatus, "PING", "0ms", 114)
createActionButton(cStatus, "Discord", BW, F.UDim2(0, X1, 0, 26), function()
    local link = "https://discord.gg/boxhub"
    if setclipboard then
        setclipboard(link)
        notify("Discord", "Link đã copy: " .. link, 3)
    else
        notify("Discord", "Link: " .. link, 5)
    end
    addLog("[BTN] Discord copied")
end)

local cPlayer = makeCard(statusPage, "Player Status", 180, 152)
StatusProxies.Race = createParagraph(cPlayer, "Race", "Human", 26)
StatusProxies.Beli = createParagraph(cPlayer, "Beli", "0", 70)
StatusProxies.Bounty = createParagraph(cPlayer, "Bounty", "0", 114)
StatusProxies.Fragments = createParagraph(cPlayer, "Fragments", "0", 158)

-- === GENERAL PAGE (Farming) ===
local genPage = pages["General"]
local cFarm = makeCard(genPage, "Farming", 180, 2)
createToggleButton(cFarm, "AutoFarmLevel", "Auto Farm Level", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cFarm, "AutoFarmNearest", "Auto Farm Nearest", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cFarm, "Farmfast", "Auto Farm Skip (Lv.1-100)", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cFarm, "Kaitun", "Auto Kaitun", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cFarm, "AutoHaki", "Auto Haki", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cFarm, "AutoKen", "Auto Ken", BW, F.UDim2(0, X3, 0, 62))
createToggleButton(cFarm, "AutoClick", "Auto Click", BW, F.UDim2(0, X1, 0, 98))
createToggleButton(cFarm, "BringMonster", "Bring Mob", BW, F.UDim2(0, X2, 0, 98))
createToggleButton(cFarm, "FarmChest", "Auto Farm Chest", BW, F.UDim2(0, X3, 0, 98))
createToggleButton(cFarm, "ChestBypass", "Farm Chest Bypass", BW, F.UDim2(0, X1, 0, 134))
createToggleButton(cFarm, "CollectBerry", "Collect Berry", BW, F.UDim2(0, X2, 0, 134))

local cFarmMode = makeCard(genPage, "Farm Mode", 100, 192)
createCycleButton(cFarmMode, "Weapon", {"Melee", "Sword", "Fruit", "Gun"}, 1, BW, F.UDim2(0, X1, 0, 26))
createCycleButton(cFarmMode, "Attack Delay", {"Normal", "Fast", "Super", "Xeter"}, 4, BW, F.UDim2(0, X2, 0, 26))
createCycleButton(cFarmMode, "Bring Mode", {"Low", "Normal", "Super Bring"}, 2, BW, F.UDim2(0, X3, 0, 26))

local cTween = makeCard(genPage, "Tween Speed", 80, 302)
createSlider(cTween, "Tween Speed", 50, 500, 350, "", F.UDim2(0, 6, 0, 26))
createActionButton(cTween, "Stop All Tween", F.UDim2(1, -12, 0, 26), F.UDim2(0, 6, 0, 50), function()
    stopAllTweens()
    notify("Tween", "Đã hủy mọi tween", 2)
end)

local cBoss = makeCard(genPage, "Boss", 100, 392)
createToggleButton(cBoss, "FarmBoss", "Auto Farm Boss", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cBoss, "AllBoss", "Auto Farm All Boss", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cBoss, "AllBossHop", "Auto Farm All Boss Hop", BW, F.UDim2(0, X3, 0, 26))
createCycleButton(cBoss, "Select Boss", {"The Saw", "Bobby", "Yeti", "Diamond", "Jeremy"}, 1, F.UDim2(1, -12, 0, 26), F.UDim2(0, 6, 0, 62))

local cElite = makeCard(genPage, "Elite Hunter", 80, 502)
createToggleButton(cElite, "Elitehunter", "Auto Elite Hunter", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cElite, "EliteHunterHop", "Auto Elite Hunter Hop", BW, F.UDim2(0, X2, 0, 26))

local cBone = makeCard(genPage, "Bone Farm", 130, 592)
createToggleButton(cBone, "Bone", "Auto Farm Bone", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cBone, "QuestBone", "Accept Quest Bone", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cBone, "Random_Bone", "Auto Random Surprise", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cBone, "Pray", "Auto Pray", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cBone, "Trylux", "Auto Try Luck", BW, F.UDim2(0, X2, 0, 62))

local cCake = makeCard(genPage, "Cake Prince / Dough King", 110, 742)
createToggleButton(cCake, "DoughtBoss", "Auto Farm Cake Prince", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cCake, "QuestCake", "Accept Quest Cake Prince", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cCake, "DoughKingRaid", "Auto Dough King Raid", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cCake, "doughkingHop", "Auto Dough King Hop", BW, F.UDim2(0, X1, 0, 62))

local cMastery = makeCard(genPage, "Mastery", 80, 862)
createToggleButton(cMastery, "FarmFruitMastery", "Auto Mastery Fruit", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cMastery, "FarmGunMastery", "Auto Mastery Gun", BW, F.UDim2(0, X2, 0, 26))

local cObs = makeCard(genPage, "Observation", 80, 952)
createToggleButton(cObs, "Observation", "Auto Farm Observation", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cObs, "Observation_Hop", "Auto Farm Observation Hop", BW, F.UDim2(0, X2, 0, 26))

genPage.CanvasSize = F.UDim2(0, 0, 0, 1050)

-- === QUEST & ITEM PAGE ===
local questPage = pages["Quest"]
local cFight = makeCard(questPage, "Fighting Style", 200, 2)
createToggleButton(cFight, "Superhuman", "Auto Superhuman", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cFight, "DeathStep", "Auto DeathStep", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cFight, "Sharkman", "Auto Sharkman Karate", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cFight, "ElectricClaw", "Auto Electric Claw", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cFight, "DragonTalon", "Auto Dragon Talon", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cFight, "God_Human", "Auto GodHuman", BW, F.UDim2(0, X3, 0, 62))

local cMaterials = makeCard(questPage, "Materials", 250, 212)
createToggleButton(cMaterials, "Radioactive", "Auto Farm Radioactive", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cMaterials, "Ectoplasm", "Auto Farm Ectoplasm", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cMaterials, "Makori_gay", "Auto Farm Mystic Droplet", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cMaterials, "Umm", "Auto Farm Magma Ore", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cMaterials, "Wing", "Auto Farm Angel Wings", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cMaterials, "Leather", "Auto Farm Leather", BW, F.UDim2(0, X3, 0, 62))
createToggleButton(cMaterials, "Scrap", "Auto Farm Scrap Metal", BW, F.UDim2(0, X1, 0, 98))
createToggleButton(cMaterials, "Cocoafarm", "Auto Farm Conjured Cocoa", BW, F.UDim2(0, X2, 0, 98))
createToggleButton(cMaterials, "Dragon_Scale", "Auto Farm Dragon Scale", BW, F.UDim2(0, X3, 0, 98))
createToggleButton(cMaterials, "Gunpowder", "Auto Farm Gunpowder", BW, F.UDim2(0, X1, 0, 134))
createToggleButton(cMaterials, "Fish", "Auto Farm Fish Tail", BW, F.UDim2(0, X2, 0, 134))
createToggleButton(cMaterials, "MiniHee", "Auto Farm Mini Tusk", BW, F.UDim2(0, X3, 0, 134))

local cSwordQuest = makeCard(questPage, "Sword Quests", 280, 472)
createToggleButton(cSwordQuest, "Saber", "Auto Saber", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cSwordQuest, "SaberHop", "Auto Saber Hop", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cSwordQuest, "pole", "Auto Pole v1", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cSwordQuest, "polehop", "Auto Pole v1 Hop", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cSwordQuest, "Rengoku", "Auto Rengoku", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cSwordQuest, "Dragon_Trident", "Auto Dragon Trident", BW, F.UDim2(0, X3, 0, 62))
createToggleButton(cSwordQuest, "Dragon_Trident_Hop", "Auto Dragon Trident Hop", BW, F.UDim2(0, X1, 0, 98))
createToggleButton(cSwordQuest, "DarkDagger", "Auto Rip_Indra True", BW, F.UDim2(0, X2, 0, 98))
createToggleButton(cSwordQuest, "DarkDagger_Hop", "Auto Rip_Indra True Hop", BW, F.UDim2(0, X3, 0, 98))
createToggleButton(cSwordQuest, "tushita", "Auto Tushita", BW, F.UDim2(0, X1, 0, 134))
createToggleButton(cSwordQuest, "tushitahop", "Auto Tushita Hop", BW, F.UDim2(0, X2, 0, 134))
createToggleButton(cSwordQuest, "TwinHook", "Auto Twin Hook", BW, F.UDim2(0, X3, 0, 134))
createToggleButton(cSwordQuest, "TwinHook_Hop", "Auto Twin Hook Hop", BW, F.UDim2(0, X1, 0, 170))
createToggleButton(cSwordQuest, "BudySword", "Auto Buddy Sword", BW, F.UDim2(0, X2, 0, 170))
createToggleButton(cSwordQuest, "BudySwordHop", "Auto Buddy Sword Hop", BW, F.UDim2(0, X3, 0, 170))
createToggleButton(cSwordQuest, "Yama", "Auto Yama", BW, F.UDim2(0, X1, 0, 206))
createToggleButton(cSwordQuest, "FarmBossHallow", "Auto Hallow Scythe", BW, F.UDim2(0, X2, 0, 206))
createToggleButton(cSwordQuest, "FarmBossHallowHop", "Auto Hallow Scythe Hop", BW, F.UDim2(0, X3, 0, 206))

local cCDK = makeCard(questPage, "Cursed Dual Katana", 110, 762)
createToggleButton(cCDK, "Tushita_Quest", "Auto Finish Tushita Quest", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cCDK, "Yama_Quest", "Auto Finish Yama Quest", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cCDK, "Get_Cursed", "Auto Get Cursed Dual Katana", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cCDK, "Guitar", "Auto Soul Guitar (Test)", BW, F.UDim2(0, X1, 0, 62))

questPage.CanvasSize = F.UDim2(0, 0, 0, 900)

-- === RACE & MIRAGE PAGE ===
local racePage = pages["Race"]
local cMirage = makeCard(racePage, "Mirage", 100, 2)
createToggleButton(cMirage, "MysticIsland", "Teleport Mirage Island", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cMirage, "Miragenpc", "Teleport Advanced Fruit", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cMirage, "LockCamToMoon", "Auto Lock Moon", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cMirage, "TweenMGear", "Tween Gear", BW, F.UDim2(0, X1, 0, 62))

local cRaceV4 = makeCard(racePage, "Race V4", 200, 112)
createActionButton(cRaceV4, "Top Of GreatTree", BW, F.UDim2(0, X1, 0, 26), function()
    topos(CFrame.new(2280.0, 14.0, 2900.0))
end)
createActionButton(cRaceV4, "Temple Of Time", BW, F.UDim2(0, X2, 0, 26), function()
    topos(CFrame.new(282.1, 193.5, -1251.8))
end)
createActionButton(cRaceV4, "Lever Pull", BW, F.UDim2(0, X3, 0, 26), function()
    pcall(function()
        local lever = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Temple Of Time")
        if lever and lever:FindFirstChild("Lever") then
            firetouchinterest(getHRP(), lever.Lever, 0)
        end
    end)
end)
createActionButton(cRaceV4, "Acient One", BW, F.UDim2(0, X1, 0, 62), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("AcientOne") end
    end)
end)
createToggleButton(cRaceV4, "BuyGear", "Auto Buy Gear", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cRaceV4, "ChooseGears", "Auto Choose Gears", BW, F.UDim2(0, X3, 0, 62))
createToggleButton(cRaceV4, "QuestRace", "Auto Trial", BW, F.UDim2(0, X1, 0, 98))
createToggleButton(cRaceV4, "Train", "Auto Farm & active V4", BW, F.UDim2(0, X2, 0, 98))

local cKillTrial = makeCard(racePage, "Kill Player Trial", 120, 322)
createToggleButton(cKillTrial, "KillAfterTrials", "Kill Player After Trial", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cKillTrial, "SkillTrialZ", "Use Skill Z Kill Player", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cKillTrial, "SkillTrialX", "Use Skill X Kill Player", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cKillTrial, "SkillTrialC", "Use Skill C Kill Player", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cKillTrial, "SkillTrialV", "Use Skill V Kill Player", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cKillTrial, "SkillTrialF", "Use Skill F Kill Player", BW, F.UDim2(0, X3, 0, 62))

racePage.CanvasSize = F.UDim2(0, 0, 0, 460)

-- === VOLCANO EVENT PAGE ===
local volPage = pages["Volcano"]
local cVolQuest = makeCard(volPage, "Quest", 100, 2)
createActionButton(cVolQuest, "Dojo Trainer", BW, F.UDim2(0, X1, 0, 26), function()
    pcall(function()
        for _, n in ipairs(workspace.NPC:GetChildren()) do
            if string.find(n.Name, "Dojo") then topos(n:GetPivot()) break end
        end
    end)
end)
createActionButton(cVolQuest, "Dragon Hunter", BW, F.UDim2(0, X2, 0, 26), function()
    pcall(function()
        for _, n in ipairs(workspace.NPC:GetChildren()) do
            if string.find(n.Name, "Dragon Hunter") then topos(n:GetPivot()) break end
        end
    end)
end)
createActionButton(cVolQuest, "Dragon Wizard", BW, F.UDim2(0, X3, 0, 26), function()
    pcall(function()
        for _, n in ipairs(workspace.NPC:GetChildren()) do
            if string.find(n.Name, "Dragon Wizard") then topos(n:GetPivot()) break end
        end
    end)
end)
createToggleButton(cVolQuest, "QuestDojo", "Auto Quest Dojo Trainer", BW, F.UDim2(0, X1, 0, 62))

local cVolCraft = makeCard(volPage, "Craft Item", 100, 112)
createActionButton(cVolCraft, "Volcanic Magnet", BW, F.UDim2(0, X1, 0, 26))
createActionButton(cVolCraft, "Dino Hood", BW, F.UDim2(0, X2, 0, 26))
createActionButton(cVolCraft, "T-Rex Skull", BW, F.UDim2(0, X3, 0, 26))

local cVolPre = makeCard(volPage, "Prehistoric Island", 180, 222)
createToggleButton(cVolPre, "FindPrehistoric", "Find Prehistoric Island", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cVolPre, "TpPrehistoric", "Teleport Prehistoric Island", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cVolPre, "TpSkullCore", "Teleport Skull Core", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cVolPre, "KillGolem", "Auto Kill Golem", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cVolPre, "DefendVolcano", "Auto Fix Volcano", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cVolPre, "CollectBone", "Collect Bone", BW, F.UDim2(0, X3, 0, 62))
createToggleButton(cVolPre, "CollectEgg", "Collect Egg", BW, F.UDim2(0, X1, 0, 98))
createActionButton(cVolPre, "Remove Lava", BW, F.UDim2(0, X2, 0, 98), function()
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and (string.find(string.lower(obj.Name), "lava") or string.find(string.lower(obj.Name), "magma")) then
                obj.Transparency = 1
                obj.CanCollide = false
            end
        end
    end)
    notify("Remove Lava", "Đã ẩn lava", 2)
end)

local cVolWeapons = makeCard(volPage, "Settings Use Weapons", 110, 412)
createToggleButton(cVolWeapons, "UseMelee", "Auto Use Melee", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cVolWeapons, "UseFruit", "Auto Use Fruit", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cVolWeapons, "UseSword", "Auto Use Sword", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cVolWeapons, "UseGun", "Auto Use Gun", BW, F.UDim2(0, X1, 0, 62))

volPage.CanvasSize = F.UDim2(0, 0, 0, 540)

-- === LOCAL PLAYER PAGE ===
local locPage = pages["Local"]
local cPvP = makeCard(locPage, "PvP", 130, 2)
createToggleButton(cPvP, "AimNearest", "Aimbot Nearest", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cPvP, "NoSt", "No Stun When Using Skill", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cPvP, "EnabledPvP", "Enabled PvP", BW, F.UDim2(0, X3, 0, 26))
createActionButton(cPvP, "Set Position Spawn", BW, F.UDim2(0, X1, 0, 62), function()
    local hrp = getHRP()
    if hrp then
        local savedSpawn = hrp.CFrame
        local function watch()
            while FeatureStates["_watchspawn"] do
                local c = getChar()
                local h = c and c:FindFirstChildOfClass("Humanoid")
                if h and h.Health <= 0 then
                    task.wait(2)
                    if getHRP() then getHRP().CFrame = savedSpawn end
                end
                task.wait(1)
            end
        end
        FeatureStates["_watchspawn"] = true
        F.Spawn(watch)
        notify("Spawn", "Đã lưu vị trí spawn", 2)
    end
end)
createActionButton(cPvP, "Respawn", BW, F.UDim2(0, X2, 0, 62), function()
    pcall(function()
        local char = getChar()
        local h = char and char:FindFirstChildOfClass("Humanoid")
        if h then h.Health = 0 end
    end)
end)

local cPlayer = makeCard(locPage, "Player", 100, 142)
createCycleButton(cPlayer, "Select Player", {"Player1", "Player2", "Player3"}, 1, BW, F.UDim2(0, X1, 0, 26))
createActionButton(cPlayer, "Refresh Player", BW, F.UDim2(0, X2, 0, 26), function()
    notify("Players", "Total: " .. #Players:GetPlayers() .. " online", 3)
end)
createToggleButton(cPlayer, "SpectatePlys", "Spectate Player", BW, F.UDim2(0, X3, 0, 26))

local cOther = makeCard(locPage, "Other Players", 180, 252)
createToggleButton(cOther, "ActiveV3", "Auto Active V3", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cOther, "ActiveV4", "Auto Active V4", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cOther, "NoClip", "NoClip", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cOther, "WalkWater", "Walk on Water", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cOther, "WalkSp", "Walk Speed", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cOther, "JumpSp", "High Jump", BW, F.UDim2(0, X3, 0, 62))
createCycleButton(cOther, "Speed", {"50", "100", "200", "300"}, 3, BW, F.UDim2(0, X1, 0, 98))
createCycleButton(cOther, "Jump", {"50", "100", "200", "300"}, 3, BW, F.UDim2(0, X2, 0, 98))

local cStats = makeCard(locPage, "Stats", 180, 442)
createToggleButton(cStats, "Stats_Kaitun", "Auto Stats Kaitun", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cStats, "melee", "Melee", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cStats, "defense", "Defense", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cStats, "sword", "Sword", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cStats, "gun", "Gun", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cStats, "demonfruit", "Devil Fruit", BW, F.UDim2(0, X3, 0, 62))
createSlider(cStats, "Stats Kaitun", 1, 100, 1, "pts", F.UDim2(0, 6, 0, 98))

locPage.CanvasSize = F.UDim2(0, 0, 0, 640)

-- === VISUAL PAGE ===
local visPage = pages["Visual"]
local cESP = makeCard(visPage, "ESP Menu", 180, 2)
createToggleButton(cESP, "ESPPlayer", "ESP Player", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cESP, "IslandESP", "ESP Island Kitsune", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cESP, "DevilFruitESP", "ESP Fruit", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cESP, "FlowerESP", "ESP Flower", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cESP, "MirageIslandESP", "Esp Mystic Island", BW, F.UDim2(0, X2, 0, 62))

local cTroll = makeCard(visPage, "Troll", 130, 192)
createActionButton(cTroll, "Rain Fruit", BW, F.UDim2(0, X1, 0, 26), function()
    notify("Troll", "Rain Fruit chỉ hoạt động local-side (client fake)", 2)
end)
createActionButton(cTroll, "Instant Level/Beli/EXP", F.UDim2(0, 262, 0, 26), F.UDim2(0, X2, 0, 26), function()
    notify("Troll", "Local-only fake, không sync server", 2)
end)

local cGraph = makeCard(visPage, "Graphic", 130, 332)
createActionButton(cGraph, "Remove Fog (Sea 3)", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cGraph, "RemoveFog", "Remove Fog", BW, F.UDim2(0, X2, 0, 26))
createActionButton(cGraph, "Remove Lava", BW, F.UDim2(0, X3, 0, 26), function()
    pcall(function()
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("BasePart") and (string.find(string.lower(obj.Name), "lava") or string.find(string.lower(obj.Name), "magma")) then
                obj.Transparency = 1
                obj.CanCollide = false
            end
        end
    end)
end)
createActionButton(cGraph, "Unlock FPS", BW, F.UDim2(0, X1, 0, 62), function()
    pcall(function()
        local rs = game:GetService("RunService")
        if rs.SetMaxFps then rs:SetMaxFps(999) end
    end)
    pcall(function()
        if setfpscap then setfpscap(999) end
    end)
    notify("FPS", "Unlocked (executor setfpscap if available)", 2)
end)

local cAbilities = makeCard(visPage, "Abilities", 180, 472)
createToggleButton(cAbilities, "nododgecool", "Dodge No Cooldown", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cAbilities, "InfiniteEnergy", "Infinite Energy", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cAbilities, "InfAbility", "Infinite Ability", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cAbilities, "InfiniteObRange", "Infinite Observation Range", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cAbilities, "InfGeppo", "Infinite Geppo", BW, F.UDim2(0, X2, 0, 62))

visPage.CanvasSize = F.UDim2(0, 0, 0, 670)

-- === FRUIT & RAID PAGE ===
local fruitPage = pages["FruitRaid"]
local cSniper = makeCard(fruitPage, "Sniper", 100, 2)
createCycleButton(cSniper, "Fruits Sniper", {"Flame", "Ice", "Quake", "Light", "Dark", "Dough"}, 1, BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cSniper, "BuyFruitSniper", "Auto Buy Fruit Sniper", BW, F.UDim2(0, X2, 0, 26))

local cFruitOther = makeCard(fruitPage, "Others", 180, 112)
createCycleButton(cFruitOther, "Fruits Eat", {"Flame", "Ice", "Quake", "Light"}, 1, BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cFruitOther, "EatFruit", "Auto Eat Fruit", BW, F.UDim2(0, X2, 0, 26))
createActionButton(cFruitOther, "Random Fruit", BW, F.UDim2(0, X3, 0, 26))
createActionButton(cFruitOther, "Open Devil Shop", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cFruitOther, "StoreFruit", "Auto Store Fruit", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cFruitOther, "Grabfruit", "Bring to Fruit", BW, F.UDim2(0, X3, 0, 62))
createToggleButton(cFruitOther, "Tweenfruit", "Tween to Fruit", BW, F.UDim2(0, X1, 0, 98))

local cRaid = makeCard(fruitPage, "Raid", 220, 302)
createCycleButton(cRaid, "Chips", {"Flame", "Ice", "Quake", "Light", "Dark"}, 1, BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cRaid, "SelectDungeon", "Auto Select Dungeon", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cRaid, "BuyChip", "Auto Buy Chip", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cRaid, "StartRaid", "Auto Start Go To Dungeon", BW, F.UDim2(0, X1, 0, 62))
createToggleButton(cRaid, "Dungeon", "Auto Next Island And Kill Mob", BW, F.UDim2(0, X2, 0, 62))
createToggleButton(cRaid, "Awakener", "Auto Awakener", BW, F.UDim2(0, X3, 0, 62))
createActionButton(cRaid, "Buy Chip Select", BW, F.UDim2(0, X1, 0, 98), function()
    pcall(function()
        local comm = resolveCommF()
        local chipName = CycleChoices["Chips"] or "Flame"
        if comm then comm:InvokeServer("RaidsNpc", "Buy", chipName) end
    end)
end)
createActionButton(cRaid, "Start Go To Dungeon", BW, F.UDim2(0, X2, 0, 98), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("RaidsNpc", "Start") end
    end)
    -- Teleport to Lab (Awakenings room)
    topos(CFrame.new(-643.86, 14.0, -1235.59))
end)
createActionButton(cRaid, "Teleport to Lab", BW, F.UDim2(0, X3, 0, 98), function()
    topos(CFrame.new(-643.86, 14.0, -1235.59))
end)

local cLaw = makeCard(fruitPage, "Misc KoKo Sword", 110, 532)
createToggleButton(cLaw, "OderSword", "Auto Law", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cLaw, "OderSwordHop", "Auto Law Hop", BW, F.UDim2(0, X2, 0, 26))
createActionButton(cLaw, "Buy Microchip Law Boss", BW, F.UDim2(0, X3, 0, 26), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("BuyMicrochipLaw") end
    end)
end)

fruitPage.CanvasSize = F.UDim2(0, 0, 0, 660)

-- === TELEPORT PAGE ===
local tpPage = pages["Teleport"]
local cWorld = makeCard(tpPage, "World", 80, 2)
createActionButton(cWorld, "Teleport To Old World", BW, F.UDim2(0, X1, 0, 26), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("TravelMain") end
    end)
    notify("Travel", "Đang tới Old World", 3)
end)
createActionButton(cWorld, "Teleport To Second Sea", BW, F.UDim2(0, X2, 0, 26), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("TravelDressrosa") end
    end)
    notify("Travel", "Đang tới Second Sea", 3)
end)
createActionButton(cWorld, "Teleport To Third Sea", BW, F.UDim2(0, X3, 0, 26), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("TravelZou") end
    end)
    notify("Travel", "Đang tới Third Sea", 3)
end)

local cIsland = makeCard(tpPage, "Island", 120, 92)
createCycleButton(cIsland, "Select Island", {"WindMill", "Marine", "Middle Town", "Jungle", "Desert"}, 1, F.UDim2(1, -12, 0, 26), F.UDim2(0, 6, 0, 26))
createToggleButton(cIsland, "TeleportIsland", "Teleport", BW, F.UDim2(0, X1, 0, 62))
createActionButton(cIsland, "Server Hop", BW, F.UDim2(0, X2, 0, 62), function()
    serverHop()
end)
createActionButton(cIsland, "Rejoin Server", BW, F.UDim2(0, X3, 0, 62), function()
    rejoinServer()
end)

local cFastTP = makeCard(tpPage, "Teleport Fast", 100, 222)
createCycleButton(cFastTP, "Select Fast", {"Sky Island 1", "Sky Island 2", "Flamingo Mansion", "Mansion"}, 1, F.UDim2(1, -12, 0, 26), F.UDim2(0, 6, 0, 26))
createToggleButton(cFastTP, "TeleFast", "Teleport Fast", BW, F.UDim2(0, X1, 0, 62))

tpPage.CanvasSize = F.UDim2(0, 0, 0, 340)

-- === SHOP PAGE ===
local shopPage = pages["Shop"]
local cShopSword = makeCard(shopPage, "Swords", 250, 2)
local swordItems = {"Cutlass [1K]", "Katana [1K]", "Iron Mace [25K]", "Dual Katana [12K]", "Triple Katana [60K]", "Pipe [100K]", "Bisento [1.2M]", "Soul Cane [750K]"}
for i, item in ipairs(swordItems) do
    local col = ((i - 1) % 3)
    local row = math.floor((i - 1) / 3)
    -- Strip price (vd "Cutlass [1K]" -> "Cutlass")
    local cleanName = string.match(item, "^([^%[%s]+)") or item
    createActionButton(cShopSword, item, BW, F.UDim2(0, X1 + col * 128, 0, 26 + row * 36), function()
        pcall(function()
            local comm = resolveCommF()
            if comm then comm:InvokeServer("BuyItem", cleanName) end
        end)
        notify("Shop", "Mua " .. cleanName, 2)
    end)
end

local cShopGun = makeCard(shopPage, "Guns", 150, 262)
local gunItems = {"Slingshot [5K]", "Flintlock [10.5K]", "Musket [8K]", "Cannon [100K]", "Kabucha [1.5K Frag]"}
for i, item in ipairs(gunItems) do
    local col = ((i - 1) % 3)
    local row = math.floor((i - 1) / 3)
    local cleanName = string.match(item, "^([^%[%s]+)") or item
    createActionButton(cShopGun, item, BW, F.UDim2(0, X1 + col * 128, 0, 26 + row * 36), function()
        pcall(function()
            local comm = resolveCommF()
            if comm then comm:InvokeServer("BuyItem", cleanName) end
        end)
        notify("Shop", "Mua " .. cleanName, 2)
    end)
end

local cShopHaki = makeCard(shopPage, "Haki & Abilities", 150, 422)
createActionButton(cShopHaki, "Buy Geppo [10K]", BW, F.UDim2(0, X1, 0, 26), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("BuyHaki", "Geppo") end
    end)
end)
createActionButton(cShopHaki, "Buy Buso Haki [25K]", BW, F.UDim2(0, X2, 0, 26), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("BuyHaki", "Buso") end
    end)
end)
createActionButton(cShopHaki, "Buy Soru [25K]", BW, F.UDim2(0, X3, 0, 26), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("BuyHaki", "Soru") end
    end)
end)
createActionButton(cShopHaki, "Buy Obs Haki [750K]", BW, F.UDim2(0, X1, 0, 62), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("BuyHaki", "Observation") end
    end)
end)

shopPage.CanvasSize = F.UDim2(0, 0, 0, 590)

-- === MISC PAGE ===
local miscPage = pages["Misc"]
local cMiscSettings = makeCard(miscPage, "Settings", 130, 2)
createToggleButton(cMiscSettings, "Remove_trct", "Disabled Notifications", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cMiscSettings, "DisabledDame", "Disabled Damage Counter", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cMiscSettings, "WhiteScreen", "White Screen", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cMiscSettings, "hadesinvis", "Hide Mobs", BW, F.UDim2(0, X1, 0, 62))
createActionButton(cMiscSettings, "Max Zoom", BW, F.UDim2(0, X2, 0, 62), function()
    pcall(function()
        LocalPlayer.CameraMaxZoomDistance = 128
    end)
    notify("Zoom", "Max zoom set", 2)
end)

local cMiscCodes = makeCard(miscPage, "Codes", 80, 142)
createActionButton(cMiscCodes, "Redeem All Codes", F.UDim2(1, -12, 0, 26), F.UDim2(0, 6, 0, 26), function()
    F.Spawn(function()
        local comm = resolveCommF()
        if not comm then notify("Codes", "Không tìm CommF_", 3) return end
        local n = 0
        for _, code in ipairs(GameCodes) do
            pcall(function() comm:InvokeServer("Redeem", code) end)
            n = n + 1
            F.Wait(0.3)
        end
        notify("Codes", "Đã redeem " .. n .. " codes", 3)
        addLog("[CODES] Redeemed " .. n)
    end)
end)

local cMiscTeam = makeCard(miscPage, "Team", 80, 232)
createActionButton(cMiscTeam, "Join Marines Team", BW, F.UDim2(0, X1, 0, 26), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("SetTeam", "Marines") end
    end)
    notify("Team", "Marines", 2)
end)
createActionButton(cMiscTeam, "Join Pirates Team", BW, F.UDim2(0, X2, 0, 26), function()
    pcall(function()
        local comm = resolveCommF()
        if comm then comm:InvokeServer("SetTeam", "Pirates") end
    end)
    notify("Team", "Pirates", 2)
end)

miscPage.CanvasSize = F.UDim2(0, 0, 0, 330)

-- ============================================================
--  KEYBIND: RightControl / Insert / P to toggle UI
-- ============================================================

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightControl
    or input.KeyCode == Enum.KeyCode.Insert
    or input.KeyCode == Enum.KeyCode.P then
        MainFrame.Visible = not MainFrame.Visible
        mobileToggle.Visible = not MainFrame.Visible
        addLog("[UI] " .. (MainFrame.Visible and "shown" or "hidden"))
    end
end)

-- ============================================================
--  STATUS READOUT LOOPS (FPS / PING / Race / Beli / Bounty / ...)
-- ============================================================

-- FPS + PING via Heartbeat (update 10 lần/giây)
local fpsAccum, fpsCount, lastFpsTick = 0, 0, tick()
local function getClientPing()
    -- 3 fallback
    local ok1, p1 = pcall(function() return LocalPlayer:GetNetworkPing() end)
    if ok1 and type(p1) == "number" and p1 > 0 then return math.floor(p1 * 1000) end
    local ok2, p2 = pcall(function()
        local s = Stats:FindFirstChild("Network")
        if s then
            local ss = s:FindFirstChild("ServerStatsItem")
            if ss and ss:FindFirstChild("Data") then
                local ping = ss.Data:FindFirstChild("Ping")
                if ping then return ping:GetValue() end
            end
        end
        return nil
    end)
    if ok2 and p2 then return math.floor(p2 * 1000) end
    local ok3, p3 = pcall(function()
        local ps = Stats:FindFirstChild("PerformanceStats")
        if ps then
            local ping = ps:FindFirstChild("Ping")
            if ping then return ping:GetValue() end
        end
        return nil
    end)
    if ok3 and p3 then return math.floor(p3) end
    return 0
end

local fpsConn = RunService.Heartbeat:Connect(function(dt)
    fpsAccum = fpsAccum + 1
    local now = tick()
    if now - lastFpsTick >= 0.5 then
        local fps = math.floor(fpsAccum / (now - lastFpsTick))
        fpsAccum = 0
        lastFpsTick = now
        StatusValues.FPS = fps
        StatusValues.PING = getClientPing()
        if StatusProxies.FPS then StatusProxies.FPS:Set({Description = tostring(StatusValues.FPS) .. " FPS"}) end
        if StatusProxies.PING then
            local p = StatusValues.PING
            local color = p < 80 and "xanh" or (p < 160 and "vàng" or "đỏ")
            StatusProxies.PING:Set({Description = tostring(p) .. "ms (" .. color .. ")"})
        end
    end
end)
table.insert(ActiveConns, fpsConn)

-- Server time + Player status (Race / Beli / Bounty / Fragments / Level) — mỗi 1s
F.Spawn(function()
    while ScreenGui.Parent do
        -- Server time
        StatusValues.ServerTime = os.date("%H:%M:%S", os.time())
        if StatusProxies.ServerTime then StatusProxies.ServerTime:Set({Description = StatusValues.ServerTime}) end

        -- Race
        local data = getData()
        local ls = getLeaderstats()
        if data then
            local race = data:FindFirstChild("Race")
            if race then StatusValues.Race = tostring(race.Value) end
            local beli = data:FindFirstChild("Beli")
            if beli then StatusValues.Beli = tonumber(beli.Value) or 0 end
            local frag = data:FindFirstChild("Fragments")
            if frag then StatusValues.Fragments = tonumber(frag.Value) or 0 end
            local df = data:FindFirstChild("DevilFruit")
            if df then StatusValues.DevilFruit = tostring(df.Value) end
        end
        if ls then
            local bty = ls:FindFirstChild("Bounty/Honor") or ls:FindFirstChild("Bounty")
            if bty then StatusValues.Bounty = tonumber(bty.Value) or 0 end
            local lvl = ls:FindFirstChild("Level")
            if lvl then StatusValues.Level = tonumber(lvl.Value) or 1 end
        end

        local function fmtNum(n)
            if not n then return "0" end
            if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
            if n >= 1000 then return string.format("%.1fK", n / 1000) end
            return tostring(n)
        end

        if StatusProxies.Race then StatusProxies.Race:Set({Description = StatusValues.Race .. " (Lv " .. StatusValues.Level .. ")"}) end
        if StatusProxies.Beli then StatusProxies.Beli:Set({Description = fmtNum(StatusValues.Beli)}) end
        if StatusProxies.Bounty then StatusProxies.Bounty:Set({Description = fmtNum(StatusValues.Bounty)}) end
        if StatusProxies.Fragments then StatusProxies.Fragments:Set({Description = fmtNum(StatusValues.Fragments)}) end

        F.Wait(1)
    end
end)

-- ============================================================
--  INIT
-- ============================================================

-- Show default tab
showTab("Status")

-- Animate main frame in
MainFrame.Visible = true
MainFrame.Size = F.UDim2(0, 0, 0, 0)
UIScale.Scale = 0.8
TweenService:Create(MainFrame, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = F.UDim2(0, 650, 0, 369),
    Position = F.UDim2(0.5, 0, 0.5, 0),
}):Play()
TweenService:Create(UIScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Scale = computeScale(),
}):Play()

addLog("UI Ready")
addLog("BOXHUB v2.0 Studio loaded")
addLog("Toggle: RightCtrl / Insert / P")
notify("BOXHUB v2.0", "Loaded. Press RightCtrl to toggle menu.", 4)

-- Auto-cleanup khi ScreenGui bị destroy
ScreenGui.AncestryChanged:Connect(function(_, parent)
    if not parent then
        for _, c in ipairs(ActiveConns) do
            pcall(function() c:Disconnect() end)
        end
        ActiveConns = {}
    end
end)
