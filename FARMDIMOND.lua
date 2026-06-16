-- BƯỚC 1: Chờ game load an toàn
if not game:IsLoaded() then game.Loaded:Wait() end

-- BƯỚC 2: Tải script bất đồng bộ chống đơ máy
local url = "https://raw.githubusercontent.com/obiyeueim/99NIGH/refs/heads/main/dimondfarm.lua?t=" .. tostring(tick())
local code = ""

local success = pcall(function()
    code = game:HttpGetAsync(url) -- Dùng HttpGetAsync thay vì HttpGet
end)

if not success or code == "" then
    -- Thử lại với hàm request nội bộ nếu HttpGetAsync bị lỗi
    local req = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if req then
        local res = req({Url = url, Method = "GET"})
        code = res.Body
    end
end

-- BƯỚC 3: Chạy script trên luồng chính (Để đảm bảo Menu hiện lên)
if code and code ~= "" then
    task.wait(0.5) -- Nghỉ nửa giây cho RAM kịp thở
    local runScript = loadstring(code)
    if runScript then
        runScript()
    end
end
