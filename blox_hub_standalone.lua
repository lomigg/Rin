--[[
    Blox Fruits Hub UI — Standalone Roblox Studio Edition
    Phong cách UI: Project Spooky (Source A)
    Danh sách tính năng: Maru/Kimp (Source B)

    Chạy trong Roblox Studio hoặc LocalScript trong game.
    Callbacks chỉ print/log — không exploit API, không loadstring.

    Cách dùng:
    1. Mở Roblox Studio
    2. Tạo LocalScript trong StarterGui (hoặc paste vào Command Bar)
    3. Paste toàn bộ code này
    4. Run (F5)
]]

-- ============================================================
--  UTILITY FUNCTIONS
-- ============================================================

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")
local StarterGui        = game:GetService("StarterGui")
local Lighting          = game:GetService("Lighting")
local LocalPlayer       = Players.LocalPlayer
local PlayerGui         = LocalPlayer:WaitForChild("PlayerGui")

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
    return PlayerGui
end

local function safeParent(gui)
    if not gui then return end
    pcall(function() gui.Parent = getSafeParent() end)
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
ScreenGui.Name = "BloxHub_UI"
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
hubIcon.Text = "BLOX HUB"
hubIcon.TextSize = 14
hubIcon.TextColor3 = Color3.fromRGB(140, 115, 235)
hubIcon.TextXAlignment = Enum.TextXAlignment.Center

local versionLbl = Instance.new("TextLabel", leftSide)
versionLbl.Size = F.UDim2(0, 128, 0, 14)
versionLbl.Position = F.UDim2(0, 0, 0, 36)
versionLbl.BackgroundTransparency = 1
versionLbl.Font = Enum.Font.GothamBold
versionLbl.Text = "v1.0 Studio"
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

-- Mobile toggle button
local mobileToggle = Instance.new("TextButton", ScreenGui)
mobileToggle.Name = "MobileToggle"
mobileToggle.Size = F.UDim2(0, 52, 0, 52)
mobileToggle.Position = F.UDim2(0, 20, 0, 80)
mobileToggle.BackgroundColor3 = Color3.fromRGB(16, 16, 22)
mobileToggle.Font = Enum.Font.GothamBold
mobileToggle.Text = "HUB"
mobileToggle.TextSize = 12
mobileToggle.TextColor3 = Color3.fromRGB(140, 115, 235)
mobileToggle.Visible = false
mobileToggle.ZIndex = 9999
Instance.new("UICorner", mobileToggle).CornerRadius = UDim.new(0, 8)
local mtStroke = Instance.new("UIStroke", mobileToggle)
mtStroke.Color = Color3.fromRGB(140, 115, 235)
mtStroke.Thickness = 1.2
mobileToggle.Activated:Connect(function()
    MainFrame.Visible = true
    mobileToggle.Visible = false
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
    end

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
        notify("Dropdown", prefix .. " = " .. tostring(choices[currentIdx]), 2)
    end)

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
--  BUILD PAGES WITH MARU FEATURES
-- ============================================================

-- === STATUS PAGE ===
local statusPage = pages["Status"]
local cStatus = makeCard(statusPage, "Server Status", 140, 2)
createParagraph(cStatus, "Server Time", "00:00:00", 26)
createParagraph(cStatus, "FPS", "60", 70)
createParagraph(cStatus, "PING", "0ms", 114)
createActionButton(cStatus, "Discord", BW, F.UDim2(0, X1, 0, 26), function()
    notify("Discord", "Link copied!", 2)
    if setclipboard then setclipboard("https://discord.gg/example") end
end)

local cPlayer = makeCard(statusPage, "Player Status", 140, 152)
createParagraph(cPlayer, "Race", "Human", 26)
createParagraph(cPlayer, "Beli", "0", 70)
createParagraph(cPlayer, "Bounty", "0", 114)

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
createActionButton(cTween, "Stop All Tween", F.UDim2(1, -12, 0, 26), F.UDim2(0, 6, 0, 50))

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
createActionButton(cRaceV4, "Top Of GreatTree", BW, F.UDim2(0, X1, 0, 26))
createActionButton(cRaceV4, "Temple Of Time", BW, F.UDim2(0, X2, 0, 26))
createActionButton(cRaceV4, "Lever Pull", BW, F.UDim2(0, X3, 0, 26))
createActionButton(cRaceV4, "Acient One", BW, F.UDim2(0, X1, 0, 62))
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
createActionButton(cVolQuest, "Dojo Trainer", BW, F.UDim2(0, X1, 0, 26))
createActionButton(cVolQuest, "Dragon Hunter", BW, F.UDim2(0, X2, 0, 26))
createActionButton(cVolQuest, "Dragon Wizard", BW, F.UDim2(0, X3, 0, 26))
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
createActionButton(cVolPre, "Remove Lava", BW, F.UDim2(0, X2, 0, 98))

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
createActionButton(cPvP, "Set Position Spawn", BW, F.UDim2(0, X1, 0, 62))
createActionButton(cPvP, "Respawn", BW, F.UDim2(0, X2, 0, 62))

local cPlayer = makeCard(locPage, "Player", 100, 142)
createCycleButton(cPlayer, "Select Player", {"Player1", "Player2", "Player3"}, 1, BW, F.UDim2(0, X1, 0, 26))
createActionButton(cPlayer, "Refresh Player", BW, F.UDim2(0, X2, 0, 26))
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
createActionButton(cTroll, "Rain Fruit", BW, F.UDim2(0, X1, 0, 26))
createActionButton(cTroll, "Instant Level/Beli/EXP", F.UDim2(0, 262, 0, 26), F.UDim2(0, X2, 0, 26))

local cGraph = makeCard(visPage, "Graphic", 130, 332)
createActionButton(cGraph, "Remove Fog (Sea 3)", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cGraph, "RemoveFog", "Remove Fog", BW, F.UDim2(0, X2, 0, 26))
createActionButton(cGraph, "Remove Lava", BW, F.UDim2(0, X3, 0, 26))
createActionButton(cGraph, "Unlock FPS", BW, F.UDim2(0, X1, 0, 62))

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
createActionButton(cRaid, "Buy Chip Select", BW, F.UDim2(0, X1, 0, 98))
createActionButton(cRaid, "Start Go To Dungeon", BW, F.UDim2(0, X2, 0, 98))
createActionButton(cRaid, "Teleport to Lab", BW, F.UDim2(0, X3, 0, 98))

local cLaw = makeCard(fruitPage, "Misc KoKo Sword", 110, 532)
createToggleButton(cLaw, "OderSword", "Auto Law", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cLaw, "OderSwordHop", "Auto Law Hop", BW, F.UDim2(0, X2, 0, 26))
createActionButton(cLaw, "Buy Microchip Law Boss", BW, F.UDim2(0, X3, 0, 26))

fruitPage.CanvasSize = F.UDim2(0, 0, 0, 660)

-- === TELEPORT PAGE ===
local tpPage = pages["Teleport"]
local cWorld = makeCard(tpPage, "World", 80, 2)
createActionButton(cWorld, "Teleport To Old World", BW, F.UDim2(0, X1, 0, 26))
createActionButton(cWorld, "Teleport To Second Sea", BW, F.UDim2(0, X2, 0, 26))
createActionButton(cWorld, "Teleport To Third Sea", BW, F.UDim2(0, X3, 0, 26))

local cIsland = makeCard(tpPage, "Island", 120, 92)
createCycleButton(cIsland, "Select Island", {"WindMill", "Marine", "Middle Town", "Jungle", "Desert"}, 1, F.UDim2(1, -12, 0, 26), F.UDim2(0, 6, 0, 26))
createToggleButton(cIsland, "TeleportIsland", "Teleport", BW, F.UDim2(0, X1, 0, 62))
createActionButton(cIsland, "Server Hop", BW, F.UDim2(0, X2, 0, 62))
createActionButton(cIsland, "Rejoin Server", BW, F.UDim2(0, X3, 0, 62))

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
    createActionButton(cShopSword, item, BW, F.UDim2(0, X1 + col * 128, 0, 26 + row * 36))
end

local cShopGun = makeCard(shopPage, "Guns", 150, 262)
local gunItems = {"Slingshot [5K]", "Flintlock [10.5K]", "Musket [8K]", "Cannon [100K]", "Kabucha [1.5K Frag]"}
for i, item in ipairs(gunItems) do
    local col = ((i - 1) % 3)
    local row = math.floor((i - 1) / 3)
    createActionButton(cShopGun, item, BW, F.UDim2(0, X1 + col * 128, 0, 26 + row * 36))
end

local cShopHaki = makeCard(shopPage, "Haki & Abilities", 150, 422)
createActionButton(cShopHaki, "Buy Geppo [10K]", BW, F.UDim2(0, X1, 0, 26))
createActionButton(cShopHaki, "Buy Buso Haki [25K]", BW, F.UDim2(0, X2, 0, 26))
createActionButton(cShopHaki, "Buy Soru [25K]", BW, F.UDim2(0, X3, 0, 26))
createActionButton(cShopHaki, "Buy Obs Haki [750K]", BW, F.UDim2(0, X1, 0, 62))

shopPage.CanvasSize = F.UDim2(0, 0, 0, 590)

-- === MISC PAGE ===
local miscPage = pages["Misc"]
local cMiscSettings = makeCard(miscPage, "Settings", 130, 2)
createToggleButton(cMiscSettings, "Remove_trct", "Disabled Notifications", BW, F.UDim2(0, X1, 0, 26))
createToggleButton(cMiscSettings, "DisabledDame", "Disabled Damage Counter", BW, F.UDim2(0, X2, 0, 26))
createToggleButton(cMiscSettings, "WhiteScreen", "White Screen", BW, F.UDim2(0, X3, 0, 26))
createToggleButton(cMiscSettings, "hadesinvis", "Hide Mobs", BW, F.UDim2(0, X1, 0, 62))
createActionButton(cMiscSettings, "Max Zoom", BW, F.UDim2(0, X2, 0, 62))

local cMiscCodes = makeCard(miscPage, "Codes", 80, 142)
createActionButton(cMiscCodes, "Redeem All Codes", F.UDim2(1, -12, 0, 26), F.UDim2(0, 6, 0, 26))

local cMiscTeam = makeCard(miscPage, "Team", 80, 232)
createActionButton(cMiscTeam, "Join Marines Team", BW, F.UDim2(0, X1, 0, 26))
createActionButton(cMiscTeam, "Join Pirates Team", BW, F.UDim2(0, X2, 0, 26))

miscPage.CanvasSize = F.UDim2(0, 0, 0, 330)

-- ============================================================
--  KEYBIND: RightControl to toggle UI
-- ============================================================

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.Insert then
        MainFrame.Visible = not MainFrame.Visible
        mobileToggle.Visible = not MainFrame.Visible
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
notify("Blox Hub", "UI loaded successfully!", 3)

-- Auto-update status (Studio safe)
F.Spawn(function()
    while ScreenGui.Parent do
        F.Wait(1)
        -- Update can be extended here
    end
end)
