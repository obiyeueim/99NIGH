-- =========================================================================
--   🌶️ CHILLI VKING (PHẦN 1/5)
--   CẤU HÌNH HỆ THỐNG · SCRIPT GỐC LUAUFORGE MỚI · CHU KỲ 00:00 GMT+7
-- =========================================================================

local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local ContentProvider = game:GetService("ContentProvider")
local CoreGui = game:GetService("CoreGui")
local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local LocalPlayer = Players.LocalPlayer
local API_BASE = "https://chillihubvking-claimkey.dongbackhai600.workers.dev" -- [MYKEY] Worker key cua ban
local KeyUrl = API_BASE .. "/"
local TutorialUrl = "https://craftvip.github.io/free/getkey.html"
local TargetScriptUrl = "https://raw.githubusercontent.com/robvxs24/freemium/refs/heads/main/chilliv5beta.lua"

local ChilliAvatarId = "rbxassetid://92622270383869"  -- Hình quả ớt cho Menu Get Key bên ngoài
local GiftBoxAssetId = "rbxassetid://115116611981430" -- Hình hộp quà cho Mini-game bên trong

local KeyFileName = "ChilliV5_KeyData.json"
local TrialFileName = "ChilliV5_TrialData.json"
local GachaFileName = "ChilliV5_GachaData.json"
local TRIAL_DURATION = 120 -- Thời gian dùng thử 2 phút (120 giây)

local InitialGuis = {}
local ScriptConnections = {}
local ActiveBlurEffect = nil
local InputBlockerScreen = nil
local OpenKeySystemUI = nil

task.spawn(function()
    pcall(function()
        ContentProvider:PreloadAsync({ GiftBoxAssetId, ChilliAvatarId })
    end)
end)

-- =========================================================================
--   [MYKEY] KEY SYSTEM RIENG (Worker + HWID + 16 GIO)
-- =========================================================================

local function GetMyHWID(): string
    local id = LocalPlayer:GetAttribute("ClientId")
    if type(id) ~= "string" or #id < 6 then
        pcall(function()
            local a = game:GetService("RbxAnalyticsService")
            local v = a and a:GetClientId()
            if type(v) == "string" and #v >= 6 then id = v end
        end)
    end
    if type(id) == "string" and #id >= 6 then return id end
    return "user-" .. tostring(LocalPlayer.UserId)
end

local MY_HWID = GetMyHWID()

-- [MYKEY] Link lay key kem HWID -> trang web tu dien san o HWID
local function BuildKeyLink(): string
    local okEnc, enc = pcall(function() return HttpService:UrlEncode(MY_HWID) end)
    if not okEnc or type(enc) ~= "string" or enc == "" then enc = MY_HWID end
    return KeyUrl .. "?hwid=" .. enc
end

local function NormalizeMyKey(raw)
    local s = string.upper(tostring(raw or "")):gsub("[^A-Z0-9]", "")
    if #s ~= 16 then return nil end
    local p = string.sub(s, 1, 4)
    if p ~= "CHIL" and p ~= "FUJI" then return nil end
    return p .. "-" .. s:sub(5, 8) .. "-" .. s:sub(9, 12) .. "-" .. s:sub(13, 16)
end

local function ApiVerify(key)
    local req = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
    if type(req) ~= "function" then return nil, "Executor khong co request()" end
    local ok, res = pcall(req, {
        Url = API_BASE .. "/api/verify",
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode({ key = key, hwid = MY_HWID }),
    })
    if not ok or type(res) ~= "table" then return nil, "Khong goi duoc server" end
    local txt = res.Body or res.body
    if type(txt) ~= "string" or txt == "" then return nil, "Server tra ve rong" end
    local okD, data = pcall(function() return HttpService:JSONDecode(txt) end)
    if not okD or type(data) ~= "table" then return nil, "Phan hoi khong hop le" end
    if data.ok == true then return true, nil, tonumber(data.remainingMs) end
    local m = data.message or data.reason or "Key khong hop le"
    if data.reason == "hwid_mismatch" then m = m .. " -- HWID: " .. MY_HWID end
    return false, m, nil
end

local CIPHER_KEY = 127

local function EncryptData(str: string): string
    local hex = {}
    for i = 1, #str do
        table.insert(hex, string.format("%02X", bit32.bxor(string.byte(str, i), CIPHER_KEY)))
    end
    return table.concat(hex)
end

local function DecryptData(hexStr: string): string?
    local res = {}
    for i = 1, #hexStr, 2 do
        local b = tonumber(hexStr:sub(i, i + 1), 16)
        if not b then return nil end
        table.insert(res, string.char(bit32.bxor(b, CIPHER_KEY)))
    end
    return table.concat(res)
end

local function GetCurrentDateGMT7(): string
    local vnTime = os.time() + (7 * 3600)
    local d = os.date("!*t", vnTime)
    return string.format("%04d-%02d-%02d", d.year, d.month, d.day)
end

local function GetSecondsUntilMidnightGMT7(): number
    local vnTime = os.time() + (7 * 3600)
    local d = os.date("!*t", vnTime)
    local elapsed = (d.hour * 3600) + (d.min * 60) + d.sec
    return 86400 - elapsed
end

local function CanPlayGachaToday(): boolean
    if isfile and readfile and isfile(GachaFileName) then
        local ok, raw = pcall(readfile, GachaFileName)
        if ok and raw and raw ~= "" then
            local dec = DecryptData(raw)
            if dec then
                local parseOk, data = pcall(function() return HttpService:JSONDecode(dec) end)
                if parseOk and type(data) == "table" and data.LastGachaDate then
                    if data.LastGachaDate == GetCurrentDateGMT7() then
                        return false
                    end
                end
            end
        end
    end
    return true
end

local function SaveGachaPlayed()
    if writefile then
        pcall(function()
            local data = { LastGachaDate = GetCurrentDateGMT7(), Timestamp = os.time() }
            writefile(GachaFileName, EncryptData(HttpService:JSONEncode(data)))
        end)
    end
end

local function LoadTrialData()
    if isfile and readfile and isfile(TrialFileName) then
        local ok, raw = pcall(readfile, TrialFileName)
        if ok and raw and raw ~= "" then
            local dec = DecryptData(raw)
            if dec then
                local parseOk, data = pcall(function() return HttpService:JSONDecode(dec) end)
                if parseOk and type(data) == "table" and data.StartTime and data.LastSeen then
                    if os.time() < data.LastSeen then
                        return { StartTime = 0, LastSeen = os.time(), Tampered = true }
                    end
                    return data
                end
            end
        end
    end
    return nil
end

local function SaveTrialData(startTime: number, lastSeen: number?)
    if writefile then
        pcall(function()
            local data = { StartTime = startTime, LastSeen = lastSeen or os.time(), Duration = TRIAL_DURATION }
            writefile(TrialFileName, EncryptData(HttpService:JSONEncode(data)))
        end)
    end
end

local function GetKeyRemainingTime(): number?
    if isfile and readfile and isfile(KeyFileName) then
        local ok, content = pcall(readfile, KeyFileName)
        if ok and content and content ~= "" then
            local decOk, data = pcall(function() return HttpService:JSONDecode(content) end)
            if decOk and type(data) == "table" and data.ExpireTimestamp then
                local left = data.ExpireTimestamp - os.time()
                if left > 0 then return left end
            end
        end
    end
    return nil
end

local function Save24hKey(customDuration: number?)
    if writefile then
        pcall(function()
            local duration = customDuration or 86400
            writefile(KeyFileName, HttpService:JSONEncode({ ExpireTimestamp = os.time() + duration }))
        end)
    end
end

local function VerifyChilliV5Key(rawInput: string): boolean
    if not rawInput or rawInput == "" then return false end
    local clean = string.lower(string.gsub(rawInput, "[%s%c]", ""))
    clean = clean:gsub("^chillihubv5%-", ""):gsub("^chilliv5beta%-", ""):gsub("^chilliv5%-", "")

    local vnTime = os.time() + (7 * 3600)
    for _, t in ipairs({ vnTime, vnTime - 86400, vnTime + 3600 }) do
        local d = os.date("!*t", t)
        local v1 = (d.day * 4339 + d.month * 3187 + d.year * 173) % 65535
        local v2 = (d.day * 6823 + d.month * 4931 + d.year * 293) % 65535
        local v3 = (d.day * 8513 + d.month * 7109 + d.year * 431) % 65535
        if clean == string.format("%04x-%04x-%04x", v1, v2, v3) then
            return true
        end
    end
    return false
end
-- =========================================================================
--   🌶️ CHILLI VKING (PHẦN 2/5)
--   SNAPSHOT UI · KHÓA MÀN HÌNH BẢO MẬT · LIVE TOAST THỜI GIAN THỰC
-- =========================================================================

local function TakeGuiSnapshot()
    table.clear(InitialGuis)
    local containers = { CoreGui, LocalPlayer:FindFirstChild("PlayerGui") }
    for _, c in ipairs(containers) do
        if c then
            for _, child in ipairs(c:GetChildren()) do
                InitialGuis[child] = true
            end
        end
    end
end

local function ApplyScreenLockdown()
    if not ActiveBlurEffect then
        ActiveBlurEffect = Instance.new("BlurEffect")
        ActiveBlurEffect.Name = "ChilliV5_LockdownBlur"
        ActiveBlurEffect.Size = 24
        ActiveBlurEffect.Parent = Lighting
    end

    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hum then
            hum.WalkSpeed = 0
            hum.JumpPower = 0
            hum.PlatformStand = true
        end
        if hrp then
            hrp.Anchored = true
        end
    end

    if not InputBlockerScreen then
        InputBlockerScreen = Instance.new("ScreenGui")
        InputBlockerScreen.Name = "ChilliV5_InputBlocker"
        InputBlockerScreen.ResetOnSpawn = false
        pcall(function() InputBlockerScreen.Parent = CoreGui end)
        if not InputBlockerScreen.Parent then InputBlockerScreen.Parent = LocalPlayer:WaitForChild("PlayerGui") end

        local shield = Instance.new("TextButton")
        shield.Size = UDim2.new(1, 0, 1, 0)
        shield.Position = UDim2.new(0, 0, 0, 0)
        shield.BackgroundColor3 = Color3.fromRGB(8, 10, 15)
        shield.BackgroundTransparency = 0.45
        shield.Text = ""
        shield.AutoButtonColor = false
        shield.Active = true
        shield.ZIndex = 15
        shield.Parent = InputBlockerScreen
    end
end

local function RemoveScreenLockdown()
    if ActiveBlurEffect then
        ActiveBlurEffect:Destroy()
        ActiveBlurEffect = nil
    end
    if InputBlockerScreen then
        InputBlockerScreen:Destroy()
        InputBlockerScreen = nil
    end
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hum then
            hum.WalkSpeed = 16
            hum.JumpPower = 50
            hum.PlatformStand = false
        end
        if hrp then
            hrp.Anchored = false
        end
    end
end

local function TerminateTargetScript()
    getgenv().ChilliV5_Active = false
    getgenv().ChilliV5_TrialExpired = true

    for _, conn in ipairs(ScriptConnections) do
        if typeof(conn) == "RBXScriptConnection" and conn.Connected then
            conn:Disconnect()
        end
    end
    table.clear(ScriptConnections)

    local containers = { CoreGui, LocalPlayer:FindFirstChild("PlayerGui") }
    for _, c in ipairs(containers) do
        if c then
            for _, child in ipairs(c:GetChildren()) do
                if not InitialGuis[child] and child.Name ~= "ChilliV5_GetKeyUI" and child.Name ~= "ChilliV5_ToastUI" and child.Name ~= "ChilliV5_InputBlocker" then
                    pcall(function() child:Destroy() end)
                end
            end
        end
    end
end

-- =========================================================================
--   [HUB-BRAND] Doi ten hub sau khi tai + son giao dien cosmic (zero-lag)
--   Chi thay chuoi nguyen van -> khong the lam hong ten ham/bien
--   Tu chua moi ham can dung (khong phu thuoc file khac)
-- =========================================================================
local HUB_BRAND_PAIRS = {
    { "Chilli Hub Discord", "Chilli VKing Discord" },
    { "Chilli Hub V5", "Chilli VKing" },
    { "CHILLI HUB V5", "CHILLI VKING" },
    { "Chilli Hub", "Chilli VKing" },
    { "CHILLI HUB", "CHILLI VKING" },
}

local function HubReplacePlain(src, from, to)
    if type(src) ~= "string" or from == nil or from == "" then return src end
    local out, pos = {}, 1
    while true do
        local a, b = src:find(from, pos, true)
        if not a then break end
        out[#out + 1] = src:sub(pos, a - 1)
        out[#out + 1] = to
        pos = b + 1
    end
    out[#out + 1] = src:sub(pos)
    return table.concat(out)
end

local function RenameHubBrand(src)
    if type(src) ~= "string" or #src < 200 then return src end
    local out = src
    for _, pair in ipairs(HUB_BRAND_PAIRS) do
        out = HubReplacePlain(out, pair[1], pair[2])
    end
    return out
end

local HUB_COSMIC_A = Color3.fromRGB(124, 58, 237)
local HUB_COSMIC_B = Color3.fromRGB(6, 182, 212)
local HUB_COSMIC_C = Color3.fromRGB(236, 72, 153)

local function HubCosmicGradient()
    return ColorSequence.new({
        ColorSequenceKeypoint.new(0.00, HUB_COSMIC_A),
        ColorSequenceKeypoint.new(0.55, HUB_COSMIC_B),
        ColorSequenceKeypoint.new(1.00, HUB_COSMIC_C),
    })
end

-- Tu lay cac root chua ScreenGui (khong dung handler cua file khac)
local function HubScanRoots()
    local roots, seen = {}, {}
    local function add(r)
        if r and not seen[r] then seen[r] = true; roots[#roots + 1] = r end
    end
    local okH, h = pcall(function() return (gethui and gethui()) or nil end)
    if okH then add(h) end
    local okC, c = pcall(function() return game:GetService("CoreGui") end)
    if okC then add(c) end
    local okP, players = pcall(function() return game:GetService("Players") end)
    if okP and players then
        local lp = players.LocalPlayer
        add(lp and lp:FindFirstChild("PlayerGui"))
    end
    return roots
end

local function HubCollectGuis(root)
    local guis = {}
    for _, ch in ipairs(root:GetChildren()) do
        if ch:IsA("ScreenGui") then
            guis[#guis + 1] = ch
        elseif ch:IsA("Folder") or ch:IsA("Configuration") then
            for _, sub in ipairs(ch:GetChildren()) do
                if sub:IsA("ScreenGui") then guis[#guis + 1] = sub end
            end
        end
    end
    return guis
end

-- Tim ScreenGui cua hub (co tieu de Chilli VKing)
local function FindHubGui()
    for _, root in ipairs(HubScanRoots()) do
        for _, ch in ipairs(HubCollectGuis(root)) do
            if not ch:GetAttribute("__CosmicSkinned") then
                for _, d in ipairs(ch:GetDescendants()) do
                    if d:IsA("TextLabel") or d:IsA("TextButton") then
                        local t = d.Text
                        if t == "Chilli VKing" or t == "CHILLI VKING" or t == "Chilli Hub V5" then
                            return ch
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Son cosmic: CHI tao instance tinh, KHONG them vong lap nao
local function ApplyCosmicHubSkin()
    local gui = FindHubGui()
    if not gui then return false end
    gui:SetAttribute("__CosmicSkinned", true)

    local painted, stroked, stars = 0, 0, 0
    local candidates = {}

    for _, d in ipairs(gui:GetDescendants()) do
        if d:IsA("Frame") or d:IsA("ImageLabel") or d:IsA("ImageButton") then
            local sz = d.AbsoluteSize
            if sz.X >= 260 and sz.Y >= 140 then
                candidates[#candidates + 1] = d
            end
        end
    end

    -- Gioi han 12 frame lon nhat de khong ton chi phi render
    table.sort(candidates, function(a, b)
        return (a.AbsoluteSize.X * a.AbsoluteSize.Y) > (b.AbsoluteSize.X * b.AbsoluteSize.Y)
    end)

    for i = 1, math.min(#candidates, 12) do
        local f = candidates[i]
        if f and f.Parent then
            local bg = f.BackgroundColor3
            local lum = (bg.R * 0.299 + bg.G * 0.587 + bg.B * 0.114)
            if lum < 0.30 then
                if not f:FindFirstChild("HubCosmicFill") then
                    local g = Instance.new("UIGradient")
                    g.Name = "HubCosmicFill"
                    g.Rotation = 90
                    g.Color = ColorSequence.new({
                        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(10, 6, 24)),
                        ColorSequenceKeypoint.new(0.55, Color3.fromRGB(26, 12, 48)),
                        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(12, 8, 28)),
                    })
                    g.Parent = f
                    painted = painted + 1
                end
                if not f:FindFirstChild("HubCosmicRim") then
                    local s = Instance.new("UIStroke")
                    s.Name = "HubCosmicRim"
                    s.Thickness = 1
                    s.Transparency = 0.35
                    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
                    s.Color = Color3.new(1, 1, 1)
                    local g2 = Instance.new("UIGradient")
                    g2.Name = "HubCosmicRimGrad"
                    g2.Color = HubCosmicGradient()
                    g2.Parent = s
                    s.Parent = f
                    stroked = stroked + 1
                end
            end
        end
    end

    -- Vien cosmic cho nut tron / nut bam nho (khong doi mau nen => giu trang thai bat/tat)
    for _, d in ipairs(gui:GetDescendants()) do
        if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.AbsoluteSize.X >= 40 then
            if not d:FindFirstChild("HubCosmicRim") then
                local s = Instance.new("UIStroke")
                s.Name = "HubCosmicRim"
                s.Thickness = 1
                s.Transparency = 0.62
                s.Color = Color3.new(1, 1, 1)
                local g3 = Instance.new("UIGradient")
                g3.Color = HubCosmicGradient()
                g3.Parent = s
                s.Parent = d
                stroked = stroked + 1
            end
        end
    end

    -- Sao tinh (khong animate => 0 chi phi sau khi tao)
    local starHolder = gui:FindFirstChild("HubCosmicStars")
    if not starHolder then
        starHolder = Instance.new("Frame")
        starHolder.Name = "HubCosmicStars"
        starHolder.Size = UDim2.new(1, 0, 1, 0)
        starHolder.BackgroundTransparency = 1
        starHolder.ZIndex = 2
        starHolder.Parent = gui
        local seed = 20260101
        for i = 1, 14 do
            seed = (seed * 1103515245 + 12345) % 2147483648
            local rx = (seed % 1000) / 1000
            seed = (seed * 1103515245 + 12345) % 2147483648
            local ry = (seed % 1000) / 1000
            seed = (seed * 1103515245 + 12345) % 2147483648
            local rt = 0.25 + ((seed % 1000) / 1000) * 0.45
            local szp = 2 + (i % 3)
            local s = Instance.new("Frame")
            s.Name = "Star" .. i
            s.Size = UDim2.new(0, szp, 0, szp)
            s.Position = UDim2.new(0.02 + rx * 0.95, 0, 0.03 + ry * 0.93, 0)
            s.BackgroundColor3 = (i % 3 == 0) and HUB_COSMIC_B or Color3.fromRGB(214, 199, 255)
            s.BackgroundTransparency = rt
            s.BorderSizePixel = 0
            s.ZIndex = 2
            local cc = Instance.new("UICorner")
            cc.CornerRadius = UDim.new(1, 0)
            cc.Parent = s
            s.Parent = starHolder
            stars = stars + 1
        end
    end

    print(("[Chilli VKing] Cosmic hub: %d gradient, %d vien, %d sao"):format(painted, stroked, stars))
    return true
end

local function LaunchTargetScriptWithWatcher()
    TakeGuiSnapshot()
    getgenv().ChilliV5_Active = true
    if getgenv().ChilliV5_ExternalHub == true then return end

    task.spawn(function()
        pcall(function()
            local hubRaw = game:HttpGet(TargetScriptUrl)
            local hubOut = RenameHubBrand(hubRaw)
            local hubFn = loadstring(hubOut)
            if type(hubFn) ~= "function" then
                warn("[Chilli VKing] Doi ten hub that bai, chay ban goc")
                hubFn = loadstring(hubRaw)
            end
            if type(hubFn) == "function" then hubFn() end
            for _, dl in ipairs({ 0.7, 1.8, 3.4 }) do
                task.delay(dl, function() pcall(ApplyCosmicHubSkin) end)
            end
        end)
    end)
end

local function FormatTime(seconds: number): string
    if seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%02d:%02d", m, s)
end

local ActiveToastLabel = nil

local function ShowLiveToast(titleText: string, initialSeconds: number, color: Color3)
    if CoreGui:FindFirstChild("ChilliV5_ToastUI") then CoreGui.ChilliV5_ToastUI:Destroy() end
    if LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("ChilliV5_ToastUI") then
        LocalPlayer.PlayerGui.ChilliV5_ToastUI:Destroy()
    end

    local ToastGui = Instance.new("ScreenGui")
    ToastGui.Name = "ChilliV5_ToastUI"
    ToastGui.ResetOnSpawn = false
    pcall(function() ToastGui.Parent = CoreGui end)
    if not ToastGui.Parent then ToastGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local ToastFrame = Instance.new("Frame")
    ToastFrame.Size = UDim2.new(0, 340, 0, 60)
    ToastFrame.Position = UDim2.new(0.5, -170, 0, -80)
    ToastFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
    ToastFrame.BorderSizePixel = 0
    ToastFrame.ZIndex = 50
    ToastFrame.Parent = ToastGui

    Instance.new("UICorner", ToastFrame).CornerRadius = UDim.new(0, 12)
    local Stroke = Instance.new("UIStroke", ToastFrame)
    Stroke.Thickness = 1
    Stroke.Color = color or Color3.fromRGB(225, 29, 72)

    local Icon = Instance.new("TextLabel")
    Icon.Size = UDim2.new(0, 36, 1, 0)
    Icon.Position = UDim2.new(0, 8, 0, 0)
    Icon.BackgroundTransparency = 1
    Icon.Text = "🌶️"
    Icon.TextSize = 18
    Icon.ZIndex = 51
    Icon.Parent = ToastFrame

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -55, 0, 18)
    Title.Position = UDim2.new(0, 44, 0, 10)
    Title.BackgroundTransparency = 1
    Title.Text = titleText
    Title.TextColor3 = Color3.fromRGB(248, 250, 252)
    Title.TextSize = 11.5
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.ZIndex = 51
    Title.Parent = ToastFrame

    local Msg = Instance.new("TextLabel")
    Msg.Size = UDim2.new(1, -55, 0, 16)
    Msg.Position = UDim2.new(0, 44, 0, 28)
    Msg.BackgroundTransparency = 1
    Msg.Text = "Thời gian dùng thử: " .. FormatTime(initialSeconds)
    Msg.TextColor3 = Color3.fromRGB(148, 163, 184)
    Msg.TextSize = 10.5
    Msg.Font = Enum.Font.GothamMedium
    Msg.TextXAlignment = Enum.TextXAlignment.Left
    Msg.ZIndex = 51
    Msg.Parent = ToastFrame

    ActiveToastLabel = Msg

    local BarBg = Instance.new("Frame")
    BarBg.Size = UDim2.new(1, -24, 0, 2)
    BarBg.Position = UDim2.new(0, 12, 1, -5)
    BarBg.BackgroundColor3 = Color3.fromRGB(30, 34, 45)
    BarBg.BorderSizePixel = 0
    BarBg.ZIndex = 51
    BarBg.Parent = ToastFrame

    local Bar = Instance.new("Frame")
    Bar.Size = UDim2.new(1, 0, 1, 0)
    Bar.BackgroundColor3 = color or Color3.fromRGB(225, 29, 72)
    Bar.BorderSizePixel = 0
    Bar.ZIndex = 52
    Bar.Parent = BarBg

    TweenService:Create(ToastFrame, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, -170, 0, 18) }):Play()
    TweenService:Create(Bar, TweenInfo.new(10, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 1, 0) }):Play()

    task.delay(10, function()
        if ToastFrame and ToastFrame.Parent then
            local t = TweenService:Create(ToastFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.new(0.5, -170, 0, -80) })
            t:Play()
            t.Completed:Connect(function()
                if ToastGui and ToastGui.Parent then ToastGui:Destroy() end
                ActiveToastLabel = nil
            end)
        end
    end)
end

-- =========================================================================
--   [KEY-WATCH] Kiem tra key lien tuc + chan hub tai lai khi doi server
--   1 request / 60 giay. Khong them vong lap theo frame.
-- =========================================================================

local HEARTBEAT_INTERVAL = 60
local HEARTBEAT_MAX_MISS = 2

local function ResetKeyFlags()
    local env = (getgenv and getgenv()) or _G
    if not env then return end
    env.ChilliV5_Active = false
    env.ChilliV5_ExternalHub = nil
    env.ChilliV5_Heartbeat = false
    env.ChilliV5_KeyExpired = false
end

local function KeyErrIsNetwork(msg)
    local s = string.lower(tostring(msg or ''))
    return s:find('khong goi duoc server', 1, true) ~= nil
        or s:find('server tra ve rong', 1, true) ~= nil
        or s:find('phan hoi khong hop le', 1, true) ~= nil
end

local KeyExpiredHandler = nil

local function StartKeyHeartbeat(activeKey)
    local env = (getgenv and getgenv()) or _G
    if not env or not activeKey then return end
    if env.ChilliV5_Heartbeat == true then return end
    env.ChilliV5_Heartbeat = true

    task.spawn(function()
        local miss = 0
        while env.ChilliV5_Heartbeat == true do
            task.wait(HEARTBEAT_INTERVAL)
            if env.ChilliV5_Heartbeat ~= true then break end
            local ok, err = ApiVerify(activeKey)
            if ok then
                miss = 0
            else
                miss = miss + 1
                if miss >= HEARTBEAT_MAX_MISS or not KeyErrIsNetwork(err) then
                    env.ChilliV5_Heartbeat = false
                    if type(KeyExpiredHandler) == 'function' then
                        pcall(KeyExpiredHandler, tostring(err or ''))
                    end
                    break
                end
            end
        end
    end)
end

KeyExpiredHandler = function(reason)
    local env = (getgenv and getgenv()) or _G
    if env then
        env.ChilliV5_Active = false
        env.ChilliV5_ExternalHub = nil
        env.ChilliV5_KeyExpired = true
    end
    pcall(TerminateTargetScript)
    pcall(ApplyScreenLockdown)
    pcall(ShowLiveToast, 'KEY DA HET HAN - LAY KEY LAI', 0, Color3.fromRGB(225, 29, 72))
    task.wait(1)
    if type(OpenKeySystemUI) == 'function' then pcall(OpenKeySystemUI) end
    print('[Chilli VKing] Key het han: ' .. tostring(reason))
end

-- Boot tu chua: chay lai sau moi lan doi server
local TELEPORT_GUARD_ON = false

local function BuildTeleportBoot()
    local Q = string.char(39)
    local head = 'local API=' .. Q .. API_BASE .. Q
        .. ' local HWID=' .. Q .. MY_HWID .. Q
        .. ' local HUB=' .. Q .. TargetScriptUrl .. Q .. ' '

    local body = [==[
local HS=game:GetService('HttpService')
local CG=game:GetService('CoreGui')
local LP=game:GetService('Players').LocalPlayer
local env=(getgenv and getgenv()) or _G
if env then env.ChilliV5_Active=false env.ChilliV5_Heartbeat=false env.ChilliV5_ExternalHub=nil end
local req=(syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request)
local function verify(k)
    if not k or type(req)~='function' then return false,'no request' end
    local ok,good,err=pcall(function()
        local r=req({Url=API..'/api/verify',Method='POST',Headers={['Content-Type']='application/json'},Body=HS:JSONEncode({key=k,hwid=HWID})})
        if type(r)~='table' then return false,'bad response' end
        local b=r.Body or r.body
        if type(b)~='string' or b=='' then return false,'empty' end
        local d=HS:JSONDecode(b)
        if type(d)=='table' and d.ok==true then return true end
        return false,'invalid'
    end)
    if not ok then return false,'request failed' end
    return good,err
end
local function norm(s)
    local k=string.upper(tostring(s or '')):gsub('[^A-Z0-9]','')
    if #k~=16 then return nil end
    return string.sub(k,1,4)..'-'..string.sub(k,5,8)..'-'..string.sub(k,9,12)..'-'..string.sub(k,13,16)
end
local function makeGui(nm,disp)
    local g=Instance.new('ScreenGui')
    g.Name=nm g.ResetOnSpawn=false g.DisplayOrder=disp
    pcall(function() g.Parent=CG end)
    if not g.Parent then g.Parent=LP:WaitForChild('PlayerGui') end
    return g
end
local function notice(txt)
    local g=makeGui('ChilliV5_BootNotice',900)
    local f=Instance.new('Frame')
    f.AnchorPoint=Vector2.new(0.5,0.5) f.Position=UDim2.new(0.5,0,0.5,0)
    f.Size=UDim2.new(0,360,0,64) f.BackgroundColor3=Color3.fromRGB(24,8,20)
    f.BorderSizePixel=0 f.Parent=g
    Instance.new('UICorner',f).CornerRadius=UDim.new(0,12)
    local s=Instance.new('UIStroke',f) s.Color=Color3.fromRGB(225,29,72) s.Thickness=1
    local t=Instance.new('TextLabel')
    t.Size=UDim2.new(1,-20,1,0) t.Position=UDim2.new(0,10,0,0)
    t.BackgroundTransparency=1 t.Text=txt t.TextWrapped=true
    t.TextColor3=Color3.fromRGB(255,220,220) t.TextSize=12 t.Font=Enum.Font.GothamBold t.Parent=f
    task.delay(8,function() pcall(function() g:Destroy() end) end)
end
local function killHub()
    local keep={ChilliV5_BootNotice=true,ChilliV5_BootKey=true}
    for _,c in ipairs({CG, LP:FindFirstChild('PlayerGui')}) do
        if c then
            for _,ch in ipairs(c:GetChildren()) do
                if ch:IsA('ScreenGui') and not keep[ch.Name] then
                    pcall(function() ch:Destroy() end)
                end
            end
        end
    end
end
local function expired()
    if env then env.ChilliV5_Active=false env.ChilliV5_Heartbeat=false end
    killHub()
    notice('KEY DA HET HAN - HAY CHAY LAI SCRIPT DE LAY KEY MOI')
end
local function openHub()
    local ok,err=pcall(function()
        local raw=game:HttpGet(HUB)
        local out=raw
        if type(raw)=='string' then
            out=raw:gsub('Chilli Hub Discord','Chilli VKing Discord')
            out=out:gsub('Chilli Hub V5','Chilli VKing')
            out=out:gsub('CHILLI HUB V5','CHILLI VKING')
            out=out:gsub('Chilli Hub','Chilli VKing')
        end
        local fn=loadstring(out)
        if type(fn)~='function' then fn=loadstring(raw) end
        if type(fn)=='function' then fn() end
    end)
    if not ok then warn('[Chilli VKing] boot hub loi: '..tostring(err)) end
end
local function startWatch(k)
    if env then env.ChilliV5_Heartbeat=true end
    task.spawn(function()
        local miss=0
        while env and env.ChilliV5_Heartbeat==true do
            task.wait(60)
            if env.ChilliV5_Heartbeat~=true then break end
            local ok=verify(k)
            if ok then
                miss=0
            else
                miss=miss+1
                if miss>=2 then pcall(expired) break end
            end
        end
    end)
end
local function keyBox()
    local g=makeGui('ChilliV5_BootKey',910)
    local f=Instance.new('Frame')
    f.AnchorPoint=Vector2.new(0.5,0.5) f.Position=UDim2.new(0.5,0,0.5,0)
    f.Size=UDim2.new(0,380,0,176) f.BackgroundColor3=Color3.fromRGB(12,7,28)
    f.BorderSizePixel=0 f.Parent=g
    Instance.new('UICorner',f).CornerRadius=UDim.new(0,16)
    local st=Instance.new('UIStroke',f)
    st.Thickness=1 st.Color=Color3.fromRGB(124,58,237)
    local gd=Instance.new('UIGradient',st)
    gd.Color=ColorSequence.new({
        ColorSequenceKeypoint.new(0.00,Color3.fromRGB(124,58,237)),
        ColorSequenceKeypoint.new(0.55,Color3.fromRGB(6,182,212)),
        ColorSequenceKeypoint.new(1.00,Color3.fromRGB(236,72,153)),
    })
    local ttl=Instance.new('TextLabel')
    ttl.Size=UDim2.new(1,-32,0,20) ttl.Position=UDim2.new(0,16,0,14)
    ttl.BackgroundTransparency=1 ttl.Text='CHILLI VKING - KEY DA HET HAN'
    ttl.TextColor3=Color3.fromRGB(243,240,255) ttl.TextSize=13
    ttl.Font=Enum.Font.GothamBold ttl.TextXAlignment=Enum.TextXAlignment.Left ttl.Parent=f
    local box=Instance.new('TextBox')
    box.Size=UDim2.new(1,-32,0,36) box.Position=UDim2.new(0,16,0,44)
    box.BackgroundColor3=Color3.fromRGB(22,25,34) box.BorderSizePixel=0
    box.PlaceholderText='Dan ma key tai day...' box.Text=''
    box.TextColor3=Color3.fromRGB(243,240,255) box.TextSize=12
    box.Font=Enum.Font.GothamMedium box.ClearTextOnFocus=false box.Parent=f
    Instance.new('UICorner',box).CornerRadius=UDim.new(0,10)
    local btn=Instance.new('TextButton')
    btn.Size=UDim2.new(1,-32,0,38) btn.Position=UDim2.new(0,16,0,92)
    btn.BackgroundColor3=Color3.fromRGB(124,58,237) btn.Text='KICH HOAT'
    btn.TextColor3=Color3.fromRGB(255,255,255) btn.TextSize=12
    btn.Font=Enum.Font.GothamBold btn.AutoButtonColor=false btn.Parent=f
    Instance.new('UICorner',btn).CornerRadius=UDim.new(0,10)
    local msg=Instance.new('TextLabel')
    msg.Size=UDim2.new(1,-32,0,18) msg.Position=UDim2.new(0,16,0,140)
    msg.BackgroundTransparency=1 msg.Text='Nhap key moi de tiep tuc su dung hub'
    msg.TextColor3=Color3.fromRGB(176,164,220) msg.TextSize=10
    msg.Font=Enum.Font.GothamMedium msg.TextXAlignment=Enum.TextXAlignment.Left msg.Parent=f
    btn.MouseButton1Click:Connect(function()
        local k=norm(box.Text)
        if not k then
            msg.Text='Ma key phai co 16 ky tu'
            msg.TextColor3=Color3.fromRGB(244,63,94)
            return
        end
        msg.Text='Dang kiem tra...'
        msg.TextColor3=Color3.fromRGB(176,164,220)
        local ok,err=verify(k)
        if ok then
            pcall(function() if writefile then writefile('chilli_key.txt',k) end end)
            pcall(function() g:Destroy() end)
            if env then env.ChilliV5_Active=true end
            openHub()
            startWatch(k)
        else
            msg.Text=tostring(err or 'Key khong hop le')
            msg.TextColor3=Color3.fromRGB(244,63,94)
        end
    end)
end
local raw=nil
if isfile and readfile and isfile('chilli_key.txt') then
    pcall(function() raw=readfile('chilli_key.txt') end)
end
local k0=norm(raw)
local ok0=verify(k0)
if ok0 then
    if env then env.ChilliV5_Active=true end
    openHub()
    startWatch(k0)
else
    keyBox()
end
    ]==]

    return head .. body
end

local function InstallTeleportGuard()
    if TELEPORT_GUARD_ON then return end
    TELEPORT_GUARD_ON = true

    local env = (getgenv and getgenv()) or _G
    local boot = BuildTeleportBoot()

    local realQueue = nil
    pcall(function() if syn and type(syn.queue_on_teleport) == 'function' then realQueue = syn.queue_on_teleport end end)
    if not realQueue then pcall(function() if type(queue_on_teleport) == 'function' then realQueue = queue_on_teleport end end) end
    if not realQueue then pcall(function() if type(queueonteleport) == 'function' then realQueue = queueonteleport end end) end
    if not realQueue then pcall(function() if fluxus and type(fluxus.queue_on_teleport) == 'function' then realQueue = fluxus.queue_on_teleport end end) end
    if not realQueue then
        warn('[Chilli VKing] Executor khong ho tro queue_on_teleport - khong chan duoc hub sau khi doi server')
        return
    end

    local function put(_) pcall(realQueue, boot) end

    pcall(function() if syn then syn.queue_on_teleport = put end end)
    pcall(function() if fluxus then fluxus.queue_on_teleport = put end end)
    pcall(function() if env then env.queue_on_teleport = put end end)
    pcall(function() queue_on_teleport = put end)
    pcall(function() queueonteleport = put end)

    put(boot)
    print('[Chilli VKing] Da chan hub tai lai sau khi doi server')
end

-- =========================================================================
--   🌶️ CHILLI VKING (PHẦN 3/5)
--   GIAO DIỆN CHÍNH DARK SLATE · TỶ LỆ CHUẨN SCALE 1.0 · DỊU MẮT
-- =========================================================================

local Languages = {
    VI = {
        LangBtnText = "🇻🇳 VI",
        SelectLangTitle = "Chọn ngôn ngữ hiển thị",
        Title = "Key Steam Chilli VKing",
        Subtitle = "chilli vking • bản cosmic",
        CenterTitle = "CHILLI VKING",
        CenterSub = "Cosmic Edition 🌌",
        Placeholder = "Dán mã key tại đây...",
        QuickPaste = "Dán",
        GetKey = "Lấy Key (16 Giờ)",
        CheckKey = "Kích Hoạt V5",
        Tutorial = "📖 Hướng dẫn vượt link lấy key",
        MiniGame = "mini game ( getkey or nokey ) 🤑",
        MiniGameLocked = "🔒 Đã mở hôm nay (Reset 00:00)",
        Notice = "📌 Key sống 16 giờ, khoá theo HWID. Bấm Lấy Key để mở trang web (HWID đã copy sẵn).",
        CopiedLink = "Đã sao chép link lấy key (kèm HWID) vào clipboard!",
        CopiedTutorial = "Đã sao chép link hướng dẫn vào clipboard!",
        Checking = "Đang xác nhận...",
        CheckingMsg = "Đang đối soát mã key...",
        Success = "Xác nhận thành công! Đang tải Chilli VKing...",
        Error = "Mã Key không hợp lệ hoặc đã hết hạn!"
    },
    EN = {
        LangBtnText = "🇺🇸 EN",
        SelectLangTitle = "Select Display Language",
        Title = "Key Steam Chilli VKing",
        Subtitle = "chilli vking • cosmic edition",
        CenterTitle = "CHILLI VKING",
        CenterSub = "Cosmic Edition 🌌",
        Placeholder = "Paste your license key here...",
        QuickPaste = "Paste",
        GetKey = "Get Key (16 Hours)",
        CheckKey = "Activate V5",
        Tutorial = "📖 How to bypass link tutorial",
        MiniGame = "mini game ( getkey or nokey ) 🤑",
        MiniGameLocked = "🔒 Opened Today (Resets 00:00)",
        Notice = "📌 Key lasts 16 hours, locked to your HWID. Press Get Key to open the site (HWID copied).",
        CopiedLink = "Key link (with HWID) copied to clipboard!",
        CopiedTutorial = "Tutorial link copied to clipboard!",
        Checking = "Checking...",
        CheckingMsg = "Verifying license key...",
        Success = "Verified! Launching Chilli VKing...",
        Error = "Invalid key or expired license!"
    }
}
local CurrentLang = "VI"

local function PlaySpringButton(btn: TextButton)
    local origSize = btn.Size
    local origPos = btn.Position
    local shrinkSize = UDim2.new(origSize.X.Scale, origSize.X.Offset - 4, origSize.Y.Scale, origSize.Y.Offset - 2)
    local shrinkPos = UDim2.new(origPos.X.Scale, origPos.X.Offset + 2, origPos.Y.Scale, origPos.Y.Offset + 1)

    local t1 = TweenService:Create(btn, TweenInfo.new(0.07, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = shrinkSize, Position = shrinkPos })
    local t2 = TweenService:Create(btn, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = origSize, Position = origPos })
    t1:Play()
    t1.Completed:Connect(function() t2:Play() end)
end

-- =========================================================================
--   [COSMIC-UI] Giao dien cosmic: tim vu tru + sao lap lanh + vien gradient
--   Chi son giao dien. Khong doi logic key / API / ten file.
-- =========================================================================

local COSMIC = {
    BG      = Color3.fromRGB(12, 7, 28),
    BG2     = Color3.fromRGB(34, 17, 66),
    PANEL   = Color3.fromRGB(20, 12, 40),
    PANEL2  = Color3.fromRGB(30, 18, 58),
    ACCENT  = Color3.fromRGB(124, 58, 237),
    ACCENT2 = Color3.fromRGB(6, 182, 212),
    PINK    = Color3.fromRGB(232, 121, 249),
    TEXT    = Color3.fromRGB(243, 240, 255),
    MUTED   = Color3.fromRGB(176, 164, 220),
    DIM     = Color3.fromRGB(112, 100, 152),
    STROKE  = Color3.fromRGB(64, 44, 108),
}

local COSMIC_SEQ = ColorSequence.new({
    ColorSequenceKeypoint.new(0.00, COSMIC.ACCENT),
    ColorSequenceKeypoint.new(0.50, COSMIC.PINK),
    ColorSequenceKeypoint.new(1.00, COSMIC.ACCENT2),
})

local function CosmicNear(c, r, g, b)
    return math.abs(c.R - r / 255) < 0.012
        and math.abs(c.G - g / 255) < 0.012
        and math.abs(c.B - b / 255) < 0.012
end

-- nang cac mau xam cu len tong tim vu tru
local COSMIC_BG_MAP = {
    { 15, 17, 23, COSMIC.PANEL },
    { 20, 23, 31, COSMIC.PANEL2 },
    { 22, 25, 34, COSMIC.BG },
    { 24, 27, 36, COSMIC.PANEL2 },
    { 24, 28, 38, COSMIC.PANEL2 },
    { 28, 20, 28, COSMIC.ACCENT:Lerp(COSMIC.BG, 0.62) },
    { 28, 33, 44, COSMIC.ACCENT:Lerp(COSMIC.BG, 0.55) },
    { 30, 34, 45, COSMIC.BG2 },
    { 32, 37, 49, COSMIC.ACCENT:Lerp(COSMIC.BG, 0.55) },
    { 225, 29, 72, COSMIC.ACCENT },
    { 8, 10, 15, Color3.fromRGB(6, 4, 16) },
}

local COSMIC_TEXT_MAP = {
    { 248, 250, 252, COSMIC.TEXT },
    { 241, 245, 249, COSMIC.TEXT },
    { 226, 232, 240, Color3.fromRGB(238, 233, 255) },
    { 148, 163, 184, COSMIC.MUTED },
    { 100, 116, 139, COSMIC.DIM },
    { 225, 29, 72, Color3.fromRGB(196, 145, 255) },
}

-- ZIndex 40: tren noi dung (31-33), duoi modal gacha (45-49).
-- MainFrame co ClipsDescendants = true nen sao o ZIndex 30 se bi che khuat.
local COSMIC_STAR_Z = 40

local function CosmicStarField(parent, amount)
    local holder = Instance.new("Frame")
    holder.Name = "CosmicStarField"
    holder.Size = UDim2.new(1, 0, 1, 0)
    holder.BackgroundTransparency = 1
    holder.ClipsDescendants = true
    holder.ZIndex = COSMIC_STAR_Z
    holder.Parent = parent

    local stars = {}
    for i = 1, (amount or 38) do
        local s = Instance.new("Frame")
        local px = math.random(1, 2)
        s.Name = "Star"
        s.Size = UDim2.new(0, px, 0, px)
        s.Position = UDim2.new(math.random() * 0.97, 0, math.random() * 0.97, 0)
        s.BackgroundColor3 = Color3.new(1, 1, 1)
        s.BorderSizePixel = 0
        s.BackgroundTransparency = math.random(30, 85) / 100
        s.ZIndex = COSMIC_STAR_Z
        s.Parent = holder
        Instance.new("UICorner", s).CornerRadius = UDim.new(1, 0)
        stars[#stars + 1] = s
    end

    -- 1 vong lap duy nhat cho ca 38 ngoi sao (do lag tren Arceus X)
    task.spawn(function()
        while holder.Parent do
            for i = 1, #stars do
                if stars[i].Parent then
                    stars[i].BackgroundTransparency = math.random(20, 88) / 100
                end
            end
            task.wait(0.7)
        end
    end)
    return holder
end

local function CosmicRepaint(obj)
    if not obj or not obj.Parent then return end
    if obj.Name == "Star" or obj.Name == "CosmicStarField" then return end

    if obj:IsA("GuiObject") then
        local c = obj.BackgroundColor3
        for _, r in ipairs(COSMIC_BG_MAP) do
            if CosmicNear(c, r[1], r[2], r[3]) then
                obj.BackgroundColor3 = r[4]
                if r[4] == COSMIC.ACCENT and (obj:IsA("GuiButton") or obj:IsA("Frame")) then
                    if not obj:FindFirstChildOfClass("UIGradient") then
                        local g = Instance.new("UIGradient")
                        g.Rotation = 12
                        g.Color = COSMIC_SEQ
                        g.Parent = obj
                    end
                end
                break
            end
        end
    end

    if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
        local c = obj.TextColor3
        for _, r in ipairs(COSMIC_TEXT_MAP) do
            if CosmicNear(c, r[1], r[2], r[3]) then
                obj.TextColor3 = r[4]
                break
            end
        end
    end

    if obj:IsA("UIStroke") then
        obj.Color = COSMIC.STROKE
        if obj.Thickness < 1 then obj.Thickness = 1 end
        if not obj:FindFirstChildOfClass("UIGradient") then
            local g = Instance.new("UIGradient")
            g.Color = COSMIC_SEQ
            g.Parent = obj
        end
    end
end

local function ApplyCosmicSkin(screenGui, mainFrame)
    if not mainFrame then return end
    pcall(function()
        for _, d in ipairs(mainFrame:GetDescendants()) do
            CosmicRepaint(d)
        end

        mainFrame.BackgroundColor3 = COSMIC.BG
        if not mainFrame:FindFirstChildOfClass("UIGradient") then
            local bg = Instance.new("UIGradient")
            bg.Rotation = 90
            bg.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0.00, Color3.fromRGB(10, 6, 24)),
                ColorSequenceKeypoint.new(1.00, Color3.fromRGB(34, 17, 66)),
            })
            bg.Parent = mainFrame
        end

        if not mainFrame:FindFirstChild("CosmicStarField") then
            CosmicStarField(mainFrame, 38)
        end

        mainFrame.DescendantAdded:Connect(function(d)
            task.defer(function()
                if d and d.Parent then pcall(CosmicRepaint, d) end
            end)
        end)
    end)
end

OpenKeySystemUI = function()
    if CoreGui:FindFirstChild("ChilliV5_GetKeyUI") then CoreGui.ChilliV5_GetKeyUI:Destroy() end

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "ChilliV5_GetKeyUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    pcall(function() ScreenGui.Parent = CoreGui end)
    if not ScreenGui.Parent then ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    MainFrame.Size = UDim2.new(0, 440, 0, 465)
    MainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
    MainFrame.BorderSizePixel = 0
    MainFrame.ClipsDescendants = true
    MainFrame.ZIndex = 30
    MainFrame.Parent = ScreenGui
    Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 18)

    local MainScale = Instance.new("UIScale", MainFrame)
    MainScale.Scale = 1.0

    local MainStroke = Instance.new("UIStroke", MainFrame)
    MainStroke.Thickness = 1
    MainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    MainStroke.Color = Color3.fromRGB(38, 43, 54)

    -- HEADER
    local HeaderBar = Instance.new("Frame")
    HeaderBar.Size = UDim2.new(1, -28, 0, 40)
    HeaderBar.Position = UDim2.new(0, 14, 0, 12)
    HeaderBar.BackgroundTransparency = 1
    HeaderBar.ZIndex = 31
    HeaderBar.Parent = MainFrame

    local MiniLogo = Instance.new("Frame")
    MiniLogo.Size = UDim2.new(0, 28, 0, 28)
    MiniLogo.Position = UDim2.new(0, 0, 0.5, -14)
    MiniLogo.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    MiniLogo.ClipsDescendants = true
    MiniLogo.ZIndex = 32
    MiniLogo.Parent = HeaderBar
    Instance.new("UICorner", MiniLogo).CornerRadius = UDim.new(1, 0)
    local MiniLogoStroke = Instance.new("UIStroke", MiniLogo)
    MiniLogoStroke.Color = Color3.fromRGB(225, 29, 72)
    MiniLogoStroke.Thickness = 1

    local MiniLogoImg = Instance.new("ImageLabel")
    MiniLogoImg.Size = UDim2.new(1, 0, 1, 0)
    MiniLogoImg.BackgroundTransparency = 1
    MiniLogoImg.Image = ChilliAvatarId
    MiniLogoImg.ScaleType = Enum.ScaleType.Fit
    MiniLogoImg.ZIndex = 33
    MiniLogoImg.Parent = MiniLogo

    local TitleLabel = Instance.new("TextLabel")
    TitleLabel.Size = UDim2.new(1, -100, 0, 18)
    TitleLabel.Position = UDim2.new(0, 36, 0, 2)
    TitleLabel.BackgroundTransparency = 1
    TitleLabel.Text = Languages[CurrentLang].Title
    TitleLabel.TextColor3 = Color3.fromRGB(241, 245, 249)
    TitleLabel.TextSize = 11.5
    TitleLabel.Font = Enum.Font.GothamBold
    TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    TitleLabel.ZIndex = 32
    TitleLabel.Parent = HeaderBar

    local SubTitleLabel = Instance.new("TextLabel")
    SubTitleLabel.Size = UDim2.new(1, -100, 0, 14)
    SubTitleLabel.Position = UDim2.new(0, 36, 0, 20)
    SubTitleLabel.BackgroundTransparency = 1
    SubTitleLabel.Text = "HWID: " .. MY_HWID
    SubTitleLabel.TextColor3 = Color3.fromRGB(148, 163, 184)
    SubTitleLabel.TextSize = 9.5
    SubTitleLabel.Font = Enum.Font.GothamMedium
    SubTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
    SubTitleLabel.ZIndex = 32
    SubTitleLabel.Parent = HeaderBar

    local OpenLangBtn = Instance.new("TextButton")
    OpenLangBtn.Size = UDim2.new(0, 60, 0, 26)
    OpenLangBtn.Position = UDim2.new(1, -60, 0.5, -13)
    OpenLangBtn.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    OpenLangBtn.Text = Languages[CurrentLang].LangBtnText
    OpenLangBtn.TextColor3 = Color3.fromRGB(226, 232, 240)
    OpenLangBtn.TextSize = 10.5
    OpenLangBtn.Font = Enum.Font.GothamBold
    OpenLangBtn.AutoButtonColor = false
    OpenLangBtn.ZIndex = 32
    OpenLangBtn.Parent = HeaderBar
    Instance.new("UICorner", OpenLangBtn).CornerRadius = UDim.new(0, 6)
    local LangStroke = Instance.new("UIStroke", OpenLangBtn)
    LangStroke.Color = Color3.fromRGB(45, 52, 68)
    LangStroke.Thickness = 1

    -- AVATAR QUẢ ỚT CHÍNH GIỮA (92622270383869)
    local CenterLogoBox = Instance.new("Frame")
    CenterLogoBox.Size = UDim2.new(0, 56, 0, 56)
    CenterLogoBox.Position = UDim2.new(0.5, -28, 0, 56)
    CenterLogoBox.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
    CenterLogoBox.ClipsDescendants = true
    CenterLogoBox.ZIndex = 31
    CenterLogoBox.Parent = MainFrame
    Instance.new("UICorner", CenterLogoBox).CornerRadius = UDim.new(0, 14)
    local CenterLogoStroke = Instance.new("UIStroke", CenterLogoBox)
    CenterLogoStroke.Color = Color3.fromRGB(225, 29, 72)
    CenterLogoStroke.Thickness = 1.2

    local CenterLogoImg = Instance.new("ImageLabel")
    CenterLogoImg.Size = UDim2.new(0.9, 0, 0.9, 0)
    CenterLogoImg.AnchorPoint = Vector2.new(0.5, 0.5)
    CenterLogoImg.Position = UDim2.new(0.5, 0, 0.5, 0)
    CenterLogoImg.BackgroundTransparency = 1
    CenterLogoImg.Image = ChilliAvatarId
    CenterLogoImg.ScaleType = Enum.ScaleType.Fit
    CenterLogoImg.ZIndex = 32
    CenterLogoImg.Parent = CenterLogoBox

    local CenterTitle = Instance.new("TextLabel")
    CenterTitle.Size = UDim2.new(1, -30, 0, 20)
    CenterTitle.Position = UDim2.new(0, 15, 0, 118)
    CenterTitle.BackgroundTransparency = 1
    CenterTitle.Text = Languages[CurrentLang].CenterTitle
    CenterTitle.TextColor3 = Color3.fromRGB(248, 250, 252)
    CenterTitle.TextSize = 13.5
    CenterTitle.Font = Enum.Font.GothamBold
    CenterTitle.ZIndex = 31
    CenterTitle.Parent = MainFrame

    local CenterSub = Instance.new("TextLabel")
    CenterSub.Size = UDim2.new(1, -30, 0, 16)
    CenterSub.Position = UDim2.new(0, 15, 0, 138)
    CenterSub.BackgroundTransparency = 1
    CenterSub.Text = Languages[CurrentLang].CenterSub
    CenterSub.TextColor3 = Color3.fromRGB(148, 163, 184)
    CenterSub.TextSize = 10
    CenterSub.Font = Enum.Font.GothamMedium
    CenterSub.ZIndex = 31
    CenterSub.Parent = MainFrame

    -- KHUNG NHẬP LIỆU & NÚT DÁN NHANH
    local InputContainer = Instance.new("Frame")
    InputContainer.Size = UDim2.new(1, -36, 0, 38)
    InputContainer.Position = UDim2.new(0, 18, 0, 160)
    InputContainer.BackgroundColor3 = Color3.fromRGB(22, 25, 34)
    InputContainer.ZIndex = 31
    InputContainer.Parent = MainFrame
    Instance.new("UICorner", InputContainer).CornerRadius = UDim.new(0, 10)
    local InputStroke = Instance.new("UIStroke", InputContainer)
    InputStroke.Color = Color3.fromRGB(42, 48, 62)
    InputStroke.Thickness = 1

    local InputBox = Instance.new("TextBox")
    InputBox.Size = UDim2.new(1, -75, 1, 0)
    InputBox.Position = UDim2.new(0, 12, 0, 0)
    InputBox.BackgroundTransparency = 1
    InputBox.TextColor3 = Color3.fromRGB(248, 250, 252)
    InputBox.PlaceholderColor3 = Color3.fromRGB(100, 116, 139)
    InputBox.PlaceholderText = Languages[CurrentLang].Placeholder
    InputBox.Text = ""
    InputBox.TextSize = 11.5
    InputBox.Font = Enum.Font.GothamMedium
    InputBox.TextXAlignment = Enum.TextXAlignment.Left
    InputBox.ClearTextOnFocus = false
    InputBox.ZIndex = 32
    InputBox.Parent = InputContainer

    local QuickPasteBtn = Instance.new("TextButton")
    QuickPasteBtn.Size = UDim2.new(0, 54, 0, 26)
    QuickPasteBtn.Position = UDim2.new(1, -60, 0.5, -13)
    QuickPasteBtn.BackgroundColor3 = Color3.fromRGB(32, 37, 49)
    QuickPasteBtn.Text = Languages[CurrentLang].QuickPaste
    QuickPasteBtn.TextColor3 = Color3.fromRGB(226, 232, 240)
    QuickPasteBtn.TextSize = 10.5
    QuickPasteBtn.Font = Enum.Font.GothamBold
    QuickPasteBtn.AutoButtonColor = false
    QuickPasteBtn.ZIndex = 33
    QuickPasteBtn.Parent = InputContainer
    Instance.new("UICorner", QuickPasteBtn).CornerRadius = UDim.new(0, 6)
    -- =========================================================================
--   🌶️ CHILLI VKING (PHẦN 4/5)
--   NÚT HỘP QUÀ TỐI GIẢN KHÔNG CHÓI · HỘP QUÀ PHÓNG XA NHÌN RÕ TOÀN THÂN
-- =========================================================================

    local ButtonsRow = Instance.new("Frame")
    ButtonsRow.Size = UDim2.new(1, -36, 0, 40)
    ButtonsRow.Position = UDim2.new(0, 18, 0, 206)
    ButtonsRow.BackgroundTransparency = 1
    ButtonsRow.ZIndex = 31
    ButtonsRow.Parent = MainFrame

    local GetKeyBtn = Instance.new("TextButton")
    GetKeyBtn.Size = UDim2.new(0.5, -6, 1, 0)
    GetKeyBtn.Position = UDim2.new(0, 0, 0, 0)
    GetKeyBtn.BackgroundColor3 = Color3.fromRGB(225, 29, 72)
    GetKeyBtn.Text = Languages[CurrentLang].GetKey
    GetKeyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    GetKeyBtn.TextSize = 11.5
    GetKeyBtn.Font = Enum.Font.GothamBold
    GetKeyBtn.AutoButtonColor = false
    GetKeyBtn.ZIndex = 32
    GetKeyBtn.Parent = ButtonsRow
    Instance.new("UICorner", GetKeyBtn).CornerRadius = UDim.new(0, 10)

    local CheckKeyBtn = Instance.new("TextButton")
    CheckKeyBtn.Size = UDim2.new(0.5, -6, 1, 0)
    CheckKeyBtn.Position = UDim2.new(0.5, 6, 0, 0)
    CheckKeyBtn.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
    CheckKeyBtn.Text = Languages[CurrentLang].CheckKey
    CheckKeyBtn.TextColor3 = Color3.fromRGB(226, 232, 240)
    CheckKeyBtn.TextSize = 11.5
    CheckKeyBtn.Font = Enum.Font.GothamBold
    CheckKeyBtn.AutoButtonColor = false
    CheckKeyBtn.ZIndex = 32
    CheckKeyBtn.Parent = ButtonsRow
    Instance.new("UICorner", CheckKeyBtn).CornerRadius = UDim.new(0, 10)
    local CheckStroke = Instance.new("UIStroke", CheckKeyBtn)
    CheckStroke.Color = Color3.fromRGB(55, 65, 81)
    CheckStroke.Thickness = 1

    local TutorialBtn = Instance.new("TextButton")
    TutorialBtn.Size = UDim2.new(1, -36, 0, 32)
    TutorialBtn.Position = UDim2.new(0, 18, 0, 254)
    TutorialBtn.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
    TutorialBtn.Text = Languages[CurrentLang].Tutorial
    TutorialBtn.TextColor3 = Color3.fromRGB(148, 163, 184)
    TutorialBtn.TextSize = 11
    TutorialBtn.Font = Enum.Font.GothamBold
    TutorialBtn.AutoButtonColor = false
    TutorialBtn.ZIndex = 32
    TutorialBtn.Parent = MainFrame
    Instance.new("UICorner", TutorialBtn).CornerRadius = UDim.new(0, 8)
    local TutorialStroke = Instance.new("UIStroke", TutorialBtn)
    TutorialStroke.Color = Color3.fromRGB(38, 43, 56)
    TutorialStroke.Thickness = 1

    local NoticeCard = Instance.new("Frame")
    NoticeCard.Size = UDim2.new(1, -36, 0, 52)
    NoticeCard.Position = UDim2.new(0, 18, 0, 294)
    NoticeCard.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
    NoticeCard.ZIndex = 31
    NoticeCard.Parent = MainFrame
    Instance.new("UICorner", NoticeCard).CornerRadius = UDim.new(0, 10)
    local NoticeStroke = Instance.new("UIStroke", NoticeCard)
    NoticeStroke.Color = Color3.fromRGB(32, 37, 49)
    NoticeStroke.Thickness = 1

    local NoticeText = Instance.new("TextLabel")
    NoticeText.Size = UDim2.new(1, -16, 1, -6)
    NoticeText.Position = UDim2.new(0, 8, 0, 3)
    NoticeText.BackgroundTransparency = 1
    NoticeText.Text = Languages[CurrentLang].Notice
    NoticeText.TextColor3 = Color3.fromRGB(148, 163, 184)
    NoticeText.TextSize = 10
    NoticeText.Font = Enum.Font.GothamMedium
    NoticeText.TextWrapped = true
    NoticeText.TextYAlignment = Enum.TextYAlignment.Center
    NoticeText.TextXAlignment = Enum.TextXAlignment.Left
    NoticeText.ZIndex = 32
    NoticeText.Parent = NoticeCard

    -- NÚT MINI GAME: TÊN MỚI, MÀU XÁM BẠC DỊU MẮT KHÔNG CHÓI SÁNG
    local MiniGameBtn = Instance.new("TextButton")
    MiniGameBtn.Size = UDim2.new(1, -36, 0, 38)
    MiniGameBtn.Position = UDim2.new(0, 18, 0, 354)
    MiniGameBtn.BackgroundColor3 = CanPlayGachaToday() and Color3.fromRGB(28, 20, 28) or Color3.fromRGB(20, 23, 31)
    MiniGameBtn.Text = CanPlayGachaToday() and Languages[CurrentLang].MiniGame or Languages[CurrentLang].MiniGameLocked
    MiniGameBtn.TextColor3 = CanPlayGachaToday() and Color3.fromRGB(226, 232, 240) or Color3.fromRGB(100, 116, 139)
    MiniGameBtn.TextSize = 11.5
    MiniGameBtn.Font = Enum.Font.GothamBold
    MiniGameBtn.AutoButtonColor = false
    MiniGameBtn.ZIndex = 32
    MiniGameBtn.Parent = MainFrame
    Instance.new("UICorner", MiniGameBtn).CornerRadius = UDim.new(0, 10)
    local MiniGameStroke = Instance.new("UIStroke", MiniGameBtn)
    MiniGameStroke.Color = CanPlayGachaToday() and Color3.fromRGB(225, 29, 72) or Color3.fromRGB(38, 43, 56)
    MiniGameStroke.Thickness = 1

    local StatusMsg = Instance.new("TextLabel")
    StatusMsg.Size = UDim2.new(1, -36, 0, 20)
    StatusMsg.Position = UDim2.new(0, 18, 0, 402)
    StatusMsg.BackgroundTransparency = 1
    StatusMsg.Text = "Chilli VKing • Cosmic Edition 🌌"
    StatusMsg.TextColor3 = Color3.fromRGB(100, 116, 139)
    StatusMsg.TextSize = 9.5
    StatusMsg.Font = Enum.Font.GothamMedium
    StatusMsg.ZIndex = 31
    StatusMsg.Parent = MainFrame

    -- MODAL HỘP QUÀ GACHA
    local GachaModal = Instance.new("Frame")
    GachaModal.Name = "GachaModal"
    GachaModal.Size = UDim2.new(1, 0, 1, 0)
    GachaModal.Position = UDim2.new(0, 0, 1, 0)
    GachaModal.BackgroundColor3 = Color3.fromRGB(15, 17, 23)
    GachaModal.ZIndex = 45
    GachaModal.ClipsDescendants = true
    GachaModal.Parent = MainFrame
    Instance.new("UICorner", GachaModal).CornerRadius = UDim.new(0, 16)

    local GachaHeader = Instance.new("TextLabel")
    GachaHeader.Size = UDim2.new(1, -60, 0, 24)
    GachaHeader.Position = UDim2.new(0, 18, 0, 12)
    GachaHeader.BackgroundTransparency = 1
    GachaHeader.Text = "🎁 HỘP QUÀ MAY MẮN (1 LẦN/NGÀY)"
    GachaHeader.TextColor3 = Color3.fromRGB(248, 250, 252)
    GachaHeader.TextSize = 12
    GachaHeader.Font = Enum.Font.GothamBold
    GachaHeader.TextXAlignment = Enum.TextXAlignment.Left
    GachaHeader.ZIndex = 46
    GachaHeader.Parent = GachaModal

    local GachaCloseBtn = Instance.new("TextButton")
    GachaCloseBtn.Size = UDim2.new(0, 26, 0, 26)
    GachaCloseBtn.Position = UDim2.new(1, -36, 0, 12)
    GachaCloseBtn.BackgroundColor3 = Color3.fromRGB(24, 28, 38)
    GachaCloseBtn.Text = "✕"
    GachaCloseBtn.TextColor3 = Color3.fromRGB(148, 163, 184)
    GachaCloseBtn.TextSize = 11
    GachaCloseBtn.Font = Enum.Font.GothamBold
    GachaCloseBtn.ZIndex = 46
    GachaCloseBtn.Parent = GachaModal
    Instance.new("UICorner", GachaCloseBtn).CornerRadius = UDim.new(0, 6)

    local GachaSubText = Instance.new("TextLabel")
    GachaSubText.Size = UDim2.new(1, -36, 0, 20)
    GachaSubText.Position = UDim2.new(0, 18, 0, 38)
    GachaSubText.BackgroundTransparency = 1
    GachaSubText.Text = "Chọn 1 hộp bất kỳ. Trúng NoKey sẽ vào thẳng script không cần GetKey!"
    GachaSubText.TextColor3 = Color3.fromRGB(148, 163, 184)
    GachaSubText.TextSize = 10
    GachaSubText.Font = Enum.Font.GothamMedium
    GachaSubText.TextXAlignment = Enum.TextXAlignment.Left
    GachaSubText.ZIndex = 46
    GachaSubText.Parent = GachaModal

    local BoxesContainer = Instance.new("Frame")
    BoxesContainer.Size = UDim2.new(1, -36, 0, 225)
    BoxesContainer.Position = UDim2.new(0, 18, 0, 64)
    BoxesContainer.BackgroundTransparency = 1
    BoxesContainer.ZIndex = 46
    BoxesContainer.Parent = GachaModal

    -- TẠO HỘP QUÀ: CĂN CHỈNH TỶ LỆ FIT 0.85 NHÌN TRỌN VẸN TOÀN THÂN
    local function CreateMysteryBox(name: string, posXScale: number, posXOffset: number, boxTitle: string)
        local BoxCard = Instance.new("TextButton")
        BoxCard.Name = name
        BoxCard.Size = UDim2.new(0.5, -6, 1, 0)
        BoxCard.Position = UDim2.new(posXScale, posXOffset, 0, 0)
        BoxCard.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
        BoxCard.Text = ""
        BoxCard.AutoButtonColor = false
        BoxCard.ZIndex = 47
        BoxCard.Parent = BoxesContainer
        Instance.new("UICorner", BoxCard).CornerRadius = UDim.new(0, 14)
        local BoxStroke = Instance.new("UIStroke", BoxCard)
        BoxStroke.Color = Color3.fromRGB(45, 52, 68)
        BoxStroke.Thickness = 1

        local Tag5050 = Instance.new("TextLabel")
        Tag5050.Size = UDim2.new(1, -16, 0, 18)
        Tag5050.Position = UDim2.new(0, 8, 0, 8)
        Tag5050.BackgroundColor3 = Color3.fromRGB(28, 33, 44)
        Tag5050.Text = "TỈ LỆ: 50% - 50%"
        Tag5050.TextColor3 = Color3.fromRGB(226, 232, 240)
        Tag5050.TextSize = 9
        Tag5050.Font = Enum.Font.GothamBold
        Tag5050.ZIndex = 48
        Tag5050.Parent = BoxCard
        Instance.new("UICorner", Tag5050).CornerRadius = UDim.new(0, 6)

        local CropMask = Instance.new("Frame")
        CropMask.Name = "CropMask"
        CropMask.AnchorPoint = Vector2.new(0.5, 0)
        CropMask.Size = UDim2.new(0, 100, 0, 100)
        CropMask.Position = UDim2.new(0.5, 0, 0, 32)
        CropMask.BackgroundTransparency = 1
        CropMask.BorderSizePixel = 0
        CropMask.ClipsDescendants = false
        CropMask.ZIndex = 48
        CropMask.Parent = BoxCard

        local GiftImage = Instance.new("ImageLabel")
        GiftImage.Name = "GiftImage"
        GiftImage.AnchorPoint = Vector2.new(0.5, 0.5)
        GiftImage.Size = UDim2.new(0.85, 0, 0.85, 0)
        GiftImage.Position = UDim2.new(0.5, 0, 0.5, 0)
        GiftImage.BackgroundTransparency = 1
        GiftImage.Image = GiftBoxAssetId
        GiftImage.ScaleType = Enum.ScaleType.Fit
        GiftImage.ZIndex = 49
        GiftImage.Parent = CropMask

        local Aspect = Instance.new("UIAspectRatioConstraint", GiftImage)
        Aspect.AspectRatio = 1

        local Title = Instance.new("TextLabel")
        Title.Name = "BoxTitle"
        Title.Size = UDim2.new(1, 0, 0, 18)
        Title.Position = UDim2.new(0, 0, 0, 138)
        Title.BackgroundTransparency = 1
        Title.Text = boxTitle
        Title.TextColor3 = Color3.fromRGB(248, 250, 252)
        Title.TextSize = 11.5
        Title.Font = Enum.Font.GothamBold
        Title.ZIndex = 48
        Title.Parent = BoxCard

        local ActionHint = Instance.new("TextLabel")
        ActionHint.Name = "ActionHint"
        ActionHint.Size = UDim2.new(1, -20, 0, 26)
        ActionHint.Position = UDim2.new(0, 10, 0, 172)
        ActionHint.BackgroundColor3 = Color3.fromRGB(225, 29, 72)
        ActionHint.Text = "MỞ HỘP"
        ActionHint.TextColor3 = Color3.fromRGB(255, 255, 255)
        ActionHint.TextSize = 10.5
        ActionHint.Font = Enum.Font.GothamBold
        ActionHint.ZIndex = 48
        ActionHint.Parent = BoxCard
        Instance.new("UICorner", ActionHint).CornerRadius = UDim.new(0, 8)

        return BoxCard, BoxStroke, CropMask, Title, ActionHint
    end

    local Box1, Box1Stroke, Box1Mask, Box1Title, Box1Hint = CreateMysteryBox("Box1", 0, 0, "HỘP QUÀ #1")
    local Box2, Box2Stroke, Box2Mask, Box2Title, Box2Hint = CreateMysteryBox("Box2", 0.5, 6, "HỘP QUÀ #2")

    local GachaResultBanner = Instance.new("TextLabel")
    GachaResultBanner.Size = UDim2.new(1, -36, 0, 36)
    GachaResultBanner.Position = UDim2.new(0, 18, 0, 298)
    GachaResultBanner.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
    GachaResultBanner.Text = "Bấm vào 1 trong 2 hộp quà phía trên để thử vận may!"
    GachaResultBanner.TextColor3 = Color3.fromRGB(226, 232, 240)
    GachaResultBanner.TextSize = 10.5
    GachaResultBanner.Font = Enum.Font.GothamMedium
    GachaResultBanner.ZIndex = 46
    GachaResultBanner.Parent = GachaModal
    Instance.new("UICorner", GachaResultBanner).CornerRadius = UDim.new(0, 10)
    -- =========================================================================
--   🌶️ CHILLI VKING (PHẦN 5/5)
--   BACKEND TỈ LỆ 80% GETKEY - 20% NOKEY · ĐỔI NGÔN NGỮ · LUỒNG DÙNG THỬ
-- =========================================================================

    local isRollingMutex = false

    local function OpenGachaModal()
        TweenService:Create(GachaModal, TweenInfo.new(0.26, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Position = UDim2.new(0, 0, 0, 0)
        }):Play()
    end

    local function CloseGachaModal()
        TweenService:Create(GachaModal, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.In), {
            Position = UDim2.new(0, 0, 1, 0)
        }):Play()
    end

    GachaCloseBtn.MouseButton1Click:Connect(function()
        if isRollingMutex then return end
        PlaySpringButton(GachaCloseBtn)
        CloseGachaModal()
    end)

    MiniGameBtn.MouseButton1Click:Connect(function()
        PlaySpringButton(MiniGameBtn)
        if not CanPlayGachaToday() then
            local secsLeft = GetSecondsUntilMidnightGMT7()
            local hoursLeft = math.floor(secsLeft / 3600)
            local minsLeft = math.floor((secsLeft % 3600) / 60)
            StatusMsg.Text = string.format("⏳ Đã mở hôm nay! Reset sau %02d:%02d (00:00 GMT+7)", hoursLeft, minsLeft)
            StatusMsg.TextColor3 = Color3.fromRGB(244, 63, 94)
            return
        end
        OpenGachaModal()
    end)

    local function ExecuteBoxRoll(chosenBox: TextButton, otherBox: TextButton, chosenStroke: UIStroke, chosenMask: Frame, chosenTitle: TextLabel, chosenHint: TextLabel)
        if isRollingMutex then return end
        isRollingMutex = true

        SaveGachaPlayed()
        MiniGameBtn.Text = Languages[CurrentLang].MiniGameLocked
        MiniGameBtn.BackgroundColor3 = Color3.fromRGB(20, 23, 31)
        MiniGameBtn.TextColor3 = Color3.fromRGB(100, 116, 139)
        MiniGameStroke.Color = Color3.fromRGB(38, 43, 56)

        TweenService:Create(otherBox, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.65 }):Play()
        otherBox.Active = false

        chosenStroke.Color = Color3.fromRGB(245, 158, 11)
        chosenHint.Text = "ĐANG MỞ..."
        chosenHint.BackgroundColor3 = Color3.fromRGB(217, 119, 6)
        GachaResultBanner.Text = "⏳ Đang mở hộp quà..."
        GachaResultBanner.TextColor3 = Color3.fromRGB(253, 224, 71)

        for i = 1, 6 do
            local angle = (i % 2 == 0) and 5 or -5
            TweenService:Create(chosenMask, TweenInfo.new(0.06, Enum.EasingStyle.Quad), { Rotation = angle }):Play()
            task.wait(0.065)
        end
        TweenService:Create(chosenMask, TweenInfo.new(0.08, Enum.EasingStyle.Back), { Rotation = 0 }):Play()
        task.wait(0.2)

        local roll = math.random(1, 100)
        local isNoKeyWon = false -- [MYKEY] tat NoKey: khong cho vuot key system

        if isNoKeyWon then
            chosenStroke.Color = Color3.fromRGB(34, 197, 94)
            chosenTitle.Text = "🎉 TRÚNG NOKEY!"
            chosenTitle.TextColor3 = Color3.fromRGB(74, 222, 128)
            chosenHint.Text = "VÀO SCRIPT NGAY"
            chosenHint.BackgroundColor3 = Color3.fromRGB(22, 163, 74)

            GachaResultBanner.Text = "🎉 Chúc mừng! Bạn trúng NoKey! Đang tải script..."
            GachaResultBanner.TextColor3 = Color3.fromRGB(74, 222, 128)

            Save24hKey(GetSecondsUntilMidnightGMT7())

            task.wait(1.2)
            RemoveScreenLockdown()
            StartKeyHeartbeat(normKey)
            LaunchTargetScriptWithWatcher()

            TweenService:Create(MainScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.8 }):Play()
            task.wait(0.2)
            ScreenGui:Destroy()
        else
            chosenStroke.Color = Color3.fromRGB(225, 29, 72)
            chosenTitle.Text = "🔑 LÀ HỘP GETKEY"
            chosenTitle.TextColor3 = Color3.fromRGB(251, 113, 133)
            chosenHint.Text = "QUAY VỀ LẤY KEY"
            chosenHint.BackgroundColor3 = Color3.fromRGB(159, 18, 57)

            GachaResultBanner.Text = "Hộp này là GetKey! Vui lòng vượt link để nhận key nhé."
            GachaResultBanner.TextColor3 = Color3.fromRGB(251, 113, 133)

            task.wait(1.5)
            CloseGachaModal()
            isRollingMutex = false

            StatusMsg.Text = "📌 Mở trúng GetKey! Bấm 'Lấy Key (16 Giờ)' để tiếp tục."
            StatusMsg.TextColor3 = Color3.fromRGB(251, 113, 133)
        end
    end

    Box1.MouseButton1Click:Connect(function()
        ExecuteBoxRoll(Box1, Box2, Box1Stroke, Box1Mask, Box1Title, Box1Hint)
    end)

    Box2.MouseButton1Click:Connect(function()
        ExecuteBoxRoll(Box2, Box1, Box2Stroke, Box2Mask, Box2Title, Box2Hint)
    end)

    QuickPasteBtn.MouseButton1Click:Connect(function()
        PlaySpringButton(QuickPasteBtn)
        local pasted = false
        pcall(function()
            if getclipboard then
                InputBox.Text = getclipboard()
                pasted = true
            elseif fromclipboard then
                InputBox.Text = fromclipboard()
                pasted = true
            end
        end)
        if not pasted then
            InputBox:CaptureFocus()
        end
    end)

    local isTutorialDebounce = false
    TutorialBtn.MouseButton1Click:Connect(function()
        if isTutorialDebounce then return end
        isTutorialDebounce = true
        PlaySpringButton(TutorialBtn)

        if setclipboard then setclipboard(TutorialUrl) elseif toclipboard then toclipboard(TutorialUrl) end

        TutorialBtn.Text = "✔ Đã chép link HD"
        TutorialBtn.TextColor3 = Color3.fromRGB(52, 211, 153)
        StatusMsg.Text = Languages[CurrentLang].CopiedTutorial
        StatusMsg.TextColor3 = Color3.fromRGB(52, 211, 153)

        task.delay(2.2, function()
            if TutorialBtn and TutorialBtn.Parent then
                TutorialBtn.Text = Languages[CurrentLang].Tutorial
                TutorialBtn.TextColor3 = Color3.fromRGB(148, 163, 184)
                StatusMsg.Text = "Chilli VKing • Cosmic Edition 🌌"
                StatusMsg.TextColor3 = Color3.fromRGB(100, 116, 139)
            end
            isTutorialDebounce = false
        end)
    end)

    GetKeyBtn.MouseButton1Click:Connect(function()
        PlaySpringButton(GetKeyBtn)
        local KeyLink = BuildKeyLink()
        if setclipboard then pcall(setclipboard, KeyLink) elseif toclipboard then pcall(toclipboard, KeyLink) end
        pcall(function()
            if type(openbrowser) == "function" then openbrowser(KeyLink) end
        end)
        print("[Chilli VKing] HWID: " .. MY_HWID .. " | Link lay key (da copy): " .. KeyLink)

        GetKeyBtn.Text = "✔ Đã Copy Link Key"
        GetKeyBtn.BackgroundColor3 = Color3.fromRGB(16, 185, 129)
        StatusMsg.Text = Languages[CurrentLang].CopiedLink
        StatusMsg.TextColor3 = Color3.fromRGB(52, 211, 153)

        task.delay(2.2, function()
            if GetKeyBtn and GetKeyBtn.Parent then
                GetKeyBtn.Text = Languages[CurrentLang].GetKey
                GetKeyBtn.BackgroundColor3 = Color3.fromRGB(225, 29, 72)
                StatusMsg.Text = "Chilli VKing • Cosmic Edition 🌌"
                StatusMsg.TextColor3 = Color3.fromRGB(100, 116, 139)
            end
        end)
    end)

    local isChecking = false
    CheckKeyBtn.MouseButton1Click:Connect(function()
        if isChecking then return end
        isChecking = true
        PlaySpringButton(CheckKeyBtn)

        CheckKeyBtn.Text = Languages[CurrentLang].Checking
        StatusMsg.Text = Languages[CurrentLang].CheckingMsg
        StatusMsg.TextColor3 = Color3.fromRGB(226, 232, 240)

        task.wait(0.3)
        local normKey = NormalizeMyKey(InputBox.Text)
        local isKeyValid, apiErr = nil, nil
        if normKey then isKeyValid, apiErr = ApiVerify(normKey) end

        if isKeyValid then
            Save24hKey()
            if writefile and normKey then pcall(writefile, "chilli_key.txt", normKey .. "\n") end
            CheckKeyBtn.Text = "✔ Thành Công"
            CheckKeyBtn.BackgroundColor3 = Color3.fromRGB(22, 163, 74)
            StatusMsg.Text = Languages[CurrentLang].Success
            StatusMsg.TextColor3 = Color3.fromRGB(74, 222, 128)

            RemoveScreenLockdown()
            LaunchTargetScriptWithWatcher()

            task.wait(0.35)
            TweenService:Create(MainScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.8 }):Play()
            task.wait(0.2)
            ScreenGui:Destroy()
        else
            isChecking = false
            CheckKeyBtn.Text = Languages[CurrentLang].CheckKey
            StatusMsg.Text = apiErr or Languages[CurrentLang].Error
            StatusMsg.TextColor3 = Color3.fromRGB(244, 63, 94)

            InputStroke.Color = Color3.fromRGB(225, 29, 72)
            local origOffset = MainFrame.Position.X.Offset
            local offsets = { -6, 6, -4, 4, -2, 2, 0 }
            task.spawn(function()
                for _, off in ipairs(offsets) do
                    local t = TweenService:Create(MainFrame, TweenInfo.new(0.04, Enum.EasingStyle.Quad), {
                        Position = UDim2.new(0.5, off, 0.5, 0)
                    })
                    t:Play()
                    t.Completed:Wait()
                end
                MainFrame.Position = UDim2.new(0.5, origOffset, 0.5, 0)
            end)
            task.wait(0.5)
            InputStroke.Color = Color3.fromRGB(42, 48, 62)
        end
    end)

    OpenLangBtn.MouseButton1Click:Connect(function()
        PlaySpringButton(OpenLangBtn)
        CurrentLang = (CurrentLang == "VI") and "EN" or "VI"
        local data = Languages[CurrentLang]
        OpenLangBtn.Text = data.LangBtnText
        TitleLabel.Text = data.Title
        SubTitleLabel.Text = "HWID: " .. MY_HWID
        CenterTitle.Text = data.CenterTitle
        CenterSub.Text = data.CenterSub
        InputBox.PlaceholderText = data.Placeholder
        QuickPasteBtn.Text = data.QuickPaste
        GetKeyBtn.Text = data.GetKey
        CheckKeyBtn.Text = data.CheckKey
        TutorialBtn.Text = data.Tutorial
        MiniGameBtn.Text = CanPlayGachaToday() and data.MiniGame or data.MiniGameLocked
        NoticeText.Text = data.Notice
    end)

    MainFrame.BackgroundTransparency = 1
    MainScale.Scale = 0.85
    ApplyCosmicSkin(ScreenGui, MainFrame)
    TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 0 }):Play()
    TweenService:Create(MainScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.0 }):Play()
end

-- =========================================================================
--   LUỒNG CHÍNH: DÙNG THỬ 2 PHÚT & KHÓA MÀN HÌNH TỰ ĐỘNG
-- =========================================================================

-- [KEY-WATCH] Xoa co phien cu (chan di truyen quyen qua teleport) + chan hub tu nap lai
ResetKeyFlags()
InstallTeleportGuard()

-- [MYKEY] Kiem tra key da luu voi server truoc khi mo hub
local savedMyKey = nil
if isfile and readfile and isfile("chilli_key.txt") then
    local okR, rawK = pcall(readfile, "chilli_key.txt")
    if okR and type(rawK) == "string" then savedMyKey = NormalizeMyKey(rawK) end
end

if savedMyKey then
    local okK, errK, remMs = ApiVerify(savedMyKey)
    if okK then
        ShowLiveToast("CHILLI VKING -- KEY OK", math.floor((remMs or 0) / 1000), Color3.fromRGB(225, 29, 72))
        StartKeyHeartbeat(savedMyKey)
        LaunchTargetScriptWithWatcher()
        return
    end
    print("[Chilli VKing] Key da luu khong dung duoc: " .. tostring(errK))
end


-- =========================================================================
--   [MYKEY] KHONG CON DUNG THU -- BAT BUOC CO KEY KHOP HWID (16 GIO)
-- =========================================================================

ApplyScreenLockdown()
ShowLiveToast("CAN KEY DE DUNG HUB", 0, Color3.fromRGB(225, 29, 72))
print("[Chilli VKing] Chua co key hop le. HWID: " .. MY_HWID)
print("[Chilli VKing] Lay key tai: " .. KeyUrl)
OpenKeySystemUI()
