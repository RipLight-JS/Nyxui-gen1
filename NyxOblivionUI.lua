--[[
    NYX x OBLIVION UI  v3
    Compact top dock + obsidian / purple theme.  Animated, with soft UI sounds.

    Tabs:  Home - Cmds - Scripts - Players - Music - News - Settings
    Mobile: fits the screen on load, UI Scale slider in Settings, "Open Nyx" pill toggles the menu.
    PC:     RightControl toggles the menu, ";" opens the command bar.

    Add your own stuff:
        UI:AddCommand({Name="Fly", Desc="...", Category="Movement", Kind="Toggle", Best=true, Callback=function(on) end})
        UI:AddScript({Name="My script", Desc="what it does", Tag="Utility", Callback=function() end})
        UI:AddTrack({Name="Song", Artist="Me", Id=123456789})
        UI.PlayerActions.Goto = function(player) end
        UI:AddWindow("Title", 220, 160)    -- draggable floating window, w.Body = content frame
        UI:Notify("Title", "Text", 3)
        UI:SetScale(0.8)

    Sounds: generated sound files are written to your executor's workspace (NyxUI folder) the first time.
            If your executor can't do that, the UI falls back to built-in Roblox sounds.
]]

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")
local TeleportService    = game:GetService("TeleportService")
local SoundService       = game:GetService("SoundService")
local Lighting           = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")

local LocalPlayer = Players.LocalPlayer

-- ================= SIZES (small, like Oblivion) =================
local BASE_W  = 340   -- menu width
local DOCK_H  = 34
local PANEL_H = 236
local PAD     = 8     -- invisible margin so glowing borders are never clipped
local TOTAL_H = DOCK_H + 6 + PANEL_H

local USE_INTER = true -- Inter font (clean, like Oblivion). Set false to use Gotham.

-- ================= THEME =================
local Theme = {
    Bg       = Color3.fromRGB(9, 5, 20),
    Row      = Color3.fromRGB(30, 19, 56),
    Accent   = Color3.fromRGB(145, 78, 255),
    Accent2  = Color3.fromRGB(184, 120, 255),
    Pink     = Color3.fromRGB(236, 96, 255),
    Blue     = Color3.fromRGB(108, 99, 255),
    Stroke   = Color3.fromRGB(92, 58, 178),
    Text     = Color3.fromRGB(248, 244, 255),
    SubText  = Color3.fromRGB(166, 150, 208),
    Good     = Color3.fromRGB(74, 222, 128),
    Danger   = Color3.fromRGB(244, 63, 94),
    Off      = Color3.fromRGB(52, 45, 76),
    White    = Color3.new(1, 1, 1),
    Font     = Enum.Font.GothamMedium,
    FontBold = Enum.Font.GothamBold,
}

local FACE_REG  = Font.new("rbxasset://fonts/families/Inter.json", Enum.FontWeight.Medium, Enum.FontStyle.Normal)
local FACE_BOLD = Font.new("rbxasset://fonts/families/Inter.json", Enum.FontWeight.SemiBold, Enum.FontStyle.Normal)

-- ================= HELPERS =================
local Motion = {On = true}                 -- Settings > Interface > Animations
local Audio  = {Play = function() end}     -- replaced by the library once sounds are ready

local function Fontify(props)
    local bold = props.Font == Theme.FontBold
    if USE_INTER then
        props.Font = nil
        props.FontFace = bold and FACE_BOLD or FACE_REG
    else
        props.Font = props.Font or Theme.Font
    end
end

local function New(class, props, children)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    for _, c in ipairs(children or {}) do c.Parent = o end
    return o
end
local function Corner(r) return New("UICorner", {CornerRadius = UDim.new(0, r)}) end
local function Stroke(c, t, tr)
    return New("UIStroke", {Color = c or Theme.Stroke, Thickness = t or 1, Transparency = tr or 0.45,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
end
local function Pad(l, t, r, b)
    return New("UIPadding", {PaddingLeft = UDim.new(0, l), PaddingTop = UDim.new(0, t or l),
        PaddingRight = UDim.new(0, r or l), PaddingBottom = UDim.new(0, b or t or l)})
end
local function Gradient(a, b, rot)
    return New("UIGradient", {Color = ColorSequence.new(a, b), Rotation = rot or 90})
end
local function List(pad, dir, ha, va)
    return New("UIListLayout", {Padding = UDim.new(0, pad or 6), SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = dir or Enum.FillDirection.Vertical,
        HorizontalAlignment = ha or Enum.HorizontalAlignment.Left,
        VerticalAlignment = va or Enum.VerticalAlignment.Top})
end
local function Tween(o, t, props, style, dir)
    if not Motion.On then t = 0 end
    local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out), props)
    tw:Play()
    return tw
end
local function Label(props)
    props.BackgroundTransparency = 1
    props.Font = props.Font or Theme.Font
    props.TextColor3 = props.TextColor3 or Theme.Text
    props.TextSize = props.TextSize or 11
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    Fontify(props)
    return New("TextLabel", props)
end
local function Input(props, children)
    props.Font = props.Font or Theme.Font
    props.TextColor3 = props.TextColor3 or Theme.Text
    props.PlaceholderColor3 = props.PlaceholderColor3 or Theme.SubText
    props.TextSize = props.TextSize or 11
    props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
    props.ClearTextOnFocus = false
    Fontify(props)
    return New("TextBox", props, children)
end
-- Buttons get a hover glow, a press flash and a soft click sound automatically.
-- Fx = false -> no overlay (use inside layouts).  Silent = true -> no click sound.
local function Button(props, children)
    local fx, silent = props.Fx, props.Silent
    props.Fx, props.Silent = nil, nil
    props.AutoButtonColor = false
    props.Text = props.Text or ""
    props.TextColor3 = props.TextColor3 or Theme.Text
    props.TextSize = props.TextSize or 11
    props.Font = props.Font or Theme.FontBold
    Fontify(props)
    local accentFill = props.BackgroundColor3 == Theme.Accent and props.BackgroundTransparency == nil
    if accentFill then props.BackgroundColor3 = Theme.White end
    local b = New("TextButton", props, children)
    if accentFill then
        New("UIGradient", {Color = ColorSequence.new(Color3.fromRGB(176, 112, 255), Color3.fromRGB(122, 62, 240)), Rotation = 90, Parent = b})
    end
    if fx ~= false then
        local ov = New("Frame", {Name = "Fx", BackgroundColor3 = Theme.White, BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1), ZIndex = b.ZIndex + 1, Parent = b})
        local corner = b:FindFirstChildOfClass("UICorner")
        if corner then New("UICorner", {CornerRadius = corner.CornerRadius, Parent = ov}) end
        b.MouseEnter:Connect(function() Tween(ov, 0.15, {BackgroundTransparency = 0.92}) end)
        b.MouseLeave:Connect(function() Tween(ov, 0.2, {BackgroundTransparency = 1}) end)
        b.MouseButton1Down:Connect(function() Tween(ov, 0.06, {BackgroundTransparency = 0.82}) end)
        b.MouseButton1Up:Connect(function() Tween(ov, 0.25, {BackgroundTransparency = 0.92}) end)
        if not silent then b.MouseButton1Click:Connect(function() Audio.Play("click") end) end
    end
    return b
end
local function Hair(parent, order)
    return New("Frame", {Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Theme.Stroke, BackgroundTransparency = 0.75,
        BorderSizePixel = 0, LayoutOrder = order or 0, Parent = parent})
end
local function IsPress(i)
    return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch
end
local function IsMove(i)
    return i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch
end
local function CopyText(s)
    local f = setclipboard or toclipboard
    if f then return pcall(f, s) end
    return false
end
local function GetParent()
    local ok, ui = pcall(function() return (gethui and gethui()) or game:GetService("CoreGui") end)
    if ok and ui then return ui end
    return LocalPlayer:WaitForChild("PlayerGui")
end
local function Count(label, target)
    task.spawn(function()
        for i = 1, 14 do
            if not label.Parent then return end
            label.Text = tostring(math.floor(target * i / 14 + 0.5))
            task.wait(0.02)
        end
        label.Text = tostring(target)
    end)
end
local function FmtTime(s)
    s = math.max(0, math.floor(s or 0))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- ================= CUSTOM ICON SET (thin outline style, same look as Oblivion) =================
-- Every icon is drawn from rounded frames / thin line segments on a 24x24 grid - no emoji, no text symbols.
-- Want the exact same artwork as an image set? Put asset ids here and they replace the drawn version:
--     Library.IconAssets["gear"] = "rbxassetid://123456789"
-- Set USE_IMAGE_ICONS = false to go back to the frame-drawn icons. (scroll has no asset yet -> it is drawn)
local USE_IMAGE_ICONS = true
local IconAssets = {
    grid = "rbxassetid://100416736645784",
    terminal = "rbxassetid://83339922273770",
    users = "rbxassetid://109865549503800",
    user = "rbxassetid://108602482914096",
    music = "rbxassetid://93124483167157",
    bell = "rbxassetid://128661778431977",
    gear = "rbxassetid://124001049411764",
    chevDown = "rbxassetid://90216448508420",
    scroll = "rbxassetid://78165404317472",
    close = "rbxassetid://74234053830878",
    minus = "rbxassetid://122431501585268",
    search = "rbxassetid://77488641945150",
    play = "rbxassetid://110551675038471",
    pause = "rbxassetid://76238685447134",
    next = "rbxassetid://119532515848566",
    prev = "rbxassetid://119739116323607",
    copy = "rbxassetid://116519625817961",
    logo = "rbxassetid://130412049167483",
    heart = "rbxassetid://127897611810416",
    volume = "rbxassetid://134673761249231",
    external = "rbxassetid://97559152217759",
    send = "rbxassetid://116928751546967",
    power = "rbxassetid://73497508830458",
}

local function MakeIcon(name, parent, size, color, stroke)
    size = size or 16
    color = color or Theme.Text
    local holder = New("Frame", {Name = "Icon_" .. name, Size = UDim2.fromOffset(size, size),
        BackgroundTransparency = 1, Parent = parent})
    local obj = {Frame = holder}
    function obj:Center()
        holder.AnchorPoint = Vector2.new(0.5, 0.5)
        holder.Position = UDim2.fromScale(0.5, 0.5)
        return obj
    end

    local asset = USE_IMAGE_ICONS and IconAssets[name]
    if asset then
        local img = New("ImageLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = asset,
            ImageColor3 = color, Parent = holder})
        function obj:SetColor(c) img.ImageColor3 = c end
        return obj
    end

    local root = New("Frame", {Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), BackgroundTransparency = 1, Parent = holder})
    New("UIScale", {Scale = size / 24, Parent = root})
    local T = stroke or (size <= 13 and 2.1 or 1.75) -- stroke width on the 24 grid (a bit heavier when tiny)
    local fills, strokes = {}, {}

    ---------- drawing primitives ----------
    local function Seg(x1, y1, x2, y2)
        local dx, dy = x2 - x1, y2 - y1
        table.insert(fills, New("Frame", {AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
            Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + T, T),
            Rotation = math.deg(math.atan2(dy, dx)), BackgroundColor3 = color, BorderSizePixel = 0,
            Parent = root}, {Corner(T / 2)}))
    end
    local function Poly(pts, closed)
        for i = 1, #pts - 1 do Seg(pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2]) end
        if closed then Seg(pts[#pts][1], pts[#pts][2], pts[1][1], pts[1][2]) end
    end
    local function Line(x1, y1, x2, y2) Seg(x1, y1, x2, y2) end
    local function Arc(cx, cy, r, a0, a1, n)
        n = n or math.max(6, math.ceil(math.abs(a1 - a0) / 15))
        local pts = {}
        for i = 0, n do
            local a = math.rad(a0 + (a1 - a0) * i / n)
            pts[#pts + 1] = {cx + r * math.cos(a), cy + r * math.sin(a)}
        end
        return pts
    end
    local function Bez(p0, p1, p2, p3, n)
        n = n or 10
        local pts = {}
        for i = 0, n do
            local t = i / n
            local u = 1 - t
            pts[#pts + 1] = {
                u * u * u * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t * t * t * p3[1],
                u * u * u * p0[2] + 3 * u * u * t * p1[2] + 3 * u * t * t * p2[2] + t * t * t * p3[2]}
        end
        return pts
    end
    local function Join(...)
        local out = {}
        for _, list in ipairs({...}) do
            for _, pt in ipairs(list) do out[#out + 1] = pt end
        end
        return out
    end
    -- outline circle / rounded box: stroke is centred on the shape edge like a real vector stroke
    local function Circle(cx, cy, r)
        local f = New("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy),
            Size = UDim2.fromOffset(2 * r - T, 2 * r - T), BackgroundTransparency = 1, Parent = root}, {Corner(r)})
        table.insert(strokes, New("UIStroke", {Color = color, Thickness = T,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f}))
    end
    local function RBox(x, y, w, h, r)
        local f = New("Frame", {Position = UDim2.fromOffset(x + T / 2, y + T / 2),
            Size = UDim2.fromOffset(w - T, h - T), BackgroundTransparency = 1, Parent = root}, {Corner(r or 0)})
        table.insert(strokes, New("UIStroke", {Color = color, Thickness = T,
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = f}))
    end
    local function Fill(x, y, w, h, r)
        table.insert(fills, New("Frame", {Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, h),
            BackgroundColor3 = color, BorderSizePixel = 0, Parent = root}, {Corner(r or 0)}))
    end
    local function Tri(x, y, w, h, left) -- filled triangle built from thin slices
        local n = 16
        local sw = w / n
        for i = 0, n - 1 do
            local frac = left and (i + 1) / n or 1 - i / n
            Fill(x + i * sw, y + (h - h * frac) / 2, sw + 0.6, h * frac)
        end
    end

    ---------- the icons ----------
    local D = {}
    D.grid = function() -- dashboard
        RBox(3, 3, 7, 9, 1.5); RBox(14, 3, 7, 5, 1.5); RBox(14, 12, 7, 9, 1.5); RBox(3, 16, 7, 5, 1.5)
    end
    D.terminal = function()
        Poly({{4, 17}, {10, 11}, {4, 5}}); Line(12, 19, 20, 19)
    end
    D.users = function()
        Circle(9, 7, 4)
        Poly(Join({{3, 21}, {3, 19}}, Arc(7, 19, 4, 180, 270, 6), {{11, 15}}, Arc(11, 19, 4, 270, 360, 6), {{15, 21}}))
        Poly(Arc(17, 7, 4, -104.5, 104.5, 12))
        Poly(Join({{22, 21}, {22, 19}}, Arc(18, 19, 4, 0, -75.5, 8)))
    end
    D.user = function()
        Circle(12, 8, 4)
        Poly(Join({{4, 21}, {4, 19}}, Arc(8, 19, 4, 180, 270, 6), {{16, 15}}, Arc(16, 19, 4, 270, 360, 6), {{20, 21}}))
    end
    D.music = function()
        Poly({{9, 18}, {9, 5}, {21, 3}, {21, 16}}); Circle(6, 18, 3); Circle(18, 16, 3)
    end
    D.bell = function()
        Poly(Join(Arc(12, 8, 6, 180, 360, 12), Bez({18, 8}, {18, 15}, {21, 17}, {21, 17}),
            {{3, 17}}, Bez({3, 17}, {3, 17}, {6, 15}, {6, 8})))
        local c = {}
        for i = -8, 8 do
            local x = 1.7 * i / 8
            c[#c + 1] = {12 + x, 20.07 + math.sqrt(1.94 * 1.94 - x * x)}
        end
        Poly(c)
    end
    D.gear = function()
        local pts = {}
        local function P(a, r)
            pts[#pts + 1] = {12 + r * math.cos(math.rad(a)), 12 + r * math.sin(math.rad(a))}
        end
        for k = 0, 5 do
            local c = k * 60 - 90
            P(c - 30, 7.9)
            P(c - 20, 7.9)
            P(c - 12, 10)
            P(c + 12, 10)
            P(c + 20, 7.9)
        end
        Poly(pts, true)
        Circle(12, 12, 3)
    end
    D.chevDown = function() Poly({{6, 9}, {12, 15}, {18, 9}}) end
    D.close    = function() Line(18, 6, 6, 18); Line(6, 6, 18, 18) end
    D.minus    = function() Line(5, 12, 19, 12) end
    D.search   = function() Circle(11, 11, 8); Line(21, 21, 16.65, 16.65) end
    D.play     = function() Tri(6, 3, 14, 18) end
    D.pause    = function() Fill(6, 4, 4, 16, 1.5); Fill(14, 4, 4, 16, 1.5) end
    D.next     = function() Tri(5, 4, 10, 16); Fill(17, 4, 2.5, 16, 1) end
    D.prev     = function() Fill(4.5, 4, 2.5, 16, 1); Tri(9, 4, 10, 16, true) end
    D.copy     = function()
        RBox(8, 8, 14, 14, 2)
        Poly({{4, 16}, {3.2, 15.7}, {2.3, 14.8}, {2, 14}, {2, 4}, {2.3, 3.2}, {3.2, 2.3}, {4, 2},
            {14, 2}, {14.8, 2.3}, {15.7, 3.2}, {16, 4}, {16, 8}})
    end
    D.logo     = function() Poly({{6, 19}, {6, 5}, {18, 19}, {18, 5}}) end
    D.heart    = function()
        Poly(Join(Arc(7.5, 8, 4.5, 135, 360, 14), Arc(16.5, 8, 4.5, 180, 405, 14), {{12, 20.5}}), true)
    end
    D.volume   = function()
        Poly({{4, 9}, {8, 9}, {13, 5}, {13, 19}, {8, 15}, {4, 15}}, true)
        Poly(Arc(14, 12, 5, -50, 50, 6)); Poly(Arc(14, 12, 9, -50, 50, 8))
    end
    D.external = function()
        Poly({{15, 3}, {21, 3}, {21, 9}}); Line(10, 14, 21, 3)
        Poly(Join({{18, 13}, {18, 19}}, Arc(16, 19, 2, 0, 90, 4), {{5, 21}}, Arc(5, 19, 2, 90, 180, 4),
            {{3, 8}}, Arc(5, 8, 2, 180, 270, 4), {{11, 6}}))
    end
    D.send     = function() Line(22, 2, 11, 13); Poly({{22, 2}, {15, 22}, {11, 13}, {2, 9}}, true) end
    D.power    = function() Line(12, 2, 12, 12); Poly(Arc(12, 13, 9, -45, 225, 24)) end

    D.scroll   = function()
        Line(15, 12, 10, 12); Line(15, 8, 10, 8)
        Poly(Join({{19, 17}, {19, 5}}, Arc(17, 5, 2, 0, -90, 6), {{4, 3}}))
        Poly(Join({{8, 21}, {20, 21}}, Arc(20, 19, 2, 90, 0, 6), {{22, 18}}, Arc(21, 18, 1, 0, -90, 4), {{11, 17}},
            Arc(11, 18, 1, -90, -180, 4), {{10, 19}}, Arc(8, 19, 2, 0, 180, 10), {{6, 5}}, Arc(4, 5, 2, 0, -180, 10),
            {{2, 7}}, Arc(3, 7, 1, 180, 90, 4), {{6, 8}}))
    end
    D.nyx      = function() Poly({{6, 19}, {6, 5}, {18, 19}, {18, 5}}) end

    ;(D[name] or D.close)()

    function obj:SetColor(c)
        for _, f in ipairs(fills) do f.BackgroundColor3 = c end
        for _, s in ipairs(strokes) do s.Color = c end
    end
    return obj
end



-- ================= LOGO =================
-- Upload NyxLogo.png and paste its id here to use the artwork instead of the drawn badge:
local LogoAsset = "rbxassetid://140680000727174" -- e.g. "rbxassetid://123456789"
local function MakeLogo(parent, size)
    local holder = New("Frame", {Name = "NyxLogo", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1, Parent = parent})
    local obj = {Frame = holder}
    function obj:Center()
        holder.AnchorPoint = Vector2.new(0.5, 0.5)
        holder.Position = UDim2.fromScale(0.5, 0.5)
        return obj
    end
    if LogoAsset ~= "" then
        New("ImageLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = LogoAsset, Parent = holder})
        return obj
    end
    local badge = New("Frame", {Name = "Badge", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.White, Parent = holder},
        {Corner(math.floor(size * 0.3)), Gradient(Color3.fromRGB(205, 140, 255), Color3.fromRGB(104, 48, 232), 55),
         Stroke(Color3.fromRGB(235, 210, 255), 1, 0.55)})
    MakeIcon("nyx", badge, size * 0.56, Theme.White, 3.2):Center()
    obj.Badge = badge
    return obj
end

-- ================= SOUND =================
local SoundData -- base64 wav files, filled in near the bottom of this script

local function b64decode(data)
    local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local lookup = {}
    for i = 1, 64 do lookup[chars:byte(i)] = i - 1 end
    local out, n, buffer, bits = {}, 0, 0, 0
    for i = 1, #data do
        local v = lookup[data:byte(i)]
        if v then
            buffer = buffer * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                local p = 2 ^ bits
                n = n + 1
                out[n] = string.char(math.floor(buffer / p) % 256)
                buffer = buffer % p
            end
        end
    end
    return table.concat(out)
end

local SFX_VOL = {click = 0.5, tab = 0.55, on = 0.6, off = 0.6, open = 0.55, close = 0.5, notify = 0.7}
local FALLBACK = {
    click  = "rbxasset://sounds/button.wav",  tab    = "rbxasset://sounds/button.wav",
    on     = "rbxasset://sounds/switch.wav",  off    = "rbxasset://sounds/switch.wav",
    open   = "rbxasset://sounds/snap.mp3",    close  = "rbxasset://sounds/snap.mp3",
    notify = "rbxasset://sounds/electronicpingshort.wav",
}

local function BuildSounds(holder)
    local ids = {}
    if SoundData and writefile and getcustomasset then
        pcall(function() if makefolder and isfolder and not isfolder("NyxUI") then makefolder("NyxUI") end end)
        for name, b64 in pairs(SoundData) do
            local path = "NyxUI/v3_" .. name .. ".wav"
            pcall(function()
                if not (isfile and isfile(path)) then writefile(path, b64decode(b64)) end
                ids[name] = getcustomasset(path)
            end)
        end
    end
    local sounds = {}
    for name, vol in pairs(SFX_VOL) do
        local id = ids[name] or FALLBACK[name]
        if id then sounds[name] = New("Sound", {Name = "Nyx_" .. name, SoundId = id, Volume = vol, Parent = holder}) end
    end
    return sounds
end

-- ================= SHARED WIDGETS =================
local function MakeToggle(parent, state, callback)
    local sw = Button({Silent = true, Fx = false, Size = UDim2.fromOffset(32, 18), AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0), BackgroundColor3 = state and Theme.Accent or Theme.Off, Parent = parent},
        {Corner(9)})
    local knob = New("Frame", {Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Theme.Text,
        Position = state and UDim2.fromOffset(17, 3) or UDim2.fromOffset(3, 3), Parent = sw}, {Corner(6)})
    local T = {}
    function T:Set(v, silent)
        state = v
        Tween(sw, 0.2, {BackgroundColor3 = v and Theme.Accent or Theme.Off})
        Tween(knob, 0.28, {Position = v and UDim2.fromOffset(17, 3) or UDim2.fromOffset(3, 3)}, Enum.EasingStyle.Back)
        if not silent then
            Audio.Play(v and "on" or "off")
            if callback then task.spawn(callback, v) end
        end
    end
    function T:Get() return state end
    sw.MouseButton1Click:Connect(function() T:Set(not state) end)
    return T
end

-- pill with a sliding highlight, like Oblivion's Overview | Server switch
local function Segmented(parent, items, onSelect, segW)
    segW = segW or 72
    local n = #items
    local bar = New("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.fromOffset(n * segW + 6, 28), BackgroundColor3 = Theme.Bg, BackgroundTransparency = 0.3,
        Parent = parent}, {Corner(14), Stroke(Theme.Stroke, 1, 0.55)})
    local ind = New("Frame", {Position = UDim2.fromOffset(3, 3), Size = UDim2.fromOffset(segW, 22),
        BackgroundColor3 = Theme.White, Parent = bar}, {Corner(11), Gradient(Theme.Accent2, Theme.Accent, 90)})
    local S = {Index = 0, Items = {}}
    function S:Select(i, silent)
        if S.Index == i then return end
        S.Index = i
        Tween(ind, 0.32, {Position = UDim2.fromOffset(3 + (i - 1) * segW, 3)}, Enum.EasingStyle.Back)
        for k, it in ipairs(S.Items) do
            local a = k == i
            Tween(it.Label, 0.2, {TextColor3 = a and Theme.Text or Theme.SubText})
            if it.Icon then it.Icon:SetColor(a and Theme.Text or Theme.SubText) end
        end
        if not silent then Audio.Play("tab") end
        if onSelect then onSelect(i, items[i][1]) end
    end
    for i, it in ipairs(items) do
        local b = Button({Fx = false, Silent = true, Size = UDim2.fromOffset(segW, 22),
            Position = UDim2.fromOffset(3 + (i - 1) * segW, 3), BackgroundTransparency = 1, Parent = bar},
            {List(4, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)})
        local icon
        if it[2] then
            icon = MakeIcon(it[2], b, 12, Theme.SubText)
            icon.Frame.LayoutOrder = 1
        end
        local lbl = Label({Text = it[1], Font = Theme.FontBold, TextSize = 10, TextColor3 = Theme.SubText,
            AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22), LayoutOrder = 2, Parent = b})
        S.Items[i] = {Label = lbl, Icon = icon}
        b.MouseButton1Click:Connect(function() S:Select(i) end)
    end
    S:Select(1, true)
    return S
end

-- ================= LIBRARY =================
local Library = {}
Library.__index = Library
Library.IconAssets = IconAssets

function Library:Bind(signal, fn)
    local c = signal:Connect(fn)
    table.insert(self.Connections, c)
    return c
end

function Library:Sfx(name)
    if not self.SfxOn then return end
    local s = self.Sounds and self.Sounds[name]
    if not s then return end
    s.Volume = (SFX_VOL[name] or 0.5) * self.SfxVolume
    s.PlaybackSpeed = 1 + (math.random() - 0.5) * 0.06
    s.TimePosition = 0
    s:Play()
end

-- border with a slowly rotating colour gradient
function Library:GlowStroke(inst, thickness)
    local s = New("UIStroke", {Color = Theme.White, Thickness = thickness or 1.2, Transparency = 0.25,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst})
    local g = New("UIGradient", {Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Theme.Accent), ColorSequenceKeypoint.new(0.35, Theme.Pink),
        ColorSequenceKeypoint.new(0.7, Theme.Blue), ColorSequenceKeypoint.new(1, Theme.Accent)}), Parent = s})
    table.insert(self.Glows, g)
end

function Library.new(opts)
    opts = opts or {}
    local self = setmetatable({}, Library)
    self.Name      = opts.Name or "NYX UI"
    self.ToggleKey = opts.ToggleKey or Enum.KeyCode.RightControl
    self.Prefix    = ";"
    self.Connections, self.Scalers, self.Glows = {}, {}, {}
    self.TabButtons, self.Pages = {}, {}
    self.Commands, self.PlayerActions, self.Scripts, self.Tracks, self.Ctl = {}, {}, {}, {}, {}
    self.Open, self.Visible = false, false
    self.SfxOn, self.SfxVolume = true, 1
    self.FPS = 60
    self.SecOrder = setmetatable({}, {__mode = "k"})

    -- pick a scale that fits this screen (phones get 1.0 or less, big monitors a bit more)
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
    local fitW = (vp.X * 0.92) / BASE_W
    local fitH = (vp.Y * 0.90) / (TOTAL_H + 12)
    local boost = vp.X >= 1300 and 1.25 or 1
    self.AutoScale = math.clamp(math.floor(math.min(fitW, fitH, boost) * 100) / 100, 0.5, 1.25)
    self.Scale = self.AutoScale

    local old = GetParent():FindFirstChild("NyxOblivionUI")
    if old then old:Destroy() end
    self.Gui = New("ScreenGui", {Name = "NyxOblivionUI", ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true, Parent = GetParent()})

    self.SoundHolder = New("Folder", {Name = "NyxSounds", Parent = SoundService})
    self.Sounds = BuildSounds(self.SoundHolder)
    Audio.Play = function(n) self:Sfx(n) end

    self.Gui.Destroying:Connect(function()
        for _, c in ipairs(self.Connections) do pcall(function() c:Disconnect() end) end
        pcall(function() self.SoundHolder:Destroy() end)
        if self.MusicSound then pcall(function() self.MusicSound:Destroy() end) end
        if self.IdleConn then pcall(function() self.IdleConn:Disconnect() end) end
        pcall(function() self:SetFullbright(false) end)
        pcall(function() self:SetWideFov(false) end)
        Audio.Play = function() end
    end)

    -- one soft heartbeat: spins the glow borders + measures FPS
    local acc, frames = 0, 0
    self:Bind(RunService.Heartbeat, function(dt)
        acc += dt; frames += 1
        if acc >= 0.5 then self.FPS = math.floor(frames / acc + 0.5); acc, frames = 0, 0 end
        if self.Visible and Motion.On then
            local r = (os.clock() * 40) % 360
            for _, g in ipairs(self.Glows) do g.Rotation = r end
        end
    end)

    ---------- ROOT (fades + pops as one group) ----------
    self.Root = New("CanvasGroup", {Name = "Root", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4),
        Size = UDim2.fromOffset(BASE_W + PAD * 2, TOTAL_H + PAD * 2), BackgroundTransparency = 1,
        GroupTransparency = 1, Visible = false, Parent = self.Gui})
    self.RootScale = New("UIScale", {Scale = self.Scale, Parent = self.Root})
    table.insert(self.Scalers, self.RootScale)

    ---------- DOCK ----------
    local dock = New("Frame", {Name = "Dock", Position = UDim2.fromOffset(PAD, PAD), Size = UDim2.fromOffset(BASE_W, DOCK_H),
        BackgroundColor3 = Theme.White, Parent = self.Root}, {Corner(17), Gradient(Color3.fromRGB(26, 15, 46), Color3.fromRGB(9, 5, 17), 90)})
    self:GlowStroke(dock, 1.2)
    self.Dock = dock

    local clock = Label({Text = "00:00", Font = Theme.FontBold, TextSize = 12, Position = UDim2.fromOffset(14, 5),
        Size = UDim2.fromOffset(52, 14), Parent = dock})
    local dateL = Label({Text = "", TextSize = 8, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(14, 19),
        Size = UDim2.fromOffset(52, 10), Parent = dock})
    task.spawn(function()
        while self.Gui.Parent do
            clock.Text = os.date("%H:%M"); dateL.Text = os.date("%a, %b %d")
            task.wait(1)
        end
    end)
    New("Frame", {Size = UDim2.fromOffset(1, 16), Position = UDim2.fromOffset(66, 9), BackgroundColor3 = Theme.Stroke,
        BackgroundTransparency = 0.5, BorderSizePixel = 0, Parent = dock})

    self.TabHolder = New("Frame", {Position = UDim2.fromOffset(72, 0), Size = UDim2.new(1, -108, 1, 0),
        BackgroundTransparency = 1, Parent = dock}, {
        List(2, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)})

    self.Chevron = Button({Silent = true, Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, -30, 0.5, -12),
        BackgroundColor3 = Theme.Row, Parent = dock}, {Corner(9), Stroke()})
    self.ChevronIcon = MakeIcon("chevDown", self.Chevron, 13, Theme.Text):Center()
    self.Chevron.MouseButton1Click:Connect(function() self:SetVisible(false) end)

    ---------- PANEL ----------
    self.Panel = New("Frame", {Name = "Panel", Position = UDim2.fromOffset(PAD, PAD + DOCK_H + 6), Size = UDim2.fromOffset(BASE_W, 0),
        BackgroundColor3 = Theme.White, ClipsDescendants = true, Visible = false, Parent = self.Root},
        {Corner(18), Gradient(Color3.fromRGB(24, 14, 42), Color3.fromRGB(8, 5, 14), 125)})
    self:GlowStroke(self.Panel, 1.2)
    local glow = New("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0, Parent = self.Panel}, {Corner(18)})
    New("UIGradient", {Color = ColorSequence.new(Theme.Accent), Rotation = 40, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.6, 1), NumberSequenceKeypoint.new(1, 1)}), Parent = glow})
    local glow2 = New("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Pink, BorderSizePixel = 0, Parent = self.Panel}, {Corner(18)})
    New("UIGradient", {Color = ColorSequence.new(Theme.Pink), Rotation = 220, Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.93), NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1)}), Parent = glow2})
    self.PageHolder = New("Frame", {Position = UDim2.fromOffset(10, 10), Size = UDim2.new(1, -20, 1, -20),
        BackgroundTransparency = 1, Parent = self.Panel})

    ---------- DRAG (by the dock) ----------
    local dragging, dragStart, startPos
    dock.InputBegan:Connect(function(i)
        if IsPress(i) then dragging, dragStart, startPos = true, i.Position, self.Root.Position end
    end)
    self:Bind(UserInputService.InputChanged, function(i)
        if dragging and IsMove(i) then
            local d = i.Position - dragStart
            self.Root.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end)
    self:Bind(UserInputService.InputEnded, function(i) if IsPress(i) then dragging = false end end)

    ---------- "OPEN NYX UI" PILL (shows only while the menu is hidden, like Oblivion) ----------
    self.PillEnabled = true
    self.Pill = New("CanvasGroup", {Name = "Pill", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4),
        Size = UDim2.fromOffset(150 + PAD * 2, 30 + PAD * 2), BackgroundTransparency = 1, GroupTransparency = 1, Visible = false,
        Parent = self.Gui})
    self.PillScale = New("UIScale", {Scale = self.Scale, Parent = self.Pill})
    table.insert(self.Scalers, self.PillScale)
    local pillBtn = Button({Silent = true, Position = UDim2.fromOffset(PAD, PAD), Size = UDim2.fromOffset(150, 30),
        BackgroundColor3 = Theme.White, Parent = self.Pill}, {Corner(15), Gradient(Color3.fromRGB(28, 14, 54), Color3.fromRGB(9, 5, 18), 90)})
    self:GlowStroke(pillBtn, 1.2)
    local chevBox = New("Frame", {Size = UDim2.fromOffset(22, 22), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = Theme.Row,
        Parent = pillBtn}, {Corner(8), Stroke()})
    local pillChev = MakeIcon("chevDown", chevBox, 12, Theme.Text):Center()
    pillChev.Frame.Rotation = 180
    New("Frame", {Size = UDim2.fromOffset(1, 14), Position = UDim2.fromOffset(34, 8), BackgroundColor3 = Theme.Stroke,
        BackgroundTransparency = 0.4, BorderSizePixel = 0, Parent = pillBtn})
    MakeLogo(pillBtn, 18).Frame.Position = UDim2.fromOffset(42, 6)
    Label({Text = 'Open <font color="#c084fc">Nyx UI</font>', RichText = true, Font = Theme.FontBold, TextSize = 11,
        Position = UDim2.fromOffset(66, 0), Size = UDim2.new(1, -70, 1, 0), Parent = pillBtn})
    local fd, fs, fp, moved
    pillBtn.InputBegan:Connect(function(i)
        if IsPress(i) then fd, fs, fp, moved = true, i.Position, self.Pill.Position, false end
    end)
    self:Bind(UserInputService.InputChanged, function(i)
        if fd and IsMove(i) then
            local d = i.Position - fs
            if d.Magnitude > 6 then moved = true end
            if moved then self.Pill.Position = UDim2.new(fp.X.Scale, fp.X.Offset + d.X, fp.Y.Scale, fp.Y.Offset + d.Y) end
        end
    end)
    self:Bind(UserInputService.InputEnded, function(i)
        if fd and IsPress(i) then
            fd = false
            if not moved then self:SetVisible(true) end
        end
    end)

    ---------- KEYS ----------
    self:Bind(UserInputService.InputBegan, function(i, gp)
        if gp then return end
        if i.KeyCode == self.ToggleKey then
            self:SetVisible(not self.Visible)
        elseif i.UserInputType == Enum.UserInputType.Keyboard and self.CommandBox
            and UserInputService:GetStringForKeyCode(i.KeyCode) == self.Prefix then
            self:SetVisible(true); self:SelectTab("Cmds")
            task.defer(function() self.CommandBox:CaptureFocus(); task.wait(); self.CommandBox.Text = "" end)
        end
    end)

    ---------- TOASTS ----------
    self.ToastHolder = New("Frame", {AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(220, 300),
        Position = UDim2.new(1, -10, 1, -10), BackgroundTransparency = 1, Parent = self.Gui},
        {List(6, nil, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Bottom)})
    return self
end

-- ================= WINDOW STATE =================
function Library:SetVisible(v)
    if self.Visible == v then return end
    self.Visible = v
    self:Sfx(v and "open" or "close")
    if v then
        self.Root.Position = self.Pill.Position
        Tween(self.Pill, 0.18, {GroupTransparency = 1})
        Tween(self.PillScale, 0.18, {Scale = self.Scale * 0.9})
        task.delay(0.2, function() if self.Visible then self.Pill.Visible = false end end)
        self.Root.Visible = true
        self.RootScale.Scale = self.Scale * 0.9
        Tween(self.Root, 0.3, {GroupTransparency = 0})
        Tween(self.RootScale, 0.45, {Scale = self.Scale}, Enum.EasingStyle.Back)
    else
        self.Pill.Position = self.Root.Position
        Tween(self.Root, 0.2, {GroupTransparency = 1})
        Tween(self.RootScale, 0.2, {Scale = self.Scale * 0.94})
        task.delay(0.2, function()
            if self.Visible then return end
            self.Root.Visible = false
            if self.PillEnabled then
                self.Pill.Visible = true
                self.PillScale.Scale = self.Scale * 0.9
                Tween(self.Pill, 0.3, {GroupTransparency = 0})
                Tween(self.PillScale, 0.45, {Scale = self.Scale}, Enum.EasingStyle.Back)
            end
        end)
    end
end

function Library:SetOpen(v, silent)
    if self.Open == v then return end
    self.Open = v
    if not silent then self:Sfx(v and "open" or "close") end
    if v then
        self.Panel.Visible = true
        Tween(self.Panel, 0.42, {Size = UDim2.fromOffset(BASE_W, PANEL_H)})
    else
        Tween(self.Panel, 0.28, {Size = UDim2.fromOffset(BASE_W, 0)})
        task.delay(0.29, function() if not self.Open then self.Panel.Visible = false end end)
    end
end

function Library:SetScale(v)
    self.Scale = math.clamp(v, 0.4, 1.6)
    for _, s in ipairs(self.Scalers) do s.Scale = self.Scale end
end

function Library:ResetPosition()
    Tween(self.Root, 0.4, {Position = UDim2.new(0.5, 0, 0, 4)}, Enum.EasingStyle.Back)
end

function Library:Start()
    self.Visible = true
    local splash = New("CanvasGroup", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0), Size = UDim2.fromOffset(120, 120),
        BackgroundTransparency = 1, GroupTransparency = 1, Parent = self.Gui})
    local sc = New("UIScale", {Scale = 0.4, Parent = splash})
    local lg = MakeLogo(splash, 64):Center()
    if lg.Badge then self:GlowStroke(lg.Badge, 2) end
    self:Sfx("open")
    Tween(splash, 0.35, {GroupTransparency = 0})
    Tween(sc, 0.6, {Scale = 1}, Enum.EasingStyle.Back)
    task.delay(0.95, function()
        Tween(splash, 0.35, {GroupTransparency = 1})
        Tween(sc, 0.35, {Scale = 1.5})
        self.Root.Visible = true
        self.RootScale.Scale = self.Scale * 0.85
        self.Root.Position = UDim2.new(0.5, 0, 0, -20)
        Tween(self.Root, 0.55, {GroupTransparency = 0, Position = UDim2.new(0.5, 0, 0, 4)}, Enum.EasingStyle.Back)
        Tween(self.RootScale, 0.6, {Scale = self.Scale}, Enum.EasingStyle.Back)
        task.delay(0.5, function() splash:Destroy() end)
    end)
end

function Library:Notify(title, text, duration)
    duration = duration or 3
    self:Sfx("notify")
    local slot = New("Frame", {Size = UDim2.fromOffset(210, 46), BackgroundTransparency = 1, Parent = self.ToastHolder})
    local toast = New("Frame", {Size = UDim2.fromScale(1, 1), Position = UDim2.new(1.2, 0, 0, 0), BackgroundColor3 = Theme.Bg,
        BackgroundTransparency = 0.06, ClipsDescendants = true, Parent = slot}, {Corner(12), Stroke(Theme.Accent, 1.2, 0.3)})
    MakeLogo(toast, 24).Frame.Position = UDim2.fromOffset(10, 11)
    Label({Text = title, Font = Theme.FontBold, TextSize = 11, Position = UDim2.fromOffset(42, 7), Size = UDim2.new(1, -50, 0, 15),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = toast})
    Label({Text = text, TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(42, 22), Size = UDim2.new(1, -50, 0, 13),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = toast})
    local bar = New("Frame", {Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, 1, -2), BackgroundColor3 = Theme.Accent2,
        BorderSizePixel = 0, Parent = toast})
    Tween(toast, 0.45, {Position = UDim2.new(0, 0, 0, 0)}, Enum.EasingStyle.Back)
    TweenService:Create(bar, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Size = UDim2.new(0, 0, 0, 2)}):Play()
    task.delay(duration, function()
        Tween(toast, 0.3, {Position = UDim2.new(1.2, 0, 0, 0)})
        task.wait(0.32)
        slot:Destroy()
    end)
end

-- ================= FLOATING WINDOWS =================
function Library:AddWindow(title, w, h)
    local win = New("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(w or 220, h or 160),
        Position = UDim2.new(0.5, 0, 0.5, 0), BackgroundColor3 = Theme.White, ClipsDescendants = true, Visible = false,
        ZIndex = 10, Parent = self.Gui}, {Corner(12), Gradient(Color3.fromRGB(26, 15, 46), Color3.fromRGB(9, 5, 17), 120)})
    self:GlowStroke(win, 1.2)
    local sc = New("UIScale", {Scale = self.Scale, Parent = win})
    table.insert(self.Scalers, sc)
    local head = New("Frame", {Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, ZIndex = 11, Parent = win})
    Label({Text = title, Font = Theme.FontBold, Position = UDim2.fromOffset(10, 0), Size = UDim2.new(1, -60, 1, 0), ZIndex = 11, Parent = head})
    local body = New("Frame", {Position = UDim2.fromOffset(6, 28), Size = UDim2.new(1, -12, 1, -34), BackgroundTransparency = 1,
        ZIndex = 11, Parent = win})
    local W = {Frame = win, Body = body}
    local minimized, full = false, win.Size
    local minB = Button({Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -42, 0, 4), BackgroundTransparency = 1,
        ZIndex = 12, Parent = head}, {Corner(9)})
    local clsB = Button({Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -22, 0, 4), BackgroundTransparency = 1,
        ZIndex = 12, Parent = head}, {Corner(9)})
    MakeIcon("minus", minB, 11, Theme.SubText):Center()
    MakeIcon("close", clsB, 11, Theme.SubText):Center()
    local lib = self
    function W:Show()
        win.Visible = true
        sc.Scale = lib.Scale * 0.85
        Tween(sc, 0.4, {Scale = lib.Scale}, Enum.EasingStyle.Back)
    end
    function W:Hide()
        Tween(sc, 0.18, {Scale = lib.Scale * 0.88})
        task.delay(0.19, function() win.Visible = false; sc.Scale = lib.Scale end)
    end
    function W:Toggle() if win.Visible then W:Hide() else W:Show() end end
    minB.MouseButton1Click:Connect(function()
        minimized = not minimized
        body.Visible = not minimized
        Tween(win, 0.25, {Size = minimized and UDim2.fromOffset(full.X.Offset, 26) or full}, Enum.EasingStyle.Back)
    end)
    clsB.MouseButton1Click:Connect(function() W:Hide() end)
    local d, ds, sp
    head.InputBegan:Connect(function(i) if IsPress(i) then d, ds, sp = true, i.Position, win.Position end end)
    self:Bind(UserInputService.InputChanged, function(i)
        if d and IsMove(i) then
            local delta = i.Position - ds
            win.Position = UDim2.new(sp.X.Scale, sp.X.Offset + delta.X, sp.Y.Scale, sp.Y.Offset + delta.Y)
        end
    end)
    self:Bind(UserInputService.InputEnded, function(i) if IsPress(i) then d = false end end)
    return W
end

-- ================= TABS =================
function Library:SelectTab(name, silent)
    if self.Current == name then
        if not silent then self:Sfx("tab") end
        self:SetOpen(not self.Open, true)
        return
    end
    self.Current = name
    for n, b in pairs(self.TabButtons) do
        local active = n == name
        b.Icon:SetColor(active and Theme.Accent2 or Theme.SubText)
        b.Label.Visible = active
        if active then
            b.Label.TextTransparency = 1
            Tween(b.Label, 0.3, {TextTransparency = 0})
        end
        Tween(b.Button, 0.2, {BackgroundTransparency = active and 0.86 or 1})
    end
    for n, page in pairs(self.Pages) do
        if n == name then
            page.Visible = true
            page.GroupTransparency = 1
            page.Position = UDim2.fromOffset(12, 0)
            Tween(page, 0.32, {GroupTransparency = 0, Position = UDim2.fromOffset(0, 0)})
        else
            page.Visible = false
        end
    end
    if not silent then self:Sfx("tab") end
    if not self.Open then self:SetOpen(true, true) end
end

function Library:AddTab(name, icon, opts)
    opts = opts or {}
    local lib = self
    local btn = Button({Fx = false, Silent = true, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 24),
        BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, Parent = self.TabHolder},
        {Corner(12), Pad(6, 0), List(4, Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center)})
    local ic = MakeIcon(icon, btn, 14, Theme.SubText)
    ic.Frame.LayoutOrder = 1
    local lbl = Label({Text = name, Font = Theme.FontBold, TextSize = 10, TextColor3 = Theme.Text,
        AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 14), Visible = false, LayoutOrder = 2, Parent = btn})
    btn.MouseButton1Click:Connect(function() self:SelectTab(name) end)
    btn.MouseEnter:Connect(function() if self.Current ~= name then Tween(btn, 0.15, {BackgroundTransparency = 0.93}) end end)
    btn.MouseLeave:Connect(function() if self.Current ~= name then Tween(btn, 0.2, {BackgroundTransparency = 1}) end end)
    self.TabButtons[name] = {Button = btn, Icon = ic, Label = lbl}

    local page = New("CanvasGroup", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = self.PageHolder})
    local top = New("Frame", {Name = "Top", Size = UDim2.new(1, -34, 0, 28), BackgroundTransparency = 1, Parent = page})
    local closeB = Button({Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -26, 0, 1), BackgroundColor3 = Theme.Row,
        BackgroundTransparency = 0.25, Silent = true, Parent = page}, {Corner(13), Stroke(Theme.Stroke, 1, 0.55)})
    MakeIcon("close", closeB, 11, Theme.SubText):Center()
    closeB.MouseButton1Click:Connect(function() lib:SetOpen(false) end)

    local footerH = opts.Footer and 36 or 0
    local scroll = New("ScrollingFrame", {Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 1, -36 - footerH),
        BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.Accent,
        AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = page}, {List(8), Pad(0, 0, 4, 6)})
    local footer
    if opts.Footer then
        footer = New("Frame", {Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -30), BackgroundColor3 = Theme.Bg,
            BackgroundTransparency = 0.25, Parent = page}, {Corner(15), Stroke(Theme.Stroke, 1, 0.55)})
    end
    self.Pages[name] = page

    local Tab = {Page = page, Top = top, Scroll = scroll, Footer = footer}

    function Tab:AddCard(h, parent)
        return New("Frame", {Size = UDim2.new(1, 0, 0, h), BackgroundColor3 = Theme.Bg, BackgroundTransparency = 0.4,
            Parent = parent or scroll}, {Corner(12), Stroke(Theme.Stroke, 1, 0.6)})
    end

    -- grouped rows with hairline dividers (the "clean" Oblivion list look)
    function Tab:AddSection(title, parent)
        local wrap = New("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
            Parent = parent or scroll}, {List(4)})
        if title then
            Label({Text = title, Font = Theme.FontBold, TextSize = 10, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 13),
                LayoutOrder = 0, Parent = wrap, Position = UDim2.fromOffset(2, 0)})
        end
        local box = New("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = Theme.Bg,
            BackgroundTransparency = 0.4, LayoutOrder = 1, Parent = wrap},
            {Corner(12), Stroke(Theme.Stroke, 1, 0.6), List(0, nil, Enum.HorizontalAlignment.Center)})
        lib.SecOrder[parent or scroll] = (lib.SecOrder[parent or scroll] or 0) + 1
        wrap.LayoutOrder = lib.SecOrder[parent or scroll]
        local S = {Box = box, Wrap = wrap}
        local n = 0
        local function NewRow(text, desc, h)
            n += 1
            if n > 1 then
                local hl = Hair(box, n * 2 - 2)
                hl.Size = UDim2.new(1, -24, 0, 1)
            end
            local row = New("Frame", {Size = UDim2.new(1, 0, 0, h or 36), BackgroundTransparency = 1, LayoutOrder = n * 2 - 1, Parent = box})
            Label({Text = text, Font = Theme.FontBold, Position = UDim2.fromOffset(12, desc and 5 or 0),
                Size = UDim2.new(0.55, 0, 0, desc and 15 or (h or 36)), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row})
            if desc then
                Label({Text = desc, TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(12, 20),
                    Size = UDim2.new(0.6, 0, 0, 12), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row})
            end
            return row
        end
        S.NewRow = NewRow

        function S:AddButton(text, desc, btnText, callback, danger)
            local row = NewRow(text, desc)
            local b = Button({Text = btnText or "Run", TextSize = 10, Size = UDim2.fromOffset(58, 22), AnchorPoint = Vector2.new(1, 0.5),
                Position = UDim2.new(1, -10, 0.5, 0), BackgroundColor3 = danger and Theme.Danger or Theme.Accent, Parent = row}, {Corner(8)})
            b.MouseButton1Click:Connect(function() if callback then task.spawn(callback) end end)
            return b
        end

        function S:AddToggle(text, desc, default, callback)
            return MakeToggle(NewRow(text, desc), default or false, callback)
        end

        -- onRelease = true: callback fires when you let go (used for UI scale)
        function S:AddSlider(text, desc, min, max, default, callback, onRelease, suffix)
            local row = NewRow(text, desc)
            suffix = suffix or ""
            local value = default or min
            local track = New("Frame", {Size = UDim2.new(0.25, 0, 0, 4), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.52, 0, 0.5, 0),
                BackgroundColor3 = Theme.Off, Parent = row}, {Corner(2)})
            local fill = New("Frame", {Size = UDim2.fromScale((value - min) / (max - min), 1), BackgroundColor3 = Theme.White, Parent = track},
                {Corner(2), Gradient(Theme.Accent, Theme.Accent2, 0)})
            local knob = New("Frame", {Size = UDim2.fromOffset(10, 10), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
                BackgroundColor3 = Theme.Text, Parent = fill}, {Corner(5)})
            local box = Label({Text = value .. suffix, Font = Theme.FontBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Center,
                Size = UDim2.fromOffset(38, 20), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Parent = row})
            box.BackgroundTransparency = 0.2; box.BackgroundColor3 = Theme.Row; Corner(7).Parent = box
            local hit = New("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24),
                Position = UDim2.new(0, 0, 0.5, -12), Parent = track})
            local dragging, lastTick = false, 0
            local function update(x)
                local a = math.clamp((x - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
                local nv = math.floor(min + (max - min) * a + 0.5)
                if nv ~= value then
                    value = nv
                    if os.clock() - lastTick > 0.05 then lastTick = os.clock(); Audio.Play("click") end
                end
                Tween(fill, 0.08, {Size = UDim2.fromScale(a, 1)})
                box.Text = value .. suffix
                if callback and not onRelease then task.spawn(callback, value) end
            end
            hit.InputBegan:Connect(function(i)
                if IsPress(i) then dragging = true; Tween(knob, 0.15, {Size = UDim2.fromOffset(14, 14)}, Enum.EasingStyle.Back); update(i.Position.X) end
            end)
            lib:Bind(UserInputService.InputChanged, function(i) if dragging and IsMove(i) then update(i.Position.X) end end)
            lib:Bind(UserInputService.InputEnded, function(i)
                if dragging and IsPress(i) then
                    dragging = false
                    Tween(knob, 0.2, {Size = UDim2.fromOffset(10, 10)}, Enum.EasingStyle.Back)
                    if callback and onRelease then task.spawn(callback, value) end
                end
            end)
            local Sl = {}
            function Sl:Set(v)
                value = math.clamp(v, min, max)
                Tween(fill, 0.2, {Size = UDim2.fromScale((value - min) / (max - min), 1)})
                box.Text = value .. suffix
            end
            return Sl
        end

        function S:AddDropdown(text, desc, options, default, callback)
            local row = NewRow(text, desc)
            local idx = table.find(options, default) or 1
            local b = Button({Text = options[idx], TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(84, 22),
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), BackgroundColor3 = Theme.Row,
                Parent = row}, {Corner(8), Stroke(Theme.Stroke, 1, 0.5), Pad(9, 0, 22, 0)})
            local dd = MakeIcon("chevDown", b, 11, Theme.SubText)
            dd.Frame.AnchorPoint = Vector2.new(1, 0.5)
            dd.Frame.Position = UDim2.new(1, 16, 0.5, 0)
            b.MouseButton1Click:Connect(function()
                idx = idx % #options + 1
                b.Text = options[idx]
                Tween(dd.Frame, 0.25, {Rotation = idx * 180}, Enum.EasingStyle.Back)
                if callback then task.spawn(callback, options[idx]) end
            end)
        end

        function S:AddKeybind(text, desc, default, callback)
            local row = NewRow(text, desc)
            local b = Button({Text = default.Name, TextSize = 10, TextColor3 = Theme.Accent2, Size = UDim2.fromOffset(84, 22),
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), BackgroundColor3 = Theme.Row, Parent = row},
                {Corner(8), Stroke(Theme.Accent, 1, 0.45)})
            b.MouseButton1Click:Connect(function()
                b.Text = "press a key..."
                local c; c = UserInputService.InputBegan:Connect(function(i)
                    if i.UserInputType == Enum.UserInputType.Keyboard then
                        b.Text = i.KeyCode.Name; c:Disconnect()
                        Audio.Play("on")
                        if callback then task.spawn(callback, i.KeyCode) end
                    end
                end)
            end)
        end

        -- read-only value that refreshes every second (tap to copy when `copy` is given)
        function S:AddValue(text, getter, copy)
            local row = NewRow(text, nil)
            local v = Label({Text = "", TextSize = 10, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right,
                AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.new(0.42, 0, 0, 14),
                TextTruncate = Enum.TextTruncate.AtEnd, Parent = row})
            local function upd() v.Text = tostring(getter()) end
            upd()
            task.spawn(function()
                while lib.Gui.Parent and row.Parent do pcall(upd); task.wait(1) end
            end)
            if copy then
                local hit = Button({Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = row})
                hit.MouseButton1Click:Connect(function()
                    lib:Notify("Copied", text .. " copied to clipboard", 2)
                    CopyText(tostring(copy()))
                end)
            end
            return v
        end

        function S:AddLabel(text)
            local row = NewRow(text, nil, 30)
            return row
        end
        return S
    end
    return Tab
end

-- ================= HOME =================
function Library:SetAntiIdle(on)
    if on and not self.IdleConn then
        self.IdleConn = LocalPlayer.Idled:Connect(function()
            pcall(function()
                local vu = game:GetService("VirtualUser")
                vu:CaptureController(); vu:ClickButton2(Vector2.new())
            end)
        end)
    elseif not on and self.IdleConn then
        self.IdleConn:Disconnect(); self.IdleConn = nil
    end
end

function Library:SetFullbright(on)
    if on and not self.SavedLight then
        self.SavedLight = {Lighting.Brightness, Lighting.ClockTime, Lighting.GlobalShadows, Lighting.Ambient}
        Lighting.Brightness, Lighting.ClockTime, Lighting.GlobalShadows = 2, 14, false
        Lighting.Ambient = Color3.fromRGB(170, 170, 170)
    elseif not on and self.SavedLight then
        Lighting.Brightness, Lighting.ClockTime, Lighting.GlobalShadows, Lighting.Ambient = unpack(self.SavedLight)
        self.SavedLight = nil
    end
end

function Library:SetWideFov(on)
    local cam = workspace.CurrentCamera
    if on and not self.SavedFov then
        self.SavedFov = cam.FieldOfView
        Tween(cam, 0.4, {FieldOfView = 100})
    elseif not on and self.SavedFov then
        Tween(cam, 0.4, {FieldOfView = self.SavedFov})
        self.SavedFov = nil
    end
end

function Library:BuildHome()
    local lib = self
    local tab = self:AddTab("Home", "grid")
    local scroll = tab.Scroll

    local ov = New("CanvasGroup", {Name = "Overview", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, LayoutOrder = 1, Parent = scroll}, {List(8)})
    local sv = New("CanvasGroup", {Name = "Server", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Visible = false, LayoutOrder = 1, Parent = scroll}, {List(8)})
    Segmented(tab.Top, {{"Overview", "grid"}, {"Server", "users"}}, function(i)
        ov.Visible, sv.Visible = i == 1, i == 2
        local p = i == 1 and ov or sv
        p.GroupTransparency = 1
        Tween(p, 0.3, {GroupTransparency = 0})
    end, 70)

    ---------- profile ----------
    local prof = New("Frame", {Size = UDim2.new(1, 0, 0, 52), BackgroundTransparency = 1, LayoutOrder = 1, Parent = ov})
    local av = New("ImageLabel", {Size = UDim2.fromOffset(38, 38), Position = UDim2.fromOffset(2, 7), BackgroundColor3 = Theme.Row,
        Parent = prof}, {Corner(19), Stroke(Theme.Accent2, 1.5, 0.1)})
    task.spawn(function()
        local ok, img = pcall(Players.GetUserThumbnailAsync, Players, LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        if ok and av.Parent then av.Image = img end
    end)
    New("Frame", {Size = UDim2.fromOffset(9, 9), Position = UDim2.fromOffset(31, 33), BackgroundColor3 = Theme.Good, Parent = prof},
        {Corner(5), Stroke(Theme.Bg, 1.5, 0)})
    Label({Text = LocalPlayer.DisplayName, Font = Theme.FontBold, TextSize = 12, Position = UDim2.fromOffset(48, 10), Size = UDim2.fromOffset(90, 16),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = prof})
    Label({Text = "@" .. LocalPlayer.Name, TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(48, 27), Size = UDim2.fromOffset(90, 12),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = prof})
    local statLabels = {}
    for i, def in ipairs({{"Friends", Theme.Text}, {"Online", Theme.Good}, {"Offline", Theme.Text}, {"In game", Theme.Text}}) do
        local x = 140 + (i - 1) * 36
        statLabels[i] = Label({Text = "-", Font = Theme.FontBold, TextSize = 14, TextColor3 = def[2], TextXAlignment = Enum.TextXAlignment.Center,
            Position = UDim2.fromOffset(x, 8), Size = UDim2.fromOffset(36, 20), Parent = prof})
        Label({Text = def[1], TextSize = 8, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center,
            Position = UDim2.fromOffset(x, 29), Size = UDim2.fromOffset(36, 11), Parent = prof})
    end
    task.spawn(function()
        local total, online, ingame = 0, 0, 0
        pcall(function()
            local pages = Players:GetFriendsAsync(LocalPlayer.UserId)
            while true do
                for _ in ipairs(pages:GetCurrentPage()) do total += 1 end
                if pages.IsFinished then break end
                pages:AdvanceToNextPageAsync()
            end
        end)
        pcall(function() online = #LocalPlayer:GetFriendsOnline(200) end)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                local ok, f = pcall(LocalPlayer.IsFriendsWith, LocalPlayer, p.UserId)
                if ok and f then ingame += 1 end
            end
        end
        Count(statLabels[1], total); Count(statLabels[2], online)
        Count(statLabels[3], math.max(0, total - online)); Count(statLabels[4], ingame)
    end)
    Hair(ov, 2)

    ---------- game ----------
    local gc = New("Frame", {Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1, LayoutOrder = 3, Parent = ov})
    local thumb = New("ImageLabel", {Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(2, 6), BackgroundColor3 = Theme.Row,
        Image = "rbxthumb://type=GameIcon&id=" .. game.GameId .. "&w=150&h=150", Parent = gc}, {Corner(10), Stroke(Theme.Stroke, 1, 0.5)})
    local gname = Label({Text = "Loading...", Font = Theme.FontBold, TextSize = 12, Position = UDim2.fromOffset(62, 8), Size = UDim2.new(1, -172, 0, 16),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = gc})
    local gby = Label({Text = "", TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(62, 25), Size = UDim2.new(1, -172, 0, 12),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = gc})
    local live = New("Frame", {Size = UDim2.fromOffset(6, 6), Position = UDim2.fromOffset(62, 44), BackgroundColor3 = Theme.Good, Parent = gc}, {Corner(3)})
    Label({Text = "Live", Font = Theme.FontBold, TextSize = 9, TextColor3 = Theme.Good, Position = UDim2.fromOffset(73, 40), Size = UDim2.fromOffset(40, 14), Parent = gc})
    task.spawn(function()
        while lib.Gui.Parent do
            Tween(live, 0.9, {BackgroundTransparency = 0.6}, Enum.EasingStyle.Sine)
            task.wait(0.9)
            Tween(live, 0.9, {BackgroundTransparency = 0}, Enum.EasingStyle.Sine)
            task.wait(0.9)
        end
    end)
    task.spawn(function()
        local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
        if ok and info then
            gname.Text = info.Name
            gby.Text = "by " .. ((info.Creator and info.Creator.Name) or "?")
        end
    end)
    local function SideBtn(y, text, iconName, color, cb)
        local b = Button({Text = text, TextSize = 9, TextColor3 = color or Theme.Text, Size = UDim2.fromOffset(100, 18), AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, y), BackgroundColor3 = Theme.Row, BackgroundTransparency = 0.35, Parent = gc},
            {Corner(9), Stroke(color or Theme.Stroke, 1, color and 0.5 or 0.6), Pad(18, 0, 4, 0)})
        local ii = MakeIcon(iconName, b, 10, color or Theme.SubText)
        ii.Frame.AnchorPoint = Vector2.new(0, 0.5)
        ii.Frame.Position = UDim2.new(0, -14, 0.5, 0)
        b.MouseButton1Click:Connect(cb)
    end
    SideBtn(2, "Copy join script", "send", nil, function()
        local s = ('game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s")'):format(game.PlaceId, game.JobId)
        lib:Notify("Join script", CopyText(s) and "Copied to clipboard" or "Clipboard not supported", 2)
    end)
    SideBtn(22, "Server ID", "copy", nil, function()
        lib:Notify("Server ID", CopyText(game.JobId) and "Copied to clipboard" or game.JobId, 2)
    end)
    SideBtn(42, "Rejoin", "power", Theme.Danger, function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end)
    Hair(ov, 4)

    ---------- quick toggles ----------
    local qrow = New("Frame", {Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, LayoutOrder = 5, Parent = ov},
        {List(6, Enum.FillDirection.Horizontal)})
    local function Chip(name, fn)
        local on = false
        local st = Stroke(Theme.Stroke, 1, 0.5)
        local b = Button({Text = name, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1 / 3, -4, 1, 0),
            BackgroundColor3 = Theme.Row, BackgroundTransparency = 0.3, Silent = true, Parent = qrow}, {Corner(13), st, Pad(11, 0)})
        local dot = New("Frame", {Size = UDim2.fromOffset(7, 7), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
            BackgroundColor3 = Theme.Off, Parent = b}, {Corner(4)})
        b.MouseButton1Click:Connect(function()
            on = not on
            Audio.Play(on and "on" or "off")
            Tween(dot, 0.25, {BackgroundColor3 = on and Theme.Good or Theme.Off})
            Tween(st, 0.25, {Color = on and Theme.Good or Theme.Stroke, Transparency = on and 0.25 or 0.5})
            task.spawn(fn, on)
        end)
    end
    Chip("Anti Idle", function(on) lib:SetAntiIdle(on) end)
    Chip("Fullbright", function(on) lib:SetFullbright(on) end)
    Chip("Wide FOV", function(on) lib:SetWideFov(on) end)

    ---------- discord ----------
    local dc = New("Frame", {Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Theme.Row, BackgroundTransparency = 0.5, LayoutOrder = 6, Parent = ov},
        {Corner(12), Stroke(Theme.Stroke, 1, 0.6)})
    local dcircle = New("Frame", {Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(8, 7), BackgroundColor3 = Color3.fromRGB(88, 101, 242),
        Parent = dc}, {Corner(12)})
    MakeIcon("users", dcircle, 13, Theme.White):Center()
    Label({Text = "Join our Discord", Font = Theme.FontBold, TextSize = 11, Position = UDim2.fromOffset(40, 5), Size = UDim2.new(1, -120, 0, 15), Parent = dc})
    self.DiscordLabel = Label({Text = "discord.gg/yourinvite", TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(40, 20),
        Size = UDim2.new(1, -120, 0, 12), TextTruncate = Enum.TextTruncate.AtEnd, Parent = dc})
    local jb = Button({Text = "Join", TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(54, 22),
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), BackgroundColor3 = Theme.Accent, Parent = dc}, {Corner(11), Pad(11, 0, 0, 0)})
    local je = MakeIcon("external", jb, 10, Theme.Text)
    je.Frame.Position = UDim2.fromOffset(22, 6)
    jb.MouseButton1Click:Connect(function()
        lib:Notify("Discord", CopyText(lib.DiscordLabel.Text) and "Invite copied" or lib.DiscordLabel.Text, 3)
    end)

    ---------- server tab ----------
    local s1 = tab:AddSection("Server", sv)
    s1:AddValue("Players", function() return #Players:GetPlayers() .. " / " .. Players.MaxPlayers end)
    s1:AddValue("Ping", function()
        return math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()) .. " ms"
    end)
    s1:AddValue("FPS", function() return lib.FPS end)
    s1:AddValue("Uptime", function() return FmtTime(workspace.DistributedGameTime) end)
    s1:AddValue("Place ID", function() return game.PlaceId end, function() return game.PlaceId end)
    s1:AddValue("Job ID", function() return game.JobId ~= "" and game.JobId or "Studio" end, function() return game.JobId end)
    local s2 = tab:AddSection("Actions", sv)
    s2:AddButton("Rejoin server", "Reconnect to this place", "Rejoin", function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end, true)
    return tab
end

-- ================= COMMANDS =================
local CATEGORIES = {"All", "Movement", "Character", "Protection", "Players", "Visuals", "System", "Troll"}

function Library:AddCommand(def)
    def.Kind = def.Kind or "Open"
    def.Category = def.Category or "System"
    table.insert(self.Commands, def)
    if self.RenderCommands then self:RenderCommands() end
end

function Library:RunCommand(text)
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if text:sub(1, #self.Prefix) == self.Prefix then text = text:sub(#self.Prefix + 1) end
    local args = {}
    for w in text:gmatch("%S+") do table.insert(args, w) end
    local name = table.remove(args, 1)
    if not name then return end
    for _, c in ipairs(self.Commands) do
        if c.Name:lower():gsub("%s", "") == name:lower() then
            if c.Kind == "Toggle" then
                c.State = not c.State
                if c.Callback then task.spawn(c.Callback, c.State) end
                self:Notify(c.Name, c.State and "Enabled" or "Disabled", 2)
                if self.RenderCommands then self:RenderCommands() end
            else
                if c.Callback then task.spawn(c.Callback, unpack(args)) end
                self:Notify(c.Name, "Executed", 2)
            end
            if self.Log then self.Log(c.Name .. " " .. table.concat(args, " ")) end
            return
        end
    end
    self:Notify("Unknown command", name, 2)
end

function Library:BuildCommands()
    local lib = self
    local tab = self:AddTab("Cmds", "terminal", {Footer = true})
    local scroll = tab.Scroll
    local current = "All"

    local pill = New("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Bg, BackgroundTransparency = 0.3, Parent = tab.Top},
        {Corner(14), Stroke(Theme.Stroke, 1, 0.55)})
    local chipBar = New("ScrollingFrame", {Position = UDim2.fromOffset(3, 3), Size = UDim2.new(1, -6, 1, -6), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 0, AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.X, Parent = pill}, {List(2, Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center)})
    local chips = {}
    for _, cat in ipairs(CATEGORIES) do
        local c = Button({Text = cat, TextSize = 10, TextColor3 = Theme.SubText, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22),
            BackgroundColor3 = Theme.Accent, BackgroundTransparency = 1, Silent = true, Fx = false, Parent = chipBar}, {Corner(11), Pad(10, 0)})
        c.MouseButton1Click:Connect(function()
            if current == cat then return end
            current = cat
            Audio.Play("tab")
            lib:RenderCommands()
        end)
        chips[cat] = c
    end

    local bar = Input({Text = "", PlaceholderText = "Type a command...", BackgroundTransparency = 1, Position = UDim2.fromOffset(32, 0),
        Size = UDim2.new(1, -40, 1, 0), Parent = tab.Footer})
    MakeIcon("terminal", tab.Footer, 14, Theme.Accent2).Frame.Position = UDim2.fromOffset(11, 8)
    bar.FocusLost:Connect(function(enter)
        if enter and bar.Text ~= "" then lib:RunCommand(bar.Text); bar.Text = "" end
    end)
    self.CommandBox = bar

    local function Header(text, order)
        return Label({Text = text, Font = Theme.FontBold, TextSize = 10, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 13),
            Position = UDim2.fromOffset(2, 0), LayoutOrder = order, Name = "CmdRow", Parent = scroll})
    end

    function self:RenderCommands()
        for _, c in ipairs(scroll:GetChildren()) do
            if c.Name == "CmdRow" then c:Destroy() end
        end
        for cat, c in pairs(chips) do
            local a = cat == current
            Tween(c, 0.25, {BackgroundTransparency = a and 0.1 or 1})
            c.TextColor3 = a and Theme.Text or Theme.SubText
        end
        local order = 1
        for pass = 1, 2 do
            local first = true
            for _, def in ipairs(self.Commands) do
                if (pass == 1) == (def.Best == true) and (current == "All" or def.Category == current) then
                    if first then
                        Header(pass == 1 and "Recommended" or "More", order); order += 1
                        first = false
                    end
                    local row = New("Frame", {Name = "CmdRow", Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = Theme.Row,
                        BackgroundTransparency = 0.5, LayoutOrder = order, Parent = scroll}, {Corner(10), Stroke(Theme.Stroke, 1, 0.65)})
                    order += 1
                    local nameRow = New("Frame", {Position = UDim2.fromOffset(11, 5), Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X,
                        BackgroundTransparency = 1, Parent = row}, {List(6, Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center)})
                    Label({Text = def.Name, Font = Theme.FontBold, TextSize = 11, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 14),
                        LayoutOrder = 1, Parent = nameRow})
                    if def.Best then
                        Label({Text = "BEST", Font = Theme.FontBold, TextSize = 7, TextColor3 = Theme.Accent2, TextXAlignment = Enum.TextXAlignment.Center,
                            Size = UDim2.fromOffset(28, 11), BackgroundTransparency = 0.65, BackgroundColor3 = Theme.Accent, LayoutOrder = 2,
                            Parent = nameRow}, {Corner(6)})
                    end
                    Label({Text = "/" .. def.Name:lower():gsub("%s", "") .. "  " .. (def.Desc or ""), TextSize = 9, TextColor3 = Theme.SubText,
                        Position = UDim2.fromOffset(11, 21), Size = UDim2.new(1, -78, 0, 12), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row})
                    if def.Kind == "Toggle" then
                        MakeToggle(row, def.State or false, function(v) def.State = v; if def.Callback then def.Callback(v) end end)
                    else
                        local b = Button({Text = def.Kind, TextSize = 10, Size = UDim2.fromOffset(46, 22), AnchorPoint = Vector2.new(1, 0.5),
                            Position = UDim2.new(1, -8, 0.5, 0), BackgroundColor3 = Theme.Row, Parent = row}, {Corner(8), Stroke(Theme.Stroke, 1, 0.5)})
                        b.MouseButton1Click:Connect(function()
                            if def.Callback then task.spawn(def.Callback) end
                            if lib.Log then lib.Log(def.Name) end
                        end)
                    end
                end
            end
        end
    end
    self:RenderCommands()
    return tab
end

-- ================= SCRIPTS =================
function Library:AddScript(def)
    table.insert(self.Scripts, def)
    if self.RenderScripts then self:RenderScripts() end
end

function Library:BuildScripts()
    local lib = self
    local tab = self:AddTab("Scripts", "scroll")
    local scroll = tab.Scroll

    local gamePage = New("CanvasGroup", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        LayoutOrder = 1, Parent = scroll}, {List(8)})
    local libPage = New("CanvasGroup", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1,
        Visible = false, LayoutOrder = 1, Parent = scroll}, {List(8)})
    Segmented(tab.Top, {{"Game", "grid"}, {"Library", "scroll"}}, function(i)
        gamePage.Visible, libPage.Visible = i == 1, i == 2
        local p = i == 1 and gamePage or libPage
        p.GroupTransparency = 1
        Tween(p, 0.3, {GroupTransparency = 0})
    end, 70)

    ---------- game card ----------
    local gc = tab:AddCard(66, gamePage)
    gc.LayoutOrder = 1
    New("ImageLabel", {Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(9, 9), BackgroundColor3 = Theme.Row,
        Image = "rbxthumb://type=GameIcon&id=" .. game.GameId .. "&w=150&h=150", Parent = gc}, {Corner(10), Stroke(Theme.Stroke, 1, 0.5)})
    local gname = Label({Text = "Loading...", Font = Theme.FontBold, TextSize = 13, Position = UDim2.fromOffset(66, 10), Size = UDim2.new(1, -150, 0, 16),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = gc})
    local gsub = Label({Text = "", TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(66, 27), Size = UDim2.new(1, -150, 0, 12), Parent = gc})
    New("Frame", {Size = UDim2.fromOffset(6, 6), Position = UDim2.fromOffset(66, 47), BackgroundColor3 = Theme.Good, Parent = gc}, {Corner(3)})
    local gplay = Label({Text = "", Font = Theme.FontBold, TextSize = 9, TextColor3 = Theme.Good, Position = UDim2.fromOffset(77, 43), Size = UDim2.new(1, -150, 0, 14), Parent = gc})
    task.spawn(function()
        local ok, info = pcall(function() return MarketplaceService:GetProductInfo(game.PlaceId) end)
        if ok and info then
            gname.Text = info.Name
            gsub.Text = "by " .. ((info.Creator and info.Creator.Name) or "?")
        end
        while lib.Gui.Parent do
            gplay.Text = #Players:GetPlayers() .. " in this server"
            task.wait(2)
        end
    end)
    local lc = tab:AddCard(30, gamePage)
    lc.LayoutOrder = 2
    Label({Text = "Scripts load only from the Library tab (your own functions).", TextSize = 9, TextColor3 = Theme.SubText,
        Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -24, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = lc})
    local gs = tab:AddSection("Place", gamePage)
    gs.Wrap.LayoutOrder = 3
    gs:AddValue("Place ID", function() return game.PlaceId end, function() return game.PlaceId end)
    gs:AddValue("Universe ID", function() return game.GameId end, function() return game.GameId end)
    gs:AddValue("Place version", function() return game.PlaceVersion end)

    ---------- library ----------
    local sb = New("Frame", {Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = Theme.Bg, BackgroundTransparency = 0.3, LayoutOrder = 1, Parent = libPage},
        {Corner(14), Stroke(Theme.Stroke, 1, 0.55)})
    MakeIcon("search", sb, 13, Theme.SubText).Frame.Position = UDim2.fromOffset(10, 7)
    local search = Input({Text = "", PlaceholderText = "Search your scripts...", BackgroundTransparency = 1, Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -38, 1, 0), Parent = sb})
    local listF = New("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2,
        Parent = libPage}, {List(5)})

    function self:RenderScripts()
        for _, c in ipairs(listF:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local q = search.Text:lower()
        local shown = 0
        for i, def in ipairs(self.Scripts) do
            if q == "" or def.Name:lower():find(q, 1, true) or (def.Tag or ""):lower():find(q, 1, true) then
                shown += 1
                local row = New("Frame", {Size = UDim2.new(1, 0, 0, 40), BackgroundColor3 = Theme.Row, BackgroundTransparency = 0.5, LayoutOrder = i,
                    Parent = listF}, {Corner(10), Stroke(Theme.Stroke, 1, 0.65)})
                Label({Text = def.Name, Font = Theme.FontBold, TextSize = 11, Position = UDim2.fromOffset(11, 5), Size = UDim2.new(1, -140, 0, 14),
                    TextTruncate = Enum.TextTruncate.AtEnd, Parent = row})
                Label({Text = def.Desc or "", TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(11, 21),
                    Size = UDim2.new(1, -140, 0, 12), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row})
                if def.Tag then
                    Label({Text = def.Tag, Font = Theme.FontBold, TextSize = 8, TextColor3 = Theme.Accent2, TextXAlignment = Enum.TextXAlignment.Center,
                        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -64, 0.5, 0), Size = UDim2.fromOffset(52, 14),
                        BackgroundTransparency = 0.75, BackgroundColor3 = Theme.Accent, Parent = row}, {Corner(7)})
                end
                local run = Button({Text = "Run", TextSize = 10, Size = UDim2.fromOffset(44, 22), AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -8, 0.5, 0), BackgroundColor3 = Theme.Accent, Parent = row}, {Corner(8)})
                run.MouseButton1Click:Connect(function()
                    if def.Callback then task.spawn(def.Callback) end
                    lib:Notify(def.Name, "Started", 2)
                    if lib.Log then lib.Log("script: " .. def.Name) end
                end)
            end
        end
        if shown == 0 then
            local empty = New("Frame", {Size = UDim2.new(1, 0, 0, 70), BackgroundTransparency = 1, Parent = listF})
            MakeIcon("scroll", empty, 22, Theme.SubText).Frame.Position = UDim2.new(0.5, -11, 0, 8)
            Label({Text = #self.Scripts == 0 and "No scripts yet - add yours with UI:AddScript{...}" or "No match",
                TextSize = 10, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 40),
                Size = UDim2.new(1, 0, 0, 14), Parent = empty})
        end
    end
    search:GetPropertyChangedSignal("Text"):Connect(function() self:RenderScripts() end)
    self:RenderScripts()
    return tab
end

-- ================= PLAYERS =================
function Library:BuildPlayers()
    local lib = self
    local tab = self:AddTab("Players", "users")
    local scroll = tab.Scroll

    local sb = New("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Bg, BackgroundTransparency = 0.3, Parent = tab.Top},
        {Corner(14), Stroke(Theme.Stroke, 1, 0.55)})
    MakeIcon("search", sb, 13, Theme.SubText).Frame.Position = UDim2.fromOffset(10, 7)
    local search = Input({Text = "", PlaceholderText = "Search players...", BackgroundTransparency = 1, Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -38, 1, 0), Parent = sb})

    local actions = {{"View", "search"}, {"Copy @", "copy"}, {"Copy ID", "copy"}, {"Profile", "external"}}
    local rows, selected = {}, nil

    local function filter()
        local q = search.Text:lower()
        for _, r in ipairs(rows) do
            local p = r.Player
            r.Frame.Visible = q == "" or p.Name:lower():find(q, 1, true) ~= nil or p.DisplayName:lower():find(q, 1, true) ~= nil
        end
    end

    local function refresh()
        for _, r in ipairs(rows) do r.Frame:Destroy() end
        rows, selected = {}, nil
        for i, p in ipairs(Players:GetPlayers()) do
            local st = Stroke(Theme.Stroke, 1, 0.65)
            local f = New("Frame", {Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.Row, BackgroundTransparency = 0.5,
                ClipsDescendants = true, LayoutOrder = i, Parent = scroll}, {Corner(10), st})
            local head = Button({Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Silent = true, Parent = f}, {Corner(10)})
            local av = New("ImageLabel", {Size = UDim2.fromOffset(24, 24), Position = UDim2.fromOffset(8, 6), BackgroundColor3 = Theme.Bg,
                Parent = head}, {Corner(12)})
            task.spawn(function()
                local ok, img = pcall(Players.GetUserThumbnailAsync, Players, p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                if ok and av.Parent then av.Image = img end
            end)
            local nameRow = New("Frame", {Position = UDim2.fromOffset(40, 4), Size = UDim2.fromOffset(0, 14), AutomaticSize = Enum.AutomaticSize.X,
                BackgroundTransparency = 1, Parent = head}, {List(5, Enum.FillDirection.Horizontal, nil, Enum.VerticalAlignment.Center)})
            Label({Text = p.DisplayName, Font = Theme.FontBold, TextSize = 11, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 14),
                LayoutOrder = 1, Parent = nameRow})
            if p == LocalPlayer then
                Label({Text = "you", TextSize = 9, TextColor3 = Theme.Accent2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 14),
                    LayoutOrder = 2, Parent = nameRow})
            end
            Label({Text = "@" .. p.Name, TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(40, 19),
                Size = UDim2.new(1, -80, 0, 12), TextTruncate = Enum.TextTruncate.AtEnd, Parent = head})
            local arrow = MakeIcon("chevDown", head, 12, Theme.SubText):Center()
            arrow.Frame.Position = UDim2.new(1, -18, 0, 18)

            local bar = New("Frame", {Position = UDim2.fromOffset(8, 40), Size = UDim2.new(1, -16, 0, 24), BackgroundTransparency = 1, Parent = f},
                {List(4, Enum.FillDirection.Horizontal)})
            for _, a in ipairs(actions) do
                local b = Button({Text = a[1], TextSize = 9, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1 / #actions, -3, 1, 0),
                    BackgroundColor3 = Theme.Bg, BackgroundTransparency = 0.2, Parent = bar}, {Corner(8), Stroke(Theme.Stroke, 1, 0.55), Pad(21, 0, 4, 0)})
                local ai = MakeIcon(a[2], b, 10, Theme.SubText)
                ai.Frame.AnchorPoint = Vector2.new(0, 0.5)
                ai.Frame.Position = UDim2.new(0, -15, 0.5, 0)
                b.MouseButton1Click:Connect(function()
                    local fn = lib.PlayerActions[a[1]]
                    if fn then task.spawn(fn, p)
                    elseif a[1] == "Copy @" then lib:Notify("Copied", "@" .. p.Name, 2); CopyText(p.Name)
                    elseif a[1] == "Copy ID" then lib:Notify("Copied", tostring(p.UserId), 2); CopyText(tostring(p.UserId))
                    elseif a[1] == "Profile" then
                        lib:Notify("Profile link copied", p.DisplayName, 2)
                        CopyText("https://www.roblox.com/users/" .. p.UserId .. "/profile")
                    else lib:Notify(a[1], "No action bound. Set UI.PlayerActions[\"" .. a[1] .. "\"]", 3) end
                end)
            end
            local open = false
            head.MouseButton1Click:Connect(function()
                open = not open
                Audio.Play("click")
                Tween(f, 0.3, {Size = UDim2.new(1, 0, 0, open and 68 or 36)}, Enum.EasingStyle.Back)
                Tween(arrow.Frame, 0.3, {Rotation = open and 180 or 0}, Enum.EasingStyle.Back)
                Tween(st, 0.25, {Color = open and Theme.Accent2 or Theme.Stroke, Transparency = open and 0.3 or 0.65})
            end)
            table.insert(rows, {Frame = f, Player = p})
        end
        filter()
    end
    search:GetPropertyChangedSignal("Text"):Connect(filter)
    self:Bind(Players.PlayerAdded, function() task.wait(0.2); refresh() end)
    self:Bind(Players.PlayerRemoving, function() task.defer(refresh) end)
    refresh()
    return tab
end

-- ================= MUSIC =================
function Library:AddTrack(def)
    table.insert(self.Tracks, def)
    if self.RenderTracks then self:RenderTracks() end
end

function Library:BuildMusic()
    local lib = self
    local tab = self:AddTab("Music", "music")
    local scroll = tab.Scroll
    local sound = New("Sound", {Name = "NyxMusic", Volume = 0.5, Parent = SoundService})
    self.MusicSound = sound
    local now, filterLiked = nil, false

    local sb = New("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Bg, BackgroundTransparency = 0.3, Parent = tab.Top},
        {Corner(14), Stroke(Theme.Stroke, 1, 0.55)})
    MakeIcon("search", sb, 13, Theme.SubText).Frame.Position = UDim2.fromOffset(10, 7)
    local search = Input({Text = "", PlaceholderText = "Search or paste an audio ID", BackgroundTransparency = 1, Position = UDim2.fromOffset(30, 0),
        Size = UDim2.new(1, -38, 1, 0), Parent = sb})

    ---------- now playing ----------
    local np = tab:AddCard(132)
    np.LayoutOrder = 1
    local art = New("Frame", {Size = UDim2.fromOffset(54, 54), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = Theme.White, Parent = np},
        {Corner(12), Gradient(Color3.fromRGB(92, 64, 168), Color3.fromRGB(46, 30, 92), 60)})
    local artIcon = MakeIcon("music", art, 24, Color3.fromRGB(200, 185, 240)):Center()
    local title = Label({Text = "Nothing playing", Font = Theme.FontBold, TextSize = 12, Position = UDim2.fromOffset(74, 14), Size = UDim2.new(1, -112, 0, 16),
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = np})
    local artist = Label({Text = "Pick a track to start listening", TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(74, 32),
        Size = UDim2.new(1, -112, 0, 12), TextTruncate = Enum.TextTruncate.AtEnd, Parent = np})
    local heartB = Button({Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 10),
        BackgroundTransparency = 1, Parent = np}, {Corner(12)})
    local heart = MakeIcon("heart", heartB, 14, Theme.SubText):Center()

    local track = New("Frame", {Size = UDim2.new(1, -20, 0, 4), Position = UDim2.fromOffset(10, 78), BackgroundColor3 = Theme.Off, Parent = np}, {Corner(2)})
    local fill = New("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = Theme.White, Parent = track}, {Corner(2), Gradient(Theme.Accent, Theme.Accent2, 0)})
    New("Frame", {Size = UDim2.fromOffset(8, 8), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, 0, 0.5, 0), BackgroundColor3 = Theme.Text,
        Parent = fill}, {Corner(4)})
    local tCur = Label({Text = "0:00", TextSize = 8, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(10, 86), Size = UDim2.fromOffset(40, 10), Parent = np})
    local tEnd = Label({Text = "0:00", TextSize = 8, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 86), Size = UDim2.fromOffset(40, 10), Parent = np})
    local seekHit = New("TextButton", {Text = "", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 0.5, -9), Parent = track})
    seekHit.InputBegan:Connect(function(i)
        if IsPress(i) and sound.TimeLength > 0 then
            local a = math.clamp((i.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
            sound.TimePosition = a * sound.TimeLength
        end
    end)

    local tr = New("Frame", {Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 99), BackgroundTransparency = 1, Parent = np},
        {List(16, Enum.FillDirection.Horizontal, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)})
    local function TBtn(iconName, size, bg)
        local b = Button({Size = UDim2.fromOffset(size, size), BackgroundColor3 = bg or Theme.Row, BackgroundTransparency = bg and 0 or 0.3, Parent = tr},
            {Corner(size / 2)})
        local ic = MakeIcon(iconName, b, size * 0.5, Theme.Text):Center()
        return b, ic
    end
    local prevB = TBtn("prev", 26)
    local playB, playIcon = TBtn("play", 30, Theme.Accent)
    local pauseIcon = MakeIcon("pause", playB, 15, Theme.Text):Center()
    pauseIcon.Frame.Visible = false
    local nextB = TBtn("next", 26)

    local vs = tab:AddSection(nil)
    vs.Wrap.LayoutOrder = 2
    vs:AddSlider("Volume", nil, 0, 100, 50, function(v) sound.Volume = v / 100 end)

    ---------- tracks ----------
    local segRow = New("Frame", {Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, LayoutOrder = 3, Parent = scroll})
    Segmented(segRow, {{"All", "grid"}, {"Liked", "heart"}}, function(i)
        filterLiked = i == 2
        if lib.RenderTracks then lib:RenderTracks() end
    end, 64)
    local listF = New("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 5,
        Parent = scroll}, {List(5)})

    local function SetPlayingUi(playing)
        playIcon.Frame.Visible = not playing
        pauseIcon.Frame.Visible = playing
    end
    local function Play(def)
        now = def
        sound.SoundId = "rbxassetid://" .. tostring(def.Id)
        sound.TimePosition = 0
        sound:Play()
        title.Text = def.Name
        artist.Text = def.Artist or "Unknown artist"
        Tween(heart.Frame, 0.2, {Rotation = 0})
        heart:SetColor(def.Liked and Theme.Danger or Theme.SubText)
        SetPlayingUi(true)
        lib:RenderTracks()
        task.delay(4, function()
            if now == def and not sound.IsPlaying and sound.TimeLength == 0 then
                lib:Notify("Couldn't play", "Audio is private or the ID is invalid", 3)
                SetPlayingUi(false)
            end
        end)
    end
    local function Step(dir)
        if #lib.Tracks == 0 then return end
        local idx = table.find(lib.Tracks, now) or 0
        Play(lib.Tracks[((idx - 1 + dir) % #lib.Tracks) + 1])
    end
    playB.MouseButton1Click:Connect(function()
        if not now then
            if lib.Tracks[1] then Play(lib.Tracks[1]) else lib:Notify("Music", "Paste an audio ID in the search bar", 3) end
        elseif sound.IsPlaying then sound:Pause(); SetPlayingUi(false)
        else sound:Resume(); SetPlayingUi(true) end
    end)
    prevB.MouseButton1Click:Connect(function() Step(-1) end)
    nextB.MouseButton1Click:Connect(function() Step(1) end)
    heartB.MouseButton1Click:Connect(function()
        if not now then return end
        now.Liked = not now.Liked
        heart:SetColor(now.Liked and Theme.Danger or Theme.SubText)
        Tween(heart.Frame, 0.35, {Rotation = now.Liked and 360 or 0}, Enum.EasingStyle.Back)
        lib:RenderTracks()
    end)
    sound.Ended:Connect(function() Step(1) end)
    self:Bind(RunService.Heartbeat, function()
        if sound.IsPlaying and sound.TimeLength > 0 then
            fill.Size = UDim2.fromScale(math.clamp(sound.TimePosition / sound.TimeLength, 0, 1), 1)
            tCur.Text = FmtTime(sound.TimePosition)
            tEnd.Text = FmtTime(sound.TimeLength)
        end
    end)

    function self:RenderTracks()
        for _, c in ipairs(listF:GetChildren()) do
            if c:IsA("Frame") then c:Destroy() end
        end
        local q = search.Text:lower()
        local shown = 0
        for i, def in ipairs(self.Tracks) do
            if (not filterLiked or def.Liked) and (q == "" or tonumber(q) or def.Name:lower():find(q, 1, true)) then
                shown += 1
                local active = def == now
                local row = New("Frame", {Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = Theme.Row, BackgroundTransparency = active and 0.25 or 0.5,
                    LayoutOrder = i, Parent = listF}, {Corner(10), Stroke(active and Theme.Accent2 or Theme.Stroke, 1, active and 0.3 or 0.65)})
                Label({Text = def.Name, Font = Theme.FontBold, TextSize = 11, Position = UDim2.fromOffset(11, 4), Size = UDim2.new(1, -60, 0, 14),
                    TextTruncate = Enum.TextTruncate.AtEnd, Parent = row})
                Label({Text = def.Artist or "Unknown artist", TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(11, 19),
                    Size = UDim2.new(1, -60, 0, 12), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row})
                if def.Liked then
                    MakeIcon("heart", row, 12, Theme.Danger).Frame.Position = UDim2.new(1, -52, 0, 12)
                end
                local pb = Button({Size = UDim2.fromOffset(24, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0),
                    BackgroundColor3 = Theme.Accent, BackgroundTransparency = active and 0 or 0.5, Parent = row}, {Corner(12)})
                MakeIcon("play", pb, 11, Theme.Text):Center()
                pb.MouseButton1Click:Connect(function() Play(def) end)
            end
        end
        if shown == 0 then
            local empty = New("Frame", {Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Parent = listF})
            MakeIcon("music", empty, 20, Theme.SubText).Frame.Position = UDim2.new(0.5, -10, 0, 8)
            Label({Text = filterLiked and "No liked tracks yet" or "Paste an audio ID above and press enter", TextSize = 10, TextColor3 = Theme.SubText,
                TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(0, 36), Size = UDim2.new(1, 0, 0, 14), Parent = empty})
        end
    end
    search.FocusLost:Connect(function(enter)
        local id = tonumber(search.Text)
        if enter and id then
            local def
            for _, t in ipairs(lib.Tracks) do if tostring(t.Id) == tostring(id) then def = t end end
            if not def then
                def = {Name = "Audio " .. id, Artist = "Asset ID", Id = id}
                table.insert(lib.Tracks, def)
            end
            search.Text = ""
            Play(def)
        end
    end)
    search:GetPropertyChangedSignal("Text"):Connect(function() self:RenderTracks() end)
    self:RenderTracks()
    return tab
end

-- ================= NEWS =================
function Library:BuildNews()
    local tab = self:AddTab("News", "bell")
    Label({Text = "Announcements", Font = Theme.FontBold, TextSize = 13, Position = UDim2.fromOffset(2, 0), Size = UDim2.new(1, 0, 0, 16), Parent = tab.Top})
    Label({Text = "News from the Nyx team.", TextSize = 9, TextColor3 = Theme.SubText, Position = UDim2.fromOffset(2, 15), Size = UDim2.new(1, 0, 0, 12), Parent = tab.Top})
    local function Post(tag, title, text, order)
        local c = tab:AddCard(74)
        c.LayoutOrder = order
        Label({Text = tag, Font = Theme.FontBold, TextSize = 8, TextColor3 = Theme.White, TextXAlignment = Enum.TextXAlignment.Center,
            BackgroundTransparency = 0, BackgroundColor3 = Theme.Accent, Position = UDim2.fromOffset(12, 10), Size = UDim2.fromOffset(60, 14), Parent = c}, {Corner(7)})
        Label({Text = title, Font = Theme.FontBold, TextSize = 12, Position = UDim2.fromOffset(12, 29), Size = UDim2.new(1, -24, 0, 16), Parent = c})
        Label({Text = text, TextSize = 9, TextColor3 = Theme.SubText, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
            Position = UDim2.fromOffset(12, 46), Size = UDim2.new(1, -24, 0, 24), Parent = c})
    end
    Post("WHAT'S NEW", "Nyx UI v3", "Smaller layout, animations everywhere, soft interface sounds, new logo and Scripts tab.", 1)
    Post("TIP", "Command bar", "Press ; on PC (or open the Cmds tab) and type a command like fov 90.", 2)
    return tab
end

-- ================= SETTINGS =================
function Library:BuildSettings()
    local lib = self
    local tab = self:AddTab("Settings", "gear")
    local scroll = tab.Scroll
    local gen = New("CanvasGroup", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 1,
        Parent = scroll}, {List(8)})
    local ifc = New("CanvasGroup", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, Visible = false,
        LayoutOrder = 1, Parent = scroll}, {List(8)})
    Segmented(tab.Top, {{"General", "gear"}, {"Interface", "grid"}}, function(i)
        gen.Visible, ifc.Visible = i == 1, i == 2
        local p = i == 1 and gen or ifc
        p.GroupTransparency = 1
        Tween(p, 0.3, {GroupTransparency = 0})
    end, 74)

    local g = tab:AddSection(nil, gen)
    g:AddKeybind("Toggle menu key", "Hide or show the menu with this key", self.ToggleKey, function(k) lib.ToggleKey = k end)
    g:AddDropdown("Command prefix", "Opens the command bar", {";", ".", "/", ","}, ";", function(v) lib.Prefix = v end)
    self.Ctl.Sounds = g:AddToggle("Interface sounds", "Soft clicks and chimes", true, function(v) lib.SfxOn = v end)
    g:AddSlider("Sound volume", "Loudness of the UI sounds", 0, 100, 100, function(v) lib.SfxVolume = v / 100 end, false, "%")
    self.Ctl.Idle = g:AddToggle("Anti idle", "Never get the 20-minute idle kick", false, function(v) lib:SetAntiIdle(v) end)
    g:AddButton("Unload", "Close the menu and stop everything", "Unload", function()
        lib:Sfx("close")
        task.wait(0.15)
        lib.Gui:Destroy()
    end, true)
    local r = tab:AddSection(nil, gen)
    r:AddButton("Reset settings", "Restore every default", "Reset", function()
        lib:SetScale(lib.AutoScale); lib.ScaleSlider:Set(math.floor(lib.AutoScale * 100 + 0.5))
        lib.SfxOn, lib.SfxVolume, Motion.On, lib.Prefix = true, 1, true, ";"
        lib.Ctl.Sounds:Set(true, true); lib.Ctl.Motion:Set(true, true)
        lib:Notify("Settings", "Defaults restored", 2)
    end)

    local u = tab:AddSection(nil, ifc)
    self.ScaleSlider = u:AddSlider("UI Scale", "Size of the whole menu", 40, 160, math.floor(self.Scale * 100 + 0.5),
        function(v) lib:SetScale(v / 100) end, true, "%")
    u:AddButton("Auto fit screen", "Match the scale to this device", "Auto", function()
        lib:SetScale(lib.AutoScale); lib.ScaleSlider:Set(math.floor(lib.AutoScale * 100 + 0.5))
    end)
    self.Ctl.Motion = u:AddToggle("Animations", "Smooth motion everywhere", true, function(v) Motion.On = v end)
    u:AddToggle("Open Nyx pill", "Show the small pill when the menu is hidden", true, function(v) lib.PillEnabled = v end)
    u:AddButton("Reset window position", "Bring the menu back to the top", "Reset", function() lib:ResetPosition() end)
    return tab
end

-- ================= SOUND DATA (generated) =================
SoundData = {
    click = [=[UklGRiQFAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YQAFAAAAAFIFPg01B0D94ucsBewMXBMJ79vNWbGM6PwumFmVN3MI++ND8hcS5xDU9rfE3LJD2rsXJUh+QDEYvvRw7YIEghBR+7LRNroQyzIFtDo6QxQkLv237+UBmg3YAgXjcsn4ygf1ViVPOo8pygm99TT7PwndB7nuwtJTy8Tp1BTWMDIujROj/aT6awVwBWr1etzi0O3hRwZmJBos9xq2A+f63P8iBRz82uYo1xbeX/qKGh4o6B63Cmj9Av4HAyj/gO7j3dvdO/K7D68hEiDGD2cBjv2FAYEAJ/TM5NLfuOwRBsAacx6tEyEF3/7i/8sAsvgO6wHjYuqQ/rMS/hsaFl8JoQDP/1cAUvsm8DXnZOlK+NgLkxePFo4MNwPv/yUALv2O9E3r8ela9GIF7hKgFasO3QX8APr/Hf639zbvl+vR8fr/yw2vEw8QLAg0Ai8Au/4s+qLyzu3W8Ob7+AjkEEgQGgrOA7QAJ/+++6v1VPDP8MX4kASlDZsPXwtuBYsBnv8I/RX40PJ68dH21AA4CjMOAgzlBowCLADk/fL5GPW08r311f3eBjoMBwwFCKgD0QCp/nb7MPcv9HH1jfvSA/0JbgvKCLwEkwFU/6X88vi/9ar1/vknAZwHZAoWCagFZgIAAJz9b/pF90X2DPn5/kkFBQn7CFwGNgOsAG/+rvu0+CH3nvhH/SEDbAeBCMsG8wNeASr/ufz/+Rn4mPgO/DoBwAW7B+0GkAQIAtf/nf0k+xv53vhB+6L/GQS6BsoGAgWoAnoAZP4j/Bn6WPnR+lz+jgKWBWcGQgUyAxMBFf8D/Qj78vmt+mj9LQFjBNAFTwWfA6EBtv/I/eX7nPrD+r/8AAAzAxMFKwXrAx4CRwB3/q78S/sD+1j8C/8UAj8E3AQSBIYCywAU/2P9+Pth+yn8Tf4SAWADagQUBNYCQAGh/wf+nfzQ+yX8xP0yAIMC3gP0AwsDpAEeAJr+OP1J/ET8av15/7EBQQO2AyQD9gGNAB//x/3F/Hz8Of3m/vEAngJgAyMDMgLuAJb/TP4//cT8Kv13/koA+wH3AgkDWQI/AQAAxP61/Rf9Nf0r/r3/XwGDAtkCbAKAAVwAMv8m/m/9VP39/Uv/0QAKApgCaQKvAawAlf+P/sr9g/3p/fP+UgCRAUoCVQLOAe4A7P/w/iP+u/3p/bT+5/8dAfMBMQLcASIBOABJ/3r++/36/Yv+jv+yAJkBAALaAUgBeQCZ/8z+Pf4X/nX+Sf9SAD4BxQHLAWEBrwDg/xn/gP4+/nD+Ff8AAOgAhQGwAWwB2QAdAGD/wv5q/nj+8v67/5cAQQGLAWwB+ABSAKH/Av+b/or+3f6E/04A/QBgAWEBDAF+ANr/P//N/qT+1f5a/w4AvAAvAU0BFgGgAAsAd/8A/8T+1/48/9n/fgD9ADIBFgG6ADYAqv8x/+f+4v4q/63/RwDKABEBDAHGAFcA2v9o/xz/B/80/5f/EwCGAM8A3QC0AGMAAACh/1n/O/9P/5L/8f9QAJUArgCaAGMAGADM/43/bP9w/5n/3f8nAGMAgQB8AFoAJADq/7f/l/+R/6n/1v8MADwAWQBdAEoAJgD9/9b/u/+y/73/2f/+/yAAOAA/ADYAIQAGAOz/2f/P/9P/4v/4/w0AHQAkACEAFgAIAPr/7v/o/+n/7//5/wIACgANAAwACAADAAAA/f/8//3///8AAA==]=],
    tab = [=[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]=],
    on = [=[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]=],
    off = [=[UklGRiQUAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YQAUAAAAANUA3AIJBY4GMwcSBxUG5gNgAOv7Nvel8ibu6OlE56roHPA6/bcM7hmLITUj1SBoHGMWFQ5CAx73getd4VTYUdCDy1POftxf9c8SFyzcOkU+5DnHMWon6RmwCGT1+eI20+PGqby4tlu6Q8yz6/cQEjHzQ2NI3kLUOMksNx5uDNz4euZK1wXLwsD4uV+798k95t8JbSo2P81FzUGkOF8t4B9ID438ceo42/zOv8RWvde8Xsh24S4D0CNDOvdCkUBUOMktRCHUEQAAP+4D38jSmsjEwLC+acdd3fD8Sx0kNeI/Jj/mNwwuaSIWFDMD4vGs4m7WUsw2xNfAC8fu2S737RbiL5A8jD1ZNywuVSMQFiUGWfU15u/Z5c+ixzzDM8cm1/DxwxCJKgU5wDutNi4uECTGF9cIofie6U7dU9MAy87F0cf91Dvt2wolJUU1wDngNRQuniQ8GUgLuvvn7I7gnNZIzn/I1chp0xPpQQXBH1UxjDfxNN8tBiV4GnkNoP4O8LHjw9l40UPLMMph0nnlAABrGj4tJTXeM5ItTCV/G2wPUwEU87fmyNyM1A/O0cvZ0WviIPsuFQYpjDKkMiwtdCVWHCMR0gP29aPpr9+C19nQq83F0ebfqPYWELckwi9DMa4sgSUBHaISHAa0+HXseeJZ2pzTsc8X0uXdnvIvC1kgyyy4LxUsdyWGHesTMQhL+yzvKeUT3U/W1dHC0mHcBe+CBvgbrCkELmErVyXpHQMVEwq6/crxweew3/DYDdS601Pb3usYApwXaSYlLJAqIiUvHu4VwQsAAEz0Qeox4nvbUNby1LLaKun7/U8TCCMdKqEp2SRbHq8WPQ0cArL2q+yY5O/dlthd1nTa5+Yw+h0PkR/tJ5MofSRwHksXiw4NBPr4/+7o5krg19rx147aEuW79g0LChyXJWMnCyRxHsYXrA/UBST7P/Eh6YziD92j2fbapeOh8ygHfBgeIxImhCNgHiQYoxBvBy/9afNF67fkOt9p26Lbm+Lj8HcD7xSGIJ4k5yI+HmgYcxHhCBj/ffVW7cvmU+E83Ybc7eGD7gAAahHTHQkjMSILHpYYIBIqCt8Ae/dV78noW+MU35rdk+F/7Mr89g0LG1IhYiHIHbAYrhJMC4QCYvlC8bLqTuXr4NLehuHW6tf5mwo0GHwfeiB0HbkYHxNIDAcEMfse84nsLue84ifgvOGE6S33XwdTFYcddR8PHbIYdhMiDWYF5vzo9E/u+uiE5JHhLeKF6M70SgRwEngbVh6ZHJ0YuBPaDaQGgf6i9gTws+pA5gfj0OLT57vyYQGQD1IZGh0PHHsY5hN1Dr8HAABJ+KrxWezt54XknuNo5/PwrP67DBgXwxtyG0sYAxT0DroIZAHe+ULz7+2L6QTmjeQ/53XvK/z2Cc8UUhq/Gg4YERRbD5YJrAJf+8v0de8Y64HnmOVR5z/u5PlIB3wSyBj3GcMXEhSsD1UK1wPM/Eb27PCW7PfotuaV50/t2Pe3BCQQJhcZGWoXBhTqD/cK5wQl/rP3VvID7mXq4ecH6J/sCvZIAs0NcBUkGAIX7xMXEIEL2gVn/xL5s/Ni78frFemd6C3sefQAAHsLqRMZF4oWzhM1EPMLswaTAGP6A/Wy8B7tTOpT6fLrJfPi/TQJ1BH3FQIWohNGEFAMcgepAaT7SPb18Wfugush6unrDfLx+/0G9A/BFGgVahNMEJsMGQinAtT8gvcr86PvtewB6wzsLvEv+twEDw53E70UKBNIENQMqAiPA/X9sPhW9NPw4u3w61fshfCf+NQCJwwcEv8T2hI6EP8MIglgBAP/0/l39fXxBu/n7MPsEPBA9+kAQgqxEC8TfxIjEB4NhwkbBQAA6vqN9gzzIfDi7Urtyu8U9iD/ZAg5D00SFxIDEDEN2wnBBeoA9fuZ96r0VvMq83L0Jvjw/hgIbxFVGCUb4hmxFbsPhgglANz2Yu1+5HbcG9WVzjbKXcpB0WHf3/I+CP4b1CviNhg9nz7TO5U1TC1HJAEbCBHTBcf5g+7+5Qzhlt4u3JbXL9BIx/TAPb7dwLvJ2dgK7bYDRxltKpU1hDuAPpVAOUI0Qso+BjdBK68clQzi+1brwNvSzcbBU7derumnaKbWrPi87tUp9MUSZi1aQbBNo1IYUXxKqkB2NfgpNB6VEfQDYvbS6uPind5H3HnZpdQCzlLH6sLJwi/IjdNf5OL4Gw6oIBMu6TWvOZ07Dj22PSM89TbVLYIhLxPnA3L0g+XS19HLcsFsuA+x7qyyrsi4ysuz5XcCmx2yMwBDNUveTBRJZUGVNxAtXyInF/AKEf768X3oh+Jd3//cc9kC1JvNOsj4xWPITdCw3YHvfwOUFtglzi/5NDw3dThAOcw4sDUILwAliBi4Cmn8R+764BPVwMrJwRa6dbTpsvi3P8Uz2vrzdg7RJYs3r0JgR2tGDUHeOGcvnSWNG7kQ9QQP+aLuHOew4hjgX90n2X/Tzs0QygvK4M722M/n4/meDBEdCSkBMCkzbTQbNSw1hzMCLzgnsRxoEEoDDvZM6ZrdU9Nsyq3CUbyiuNW5A8LW0cXnewAeGJorSDnJQJRCoT9IOQkxHCj5HlwV2wqt//j0Rex45h7jquBx3cPYTtO4ztPMBs8M1uHhlPExAw8UoSGHKhAvzTBoMZcx0zD8LUQosx8FFSgJ4PzH8GrlO9tg0qzKDMQmv5+9msGMzCjeJfQNC4IfOy9DOaw9Jj3LOPYx9imdIf8YtA+MBST7y/HC6lnmn+MB4Uzddtib02rQddDD1K3dxequ+jILxRlxJKcqVC0eLkMu5y08LEconSGbGA8OyQJu94Tsg+K02Q7SZcvnxaHCacMPykHX1ekQ/6ETyyT/MNU3rjllNyUyNiugI88bkROHCtQAYfd47+/piOYO5CDhFd1s2IHU5tLf1BbbheVW89gCvRHLHb4lvykYK0YrBisNKnUnhiIzGwsS1wdJ/eryMOl34IPcadf30rXPqs4H0bjX4+Kz8WQCuBKGIE4qji+1MNIuFytqJi0hUhuWFNkMTgR6+/7yXOvD5A7f/dmA1frRTtCk0fvWs+A+7hv+MA5UHN8mES0eL+8tsCpZJmsh7hupFW4OVgbR/Xn12+0554Phedz510TUFtKG0p/W8d4v6x760QklGFcjbCpfLe0sMio1JpIhbByVFtUPMwgDANr3RfCc6eHj3d5h2ozW+NOj05zWl92G6HP2oQUCFLsfoyd4K8krnSn+JaUhzhxbFxIR5AkSAh76m/Lt6yzmK+G03M7Y7NXw1OfWoNxE5h3zqQHxDxMcuSRrKYMq7ii1JaUhFx3/FyUSawv7A0b82/Qs7mPoZOP03gXb6ddl1njXBdxk5CDw7/39C2cYtSE4JxspJChZJZQhSh2FGBITyQy+BU/+BfdZ8InqiOUe4S7d69n310TYvdvk4nztefotCL0Umh7kJI8nPyfpJHMhah3wGNwTAA5bBzgAF/l18p7smec140ff6tuf2UPZw9u/4TLrSveHBB8RbxtwIuElPCZjJEEheR1DGYYUEA/SCAICEft+9KTumek35U/h491W22vaDNzw4EHpZ/QTAZINOxjgHxEkGyXHI/8gdx2BGRMV/g8lCqoD8fx09prwiOsn50Xj0t8V3bXbkdxx4Kfn0vHX/R8KAxU5HSEi3CMUI60gZx2sGYYVyhBTCzIFt/5X+IDyaO0F6SnlteHX3hjdSd064GDmi+/V+ssGzxF/GhQgfiJIIkggSB3GGeEVeBFfDJgGYAAm+lf0Ou/T6vvmiuOW4I3eLd5G4Gjlku0T+J4DpA63F+sdAiFjIdEfGx3RGSgWChJLDd0H7QHe+x72/fCS7LzoUOVQ4g7gNN+M4Lvk6OuT9ZwAiwvoFKobaB9jIEYf4BzPGVwWghIXDgIJXgOA/dT3s/JC7mzqBucB5JbhV+AG4VPkiOpX8839iAgWElQZsx1IH6celhy/GYAW5BLHDgcKsQQL/3n5XPTl7w3srOim5SDjkOGs4Srkculg8TH7oQVJD/AW4xsSHvIdPByjGZUWMhNdD+8K6AV8AAz79/V88aDtQupA56jk2eJ34jrkoOiu78z43QKEDH8U/BnCHCYd0ht6GZ4WbhPaD7oLAQfWAYz8hPcG8ybvyuvM6CrmK+Rh433kEOhA7qP2QADPCQkSARhZG0McVhtEGZoWmhNBEGoM/wcWA/j9AvmE9KDwQ+1K6qTng+Vj5O3ku+cU7bX0zv0uB5EP9BXXGUkbyRoCGYsWuBOVEAIN4Qg8BE//cfr39Q3yr+666xTp3OZ35YLlnecn7APzi/unBB0N2hM/GDcaKBqyGHEWyhPXEIINqQlJBZAA0Ptd93DzD/Ac7XnqMuiY5jfmsed2643xePk+ArEKthGSFg8ZcxlTGEwW0BMKEe0NWAo9BrwBHv24+Mj0Y/Fy7tPrhOnB5wfn8Of96lPwmff5/1QIjg/TFM8XqhjlFxwWyxMvEUYO8AoYB9ICW/4F+hb2rfK77yDtzuru6OrnVui56lPv7vXZ/QkGZA0GE3sWzRdnF+AVvRNIEY0OcgvcB9EDhv9F+1r37PP48GHuEOwc6t7o3Oij6onuePTi+9UDPwsuERMV2hbYFpkVpRNWEcYO4AuJCLoEnQB3/JL4IvUr8pbvSO1I69zpfum56vTtN/MW+rwBIQlND5oT1BU4FkQVgxNaEfEOPQwgCY4FoQGa/cD5TvZU88Dwde5v7OHqNer16o/tKfJ3+MP/EQdpDRESuhSGFeIUWBNWERAPiAyiCUsGkgKu/uP6cfd09N/xmO+Q7enr/+pR61jtTvEH9+r9EQWFC3wQjhPCFHIUIxNIESUPxQwSCvQGcAOx//r7jPiK9fXysPCo7vHs1evK60rto/DE9TX8JQOkCd0OURLsE/QT4xIyETAP9QxxCokHOgSkAAT9nfmZ9gD0vvG47/fttexa7GHtJfCw9Kf6UgHLBzgNBREEE2UTmBIUETMPGg3ACgwI8QSGAQL+pPqf9wP1wfK/8Pnumu397Jnt0u/J80D5mv/9BY8LrA8LEsgSQRLtEC4PNA0BC3wIlQVXAvL+ovud+P71vPO98fXvge6u7e3tpu8O8wL4//0+BOcJSA4DERoS3RG9ECEPRQ01C9wIJwYYA9T/lfyU+fL2rvSx8urwae9r7lnune988uz2hfySAkMI3AzrD10RbRGEEA0PTw1eCy4JqAbHA6YAff2C+t73l/Wd89jxTvAw79nute8T8v/1LPv7AKUGagvHDpAQ7xBBEPIOUA19C3IJGAdlBGsBWv5o+8P4efZ/9L3yL/H572nv6O/O8Tn19fl9/xIF9gmXDbUPYxD0D88OSw2TC6kJeQfzBCECKv9F/KH5Vfda9ZrzC/LE8AbwNfCr8Zn04/gY/owDgwhfDMwOyQ+bD6QOPw2hC9YJzAdxBccC7/8Z/Xj6Kfgt9nD04fKO8a3wlfCn8R708/fQ/BcCEwcfC9YNIg83D3EOLQ2oC/gJEgjgBV8DpgDj/Uf79/j59j31sPNX8lnxB/G+8cXzJ/el+7UAqgXbCdQMbQ7IDjYOFA2pCxMKTAhBBugDUAGj/hD8v/m+9wL2efQc8wryh/Hu8YzzfvaZ+mn/SgSVCMkLrA1MDvEN9QykCyUKewiUBmME7gFZ/9H8gfp9+MH2OvXc87zyEvIz8nDz9fWr+TP+9gJQB7YK3gzEDaINzwyZCzEKoQjbBtAEfwIDAIn9PPs3+Xn38/WX9G3zpPKK8nDzjfXd+Bb9sQEOBp4JBQwwDUkNoQyICzYKvwgXBy8FAgOiADr+8vvq+Sv4pvZM9Rz0PPPv8ofzQvUu+BT8fQDTBIIIIwuQDOYMbAxyCzYK1QhJB4MFeQM3AeH+oPyZ+tf4U/f69cj01/Ng87PzE/Wd9yz7XP+fA2QHOArmC3kMLwxWCzEK5AhyB8sF4wPAAX//SP1C+375+fei9nD1c/Ta8/Hz/vQp91/6T/53AkgGRwkwCwEM6Qs0CycK7giSBwgGQQQ9AhMA6f3m+yD6mvhF9xP2DvVb9D/0APXQ9q35WP1cAS4FUQhxCn4LmgsLCxgK8girBzwGkwSvAp0Ag/6E/L36Nfnh97H2p/Xh9Jn0FvWS9hf5ePxQABsEVweqCfEKQgvcCgQK8gi+B2YG2wQVAx4BFf8c/VX7y/l3+En3PfZo9f30P/Vr9pv4sPtV/w8DXQbcCFoK4QqlCusJ7QjLB4kGGQVxA5UBnv+v/en7XfoI+dz30Pbx9Wn1d/Vb9jj4//ps/gwCZAUICLsJdwpnCswJ4wjTB6QGTgXCAwECHgA7/nj86vqU+Wr4Xvd59tr1vPVf9u33ZvqW/RYBbgQwBxIJAwohCqgJ1gjWB7oGegUKBGQClwDB/gL9dPsc+vL46Pf/9k/2DPZ09rj35fnU/CwAfgNWBmMIhwnUCX4JxAjVB8oGnwVIBL0CBwFA/4f9+Puf+nX5bfiC98b2ZfaZ9pn3e/km/FP/lAJ7Ba4HAgl+CU0JrQjRB9QGvAV9BAwDbgG3/wf+efwe+/T57fgC+D73xPbM9o33JvmO+4j+rgGIBLwGGgilCIMI8AcgBzUGNwUgBOcCjQEhAL7+AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==]=],
    open = [=[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]=],
    close = [=[UklGRiQjAABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YQAjAAAAAIcA4AF3A8MEhgXCBYMFrgQRA5gAfP0i+tX2nPNp8I/tEexj7Z/ym/uiBhIRkBgXHCccChrAFm4SqAw0BZX82vPm697kbt682EDVl9Yd3yLv/QPcGOwohjH/Mqkv4imkIgMZZQ1GACXzhufu3ePVCM9jypnKkNJF42r62BLSJp4y4jXyMtAsTSWOHP0RmwWO+HLsQuLZ2aPS+MzdykvPO9zO8OkI2h7nLVk0lTOMLqQnoh8SFpoK5/1/8bbm191Y1gnQOMyazcnWMugH/woW7CeoMXsz5y+0KVAiphksDxQDoPZR6+jhF9pi02POTs330t/glfW4DM4gvi16MsUwfCuqJMMcRBP6B737EPAT5t3d3tYe0SjOtdAD2/LsRAPEGJgobjACMfEsvSZ4H+EWgQy9AOj0Yuqw4WnaMtTmz9vPstZr5RL6GBBNIj0tdTD9LY0o1SEGGpkQhAXH+dTumOX73XXXR9I00OXTNt988SEHCRvgKPkugS4UKuojwhw7FPsJlv5k86DpleHN2hPVgtGC0nTa1ulA/gkTYCNxLFYuQyu/JSQfaRcPDjoDBPjJ7UHlLt4b2IbTWtIo113jzPWcCt4czShXLf8rVCc8IS0atRGcB578EvIG6ZXhQdsF1jbTQdU43hruGQKOFQ4kZislLJwoFCOVHOoUpwsbAXH26+wJ5XPe0dja1JvUeNpu59r5sw1KHmsokiuCKbAkrx62F00PYwXV+u/wkeir4cTbCtcD1RTY+OEx8p4FqhdhJCUq6ykKJoogJBqJEmEJJ/8O9TXs7OTJ3pbZQ9bz1tDdZeuj/WcQVB/DJ7IpEicrIkMcXBUEDVEDOfn47zzo1OFV3CLY6db42q3lFPbKCGIZYiS5KK4nkSMfHtEXQxA9B1391/Ok6+bkLd9r2sPXYNkr4TrvIgG7EgIg4SbCJ7Akwx/0GR0T2ApkAcn3Ke8E6A/i9NxM2eXY6d1S6b75nwu6GhkkKyd2JTEh0xuZFRgOOgW8+8vyNev25J/fT9tZ2eHbg+To8lUEsRRdIM0lxyViInkdwhf4EMsIn/+D9oDu5edY4qHditr32uLg3+wr/RsOuhuRI4QlRyPsHqQZfBMJDFoDRPrm8eTqF+Ud4ETcBdtx3tPnafY6B0wWbSCQJMkjKSBMG6oV7Q7cBv79ZvX47dznr+Jb3tvbHN3f41DwVgBAEGcc0iLNIyUhwhyRF3YRFAqcAfT4JvGs6kjlqOBK3cXcDeEV67j50QmRFzsgNCPOIQYeOxmrE/oMCwWD/G/0ju3m5xHjI99B3VPf2+af8z8DEhLIHOUhCyITH7IalhWIDzsIAADK94jwjOqG5T/hYt6Z3rLjRO7S/BkMhhjNH8Ah2h/8G0MXxBEfC1kDLPub80DtAOiA4/rfud6Z4dDpx/bjBZET5BzSIEUgFB29GLQTsQ18Bob+xPYJ8IDq0eXi4YrffuBb5lvxsv8TDjAZLR87IPEdCRpkFfIPWwnEAfn56fIK7Sno+ePg4ETg6uO77MT5QQjEFMQcoh+AHikb4BboEe8L2AQt/eD1pe+F6ifmkuLF4HTiBOlV9FYCwg+VGWMerB4VHC4YnRM2DrAHTgDo+Fby6exe6H3k1uHh4UTmle+S/FkKrRVtHFsewRxSGRoVMRBECk8D9Psd9VrvmeqG5k/jEOJ45KjrLfe+BCgRuxl1HRgdShpqFusRjQwdBvj+9/ff8drsnugM5dvij+Oi6FvyLv8rDFMW6BsDHQsbkRdrE44OrQjhAdz6ePQm77vq8OYZ5G3jhuZD7t/56AZIEqoZaxyEG5AYvBRNEPkKoQS+/Sb3gfHc7OjopuXv40rlAOsH9ZQBug26FjsboRtgGeUV0BH+DCwHjgDi+e/zBO/o6mTn8OTZ5Jzo0fBo/NMIJhNnGUsb9BnpFpcTaRCyDPwHhwIJ/RD4nPNT7zPrFeh856jqjPFo+m0CGQd0B28EQgA3/av8w/63AmEHmwtdDtsOzwzUCHUEsgEAAmUFRAoWDq0OMgtMBGT7r/HJ5xbelNU40GbQnddE5Vj2WwaFElcadx82JNYplS8oMzIytSuPINkSpwQV9ynqgt0r0QzGxr0mupm82sXH1Tnr7gO2HAYy/UBKSHpIZEMNO7EwiCReFm4Gz/UN5lHYxczXwkq6QLRrs+e6XsyL5iQFUCLqOEVGnkosSIlBfzjBLWEhghOmBJz1LOcC2szOZcbJwcfBnsblz8bcVey3/eAPPSGjL9o4iDvpN78vbSXBGj0QYgXF+QnuDeT83d7cvt8C5OXmJ+fT5aXlaOlR8lP/pQ0aGlwihiX+I+oewhcPEEsJngR5AlgC3wJyAuP/4Prs8/zrIORy3UDZ/tjV3dnnefW7A2UPdhYhGZAZeRpoHcchRSVFJW8gVhfsCzkARfXp6pTgTdY+zWHHmsbYy8HW+OWv9xMKdBs6KgM16DrEOzE4ODHOJ44c0Q8QAhf04+Yw2yfRkMiJwT69+708xivXYO/XCkAkDDcVQQNDRz+EOEIwwSacG78O0gD88kHmHtup0RTKJMUhxEjIGdLv4CHzega9GPcnpjLiN4k3azITKj8gJRYPDJoBfPZJ65rhWtug2ebbM+BF5Pnm/ehi7Czz5v0RC8sXLiGZJRol8SCnGmQT3guxBKn+lvrf+A/52/mr+Vn3vPKy7MLml+KZ4ajk3ete9kkCIg2aFJYXwhZKFLYShBNVFi0ZphlTFmwPdAYd/Uv05ut/40PbfdQp0fHSMdq+5XTzQQHbDdcYKyKcKYcuJDACLlIo2B+KFUYKrv4681boXd6Q1TLO0siXxjDJMNIL4kr3hw52I3gy8zmcOqU2UTDgKFkgQBZ7Csb9YPFW5vjcANVDzmXJ+8faywnW+OVx+VMNoh5TK5QymTQ0MoAspCSjGygSbAhZ/u/zt+nf4NPaidjl2b7dj+Jw55/sPvNW/MoH+hNYHqQk9CX4IlIdlhaTD2gIHgE9+tj08vG/8ULzs/Rs9NTxsO3L6Rno7emJ7yP4KwK/Cw0T0hbIFtcT1A/BDN0LBw3YDm4PdA3ACDMC//rm8wftTOYj4M7b+9rX3jLnX/L1/fMHoA+BFZkabh+HI64ltSQyIL0Yig/LBTf8/vIX6pnh79nS0zPQGtB/1PXdPOzk/V8QpCArLNExFzKWLgApSCJ/GlARvgZ++6/wOOdK34HYndI9zgrNB9Fj24Xr7P4NEqQhxSs0MO8vXiyvJpofgRekDkMFp/sd8h/pY+HF2wXZadme3OrhpuiV8Nf5awSrDxUawyFDJVAk5x+pGfMSSQx4BUD+Bvfw8E/tt+x07s3w+PEj8fnuQe3q7QTySPlJAiALGBIhFukW0hTNECwMRwgMBp0FQQa7BuYFOAPn/pT55PNF7hjpBeUi45bk7el98nH8gQUNDNcP9xH6E8sWEBpjHDYcwxh2Eo0KWQKO+i3z6+vB5ETehtmu14zZYd/b6CX19wKwEIscDSVzKeMpNyd6ImQcMRXdDJID6vm68Kro2uEA3P/WfNME02nXsuEt8VYDrxQWIuYpSCyhKpcmQiH+GrsTewuSApH5BPFQ6brio92W2i3azNxu4qLqsPTK/wcLXxWdHaUi2SNyIXYcPRbND3QJ6QLo+8X0ku6f6qTpM+vb7ffvtPCR8Bbx3fOX+ZcBJQpQEcAVEBeoFVQS7Q03CewErQHc/2H/oP+u/7X+TfyX+CL0q+8B7PjpWeqr7dLz1Pv2A2YKBQ77DpcOgw7FDx8SOxSAFAQS/gyGBtT/i/md87Ltyuea4lrfNN+p4mDpWvJm/H4G2w/YF94dbCFCIoMgnRwbF3QQ+ggBAfP4TfFy6t7kzuAx3m3dht+r5W7wBf8wD+UdayheLf8ssSgQIisaUhFrB3/89/CG5c7aL9HtyI/CJb8uwAXHL9Ts5j79aBSiKa46KUapS6FLNEfWP9k2Ay1kIpQWRgnY+nfstN/C1VbPRssmyAzFMcLpwOzCZ8lk1NbiH/OxA2ATRyGSLGw0RTgwOBE1WDBjK9wmdyI7HSEWugx3AY71iOrK4TLc3dkY2o3bqtxB3C/ante91tzZWeLh73oARxGXH70pRC+MMEQuEymvIRsZtBDmCZcFvwNwA1sDgAKjAC3+rPtI+Yz2svIs7R3me97B13bTt9Lz1dfcZ+Y38cr7CAWqDEkTCxroIfcqHzRvO/U+mD1+N8ot9iEjFdkHQfqF7BDfeNIyx3G9VLVgr86sbK/suPrJkOH6/IgYpzDDQsNN7VFwUN1KsUIPOZgubSNnF2oKyvxj72jj5dlD0yHPo8wRy0/K+Mrzzd7TqNyZ57fzMwCIDD8YpCKvKlovMjC4LUkpfSRbIOQcKhn/E7kMpwP9+UnxzuoU58bl6OUy5nnlGONA3xDbWtgP2XvesOhl9mYFVhNlHqUl8yikKFElyx8yGesSPg7XC2QLsgtBCxQJJwVcANX7M/gy9dzxOO305rvf+9hQ1O3SR9UW24njkO0b+E8Csws/FEIcFiS7K50yqTe2OQs4rTJNKucfVRQZCH770u6N4jjXKs1uxPu8JrcHtGi1G70KzHPh0PqFFP8qvDvKRZ1JekjUQ9w8YzTlKqAgsBUnCj7+cPKE51Teg9c+0znR89AB0knU6NcC3YPjJuua87H8UwZFENUZ3iEaJ8ooIydTI/MeNxtZGJ4V5xF6DIgFIP6j9xfzsvDW72/vau4N7DHoQuM63nnaeNle3JHjdu6M+9gIdxQRHQYiYyO4IfYdVRkdFVcSXRGpEfgR4xCSDTYI6wEU/I73PfQp8Sztr+cb4bDa+NUg1KbVW9qs4eTqUvVEAA8LFxXyHXQllCs/MDMzADQ9MsMtxybKHWUTJwiG/Pbw7eXU29zS/comxKS+c7sxvJDCe89g4gr5NRCaJOozSD0pQbJAHD1SN+wvVyf0HRUU8Qmp/2f1kOvS4vnbpNcC1sHWNdml3Ivgp+T66LPtF/N1+fcAbwkoEvIZfh/qITUhSB6OGjkXthSREukPFwwvB/oBhv2E+uv4A/jR9or04PAH7IzmNeHs3Lnamts04IXorfMXAOMLaRWpG3MeUB5GHIsZOxcHFv8VfhZhFoUUVhAnChcDifxn97fzpfAU7VTokOLB3DnYD9bN1nLas+As6W/z4f6dCpcV2R7UJYQqQy14Lkkujiz0KEYjmRtUEhAIcf0B8y/pOuA12BHR0crOxebCc8PWyNPT+uOC97ULyx25K6o05DhGOcM2DjKjK/EjdRunEtIJAAEl+F7vNOeM4FHcB9t73NPf5+O258PqLO1+73fyt/aJ/LkDjQvlEocYlBvdG/4ZEBcoFNcRARAfDrMLrwiFBdMC8QCv/2P+S/z0+GL0Ae9f6Qjkht+D3NbbUd5h5K3tAfmTBJcOzBXTGSUbxhrTGSgZJhmdGegZIhmFFsYRSAsJBDr9sveY81jwBu306BbkDd/d2nzYhtg124bgWuhm8gz+PAqXFdIeKyWkKOYpyynmKDwnYSTRH1QZJhHmB0/+/fRM7FvkJd2o1gXRpMxCyuHKfc+d2O7lJPYyB+oWjyNCLP8wSjLJMAsthie4IC4ZcBHLCTwCl/rT8mHrKeU44TrgEOLG5fjpZO1t70fwxvDv8ZP0BfkL/+4Frgw9Es8VERdMFj0UxxGZD+8NowxoCxIKsAhpB0QG/gQcAywAC/z29mnx4euz5iLimd7N3KXd0+Fi6XTzcf6MCGsQihVDGHkZGxrEGo4bJxz+G38aRBdBEtsL1AQV/lT41PNM8Bntoemn5XPhs90126raiNwU4VjoGfKl/ckJABXdHY0jHCZcJmUlByRqIhogbxz+FuQPswcs/+r2Ou8n6KjhzNvR1ijTZ9E00iDWdN395+n03wJMEMEbTiSYKcArKCtHKJwjsx0iF2wQ1QlUA7X86PVO77/pQOZ/5WXn/urb7qzxzvKF8r/xo/EP81n2R/syAUcHqgykEMcSDhPdEeQP4A1bDIgLSwtZC2QLKwtvCu8IbAbKAir+5vhy8yjuMump5NLgSd7y3Z/gl+ZL72b5RAOMC6ARqxVWGE8a8BspHZ8d6xzFGh4XGxIPDH4FA/8u+Vr0iPBh7WjqPufX45HgEd4a3VneR+IM6WLyg/0qCdATEBwjIRwj0CJmIcEfIx4qHCkZoxSXDn8HCADC+PDxm+vC5YjgQdxZ2TjYLdls3A3i+unY8+/+OAqQFPMctyKiJdklwyPrH+oaURWSD+UJQgSE/qT4+PI67kbrr+pd7HTvpfK79CL1HPSR8p/xIPJq9E34Rv2rAtEHFgz1DigQyQ9WDpIMQAvYCmILfAyQDQcOdA2iC5MIdgSd/2v6OPU68H7rDOcV4yHgAN+C4A/lWuxf9b/+OgcfDlwTSxdRGpUc8R0cHuEcQBpmFpIRBgwHBu3/Jfob9Q7x6+1V69boJOZX4/Pgwd+V4AnkT+oU84D9TwgVEpcZJR7TH18f1R0QHGYalhgOFlMSTQ1NB98Affpo9Lbue+ns5GHhM9+Y3pnfJeIz5s7r+vKF++EEJg5JFmEc6h/YIIMffBxfGLQT1g7xCQcFDQAS+2D2hfIi8J3v2/Ap83n1zfan9jz1U/Pi8bHxGPMD9hX60/60AyUIkAuEDeEN/wycC5YKkAqoC3ENJQ/5D2UPSA3WCXkFoACo+8r2GvKX7UXpVOU24pzgPeGM5HTqSvL/+oADCgtKEUEWChqlHO4dwB0bHDIZVxXVENQLaga+ACL7Cvbd8bzuauxq6kvo9OXJ44/iKOM75vnrA/R8/TMH7Q+kFssabRwaHKwa5RgoF2EVLBMfEA0MHAenARL8ofaD8ePsBOky5qjkbeRW5Snnzulv7VryvPhhAJgIVxCTFpMaJByKG1IZEhZBEikO8AmpBWMBRP2I+Yz2rfQh9Mv0LPaF9yD4mfcO9g/0XvKn8UnyU/ST97X7SgDHBI4IEwsWDNAL7QpNCqAKEAwuDiIQDRFjEBIOcgoMBlwBs/ws+Mfzfe9Y64rnceSX4pLi0uRw6RXwCfhnAGMIZg8fFWUZHhw4HbkczxrSFyEUABCFC6YGbQEY/Bj36/LQ76Xt9+tI6mHoieZ05fnlu+jh7Qn1YP3cBXsNcBNNFwoZBhnbFygWWxSOEpIQFg7fCuUGVQJ5/Z74DPQH8Nbsr+qp6aPpUOpo69js4u4A8p32wvzpAx8LTBGdFb8X3BduFvwT7RCCDeAJLQaTAkT/bfw5+sX4G/gh+JD4+/jz+C74r/bI9AHz6PHl8SrzsfVF+Yj98gHmBdEIZArACnYKTwrvCoQMqA6NEF4RlxA0DpoKWQbtAZj9YvlD9TTxSe2z6b7my+RN5KzlJ+mu7tj18f0hBqAN0hNYGAob7hs0GzAZShbdEiIPHwu9BvcB//w8+Cr0GvH/7n3tHeyf6i/pYeju6GTr4e8I9iT9WgTlCiwQ1RPFFSMWTxXCE/ARHRBKDkQMxwmlBuECsP5k+l728/Jl8NLuKO4r7oLu6e5c7y/w7/Ej9fj5EgCbBo0MDRGtE3gUyxMVErEP2gzCCZ4GqgMaAQz/e/1R/Hn73vpv+gj6efmP+DH3evW481zy1/F68mH0c/da+5f/kAO9BssIygknCoEKYQvvDNsOdxAPETEQ3g11CnwGYQJb/m/6kfbD8h7vzusL6RbnQ+bw5nfpAe5k9BX8OwReCXMPGxT8FhYYsRdAFjAUyBEaDxEMlgiqBHQAO/xC+Lf0ovHu7ojseuoA6XvoVenV6wHwkvUB/KYC4ggtDjESwxThFawVXRRBEqYP0AzlCesG0gOIABX9pvmO9if0sPIs8mLy6/Jn86HzsvPx89j0yPbj+fT9fwLrBqUKSw22DvcOQQ7WDP0K+QgGB1UFAQQLA1UCqQHRAKX/Ff4w/BX64/e19aPz0vF38OLvZPA08lD1b/kK/oMCVAY1CSkLcAxfDTIO8w55D30PvA4aDagKnQdBBNIAev1G+jn3UfSV8Rfv+uxt667qBeu37PTvu/TF+oUBPAggDpASOxUrFrYVVBRvEkQQ3g0oCwoIiQTHAAL9cvk89mjz7vDI7grt4+uY623sh+7h8Uj2Z/vQABoG2gq6DnUR5xIREx4SVxAVDqELIwmfBv0DKgEv/jz7ovix9pb1Q/Vx9br1y/V/9f70pvTs9C/2j/jo+9j/3gN9B1QKKAzsDLcMvQtGCqQIIgf0BSoFqAQ3BJMDiwIMASv/Dv3h+r/4r/az9NzyWPF08Ifw0/Fh9Pr3LPxvAE4Eggf+Cd4LTQ1oDi0Pfw83DzsOhgwzCmoHWwQxAQr++voT+GD15/Kv8MXuQ+1f7GXsq+1x8MT0Yvq8ABIHnAzAEDoTGhS2E30SzRDcDrMMQgp7B2MEFgHE/ZX6qfcN9cny5fB476TukO5X7wbxk/Pl9tL6Jf+aA+AHmQtuDiEQnhADEJcOsQybCn0IWQYaBLABKv+0/Jf6Efk5+PX3/ff496b39vYV9lz1M/Xr9af3U/qq/UcBwgS4B94JDgtHC7QKnglgCEsHkAYuBvgFpwX1BL0DAgLw/7v9kvuI+Zb3sfXf80fyNPH58Njx4/P09rP6tP6SAgkG9QhQCx8NYg4UDysPog58DcsLpwkoB2cEfgGI/qH75fho9jD0N/J78ArvFO7n7d/uQvEi9T/6EADeBfEKww4WEfwRwRHBEEsPjg2ZC2YJ8AY9BGEBev6k+/r4k/aE9OLyxfE98VLxAPJB8w/1afdP+rP9cAFEBc8IrQuODVIODQ7+DHYLuQntBxcGKwQhAgoAEf5p/Dv7jfo9+gz6t/kS+R74BvcW9qH17PUa9yj57vsl/3ACcgXRB1UJ7Qm6CQcJLgh/Bx8HBAf2BqgG3gV/BKICfABJ/jH8QPpp+Jv21/RA8xfyp/Es8sDzTPaW+U/9IQHHBAgIvQrIDBoOrg6QDtYNnQwACxIJ2wZkBLoB9/4+/LL5a/ds9anzFvK88MXvf+9C8FLyvfVH+nT/oQQxCa8M6A7nD+IPIQ/kDVcMkAqWCG0GGQSlASD/mvwv+vz3JPbG9PHzpfPQ81n0L/VT9tz35vmD/KP/CQNbBi4JLQsvDD0MiwteCvIIbAfXBTMEggLXAFL/Ev4o/Y38Hvys+wz7KvoO+d731PYt9iD21PZX+Jr6bf2CAHwD/AW9B6YI0AiACAsItQebB6gHogdFB2AG6wQEA+UAxP7E/Or6Kvly98T1PfQR837yu/Lj8/T1z/g9/Pn/uAMvBxoKRAySDQgOwQ3rDLILMwp7CIcGUgTlAVj/0vx6+mb4mfYC9ZTzVvJv8STxxfGL8332aPrh/mIDbAedCsYM5g0dDpwNlgw1C5oJ1gf1BfkD4gGz/3b9R/tM+a73j/b29dT1AvZd9s/2ZPdD+J/5mPst/ioBOATxBv8INQqSCjoKYwlBCPYGmgU3BNoClAF1AIv/0P41/pz96/wP/AP71vmk+JL3yfZ59sn21vel+Rj87/7PAVoERgZ0B/cHCQjxB+YH+gcUCAEIjAeSBhcFPAM1ATH/Sv2F+9j5OPin9jr1GPRw83HzPPTg9VX4evsV/9UCYQZgCZAL0gwvDdIM9AvICmwJ5wcsBjQEAQKv/2H9Pfvi+qL5iPiI96P25vVz9Xj1IvaO9775jfy7/+0CzwUYCKAJZAp9ChgKYwmCCIcHcwY9Bd0DUQKmAPP+T/3P+336VflN+F33ivbq9aT15fXW9or48vrf/QUBDwSpBpoIyglBCiEKmgnUCO0H7wbWBZcELQOcAfX/T/7B/F37JPoR+Rn4Ofd89v716vVs9qT3mPku/Cv/PQIQBV0H9gjSCQYKuAkWCUYIWwdZBjgF8AN+AusATP+3/UL89/rW+dX47fce93r2JPZH9gv3iPi2+m79agBbA+8F6QctCb0JtwlECZEIuQfLBsQFmwRKA9IBQACs/iz90Pue+pL5ovjI9wz3hvZd9rv2w/eA+d77qv6ZAVwEqQZQCEMJjwlZCcsICgguBz0GMAX+A6QCKQGe/xj+rvxr+1D6V/l1+Kr3BPeh9qr2R/eR+If6Cv3d/7ICPQU+B5QIOwlNCfAITQiFB6UGsAWcBGEDAQKFAAP/j/08/BL7DPoj+U/4lfcJ98/2Dvfq93L5mvs2/gIBsQP8Ba8HtggaCfoIfwjOBwEHHgYkBQgExQJgAen/cv4T/dj7xPrQ+fX4L/iJ9xz3D/eH96L4ZPq0/F3/FQKTBJgG/ge7COQImwgKCFAHfwaZBZgEcwMqAsMAU//s/aP8f/t/+pz5z/gY+Ij3P/dj9xf4b/lj+9D9dwARA1YFEwcsCKYInAg0CJMH0wb/BRUFDATfApABLADG/nL9Pvww+0P6b/mu+An4lPdz98z3vPhM+mv86P6DAfMD+QVrBz0IfAhICMcHGwdYBoAFkQSBA0wC+wCc/0P+Av3l++z6D/pH+ZT4A/iu97r3Svh1+Tj7dv35/3sCuAR7BqQHNAg/COoHWAelBt4FAwUNBPUCuwFpABP/yv2f/Jf7sPrh+Sb5gvgI+Nj3FPjd+D/6LfyB/vwAXANgBd0GwQcUCPQHhQfnBjAGZgWHBIkDagIsAd//k/5c/Ub8Uvt7+rr5C/l5+Bv4EviC+IP5F/so/Yb/7wEiBOgFIAfDB+MHnwcdB3cGvAXwBAsEBgPgAaEAW/8d/vr8+PsW+076mPn2+Hn4O/hf+AT5Ovr7+yT+gADNAs0EUgZHB64HogdDB7MGCAZLBXoEjgOCAlgBGwDe/rH9ofyz++L6Jvp7+er4hPhr+L74mPkA++X8Hf9sAZQDWwWeBlMHhwdWB+IGSAaaBdoEBQQSAwAC0wCc/2r+T/1T/Hf7tPoD+mX55fid+Kv4MPk++tP70/0OAEcCQQTMBc8GSQdQBwEHfwbfBS4FawSQA5YCfgFSACP/AP73/A78QvuM+ub5Vvnr+MP4/fi0+fP6rfzA/vQADQPTBCAG5gYsBwwHqAYaBncFxAT9AxsDGgIAAdj/sv6f/an80vsU+2n6zvlO+f34+Phg+Un6tPuN/aj/ygG8A0oFWgbmBv4GwAZLBrcFEQVaBI4DpgKgAYQAY/9K/kj9ZPyd++z6S/q9+U/5Gvk++dX57fp//G3+hQCOAlEEpgV6BtIGxAZuBuwFVAWsBPIDIAMxAicBDgD1/ur9+vwo/G/7yfoy+rL5WvlG+ZT5Wvqe+1D9Sv9WAT0DzQToBYQGrgZ/BhcGjgXzBEgEigOxAr0BsQCd/47+lP22/PP7R/uq+h/6r/lx+YH5+/nv+lr8JP4fABcC1QMvBREGeQZ7BjQGvgUwBZME5QMiA0MCSgE/ADL/Mf5H/Xn8xfsj+5H6Evq1+ZT5y/ly+pH7Hf32/uoAxQJVBHgFIwZeBj8G5AVlBdQENASDA7kC1QHZANP/z/7b/QL9RPyc+wX7fPoL+sX5xfkl+vf6Pvzk/cP/qAFeA7wEqQUhBjQG+gWRBQ0FeQTXAyEDUQJoAWwAa/9y/o/9xvwW/Hn76/pt+g364fkE+o76i/vz/Kv+hwBUAuIDDAXEBQ4G/wWxBT0FtQQfBHoDvgLpAf0AAwAK/x7+Sv2R/O37WvvV+mT6GPoJ+lL6Bvsp/K39cP9AAe4CTgREBcsF7QXBBWMF6QRfBMcDHQNcAoIBlACg/7D+0v0O/WL8yvtA+8T6Yvot+j76rvqL+9H8af4sAOoBcwOjBGcFwAW/BX4FBwV9BOkDSgObAtoBBwErAFP/if7X/T/9vvxO/O37nftp+2L7m/si/Pj8E/5a/6cA2gHTAn4D2QPtA8kDgwMqA8gCYQL0AXwB+QBvAOT/X//n/oH+Lf7m/ar9eP1T/UT9VP2M/fP9g/4z//D/pAA/AbIB9wEQAgYC5QG1AYABSgERAdcAmQBYABgA2/+l/3j/Vf87/yf/Gf8Q/w7/Fv8q/0v/d/+r/9//DgAzAEsAVQBTAEgAOQAoABgACwAAAA==]=],
    notify = [=[UklGRqQ+AABXQVZFZm10IBAAAAABAAEAgD4AAAB9AAACABAAZGF0YYA+AAAAAOoB0wMZBfUE2Al5AkD3LOuv7vb0A/He91wGJyaXItIY+QnwC5H90dUfyKnPG/nV91AHxh7DSa5IvBbs/HHpl+sVtPGtpcnUCUEiVhueN2dHk0v//0jc1My118jEALa26CIcfkelKpkzdDUZLW/w/bdVwffMFeDHzoUC/TRnVb05IRo+IIEG1uIWpDa6EdkG+Nf4hhApS85RYzsj/QP+rusu0TyqpLbL9dUPlCFFHGRMLkpuJpTo/NIJ34zGAb8Jw4IPoi+KN9UphTUjPm8GwdY3s3LVENI31EzjiR3STy89BC2IFgYjMO/YwKyryMyl8JrrcgcbKENdBj+UGs/8LPph5YawcbRl0ZEP5Q0PHaY0DlGUPQ37neRa1rfeQrbpvwnq9iOFNeQjQThXOHYtBuK2xuLGfdds0tvOkwkqNBdPvCcOJvkg2AyW1nirGcc72+Tz7eoqHUxGPVBxKqADtQhe7MTPnqQXytDyGg45ER0iiFDPQpUgH+S057TcnchUtqvPvRNtJTUveCNWRGA0oAUW0YvE5NunywHSQeLbKl1A6DeiJPEjsiPZ53bDmbGL3YjjWurfAdcyG1YcMtAaRgH8B9HYrLWYthbgcQg6AqUdbjWGVvMqZv/S52nlItl5sfLHCu44J8Mg5SY1NxlAQCJy3nzS5s0K3WLDWNjzCdc3qj7DISQukiJ1DlHKVrv0y2zhzuaW6c4kKELaShwbxBFuChDxbsZeq9HWSvBgCbcDnC5PSzlAMhTC6xn0ztpIyPOwTOEtDusgoyHkKMxJ2SteA+3OBNkp2J3LH8sJ7N0tWDNQMgQgHDOOGsznlsHlwOfi3dlU6dH/HD4jRsst0hbxDeMJ2tARu1O72+13+R0A8Bl/PVdQmB4OBLfsY/KwzJS228oh+Dkf5BMhKkA3akXBEQrlF9jS2bPXP7054ZoKCTnGKj8mUS+XKBMGyMdJyQ3QAuWg11TyqCRwQuA8dhbfHOMKbPMWvCW7gtof8jz9YwHuNutEPDwUCF37gPZs3VrBcbYm7ZIH9xtmFUk19kS0KIf7H9cb5pXTt8vdxVH7cCbZLC8oWCXjOW0Rleg4wezTp92N1yzk3gZKQJI3PCtSFP8cjQEQ0Sq80ce38RrtOwBuF/5GAkGUG0sEN/j/9P3Dt70Lzo0CNw9TEbEoKj2zQIIGXu363B7lWcuuwYvkTBDPMLgdKiwuL8QtD/jTz3PQSdil30PQofufIiFC9ip3HEggKQ+a7Se6CsqE24Xzde5UCcg2pUJXMQsFyAjK9evforgcxXXvZAU/EacSYz5MPVUmy/JJ57joxNO0xsDJ4gWiHCcoAB6jMfM1+A3n5EzJtuBv1qPXIt+fE9k38S/2JL0Z2SQi+CXUAr1p2P/qp+jh/CQcy0gOMhoc+wOKBmvt8sP4wETXwQT2AKkSXSYtReEy5gRV8cvm2OfZwa3JHOZiF7sgMBtILWIzuSox7tfa1NQ04XDTqdM5/3QkWzqnHu4kTSABFBbix8Lu0cvfDO485tYS3jJpQTwiagwpDi/4MNzdtuPTd+2sBIgD6xm7Pj850B5k8SL2t+bK1Va/l9bWBhUXXx9uG4c7xy0oDWTfDdkK4/7TK9Ra4cgc5Sv/K20d0SUFImX0+tNQxAzkYeGB6FL4dyYyQBYqzxl8CQAP1eN8yHnCwOTT/Mj6RhFBKQFHeyRECADzuPPY4BrBXs7w6woYihHkHa8rJzr2HtftxeF23H3jMcnd21n/figpK6McrigaI44Sndllz1fV3OUp4oLowBaSMbU6bhcRF3EOXPz80j+/xtvT7TD//vqUI8U5lTcJE8f5+fwN55nTY71v5DYCkhRnEzkivjyXKPoIZ99X6JzfENX4zfrrnhzQI5wlixtdMOAZ3PRJ0b7SquVc3FbmE/lKLi0zSidCFRoVPg213wvLdcia7kfxZfqUDWsxAj/PHMIJZ/gv/BvXTsYa0Pn1VA80CqQeTy1GPM0RkvP/5FPn2dx1x3Hh9gHoJwYcziA4KL0oFgkx2mXYZ9pD52LXhPDPFQ4zPC1KFkod/w8z/MDLaczk3dnw7/NM/PUnJzZpMjsKDQZs/SnqY8zaxMrr//5TDy0LCix4N9gmsABM6P7vvt3i06jLW/jzFQEg/xsQIqQyABSw81bSgOG/4CvcROFmAWgtfSmbI2YUAiBqBQLhnsrP1Dnv8+lz+UINHTjtMWgbPAgwA0H7btLHymjUrP1/AsAJNxynM3I12Qpe+P7pJ+/20qnMJ+OLCPweOBTOIw4pPyuN/Z7hpNyo4tTgktSg9qsVpjETH+8bJx56FPr01MyQ1izgIPEB6esDbyaqNU4nJwpbDsD91+oqxqXRd+wT/x0F0gsNMVMyciMd+n31YvBm31POwdHc/sAPWRu3FAQsny1YEr7uIttI6aDclduX3hAMaiXzJM0cwRpUIx7/TOJDzDDi4uht6Jb1cxP1NoYniBqLCAMO1fMN1AnMKt41/V75EApOG3Y5ICnhCqT5g/Oy7pXNUNKm5QIOohH3E/0i5i3sJYX3Bund4EHp1dZS2Tv4ExkhKXkXJiGNHkgXMOsw1UHbeOXa6j3lYQooJOUz4BogEYIQ8gCa5UzHHNz56zP+iPoME3QvbjAYGxn7Sf9q72vg48h23Sn+PA2jEhQVxjGcJ7oQXOpx6FXpjNxl1x3jnxEDHUAhABfDJOkei/1P4F3Ud+mg4ivouPJfHGsuziLFFrgOJxI67SXX1s2F6a31pfaSB64fczjFHq4MDfu5/aTnDM+51JDsjAxZB54V+SECM/Ma1fik7Kro5Oiy0JHfBflxHBAcshcmIiEijBMV5mHeXN5i6uPgSun1C90kVywMFFsYphDNA4Hd1c+94DPuKPgd9swZuCuvLuoQGAN+AiXxzdyyyZDnIvtbC/EI+xuLMMokPgs77Afz+uZ03ZfSR+3HD3EYdRpyF0IrhxiD/eLdAOHp6LLgK+Wy9Q8hqCRcIM4SlBh6Dpjrkte51Mzvke2d9tAEACcUMFIa9AvnAE8CvuBC01fWgvUyBL4DsRTuJHcyNxH4/OrutPEd4p/RtuId/T0aXBHDGnAhpCZACl7oveMQ5MrpENq671MLcSZPIPgUMhsWE4YBMdn22XriLPF67m35iRtQKo4oRAv2C2cCt/M01sDRwett+r8FSwQIIwEsWiORA9D07fYN5xHb1NKM9qgK3BUxEh4esyohFb76VeCj6yLlJeHz4Bv+cB6rHs4bmxOtHwoIyey91gDgee7c6bv0dQb+KsklURn8CVEKVf/a3n/VpNt4+rT6+QNnEtwq2SpWDQX/NfRM9uraV9bw44MDjRFJDZAbWCO8JoIBUu6J5nDrNeM52lTz3AzYI+gVchkPG/4WAvoK3Gng1+Ui8C7n0//lGYEqLB7/DHkQugOd8nzSCNwE7Gj7svz8BiMlFCntHlL/y/6F9vvov9Xm2RT6YQf0EMYNeCXpJSEUlvX86MfvcOOk34fgRwbPF8EbahUYGu0fRARh7GXZAepT6arpKvEfDQgoBx8qF0cLuxH/+NHg2NUH5Vb4ePU5Aw4TXS6/IM0N/f7P/NjzjdjS2XjnCwc/B+cNFRobKEggVv6y8vvqk++42/reHfTTEF0b0BEKHDgcuhdq8i7jWeMt673ph+a/A00Z4Se0FMYSAhHpBsTsdNXz4vjs2/lD9UAN9iJKKJ4W0wGkBK72rehp0rDj7PiGBukIDBAgKAAifRHB8nTz6e5o5GXbUOYZCX4S2BeoEbMhSRuuA4npk+H07dvly+go8CEUiyAoHO8SjhHCEu30SOJZ2Njt/vGc9HgAIxh9K8wZBg7FACcEpe3T2vfapu40BOYAWg4gGlAr7BYiAFv0XvJs7b7YN+Pk9f0S5BD3EqIb/B+jEu3vSump5nnuDuL/6iwEHBsgIP0QFheeESUIVOYg3azlEPC68+jzeBHDIPoljQ6pCMsF9fhM5BvVjeqV94gEwgEvFtsllSB2C+D1LfrV7YfkS9gm77sGHRAzEb4TAiXQFrgC/Ofk63vsquV85Y30URbPGX4ZKxBHGX4OnPRo4ZHfP/Hl7D70E/8JHsgjSRcQDLYGxgVF6Z/dBd3l9fj8f/+aDOAd3yg+EIQCgfY3+Vfn69rX5MX6qA/tCbAUbRsAI2MKyPJG7HvsZ+xr3qLvYgQcHB4WzhLkF3sUbQRl5FTkpudB8gfs8ve6Ec4gZB+FC3kO7gVx+ufetdzN7G741f7x/7kalyLUHhUFav3F+wHvWOFr2pL1ZQPdDcMKxxkAIwYV9/516/byHOrj5Y/iK/wRE1QWkBRCEjkdwAkS9eTgIekS73rr0fEmAsMfRhwHFnsKVA73AQPpTN7m4oL4iPaa/xoLziKBIUsOuwLq+yj7oOKI3kXmQQDtBzQIIhQcHjohSAT19pDuafJp5jPgi/ERB5UYEQ/RFbUXURd3/fDnMOij6x3wz+fB/LAQ6iBmFg0OfBDnB/T3Vd1f5FXtZvli94cDCxtNIbYZ6QJfBGr7cfDY3HPhNPcuAtEIyAisHigf8RNe+kPzvfQE6qTj9OPrAS0OEBQ8DzUYtRu9B2PzZOQJ8G/rlOsa73YICBwkGAQTrwzFEh/9huqF3jjrovX48xf+EQ1GJNEZeg5eAh4Dw/cw4lTglOr6AY8A1AjVEjkioBr5Ahf5MfNa9FbhL+RJ8swK0hBBD2AaTB0vHRH0vt2c4P3kJ+R59kocByTtIh8WS/KV5DP9Duyd7ZkUTSVOAZ/idfhO1B3sGRyRHQQ0lkDBIuu7JrVgz9OxNOyjP+ZT4FEKQ/4C87FMtl/Kmq45BedRuUKCLx8bkPzvuMXZ6Olg4wYz1jy4C/LprvYI2gC9Fgf/LakrLEuRJ6ncZsWwxK60WMHHOLdWmj6nUYUZdNn8rp2627Wu47JMRDq+KEc3PAxVyEPBlunN74cON0FCEmb52gYA0T2+Q+xvM7UmPi/aSAf0YtNxwCyrIcItFGNRwDTOTopIjOM2tBG43rcz2rMdrkINK+o+qCd3wQvLz+Vd7d/5iSlaN4H7DQa23SK3xe1mGgEfSCjIT8wfXckix+e5frLU/hIufT9xUABUXQQcrTTOkLmavQsGZDXSQSUz2C+53w7FFPDS2kvnMik4O4IONvRp84nKP9C+ETcMfC24VD8oU+E1w+nUL6eL0zopvTaVVU9Q/Bkaz9jI6sXyowTshDzvM1s01DDlAePT1tVQ5AvWKCNLP44GAgUx+wLfhbyQ9LAc2xt9UPcyt/Jc3qHPpKrXtuUWwz+lNmNY7zPA6aDSz7ZErwfS/i1zMekfikvtFLrb3s3i3kTlCwIsOacTaAbzEzXarLnl6EUW6Rs/LmFLyQ6N4sjb1aEPuU/9hy6WLxlKPV3S+EfRTMVyrpTMeAdbK/smUEYyM0rYH9KD64jZNfQyIP8sHw+ACgXxyLL96T8JSQdbKh1LWzJi4Vjcp74nqTHrmRMNKIxQSl2wF5jQjtZDwTurqvbwHR4vtkGaMKX5VM++9BbU+9dkJCstIBgvAz/9ms9Az4MAN/y4HqRWmzFU9Xfis9PqrWy+RRELH7VG/18IIRXz5tm0yyigNtfTJz8fmjbhOawOcOUB4VPaSdGlEt83EwkKDuUOIduBySvjTQpGEPRFQEFt/Cr+FdrsrHKwGvt+JhQolFllQKkBfevUxaSmAcy9EO0fphzzStwobONS5TrWKd0f+z0nzRjPCLgljOBzv7bkoACrDG4oBkp4HRn7gex0rRCtk/FpDDkg/UeUXEMXBeOP3gOqCMVw90kOniO1QZw/T+gC4mTuWtEG69sW/CFPF/wXiffywL/f2AHa78UiyUkFM1oChehi0JOkHN4I/fkLwUxUWkYq0uvs6RrH8ajo5M0JmhsuQtY3NAO36OPxd9gdy/cZJCUuEygZQf6t3hXPNvWH7VsNllM+MqoJ+/lH4MKxTLqn9XwKiTSLX30tmAW8+ZfM+6kkxx8RIRBgKo9F2hDC/FPqgdixzZ4Eey2sBnIXphkz5PfOa+Gi8pwHXTiLQf0M/A0Y9O+rI7d849wLbxszTGdM1A4ECfvTWaqGx936mwueFFJIizAp9Xbx592/0Jv52RWXE28SFCgj9Mm/eepi7X/8jCLmPacrCgsCA+a49a4u5WrzNwu+P1xYjScy/uHspLhGu6XvHPSGFohBXDvWAPvp+fnSyx3k3w4YEsceEh4BA7zLtOFN9iji4BMJROUx7xW+/5/YarOmztDum/HpPe9YRCyUDID2YtexqpzZ8PdEBtw+lzaaDjr6ofqB15fKPQrpHKgORSIyCpjiz9665QnmZvz6Rq80VxChFrfoqMA3uWTiuPWlIAFY9DBAGFUQnNtOr8jGoffEAtMd7UIJG6IFOwCx0g7Sn/hsHj8HNRY+KNfoh9xl36zjj/vMKuw6lBb9HtYFFruLuHLcDe4iD5U8NEmGIbQXru6ErA7NS+ls9tMN0ztVOKz/lgJe4+7OVvR6CbMJMBdbLHH+bM7b52nppud5HHIwqCxdIFINS9FFsP7iJN7W9Q017UqqNCsRmgCfxVa/P+U948IEDzx1N5gMBv1c+0TVeNmgCQYE/BtAKdoDa+AJ4TnzxNU8BYA6zirDJbMQMeg0wHHOKN0Y4RgoHVEMLZIeqQ3O3oi8S80O7MDzFDLUN2EOrBAE/33enMqq/mkSbAjAJxYR8+z76JLklNix9P8yEzKiFswlD/0SyNDHHs/45l4N8EbhM/oecil/5x2+68ca53DzcBEFO44epBH4DOPah8+89/MKwgUaFukqMfgi4SPqltMP9GQcSi3GHq0mZhrEyB/EZNYV2wv+Mi26Ps4rHijb/0K+6Mzl5Wjf+gXzL4UzqBCjCBLztst/9Pz9jP2qGnMqlwox2qftruNU3RwPDiWuJhQu+RpR4dnBlduG1wTeNCiIPEY0Zyc2CozciMMn4xnV5/OgMz4ufhYkCoUDxNqN2g3+C/z1E5Qu/wiJ61juden01eryNi/mIs0ptCSz8IXWJM8W1eXRvRN+Q3ooris2HtDtRsrSzwjc4elVIB4zdhB0GmYO290X1gXxYQnmAq8k1RpD8aD51eKe01HrwyGvKHMZUzCADFXY/tFmzK7TFQLLL78vqyXzNJ/9lcZz1afXTOi2BXAs/yEKFloc8uAH1YL0Uf6R/rIVHirgAkftOO740srlLRUPGpogmC6XI8vg1crn3OvJ6/BwHEcuRDKPMGQSNs5y1oLhSNOS+GwlPipgGn0T1/mg1qrtlvt57iEaGyo4Df7tFu456PfS/ARAF+QcqDZZI03zMdJJ36TP99H+E2wvWy1VNPAXg+ox1m3cnNL+4YYo1SUfFvsaUAXy58jax/fb8uoLLy+XC4X30fjz6RTSqOuZGxgdWyeOMLb+weR93u7JCM6z/QczUSLWLcsvbPcG3wvT39SM32cR0ijhD9whYBgD5mXbwu/B+dsBJR19HvL6XwGu7aHK5eorDkEdrxk7MtocO+UU42jLg8p09HEcuSOYKCU8pA0M2E3dgNej2AQAbRobH+UcDSGV8J3Vg/kK8ST4jxOAJKYNTvZw93fSbOA7CQAMixnqM4YpmPNa25Pe38j13jkRvBnoMOc4dhos5nnc4ebUyHXuOhn3Hb8g0xktA2HflO+U9Lfn2xHzKcUNFvxd963mhdbK9KAO+A4EONgrMf3R6W7h9dFex6QD3R5+I4I6GCES+k3mseAQzSvboha6HlkS0iOuDR/t8+aA7GLwfgFoKxwP6vxPCNjoINbW40YMYRJhI0A1Pgrl9Mfrfcu7xhDzKxuAHJUqPzh1BsbrguKoy5vdmQEqHIsOGiLLI1vrTuaA7c/wQ/yWFx8cgwMyCl31Ss2q5GMFGQoYGj0vkiWk95jt/NagwKvu3wd+Fa0nKjzCHNbm4+rz15zSTPZFDYQVeiGdJMH659+u95fvleuDE0UcaxLDA3X6SNwq2YgDHPzyED004SrvBJnq6+bYyHDX9AC2Cpcmnj1FIKn3Guz95gPMReDhEMAPhyC8IYgF8O7z7gL0EODHCr4l5wymB6z/werN2Dvuo//yBtIv0jGxBYP7/+1a0CXKtu/0ETYWEzmUKecCVfsv5LLPytTnCJATBw5vJ9UTefWA72Lr+Off/vwfURJ5AdERHvE01QfnLfmvCkob1zPcFCcAi/01zu7HceikCIQQYCZQOZsSpvp77sjOEdew+4wJIA0XIN0nPffH6sH0WeWo+nYP9BbqCoYP+v+J0BTlDfu7/KsSrywgJ/gH3PoV4P/DP+R4/QIBMyVdONwjIPro8lziUMw+8hf//wqaIpMkxwT56DX7ROyS5lUMsxfzEKEPJwCp4mbdB/iV9bYB8jL1KH0P3/3466DSb9Cw9hf6OhsOPKwisAZd+mztT84U3L8CJgdIGfgm3Qiz+MX3xO374bH+HiI4CtkNBgs97DniTecD9gD8UyfXMKwMSQqJ+ivW68vJ5vz+CA4AL18uTQu0CR3xl87u2Jr4tQqPB7klZxo0+vn7v+lb5Yv5UBd7D5EGBhhy+XzaTuev8Nz72RclKowcIgvKCdbasMYB6G70XgYqHgI1khzKBVP99dLU1z70u/xTBe8e8SZSAS7zufex5FjymA3WC7sQyhTDBfTbZ+IW+VbtagyYJRclFBUwBlLsd8mn4XLxI/NeGgA1WSQ5Cl3+L+nt0UPpI/nz+/chQCMOCdb2EvsX8CfgvgcQEJ4OrBeABejqf+Jg8xjs/PhkKIMofxNwDoP1uNlw1X3om/G4CrM3NiJWD1ILp/HY1zzYnflZ/HsSoSamC2IBpv/g7WTggPq1Fh8LUg5iFP7x6eek6kXoyfdlGZUtmRD0E3QJ1duJ1CPf1vFQAmkljCufEh0VI/3L1FjaivK8+28FDx4tHuwA8AKq8Arfs/oWC4oMHAn7GiYDwt9f7OLoQvJMDxoiGhzrFVgToedvzS3lTuvf9VsZ+CmCIgERygZm35jWTvS07tD+ixpgI94JX/pr/UTkjO8gBzwFBA9NGyQJB+eI5sPzFegJ/54h1RxhHpkR/PTf1nLeDO1x5HgQyCwwIvUVuQhj8nPYfucb8J7zkhlaI4gJNwL//8zvOOMs/RMNugcaHS4LX/BQ7RfuwuiS7scepCIQFtYZxf9v48jbpeIK5vcAcyp4Io4Soxit+vDdc94L7Y337gcQJFUNVAYnCjftu+MF9UAOYAeHD5wYdfnt7kvuZuIV79kRYCF0FU8YmBXL5p3aruGh4uL7iBckJqYWYxwpCl7b2eDz7Bzy3v55GKgbRgjoCJL28N/+9ooGWALEDcQZ0wpT6ZPuw+lT5p8K0RWuGYwcaxom9evVpOd54z3r3Q5GIUYgqBtRDs7qCN3X8ELqkPK6GLgbXA9PA5D/lOqk6ssEDfwkDeQdDQyR8U3snfIY4+v2FBe0F+ceEh14/MjjZuMt5mzf1wBvJgAbVx0hE7f4zORr5bTsPupeEvse4AlCCpYFMPKU5Y74dwTGBZYaOBLU9O/2B/B64kvsZw9iHnsTbyEXCtnrVec23lng6PWXHq4cKRV4IG0EXOZz5Hnogu6UAxEaLRCwCNMRKfKR4+H2twFBBrkMzBq5ACX1ZvUL3tbqEggVF1sT6xwmHInzQePC5HXcDfGqD+oYhRqTH9ITyObE5F7vz+bG+6sP2xdRDWQNkf3c4df2SgDr++sL1hpADb/0oPKM6njilAA+D5IPtSLKHUIACOMD6bjj299kB/4UWByGIXYU7vUF5bjxpuX269AQeBdxDq8MFwKA78HslP18+QcFEyFXDD36ePXC8GLkqO3vDrgOFx4NIz0E+e/v6nTki9pD92wZ3xaeHPUc0P5y77jqZOaL6HMG1Rs4B4oPUQx88xDsTPMC/8gAjxg4FP36uv6A9Irg5ejRBQYT2xPiIHcUZPS78bbh/9gG8nkOehdUE90krw0c7trtPOX76RP9QRJqDXMMoRWa+Ffm6vbN+9/+AA5MFtAIO/s++5jgjuQBBNkIXxG4HF8gSv+F7DTrAdnY6mYFVQ4NF3YjRhg3823r4/Cr47LzBgwuDmESRRBkAqTodfRC//XyCQsuGBkPUv79943t1uAr+q0FYgimIJ0iUwaO8cbt/uPs3E37qQ0MEvUl3Bef/qDwzfHb5qPkBgsZEF8NJBKgBYX0KfDY+WL0IwHZHKoPGP7x///xA+WX6yECBQrTFpYnhgmK+rv1weNE26rtsQ7IDjcb+CDmBd34wfHN5GLlTQAtEvIHEQ85E3D2ovBW9Oj1QwCHERUWFf99BS/7+t9W6RH8rAlrDz4gsRjX/rr6Augj18zslQSDC9sTdCI3Fn/2d/W26LLjofspBxgLMw0OGBj/4+k0+Ub2G/r8Cr0TEAvfA0j/ueXc4sX9jgBFCH0eQB6ECm/2D/Fy3PTj4f/8AEMTyyItG9v9M/Oc9FXide8aBfQH0xA1FR0El/B29fD7QPAABIYY9wutB879WfCH5P/y2P9o/usdlSLdC4v9BvXE5nLchfMTAx4LUCKmHCUDoPxr9ePmZOTRAJIMtQezFmEIkvij9rn1pPJS+ycZ8w67AjsHavYN5zzrU/lyAbMSziOcEAIBTwFP56DbIeuBAN4JjBQ4I+UK/QDP+nLk+eW6+Y8KswSkD3kV5vu69Gr29vAL/KsO7BDFBXgIxgIX4+7oTfga/RUNcBqEG84GYAM28P3XKev7+tcBOw/PIJwYvADY+9Dtf+J/964BwgJCEDAWfAVa7xH65/X18jQKkQ0ODeUJ9QPC69rj+PlW+BkBXRqTHTgPlQIt9kTijeI++Hf5OAlTIxcZXAfF+7D3I+aA6k0BhP9WD40WcQY994X4Lvq77Yb/xxPNC7MKYQZo8vrphfCy93r50RR2I68Mfggo/Ufqw+BK7Kb77AEqHooc/geUBYP7tegy5aP6DAW7BYcUaA2k+nD9cvXC7lf6eRD2D4MDDA54+xbqG+5n8R771guqH2kSaQh/CYDuC94s6hz31AAMEQkeNREGBsIDFOh95ZD48P+NA4IMFRdyABX5+flQ7aD5zAndDIoHaw3QBv3puump9fn08QWIFyQX3Q8ZCQf5Gt1n6dH2EPbaC/cazBlPCH4CwfO247L1pPve/DQOkhYrB3H36Pot9gzwEwVACw0JTxFCBpbyIOgf9n303fe1FtQY6xJzC9b8zeiE5E3z5/GkAdQd6RjICiUGk/rr6mHqsPrn+6oIABkABqT9Gv1d+ILuv/kOEJ4Iow2kC/r2Cu9L8bLx8vPgDf8dlg8fDX0HLO585lPqaPIm/ccUrRwpCW0NLgJX6wjp7PST/24ByRJeDtb+7gHw923smvjDCoQLKgckDxwDRO3q8Sru7vJDCJoWJBT+CwoRO/Zr4grsfu/I+dUKLhkiEogMSgnA7sXmgve4+dz9kQweE7YGSPyj/W/tifX/B2cFvQklDxcLyvC57ND0vO7u/5ARahPlErYQlf7c5c7pfvMd79sDyRf4FEQQIwfT+WHodPNR+Tv11QziEwYJo/2R/ev28u4CAacG0Qb0EmYLLfa97wj0KfG+8kIOahazEFwU3QEr8MTpQ+8E7uD4gRgUFboNBQ2K/4/vyews9ir3qQTLFXMIv//fA4D3Q++894sINQimC28RUfr/9GP0CO3j8LkFYxiLDnIRAg4k9ePrxuvy61r3Bg62FmgM5g9jCrjuI+2Z8wP4PQAHDcsPAQGEBkT7dOtK+LEElAdiBwURBwfp86/0Uu4I7QUDBxCoD00RZxPG/8zn4u6p7IjxGweSEKwSxw+NDlP1D+rr97r0iPmrCaUQZQg4AhL/U/Ae86EEJAGFBhQTFAtq+WPwBPVt7K/4Ng1KDBEV0RSgBC/uQO3V8T7qOv1wEXcRQhLjDRj9p+828432vvEBB58TtwacBNn/QPh98DL8rwNDAjsUlw0Q+yT2X/XA7l/vwwaWELkP4hZkCfj04vHg7XbqNvQSDwYT7AuTE3EDzvRT8XnylvSA/8US6QfpAuoHwvm870L3YQLnBJwLgxG3AFn4GfrL6tbt4QDzDpQOEBE7FCP7g/JP77bne/ODBsoQwgvVErUOLvWH8Jf04PLv/AAK+Au7BbAHUgAC7KD3pgHhAL0IRg89C3T59vjZ75bppv7DCAQLKBKSFkMFt/BH8fnsJOxnAbcKog1nFMYPCf1v7qX4PvPo8zAIgQsvCgQGswEr8/PyjgHf/K4DBRPqDPb9sPea9Pvst/OrBpwHiRHfGQoHuffu8ZLx4egh9i4MVgt0E18RdgHQ9c31h/RW72YC9A+gBrcGGgUm+P7zQfkA/10AsxAtEQT9rv2y9/jtZ+4S/zcLBgxdGIINcvuK+FzwAugR8SUHYQ3AC1QUsQkQ+Jv3MfFp8XP9LgzPCAMDXwz++2XxAfjC/PoBiAlfEQ0E3f3j/bTsPOs0/eEGpgoDEr0UeQNO9w31euaw7/IB6wekCxoSwRKu+jL1k/ar72L69wWrCAAHvwpqAhfwhPa3/937hgZ/D5kKWAGO+5Tzo+g7+sADtQO8EjcWnQpf+Mz1Y+6l6Wr8QgTyCI0UcRLgAO/19PiS87XwFAT7CH0HagszAmr3KvSJ/oX6Cf/dEi4MygJ4/eP23+2b8VIAOwIKDhAaKgs8/f/5e/HZ6b7x1QSBB9MPcRU7A7z8UfmL8wXvWP2wDIEE5gj+B3v6avYC+V/6DP67DYcQSAFIAX/9TO1T77L51wPfCR4V7BF4/xIA+POs59Dvsf/tBywJmRSeDGr9/fs889DuufsdBwsGWQWDDPoAT/L2+TT5gv3nCK0N9QdFAcUCaO/o6oH6nv9CBkcQ4BQsCHv++fhf6cnsIf7nAJwH3hIEEgMCn/js+d3uTPfJAxcDoAh8CzwFxPNc9/X9IfjOA7gNawqjBfAAavWt60X2Uv/1/R4PDBdhC4kBbvnM8bPpvPeW/2UCKRRHEuYE8PuM+wD0ue8ZAGQFtwXSDEwF7/iA+IP7t/j5+y8PEQ27A7MEl/i48FTxlfrq/b4IMhl+DPoCTgCd9PPqR/D8/bwCxAzXFAwHHgCI/9jyxO90+hsHMwSGB9ALuvsC+qD5t/ZE/LwJQQ9JA4sFcAE18LLvQfe4/F8GNRKWEWMFGASP+iToE/C6+soAuQc2EaQP7QAhAdX1Fe6c+lcCKwORBVcNWwNC9mD6efgn+RQH8QrAB70GjgQR9S3rKflz+j0A4A6xEZQMsQMh/ufsnezt+vn6NwMTEaERuQWb/nD7PfHF9EMBT/+WBgYO3wR7+Qj4Rv0D9vH/TAzzB7gJpQTw+M3uOPX1+lP5owolFYYMsQbp/7vzTO0P9CP7o/35DzQTWQX/Aq79zvVW8C78mAKKAt4NjAbL+677Rftk9i/66wrKC4oFHAiA/QvyQ/S+9bH5rQSYFHgOPgV5B6X3+e1t8EX4jP5xCFsTaQhBBLkDR/Xx75b5zgFXAkQHxwu4/1D7u/yv83766AYoCwMG9gZiBhHz+fHj9Rj3nwIUDicQkwj1CBj/X+zq73X4UfqeBKwOaw5FBngDqfof7g36Sf+m/m0GxAtOBl35QPwI+Hz2lwTBB9wGswm3B5/4Pu8b9+73jvqDCzIPrQxQCtQA3vKB7fn48Pay/UgP0w4kCeoCZf6C85r0cv4l/EUEKQ72BVb83/tc+zT2R/xUCZAGBgrXCY36JfQB9f339/UnBakSYwsoC6oErPep8JDzsPbp+VkLZxHDBlMGkAJM9lTzDPk3/9AAsgsLCZf8NABC+1b1BflRBgAKswUWC/MAqfVx9ln0FPVnAVkPiQ0+CNIKm/3870Dz8PND+kYF1w45CtQFjQil96vxVflx/TwA+AV3C+YBdv4x/vDz1Pf2BNgGMQZtCfwH3Pg58xH3uvKe/o0K+AuPC1YLTgSh8OXx8/at9QEBOQuXDPUIKAdU/YLxufjY/ab6NgV3CwEGov6j/J35mPTuASkFDARhDA4JCv0g8273u/XN9hIH2AvpC+QNGQW59grysvYP9eb4fgv3DOoIaQiq/4X3KfVH/PX5/AABDpQFmP/A/qX74/Wa+kMF0wTCCUsML/5R9134uPSF9BUAKw7ECvELSApM+tj1D/TH8xH3QQbiDnMGTwnQBfj4ZfWW+E37Y/9jCQYJN//3AT7+l/NZ+SUCtgZhBhULXAVD+E760PMy8k7+4glkC1wJsw3eAYT0MPUS8771kAI8CjcJgggcCof8mvK/+hj6d/1YBfAIqQRFAMkAbvTB9q0C+QIqBXkKlAkA/SX3M/fl8QX6SgeVB3ULfQ5xBk33bPOY92zyLf00CMwISgsOCbkApfRV+Tj8FPgSA04K2wW5AVj/lPnK9Wj+AwNLAVQMbAvk/jP5even9Qz0fAJyCE8JfhC2B2b7PPYX9y/zHfbDBkoKZQj9CuACf/mm+Kv52PhA/sELSAZTABYDXvsp92H5cwHiAkQI3w2pAG37Mftw9J/yBP2DCCMJIwzWDO/+C/m89wjxpPXWAY4KoQZ3CcEJ0frI+Jn4kPjk/bwGSgi7AE8EEwCT9IX4FQBfAkEG2woiB/n8SPxr9nrvX/zdBIMHUgrsDYwGV/ix+PryJvOl/84FIQeaCcQLp/8W9uH6cPkg+m0EswbzBLwDQgFy9271WgGJ/9oCSwtNCX8BfvoQ+ZrxcfdUA5EDzQnZD7UIDPy99033WvIP+SYFRQXMCt8LwgGt+aj57/tE9nYAGgl1BLUENAH1+r722/zp/0z/zgprDDgBUf19+qb0Q/R+/fIEpAYfEO4K7P0e/KP3KfMw9DECVQemBrQM3wSC/F77gvn+9u/8gggHBoYBIgWz/QT3nPo8/fcAvgYMDdYDyP2Q/330hvJp+ksDpQYYCzYOUwJO/an6bvGi80b/agWuBaIJ8wq4/m36APvk9eH8cATuBboC9wTrAnr1FvkS/t/+AAX6CfkHngB+/z34CvCJ+bMBqQLWCfUNeQj5/br6jvUO8Y/94AG2A3AKmQsZAw35Zvzg+Fb4kwKjBG4E+wXMAiP59fbE/vb9oP/nCjAJlQOO/8/51/NB9TIAwP/ZBlwQWwnKAJT73fiA8hn3QAFBAh4JBg1/A8f8mvyL+qX2bP1PB4MDaAVdBCD7g/lZ+6r9Rv12CJYMggJhAS/9uPVU9ND6VwBiBDkOWgwPAfP/Cft08rb0m/0UBAsF+Qt+Bwr+Uf92+Wr2uvtYBRYFBgLdBnP/kfgE+2b7wv3GBf0KiwXnAAwCdPfD8Q36FP66A7oJQw3qBTEAyP5Q8l7z6PwHAbYDBAlfC4EBY/1P/Pr1yPpDA+UCeANNBscDvvif+PT9UvtkA88IJgdQBLcBSPsP8Xr4cv6+/sYHOQ1rCUECNf479yHyqvp3/8H/zAm1Cz0Ep/3U/DX6wvbtAKcC5gL3B38DmPtn+Mn97vuM/dwIzQjaBFgDSvwm9Sb2Ovxe/R4DNw8JCjMDwgDI+bT0pfUg/k7/mwZPDT8E/v8N/+76g/Yg/EUE0wJdBTEG2PzX+n/8evqK/GkFdwvvA3gDKwF59jv2lvis/LMBlAt6DDgDqwME/vPzzPRd+8j/uwNECnMImQBfAeH7HfUA/AQCdwOqAusGFAKV+bP8xvmG+xMEuwj5BV4DjQQb+kvzC/lc+4f/bQg2C6wH2QMjAcf1wPJP/N38RQEoCCcKawR9/5X+Q/YG+ogBgQACAzQHkgRH+xj6zvwv+lwA4AeJBV0GyATp/IT0Kvfl/O76KAXZC98IHgb5AAH6jPOc+a785/ytB0oL6gTrAPL+Z/q19zn+cQH4AH8I8QSY/J77ZPxT+1/7hAbJBx4FmAZ3/pn3PPdM+lz6gABEDB4K5QRxBI/89PXx9m/6Zv2uAxYMRQV0AZsC8/rA9+z6pwGtAdIEUwdL/tv8XP1G+c36nwOtCP8E/gTeAzf5LfcK+Y342f9LCBkLOwWwBekBavVq9ov5ffzDAUMISQiKAp4Dtv3m9UT7gQCbADwDlAZrAzD8Hf12+r34CQP2BUcFlAXWBZj98/SH+QT5avwBBgQJ6we4BqgDtviA9PP6//rC/TUHagisBY4Ccf+Y+OD4wgAQ/u8BzAeCBCv+cfvd/BP5cv6sBTkE4gZOB+7+bPdH+Jn6XflNAT8KoQcfCHYEpvvz9pL4QPsu+jEFPAq0BM0DsgCj+4H4EP1B/+r/nwcJBuL93/0k/bv5K/sAA7gGygQ8CGoBPPkT+pT4r/jA/QoJKAm1BVoHHv9X+Cz44Piu+twBYwnFBcACxATc/O73vfth/t8A6QM4B04A/f1v/yz4Ifp+AfoF5QQFBtkF9ftE+WH5wfbt/BAGGgh5BlEHaATD+Db3/fkE+UYA4AX3BmcEwwRBALn2n/vf/n/+swI7Bv0Dm/5i/rP6HPirAGIEHgMiB+4G7P9n+GT54fgj+egDQgYDB/0IQAUx/Hj2APtF+W/7CAXcBrwF/gTcADP62fne/jr9xf8DCGgE2P8h/jr8uvk3/NMDZAKOBiMJfQC/+rb52PnD97L+KgePBpAIMQfk/Z354fkd+VL5zQHaCDUEJwU+AyH8tfrN+9X9jv5sBm0G8P4dAAT+dvmG+tYAJATTBGkI2gOX+y78Rvll9q385QS+B+QFsgg5AjD6wvqs9xv5yP+1BjkFqANjBqX+QPkB/Ov8z/66A+4F4gGh/4sAKfmm+MoAggJvBG0GrwYo/xL7/fp29Rz7UwNHBTkGgAgrBvf7Qfka+tD3rv1oBH0EiAX+BZkBQfk1+8X+CPwiAnoFzgMZAVr/1fu890L/KQJqAREH8AecAcD7n/p0+B/4mABgBMsEQArCBoX+/fmt+kv5EvkRA9wEDwXfBuMBQ/zp+h3+7PuN/sYGmgTMAIAAzPzF+fv7vgB0AQEFIAobAiH9kvwF+cP3BvxSBMIEOgj0COH/jvxs+4f4Jfi+/w0G/ANqBSQFif0G/IL8hvtT/lwEUQYDAG0B7P8O+Qj7jf7sAfwDJghPBfn9g/5U+sf1GPsqAr4EJwbACJcE2/yL/Kf4D/f0/msDOwQwBO8G7QBS+jL9kft2/csCyAR0AlcBpAFI+pn4Uf+MAFkCAAdzBjEC+f5h/ir4jPnCADIBMARHB78ESP72+2/8W/g9/V0EvwM5BX0FAAF1+ov6n/zB+sMBDwdtBOgDHAIZ/SH4a/u9/lD+nwW7B+cC4AB5/mr6JPhr/s4BmwGOBwQGuv9q/fr72Pl8+okCdgRkAwgHcgIX/O76kvt1+03+WQZ8BREDawQ8/mT5dvph/Xz+OgJ+CEgE5ADTANP6rPhA/KsAoAHoBDoIHwHe/a39Xfk7+q7/IwSTA4EFqgUL/VT7KPxC+oL9gQNkBn8DAQS7AXb5cPrK/Av9TQFaBoAGYQE0AdT9ove0+z3/jgA8BDgHUwQF/l/+RPsz+M3+cwJmA0cF2gWSALn6wvzQ+u/6rgIWBXUEIQTZAon80PgY/Wn81/76BQgGVANXAWX/lvkd+VP/Of+HAoQH1ARzABb+zPyt+KX7nAL5Ab4ExQbaAfH8tfsC/P35m/+tBXYDzwQOBCb+Jfo2+z795PytA0cHAQPjAmUADPsk+eL85/8wAIUGsga7AOT/Jv2k+Vb6KgDTApsCQgcEBH79Gf17+2D6Tf3mA7wEQwPKBRcAjPqy+/H75Pz1ALoGvgQAAtICPfwT+Ur8Qv4lAAQEogetAnT/kv+9+bX5s/50AdsCawVMBi7/xPxK/Vz5S/wIAjoE8wPKBDcDcPsm+838GPv0/wkFcgUBA4UCgf/G+Gj7Mv4p/mcDkwaVBGQApP9z/B/4n/3NAFIBdAUSBuQBJf1h/RD7svkZAXgDWgNzBbgDVf6L+rb8q/vr/KcEBwWDA4EDZwAq+6X59f3U/aEACAe8BMsBdABb/YD54vqsAIMAjwNlB5AC7/6L/bD73vnl/dIDiALCBKMFPf8a/O379PsI/KsBJQb8AvgDaALq+3X6QPz2/Rv/7gSwBpwBswHi/sn5svpr/tUA4QGaBiAF6f4B/0v8mPnJ/JwBXwNSAzgG6QHq+w79gPte+wAAoQR+BPACEgQa/tL5tPyp/Gj+LgNVBqkD/AATAfT6gvkn/i//jQEyBRQGGAFX/m7+fPk0+98A+wGjA2AF9AOs/Sr8H/0T+mX+0QPkA+oDvQO7AJv6c/uV/Vv8AgLXBRoEVgIDAZL9//ii/IT/Xf/UBCAGfQKT/1H+j/tp+Wn/CALoAe8FggSg/738vPxU+6/72wIDBAsDCwWKAZP8+/rq/M/8/v7IBYYEZgKcAkb+dvoH+83+Rv8qAicHOANTAKX/3PsQ+u/8qQGgASEEfgZyAL79UP0h+4D7CwBgBNkCUgQOBCX9wfuA/EL8NP5GA9wFZALZArkAd/o++3/9uv4jAYAFeAVgAHoArP1d+YP84P+CATcD/gVAA5H9R/7q+zb6Lf+sAnsDsQOrBOz/Dvs4/fb7rvxMAsgE1gN2AiACmvzd+cz9nv3d/8UEWgVmAhgAY/9k+ov62P8VAJoCtwUgBKz/mv2B/ff59fySAkcC9APUBIYBqvwM/Cn9WPtTAOwEQwOCA38Cfv58+iX8Zf7h/YgD7wWYAowBo/8a/PL59/2gAIsAhwUkBXwA7v5X/S/7PPvtANsCUAK1Bb8Cvv27/Hn8+/vj/f8DFgSNAiYEjf9p+977V/0W/u8AFwaxA0QBigGk/Gb6t/yS/5cAUgN2Bq0BE//x/gD7H/sB/0QCdQJBBAAFrv7y/Fb9I/tW/eQBWwTqAokDPAK5+9n7Tv3j/D4AVgT8BL8BmQEp/9n5VvzK/oH/ywJzBdkDZP9X/9T8t/lb/h4B7wEVBN0ETQHB/MD9+/ta+z4BUgM8A7ID2QI5/uP6iv3D/Cn+/gN0BOgC3gEyAKv7kfrZ/rT+IwGiBf8DFwFg/+79fvoA/DMB5QBAA5UFDgKC/j394PwG+8L+sQNgAtYD4wNN/yj8Wfxi/fT87QFTBXsCzwIxAbX89foa/S3/ev90BGcFHgG1AH/+Nftj+0X/dQGYAYcFywPK/nb+w/xP+0/9FAJBA4YC5AT9AGT8Bf2V/On8BQCDBMID9wHnAu394voB/fL9Wv+PAq4FpwI8AGYAnfvk+nf+PgCrAQkEKgVBAB/+X/7M+n382wCIAvYC/AMoA1/9kfyP/aj7Jv9JA+EDvAKKAmQAA/tO/Db+w/3yAdIEtwMWAV0A2f0C+pT9+/8+AO0D4AQPAq3+Zf5h/LX6BQASAiICbQRtA37/dPx1/Wn82fzRApADugJbAwAB7/xQ+/f9xv2o//wExAPYATIBgf5M+7/7w//L/yYCwwV9AuL/1v7X/CP7q/0nApABgQPiBCAAqf02/Zb8c/xuADUETgJaA60Cfv0a/Pf8xf2v/hkDFwWoAekB8/+G+9v7Mv7d//UAxgRiBNb/4v+p/ev6FP1vAP0BawLxBEICh/0q/pX83vtb/9UCQgOKAqcDaP+l+4H9A/3//d8BeQQdA1kBewHF/Pf6OP6q/n0AugO7BIkBZP9P/zb70vsPAM0AbgJIBH8DEf+G/fb9MPv+/VQChQIeA2MDOAGT/JT86f2W/MEAIwQZA1cCcwG6/vb6B/0a/8r+LwPDBEYCdQBF/+P8zvrT/vgA6AB7BOsDVAA+/rf9UPwl/GABrQIlAkQE3gH9/ZX8Z/0c/X/+0ANxAxECtgJV/yD8K/x3/tz+BAFFBdoCxwB9ADP9cPs0/X0AxgDXAj4FAgHe/nv+Nfwr/Ff/rgIKAmUDwQOG/in9dP2n/Aj+1AErBBgCnAJXAUD8avzI/Uv+UgDLA1YE4ADvAN3+//oB/U3/cAAuApAEDQPX/iX/Kv0z+8r+YQE5AvEC7AO2AMX8B/7E/MX8JgEwA+4CXgIvAh7+fvsX/rD9If9DA/0DQwK+AA4AIPyQ+1z/cP9rAV0EcANzAMb+Xf5g+wr9WwE7AdgCFQS1ASz+SP27/Qv8dv9QA00C8gKPAmv/Rvzs/Fn+x/0HAm8EKwLHAWMAZP13++r95v/b/+UDPQTZAOH/Z/5W/Az89f+vAXUBegS5Atj+DP5X/Zb8z/1XAu0CAgKqA18A6vwK/ZX9+v0bADgEBgNZAdsB/v3R+0n9Af/m/yEC7gTVAdP/zP9g/P/7u/4EAZABMQM4BLb/Hv5J/gz8a/3XANECSgL9AlwCXf0A/eD9C/2U/9oCrwPGAbgBBACe+wH9rP7p/rIBBAQ7AzMA/P8D/hf7Pf5MAOMACAPuA5YBLv6M/gD99PtRAA4CNgIiA6YCUP+B/An+Pv3k/YgCMQNfAgYCrwAz/dv7tP6C/jMAGQQzA1IBMQDJ/vj7i/xRAC8AFgJ2BAICfv9k/qn9Afxi/kMCiAHsAoEDBACa/Vr9sv02/cQAxgPxAYECmQHv/Wb8hP3S/hP/5gI5BDcBHAFy/378XPzc/okA2AAWBF0Dm/9h/9H9NfyH/eUAGwLcAfwDcQG6/Qz+R/0j/Xv/5ALZAsMBvAIV/1L8sf33/ef+gwEbBGMCqADhABL9+Pt9/ov/zADpAhkE0wAP/yr/EPzd/CQAWQEZAjYD4AKu/q39PP5V/Lr+CgKlAk8CXgLiALH8JP1n/rL97AByA+MCXgHKANf+kvvF/Yn/kv+zAtID9AGn/yf/cf22+2v/HQE2AXYDAgMrANj9I/4i/Qz9igFvAgEC/gJMASz+q/wu/ur9Gf9pA+YCrAGLAVP/sPyd/Ej/YP8iAV0EPQJlALb/y/09/L/9CAHZAHgCEQSgALn+O/5A/fP8tP/AArEBtAKkApr+Wf2t/dn9hP7OAb8DhAHfAZsA4/zb/ET+Tf9RAFgDlwNaAGcAr/4V/Hv9xP//AKsB0gNFAqT++f6H/Xj8Cf+YAT0CFQIiAzQACv0y/n794/33AA4DfwJwAZ8BFf41/G/+f/7M/5UCkwOgAQ0A5/+a/IL8n/8PAH0BUQP0Aur/h/6k/jf86P1OAYMBWwLvAmgB+P2I/U3++/z0/9gCPwIeAp8BgP9+/If99f6I/vYBnAPvAegA7f/o/QX8m/5JADkARANIA60APv+D/i39uPxuALABagF2A+8B8f7M/fH9gf1T/mECiAKrAY8CBgBg/Sn9b/6z/kEApgNLAuQA5gBc/tz81/3S/yoAngGMAw8Bpv9u/6r9b/02/y0BEAH6AX4Ck/+r/rv+9/2i/poA8gEoAX8BDAFy/lj+3f7j/uD/fAHrAZsAoQDS/wn+tP6F/+L/rgCkAUMB1//h/y7/Vv5w/zoAgwDgADYBZwBK/4v/Kv8L/yAAngCgAJkAkQDG/zH/oP+G/7n/cgCUAF4AMAAUAJn/ff/j/+T/EQBXAEMAEQD4//H/0v/k/wQAAgAFAAAA]=],
}


-- ================= BUILD =================
local UI = Library.new({Name = "NYX UI", ToggleKey = Enum.KeyCode.RightControl})

UI:BuildHome()
UI:BuildCommands()
UI:BuildScripts()
UI:BuildPlayers()
UI:BuildMusic()
UI:BuildNews()
UI:BuildSettings()

-- dock order like Oblivion: Home, Cmds, Scripts, Players, Music, Settings, News
local order = {"Home", "Cmds", "Scripts", "Players", "Music", "Settings", "News"}
for i, n in ipairs(order) do UI.TabButtons[n].Button.LayoutOrder = i end

-- floating command log (draggable, minimise, close)
local logWin = UI:AddWindow("Command Log", 210, 150)
local logScroll = New("ScrollingFrame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2,
    AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 11, Parent = logWin.Body}, {List(2)})
local logN = 0
UI.Log = function(text)
    logN += 1
    local l = Label({Text = os.date("%H:%M") .. "  " .. text, TextSize = 9, TextColor3 = Theme.SubText, Size = UDim2.new(1, 0, 0, 13),
        LayoutOrder = logN, ZIndex = 11, TextTruncate = Enum.TextTruncate.AtEnd, TextTransparency = 1, Parent = logScroll})
    Tween(l, 0.3, {TextTransparency = 0})
    logScroll.CanvasPosition = Vector2.new(0, 1e5)
end

-- ================= YOUR COMMANDS (edit / add yours) =================
UI:AddCommand({Name = "Log", Desc = "Open the command log window", Category = "System", Kind = "Open", Best = true,
    Callback = function() logWin:Toggle() end})
UI:AddCommand({Name = "FOV", Desc = "Set field of view: /fov 90", Category = "Visuals", Kind = "Open", Best = true,
    Callback = function(v) Tween(workspace.CurrentCamera, 0.4, {FieldOfView = math.clamp(tonumber(v) or 90, 30, 120)}) end})
UI:AddCommand({Name = "Fullbright", Desc = "Remove darkness and shadows", Category = "Visuals", Kind = "Toggle", Best = true,
    Callback = function(on) UI:SetFullbright(on) end})
UI:AddCommand({Name = "Waypoint", Desc = "Save a spot, return to it: set / go <name>", Category = "Movement", Kind = "Open", Best = true,
    Callback = (function()
        local waypoints = {}
        return function(action, wname)
            local root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if not root then return end
            wname = wname or "main"
            if action == "set" or (action == nil and not waypoints[wname]) then
                waypoints[wname] = root.CFrame
                UI:Notify("Waypoint", "Saved '" .. wname .. "'", 2)
            elseif waypoints[wname] then
                root.CFrame = waypoints[wname]
                UI:Notify("Waypoint", "Returned to '" .. wname .. "'", 2)
            else
                UI:Notify("Waypoint", "No waypoint named '" .. wname .. "'", 2)
            end
        end
    end)()})
UI:AddCommand({Name = "Emote", Desc = "Play an emote: /emote wave | dance | laugh | cheer | point", Category = "Character", Kind = "Open", Best = true,
    Callback = function(e)
        local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if h then pcall(function() h:PlayEmote(e or "wave") end) end
    end})
UI:AddCommand({Name = "Time", Desc = "Set the time of day: /time 14", Category = "Visuals", Kind = "Open",
    Callback = function(v) Lighting.ClockTime = tonumber(v) or 14 end})
UI:AddCommand({Name = "Zoom", Desc = "Let the camera zoom out much further", Category = "Visuals", Kind = "Open",
    Callback = function() LocalPlayer.CameraMaxZoomDistance = 1000 end})
UI:AddCommand({Name = "Anti Idle", Desc = "Never get kicked for being idle", Category = "System", Kind = "Toggle",
    Callback = function(on) UI:SetAntiIdle(on); UI.Ctl.Idle:Set(on, true) end})
UI:AddCommand({Name = "Reset", Desc = "Reset your character", Category = "Character", Kind = "Open",
    Callback = function()
        local h = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if h then h.Health = 0 end
    end})
UI:AddCommand({Name = "Rejoin", Desc = "Rejoin this server", Category = "System", Kind = "Open",
    Callback = function() TeleportService:Teleport(game.PlaceId, LocalPlayer) end})

-- Player rows: View = spectate (tap again to go back)
local viewing = false
UI.PlayerActions["View"] = function(p)
    local cam = workspace.CurrentCamera
    local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
    if p == LocalPlayer or viewing == p then
        viewing = false
        local mine = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if mine then cam.CameraSubject = mine end
        UI:Notify("View", "Back to your camera", 2)
    elseif hum then
        viewing = p
        cam.CameraSubject = hum
        UI:Notify("View", "Viewing " .. p.DisplayName, 2)
    end
end

-- Scripts > Library: your own functions go here
UI:AddScript({Name = "Hello", Desc = "Example script - prints to the output", Tag = "Example", Callback = function() print("Hello from Nyx") end})
-- UI:AddScript({Name = "My script", Desc = "what it does", Tag = "Utility", Callback = function() end})

-- Music: add your own tracks (audio ids you own or that are public)
-- UI:AddTrack({Name = "Song", Artist = "Me", Id = 123456789})

UI:SelectTab("Home", true)
UI:Start()
UI:Notify("NYX UI", "Obsidian Edition is ready.", 3.5)

return Library
