--[[
╔══════════════════════════════════════════════════════════════╗
║          MAPA ANALYZER & CLONER - NDS EDITION (v2)           ║
║         Ferramenta de Estudo para Roblox Studio              ║
╠══════════════════════════════════════════════════════════════╣
║ Mudanças desta versão (v2):                                  ║
║  - Drag isolado no Header (cliques em botões funcionam)      ║
║  - Concatenação corrigida em "Status: Habilitado/Desab."     ║
║  - Contagem de linhas correta (countLines com gsub + 1)      ║
║  - JSON do backup salvo como StringValue (Lua-safe)          ║
║  - BatchSize realmente aplicado na recursão de análise       ║
║  - Funções todas locais (sem poluir _G)                      ║
║  - Conexões rastreadas e desconectadas no fechamento         ║
║  - Hover/feedback visual nos botões                          ║
║  - Search/filtro na aba Scripts                              ║
║  - Tree truncada com aviso (evita travar com 100k objetos)   ║
║  - Aba Config edita os parâmetros em runtime                 ║
║  - Imports não usados removidos (Mouse/RunService)           ║
║  - Fallback para clipboard quando setclipboard indisponível  ║
║  - ClearContent agora pega qualquer GuiObject                ║
║  - Suporte a Beam, posições de Models via GetPivot           ║
╚══════════════════════════════════════════════════════════════╝
--]]

-- ═══════════════════════════════════════════════════════════
-- CONFIGURAÇÕES
-- ═══════════════════════════════════════════════════════════

local CONFIG = {
    MapName       = "Map",     -- Nome do modelo/folder em Workspace
    MaxDepth      = 50,
    MaxObjects    = 100000,
    BatchSize     = 200,       -- yield a cada N objetos processados
    MaxTreeNodes  = 2000,      -- limite de nós na aba Estrutura
    MaxScriptList = 500,       -- limite de scripts listados na aba Scripts
}

-- ═══════════════════════════════════════════════════════════
-- TEMA
-- ═══════════════════════════════════════════════════════════

local Theme = {
    Background = Color3.fromRGB(25, 25, 35),
    Secondary  = Color3.fromRGB(35, 35, 50),
    Tertiary   = Color3.fromRGB(50, 50, 70),
    Accent     = Color3.fromRGB(80, 120, 255),
    Success    = Color3.fromRGB(50, 200, 100),
    Warning    = Color3.fromRGB(255, 180, 50),
    Danger     = Color3.fromRGB(255, 70, 70),
    Text       = Color3.fromRGB(255, 255, 255),
    TextDim    = Color3.fromRGB(180, 180, 180),
    CodeBg     = Color3.fromRGB(15, 15, 22),
}

local function lighten(color, amount)
    amount = amount or 0.12
    return Color3.new(
        math.min(1, color.R + amount),
        math.min(1, color.G + amount),
        math.min(1, color.B + amount)
    )
end

-- ═══════════════════════════════════════════════════════════
-- SERVIÇOS
-- ═══════════════════════════════════════════════════════════

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local HttpService      = game:GetService("HttpService")
local TweenService     = game:GetService("TweenService")

local LocalPlayer = Players.LocalPlayer or Players:GetPropertyChangedSignal("LocalPlayer"):Wait() and Players.LocalPlayer
assert(LocalPlayer, "Este script precisa rodar como LocalScript com um LocalPlayer.")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════
-- ESTADO
-- ═══════════════════════════════════════════════════════════

local function defaultStats()
    return {
        TotalParts       = 0,
        TotalModels      = 0,
        TotalScripts     = 0,
        TotalTools       = 0,
        TotalLights      = 0,
        TotalParticles   = 0,
        TotalDecals      = 0,
        TotalNPCs        = 0,
        MaxDepth         = 0,
        LargestFolder    = "-",
        TotalScriptLines = 0,
    }
end

local DataStorage = {
    ClonedMap  = nil,
    MapInfo    = {},
    Scripts    = {},
    AllObjects = {},
    Statistics = defaultStats(),
}

local UIState = {
    scriptSearch = "",
    activeTab    = 1,
}

local function resetState()
    if DataStorage.ClonedMap then
        pcall(function() DataStorage.ClonedMap:Destroy() end)
    end
    DataStorage.ClonedMap  = nil
    DataStorage.MapInfo    = {}
    DataStorage.Scripts    = {}
    DataStorage.AllObjects = {}
    DataStorage.Statistics = defaultStats()
end

-- ═══════════════════════════════════════════════════════════
-- RASTREAMENTO DE CONEXÕES
-- ═══════════════════════════════════════════════════════════

local Connections = {}

local function track(conn)
    table.insert(Connections, conn)
    return conn
end

local function disconnectAll()
    for _, c in ipairs(Connections) do
        pcall(function() c:Disconnect() end)
    end
    table.clear(Connections)
end

-- ═══════════════════════════════════════════════════════════
-- HELPERS GERAIS
-- ═══════════════════════════════════════════════════════════

local function countLines(source)
    if type(source) ~= "string" or source == "" then return 0 end
    local _, n = source:gsub("\n", "\n")
    -- +1 se a última linha não terminar em \n (linha final sem newline)
    return n + (source:sub(-1) ~= "\n" and 1 or 0)
end

local function tryGetSource(obj)
    local ok, src = pcall(function() return obj.Source end)
    if ok and type(src) == "string" then return src end
    return nil
end

local function safeFullName(obj)
    local ok, name = pcall(function() return obj:GetFullName() end)
    if ok then return name end
    return obj.Name
end

local function clipboardCopy(text)
    -- setclipboard é exposto pelo Studio e por alguns ambientes; fallback p/ StringValue
    local fn = rawget(getfenv(), "setclipboard") or rawget(getfenv(), "toclipboard")
    if typeof(fn) == "function" then
        local ok = pcall(fn, text)
        if ok then return true end
    end
    return false
end

local function getModelPosition(obj)
    if obj:IsA("BasePart") then
        return obj.Position
    elseif obj:IsA("Model") then
        local ok, pivot = pcall(function() return obj:GetPivot() end)
        if ok then return pivot.Position end
    end
    return nil
end

-- ═══════════════════════════════════════════════════════════
-- FÁBRICAS DE UI BÁSICAS
-- ═══════════════════════════════════════════════════════════

local function makeCorner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = parent
    return c
end

local function makePadding(parent, all)
    local p = Instance.new("UIPadding")
    p.PaddingLeft   = UDim.new(0, all)
    p.PaddingRight  = UDim.new(0, all)
    p.PaddingTop    = UDim.new(0, all)
    p.PaddingBottom = UDim.new(0, all)
    p.Parent = parent
    return p
end

local function makeListLayout(parent, padding, horizontal)
    local l = Instance.new("UIListLayout")
    l.Padding = UDim.new(0, padding or 5)
    l.SortOrder = Enum.SortOrder.LayoutOrder
    if horizontal then
        l.FillDirection = Enum.FillDirection.Horizontal
    end
    l.Parent = parent
    return l
end

local function bindHover(button, baseColor)
    local hoverColor = lighten(baseColor, 0.10)
    track(button.MouseEnter:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = hoverColor }):Play()
    end))
    track(button.MouseLeave:Connect(function()
        TweenService:Create(button, TweenInfo.new(0.12), { BackgroundColor3 = baseColor }):Play()
    end))
end

-- ═══════════════════════════════════════════════════════════
-- FORWARD DECLARATIONS
-- ═══════════════════════════════════════════════════════════

local AnalyzeMap, CloneMap, CreateBackup, ExportData
local UpdateStatus, UpdateContent, ClearContent, ShowScriptCode
local UI = {} -- referências às instâncias da UI

-- ═══════════════════════════════════════════════════════════
-- LÓGICA: Análise do Mapa
-- ═══════════════════════════════════════════════════════════

function AnalyzeMap()
    local map = workspace:FindFirstChild(CONFIG.MapName)
    if not map then
        UpdateStatus("❌ Mapa '" .. CONFIG.MapName .. "' não encontrado em Workspace")
        return false
    end

    UpdateStatus("⏳ Analisando '" .. map.Name .. "'...")

    DataStorage.MapInfo = {
        Name             = map.Name,
        FullPath         = safeFullName(map),
        Hierarchy        = {},
        ImportantObjects = {},
    }
    DataStorage.Scripts    = {}
    DataStorage.AllObjects = {}
    DataStorage.Statistics = defaultStats()

    local stats        = DataStorage.Statistics
    local folderCounts = {}
    local objectCount  = 0

    local function processObject(obj, parentTable, depth, path)
        if objectCount >= CONFIG.MaxObjects then return end
        if depth > CONFIG.MaxDepth then return end

        objectCount += 1

        if objectCount % CONFIG.BatchSize == 0 then
            UpdateStatus("⏳ Analisando... " .. objectCount .. " objetos")
            task.wait()
        end

        table.insert(DataStorage.AllObjects, {
            Name = obj.Name,
            Type = obj.ClassName,
            Path = path,
        })

        -- Contagens de tipos
        if obj:IsA("BasePart") then
            stats.TotalParts += 1
        end

        if obj:IsA("Model") then
            stats.TotalModels += 1
            folderCounts[obj.Name] = (folderCounts[obj.Name] or 0) + 1
        elseif obj:IsA("Folder") then
            folderCounts[obj.Name] = (folderCounts[obj.Name] or 0) + 1
        end

        if obj:IsA("Tool") then
            stats.TotalTools += 1
        elseif obj:IsA("Light") then
            stats.TotalLights += 1
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam") then
            stats.TotalParticles += 1
        elseif obj:IsA("Decal") or obj:IsA("Texture") then
            stats.TotalDecals += 1
        end

        -- Scripts (LuaSourceContainer = base de Script/LocalScript/ModuleScript)
        if obj:IsA("LuaSourceContainer") then
            stats.TotalScripts += 1

            local source = tryGetSource(obj) or ""
            local lines  = countLines(source)
            stats.TotalScriptLines += lines

            local scriptType =
                obj:IsA("LocalScript") and "LocalScript"
                or obj:IsA("ModuleScript") and "ModuleScript"
                or "Script"

            local disabled = false
            pcall(function()
                if obj.Enabled ~= nil then
                    disabled = not obj.Enabled
                end
            end)

            table.insert(DataStorage.Scripts, {
                Name      = obj.Name,
                Type      = scriptType,
                Path      = path,
                Lines     = lines,
                Disabled  = disabled,
                Source    = source,
                HasSource = source ~= "",
            })
        end

        -- Identificação heurística de objetos importantes
        local nameLower = obj.Name:lower()
        local category

        if obj:IsA("SpawnLocation") or nameLower:find("spawn", 1, true) then
            category = "Spawn"
        elseif nameLower:find("checkpoint", 1, true) then
            category = "Checkpoint"
        elseif nameLower:find("hazard", 1, true)
            or nameLower:find("kill", 1, true)
            or nameLower:find("danger", 1, true) then
            category = "Hazard"
        elseif obj:IsA("Model") and obj:FindFirstChildWhichIsA("Humanoid") then
            category = "NPC"
            stats.TotalNPCs += 1
        elseif nameLower:find("npc", 1, true) then
            category = "NPC"
            stats.TotalNPCs += 1
        elseif nameLower:find("goal", 1, true)
            or nameLower:find("finish", 1, true)
            or nameLower:find("win", 1, true) then
            category = "Goal"
        end

        if category then
            local pos = getModelPosition(obj)
            local posStr = "N/A"
            if pos then
                posStr = string.format("%.1f, %.1f, %.1f", pos.X, pos.Y, pos.Z)
            end
            table.insert(DataStorage.MapInfo.ImportantObjects, {
                Name     = obj.Name,
                Type     = obj.ClassName,
                Category = category,
                Position = posStr,
            })
        end

        if depth > stats.MaxDepth then
            stats.MaxDepth = depth
        end

        -- Hierarquia
        local node = {
            Name     = obj.Name,
            Type     = obj.ClassName,
            Children = {},
        }
        table.insert(parentTable, node)

        for _, child in ipairs(obj:GetChildren()) do
            processObject(child, node.Children, depth + 1, path .. "/" .. child.Name)
        end
    end

    local ok, err = pcall(function()
        processObject(map, DataStorage.MapInfo.Hierarchy, 0, "Workspace/" .. map.Name)
    end)

    if not ok then
        UpdateStatus("❌ Erro na análise: " .. tostring(err))
        return false
    end

    -- Maior pasta
    local maxCount = 0
    for name, count in pairs(folderCounts) do
        if count > maxCount then
            maxCount = count
            stats.LargestFolder = name .. " (" .. count .. "x)"
        end
    end

    UpdateStatus(string.format(
        "✅ %d objetos | %d scripts | %d linhas",
        objectCount, stats.TotalScripts, stats.TotalScriptLines
    ))
    return true
end

-- ═══════════════════════════════════════════════════════════
-- LÓGICA: Clonagem
-- ═══════════════════════════════════════════════════════════

function CloneMap()
    local map = workspace:FindFirstChild(CONFIG.MapName)
    if not map then
        UpdateStatus("❌ Mapa '" .. CONFIG.MapName .. "' não encontrado")
        return false
    end

    UpdateStatus("⏳ Clonando mapa...")

    if DataStorage.ClonedMap then
        pcall(function() DataStorage.ClonedMap:Destroy() end)
        DataStorage.ClonedMap = nil
    end

    local container = Instance.new("Folder")
    container.Name = "NDS_ClonedMap_" .. os.time()
    container.Parent = workspace

    local ok, err = pcall(function()
        local mapClone = map:Clone()
        mapClone.Parent = container
    end)

    if not ok then
        pcall(function() container:Destroy() end)
        UpdateStatus("❌ Erro ao clonar: " .. tostring(err))
        return false
    end

    DataStorage.ClonedMap = container
    local descCount = #container:GetDescendants()
    UpdateStatus("✅ Clonado em '" .. container.Name .. "' (" .. descCount .. " descendentes)")
    return true
end

-- ═══════════════════════════════════════════════════════════
-- LÓGICA: Backup
-- ═══════════════════════════════════════════════════════════

function CreateBackup()
    if not DataStorage.ClonedMap then
        UpdateStatus("⚠️ Clone o mapa primeiro (aba Analisar)")
        return false
    end

    local existing = workspace:FindFirstChild("MapAnalyzerBackup")
    if existing then existing:Destroy() end

    local backup = Instance.new("Folder")
    backup.Name = "MapAnalyzerBackup"
    backup.Parent = workspace

    local mapCopy = DataStorage.ClonedMap:Clone()
    mapCopy.Name = "MapClone"
    mapCopy.Parent = backup

    -- Relatório como JSON em StringValue (sem o bug de "return JSON" como Lua)
    local report = {
        MapName          = DataStorage.MapInfo.Name,
        Statistics       = DataStorage.Statistics,
        ScriptsCount     = #DataStorage.Scripts,
        ImportantObjects = DataStorage.MapInfo.ImportantObjects,
        Timestamp        = os.time(),
    }

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(report)
    end)

    if ok then
        local sv = Instance.new("StringValue")
        sv.Name = "AnalysisReport_JSON"
        sv.Value = encoded
        sv.Parent = backup
    else
        warn("[MapaAnalyzer] Falha ao serializar relatório: " .. tostring(encoded))
    end

    UpdateStatus("📦 Backup salvo em Workspace > " .. backup.Name)
    return true
end

-- ═══════════════════════════════════════════════════════════
-- LÓGICA: Exportação
-- ═══════════════════════════════════════════════════════════

function ExportData(format)
    if not DataStorage.MapInfo or not DataStorage.MapInfo.Name then
        UpdateStatus("⚠️ Execute a análise primeiro")
        return
    end

    local stats = DataStorage.Statistics
    local text

    if format == "txt" then
        local buf = {}
        local function w(s) table.insert(buf, s) end

        w("═══════════════════════════════════════════")
        w("      RELATÓRIO DE ANÁLISE DO MAPA         ")
        w("═══════════════════════════════════════════")
        w("Mapa: "    .. (DataStorage.MapInfo.Name or "N/A"))
        w("Job ID: "  .. tostring(game.JobId))
        w("Place ID: " .. tostring(game.PlaceId))
        w("Data: "    .. os.date())
        w("")
        w("── ESTATÍSTICAS ──")
        w("Parts:           " .. stats.TotalParts)
        w("Models:          " .. stats.TotalModels)
        w("Scripts:         " .. stats.TotalScripts .. " (" .. stats.TotalScriptLines .. " linhas)")
        w("Tools:           " .. stats.TotalTools)
        w("Lights:          " .. stats.TotalLights)
        w("Particles/Beams: " .. stats.TotalParticles)
        w("Decals/Textures: " .. stats.TotalDecals)
        w("NPCs:            " .. stats.TotalNPCs)
        w("Profundidade:    " .. stats.MaxDepth)
        w("Maior pasta:     " .. stats.LargestFolder)
        w("")
        w("── SCRIPTS ──")
        for i, s in ipairs(DataStorage.Scripts) do
            w("")
            w(string.format("[%d] %s — %s", i, s.Type, s.Name))
            w("Path:   " .. s.Path)
            w("Lines:  " .. s.Lines)
            w("Status: " .. (s.Disabled and "Desabilitado" or "Habilitado"))
            if s.HasSource then
                w("--- Source ---")
                w(s.Source)
                w("--- /Source ---")
            end
        end
        text = table.concat(buf, "\n")

    elseif format == "json" then
        local payload = {
            MapName          = DataStorage.MapInfo.Name,
            JobId            = game.JobId,
            PlaceId          = game.PlaceId,
            Statistics       = stats,
            Scripts          = DataStorage.Scripts,
            ImportantObjects = DataStorage.MapInfo.ImportantObjects or {},
            Hierarchy        = DataStorage.MapInfo.Hierarchy or {},
        }
        local ok, encoded = pcall(HttpService.JSONEncode, HttpService, payload)
        if not ok then
            UpdateStatus("❌ Erro ao gerar JSON: " .. tostring(encoded))
            return
        end
        text = encoded

    elseif format == "summary" then
        text = string.format([[
MAPA: %s
═══════════════════════════════════════
📦 Parts:         %d
📁 Models:        %d
📜 Scripts:       %d (%d linhas)
🔧 Tools:         %d
💡 Lights:        %d
🎨 Particles:     %d
🖼️ Decals:        %d
🤖 NPCs:          %d
🌳 Profundidade:  %d
📂 Maior pasta:   %s]],
            DataStorage.MapInfo.Name or "N/A",
            stats.TotalParts, stats.TotalModels,
            stats.TotalScripts, stats.TotalScriptLines,
            stats.TotalTools, stats.TotalLights,
            stats.TotalParticles, stats.TotalDecals, stats.TotalNPCs,
            stats.MaxDepth, stats.LargestFolder)
    else
        UpdateStatus("❌ Formato desconhecido: " .. tostring(format))
        return
    end

    if clipboardCopy(text) then
        UpdateStatus("📋 Copiado para clipboard (" .. #text .. " chars)")
    else
        local existing = workspace:FindFirstChild("MapAnalyzerExport")
        if existing then existing:Destroy() end
        local sv = Instance.new("StringValue")
        sv.Name = "MapAnalyzerExport"
        sv.Value = text
        sv.Parent = workspace
        UpdateStatus("⚠️ Clipboard indisponível — salvo em Workspace > MapAnalyzerExport")
    end
end

-- ═══════════════════════════════════════════════════════════
-- UI HELPERS DE CONTEÚDO
-- ═══════════════════════════════════════════════════════════

local function makeLabel(parent, text, color, opts)
    opts = opts or {}
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, opts.height or 22)
    lbl.BackgroundTransparency = 1
    lbl.Text = text
    lbl.TextColor3 = color or Theme.Text
    lbl.TextSize = opts.size or 13
    lbl.Font = opts.font or Enum.Font.Gotham
    lbl.TextXAlignment = opts.align or Enum.TextXAlignment.Left
    lbl.TextWrapped = opts.wrap == true
    lbl.AutomaticSize = Enum.AutomaticSize.Y
    lbl.Parent = parent
    return lbl
end

local function makeFrame(parent, height, color)
    local f = Instance.new("Frame")
    if height then
        f.Size = UDim2.new(1, 0, 0, height)
    else
        f.Size = UDim2.new(1, 0, 0, 0)
        f.AutomaticSize = Enum.AutomaticSize.Y
    end
    f.BackgroundColor3 = color or Theme.Background
    f.BorderSizePixel = 0
    f.Parent = parent
    makeCorner(f, 6)
    return f
end

local function makeSection(parent, title, color)
    local section = Instance.new("Frame")
    section.Size = UDim2.new(1, 0, 0, 30)
    section.BackgroundColor3 = color or Theme.Accent
    section.BorderSizePixel = 0
    section.Parent = parent
    makeCorner(section, 6)

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -20, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = title
    lbl.TextColor3 = Theme.Text
    lbl.TextSize = 14
    lbl.Font = Enum.Font.GothamBold
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = section
    return section
end

local function makeButton(parent, text, color, callback, opts)
    opts = opts or {}
    color = color or Theme.Accent

    local btn = Instance.new("TextButton")
    btn.Size = opts.size or UDim2.new(1, 0, 0, 38)
    btn.BackgroundColor3 = color
    btn.Text = text
    btn.TextColor3 = Theme.Text
    btn.TextSize = opts.textSize or 13
    btn.Font = opts.font or Enum.Font.GothamSemibold
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = parent
    makeCorner(btn, 6)
    bindHover(btn, color)

    if callback then
        track(btn.MouseButton1Click:Connect(callback))
    end
    return btn
end

local function makeTextBox(parent, placeholder, default, onChanged)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 32)
    box.BackgroundColor3 = Theme.Tertiary
    box.PlaceholderText = placeholder or ""
    box.Text = default or ""
    box.TextColor3 = Theme.Text
    box.PlaceholderColor3 = Theme.TextDim
    box.TextSize = 13
    box.Font = Enum.Font.Gotham
    box.ClearTextOnFocus = false
    box.BorderSizePixel = 0
    box.Parent = parent
    makeCorner(box, 6)

    local pad = Instance.new("UIPadding")
    pad.PaddingLeft  = UDim.new(0, 8)
    pad.PaddingRight = UDim.new(0, 8)
    pad.Parent = box

    if onChanged then
        track(box.FocusLost:Connect(function()
            onChanged(box.Text)
        end))
    end
    return box
end

-- ═══════════════════════════════════════════════════════════
-- UI: Visualizador de Código (modal)
-- ═══════════════════════════════════════════════════════════

function ShowScriptCode(scriptData)
    local existing = PlayerGui:FindFirstChild("MapaAnalyzerCode")
    if existing then existing:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "MapaAnalyzerCode"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 100
    gui.Parent = PlayerGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0.85, 0, 0.85, 0)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.BackgroundColor3 = Theme.Background
    frame.BorderSizePixel = 0
    frame.Parent = gui
    makeCorner(frame, 10)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 46)
    header.BackgroundColor3 = Theme.Tertiary
    header.BorderSizePixel = 0
    header.Parent = frame
    makeCorner(header, 10)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -150, 1, 0)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "📜 " .. scriptData.Name .. " [" .. scriptData.Type .. "] — " .. scriptData.Lines .. " linhas"
    title.TextColor3 = Theme.Text
    title.TextSize = 14
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.Parent = header

    local copyBtn = Instance.new("TextButton")
    copyBtn.Size = UDim2.new(0, 80, 0, 32)
    copyBtn.Position = UDim2.new(1, -120, 0.5, -16)
    copyBtn.BackgroundColor3 = Theme.Accent
    copyBtn.Text = "Copiar"
    copyBtn.TextColor3 = Theme.Text
    copyBtn.TextSize = 12
    copyBtn.Font = Enum.Font.GothamSemibold
    copyBtn.AutoButtonColor = false
    copyBtn.Parent = header
    makeCorner(copyBtn, 6)
    bindHover(copyBtn, Theme.Accent)
    track(copyBtn.MouseButton1Click:Connect(function()
        if clipboardCopy(scriptData.Source or "") then
            UpdateStatus("📋 Source copiado para clipboard")
        else
            UpdateStatus("⚠️ Clipboard indisponível")
        end
    end))

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 32, 0, 32)
    closeBtn.Position = UDim2.new(1, -38, 0.5, -16)
    closeBtn.BackgroundColor3 = Theme.Danger
    closeBtn.Text = "✕"
    closeBtn.TextColor3 = Theme.Text
    closeBtn.TextSize = 14
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.AutoButtonColor = false
    closeBtn.Parent = header
    makeCorner(closeBtn, 6)
    bindHover(closeBtn, Theme.Danger)
    track(closeBtn.MouseButton1Click:Connect(function()
        gui:Destroy()
    end))

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -56)
    scroll.Position = UDim2.new(0, 8, 0, 50)
    scroll.BackgroundColor3 = Theme.CodeBg
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 8
    scroll.ScrollBarImageColor3 = Theme.Accent
    scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = frame
    makeCorner(scroll, 8)

    local code = Instance.new("TextLabel")
    code.Size = UDim2.new(1, -16, 0, 0)
    code.Position = UDim2.new(0, 8, 0, 8)
    code.BackgroundTransparency = 1
    local src = scriptData.Source
    code.Text = (src and src ~= "") and src or "-- (Source vazio ou inacessível)"
    code.TextColor3 = Color3.fromRGB(220, 220, 230)
    code.TextSize = 12
    code.Font = Enum.Font.Code
    code.TextXAlignment = Enum.TextXAlignment.Left
    code.TextYAlignment = Enum.TextYAlignment.Top
    code.AutomaticSize = Enum.AutomaticSize.Y
    code.TextWrapped = false
    code.Parent = scroll
end

-- ═══════════════════════════════════════════════════════════
-- UI: ScreenGui principal
-- ═══════════════════════════════════════════════════════════

local function CreateUI()
    local existing = PlayerGui:FindFirstChild("MapaAnalyzerUI")
    if existing then existing:Destroy() end
    disconnectAll()

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "MapaAnalyzerUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    ScreenGui.IgnoreGuiInset = false
    ScreenGui.DisplayOrder = 50
    ScreenGui.Parent = PlayerGui
    UI.ScreenGui = ScreenGui

    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 620, 0, 520)
    MainFrame.Position = UDim2.new(0.5, -310, 0.5, -260)
    MainFrame.BackgroundColor3 = Theme.Background
    MainFrame.BorderSizePixel = 0
    MainFrame.Active = true
    MainFrame.Parent = ScreenGui
    UI.MainFrame = MainFrame

    local sizeConstraint = Instance.new("UISizeConstraint")
    sizeConstraint.MinSize = Vector2.new(380, 400)
    sizeConstraint.MaxSize = Vector2.new(900, 720)
    sizeConstraint.Parent = MainFrame

    makeCorner(MainFrame, 10)

    local Shadow = Instance.new("ImageLabel")
    Shadow.Size = UDim2.new(1, 30, 1, 30)
    Shadow.Position = UDim2.new(0, -15, 0, -15)
    Shadow.BackgroundTransparency = 1
    Shadow.Image = "rbxassetid://5554236805"
    Shadow.ImageColor3 = Color3.fromRGB(0, 0, 0)
    Shadow.ImageTransparency = 0.5
    Shadow.ScaleType = Enum.ScaleType.Slice
    Shadow.SliceCenter = Rect.new(23, 23, 277, 277)
    Shadow.ZIndex = -1
    Shadow.Parent = MainFrame

    -- Header (ÚNICA região de drag — não conflita com botões)
    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, 0, 0, 50)
    Header.BackgroundColor3 = Theme.Tertiary
    Header.BorderSizePixel = 0
    Header.Active = true
    Header.Parent = MainFrame
    makeCorner(Header, 10)

    local headerFix = Instance.new("Frame")
    headerFix.Size = UDim2.new(1, 0, 0, 12)
    headerFix.Position = UDim2.new(0, 0, 1, -12)
    headerFix.BackgroundColor3 = Theme.Tertiary
    headerFix.BorderSizePixel = 0
    headerFix.Parent = Header

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -60, 1, 0)
    Title.Position = UDim2.new(0, 15, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "🗺️ MAPA ANALYZER — NDS v2"
    Title.TextColor3 = Theme.Text
    Title.TextSize = 18
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = Header

    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Size = UDim2.new(0, 36, 0, 36)
    CloseBtn.Position = UDim2.new(1, -42, 0.5, -18)
    CloseBtn.BackgroundColor3 = Theme.Danger
    CloseBtn.Text = "✕"
    CloseBtn.TextColor3 = Theme.Text
    CloseBtn.TextSize = 16
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.AutoButtonColor = false
    CloseBtn.Parent = Header
    makeCorner(CloseBtn, 8)
    bindHover(CloseBtn, Theme.Danger)
    track(CloseBtn.MouseButton1Click:Connect(function()
        disconnectAll()
        ScreenGui:Destroy()
    end))

    -- Tabs
    local TabsContainer = Instance.new("Frame")
    TabsContainer.Size = UDim2.new(1, -20, 0, 36)
    TabsContainer.Position = UDim2.new(0, 10, 0, 60)
    TabsContainer.BackgroundTransparency = 1
    TabsContainer.Parent = MainFrame
    makeListLayout(TabsContainer, 5, true)

    local Tabs = {
        { label = "📊 Analisar",  id = 1 },
        { label = "📜 Scripts",   id = 2 },
        { label = "🗂️ Estrutura", id = 3 },
        { label = "📋 Exportar",  id = 4 },
        { label = "⚙️ Config",    id = 5 },
    }
    local TabButtons = {}

    for i, tab in ipairs(Tabs) do
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0, 110, 0, 32)
        btn.BackgroundColor3 = i == 1 and Theme.Accent or Theme.Secondary
        btn.Text = tab.label
        btn.TextColor3 = Theme.Text
        btn.TextSize = 12
        btn.Font = Enum.Font.GothamSemibold
        btn.BorderSizePixel = 0
        btn.AutoButtonColor = false
        btn.Parent = TabsContainer
        makeCorner(btn, 6)

        track(btn.MouseEnter:Connect(function()
            if UIState.activeTab ~= tab.id then
                btn.BackgroundColor3 = lighten(Theme.Secondary, 0.06)
            end
        end))
        track(btn.MouseLeave:Connect(function()
            if UIState.activeTab ~= tab.id then
                btn.BackgroundColor3 = Theme.Secondary
            end
        end))

        track(btn.MouseButton1Click:Connect(function()
            for j, b in ipairs(TabButtons) do
                b.BackgroundColor3 = (Tabs[j].id == tab.id) and Theme.Accent or Theme.Secondary
            end
            UIState.activeTab = tab.id
            UpdateContent(tab.id)
        end))

        table.insert(TabButtons, btn)
    end
    UI.TabButtons = TabButtons
    UI.Tabs = Tabs

    -- Content
    local ContentFrame = Instance.new("ScrollingFrame")
    ContentFrame.Size = UDim2.new(1, -20, 1, -130)
    ContentFrame.Position = UDim2.new(0, 10, 0, 102)
    ContentFrame.BackgroundColor3 = Theme.Secondary
    ContentFrame.BorderSizePixel = 0
    ContentFrame.ScrollBarThickness = 6
    ContentFrame.ScrollBarImageColor3 = Theme.Accent
    ContentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ContentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    ContentFrame.Parent = MainFrame
    UI.ContentFrame = ContentFrame
    makeCorner(ContentFrame, 8)
    makeListLayout(ContentFrame, 6)
    makePadding(ContentFrame, 10)

    -- Status bar
    local StatusBar = Instance.new("Frame")
    StatusBar.Size = UDim2.new(1, 0, 0, 22)
    StatusBar.Position = UDim2.new(0, 0, 1, -22)
    StatusBar.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
    StatusBar.BorderSizePixel = 0
    StatusBar.Parent = MainFrame

    local StatusText = Instance.new("TextLabel")
    StatusText.Size = UDim2.new(1, -20, 1, 0)
    StatusText.Position = UDim2.new(0, 10, 0, 0)
    StatusText.BackgroundTransparency = 1
    StatusText.Text = "🔔 Pronto"
    StatusText.TextColor3 = Theme.TextDim
    StatusText.TextSize = 12
    StatusText.Font = Enum.Font.Gotham
    StatusText.TextXAlignment = Enum.TextXAlignment.Left
    StatusText.Parent = StatusBar
    UI.StatusText = StatusText

    -- ─── Drag (apenas no Header) ───
    local dragging = false
    local dragStart, startPos
    local activeChangeConn

    track(Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos  = MainFrame.Position

            if activeChangeConn then activeChangeConn:Disconnect() end
            activeChangeConn = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if activeChangeConn then
                        activeChangeConn:Disconnect()
                        activeChangeConn = nil
                    end
                end
            end)
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if dragging
            and (input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))

    return ScreenGui
end

-- ═══════════════════════════════════════════════════════════
-- UI: Status / ClearContent
-- ═══════════════════════════════════════════════════════════

function UpdateStatus(text)
    if UI.StatusText then
        UI.StatusText.Text = text
    end
    print("[MapaAnalyzer] " .. text)
end

function ClearContent()
    if not UI.ContentFrame then return end
    for _, child in ipairs(UI.ContentFrame:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end
end

-- ═══════════════════════════════════════════════════════════
-- UI: Renderers das abas
-- ═══════════════════════════════════════════════════════════

local TabRenderers = {}

-- TAB 1: ANALISAR ─────────────────────────────────────
TabRenderers[1] = function(parent)
    makeSection(parent, "📊 ANÁLISE DO MAPA", Theme.Success)

    local infoFrame = makeFrame(parent, nil, Theme.Background)
    makeListLayout(infoFrame, 6)
    makePadding(infoFrame, 12)

    local map = workspace:FindFirstChild(CONFIG.MapName)
    makeLabel(infoFrame,
        "🌍 Procurando '" .. CONFIG.MapName .. "': "
        .. (map and "✅ encontrado" or "❌ não encontrado"))
    makeLabel(infoFrame, "🔑 JobId: " .. tostring(game.JobId))
    makeLabel(infoFrame, "👥 Jogadores: " .. #Players:GetPlayers())

    if DataStorage.MapInfo and DataStorage.MapInfo.Name then
        local s = DataStorage.Statistics
        makeLabel(infoFrame, "📦 Parts: " .. s.TotalParts)
        makeLabel(infoFrame, "📁 Models: " .. s.TotalModels)
        makeLabel(infoFrame, "📜 Scripts: " .. s.TotalScripts .. " (" .. s.TotalScriptLines .. " linhas)")
        makeLabel(infoFrame, "🔧 Tools: " .. s.TotalTools)
        makeLabel(infoFrame, "💡 Lights: " .. s.TotalLights)
        makeLabel(infoFrame, "🎨 Particles: " .. s.TotalParticles)
        makeLabel(infoFrame, "🖼️ Decals: " .. s.TotalDecals)
        makeLabel(infoFrame, "🤖 NPCs: " .. s.TotalNPCs)
    else
        makeLabel(infoFrame, "⚠️ Clique em 'Iniciar Análise' para começar", Theme.Warning)
    end

    makeButton(parent, "🚀 INICIAR ANÁLISE", Theme.Success, function()
        task.spawn(function()
            if AnalyzeMap() then UpdateContent(1) end
        end)
    end)

    makeButton(parent, "📦 CLONAR MAPA", Theme.Warning, function()
        task.spawn(function()
            if CloneMap() then UpdateContent(1) end
        end)
    end)

    makeButton(parent, "🗑️ LIMPAR CLONAGEM", Theme.Danger, function()
        if DataStorage.ClonedMap then
            pcall(function() DataStorage.ClonedMap:Destroy() end)
            DataStorage.ClonedMap = nil
            UpdateStatus("🗑️ Clone removido")
        else
            UpdateStatus("⚠️ Nada para limpar")
        end
    end)
end

-- TAB 2: SCRIPTS ──────────────────────────────────────
TabRenderers[2] = function(parent)
    makeSection(parent, "📜 SCRIPTS ENCONTRADOS", Theme.Accent)

    if #DataStorage.Scripts == 0 then
        makeLabel(parent, "⚠️ Nenhum script. Execute a análise primeiro.", Theme.Warning)
        makeButton(parent, "🔍 Analisar agora", Theme.Accent, function()
            task.spawn(function()
                if AnalyzeMap() then UpdateContent(2) end
            end)
        end)
        return
    end

    local statsBox = makeFrame(parent, nil, Theme.Background)
    makeListLayout(statsBox, 4)
    makePadding(statsBox, 10)
    makeLabel(statsBox, "📊 Total: " .. #DataStorage.Scripts
        .. " scripts | " .. DataStorage.Statistics.TotalScriptLines .. " linhas")

    -- Search
    makeTextBox(parent, "🔍 Filtrar por nome, tipo ou path...", UIState.scriptSearch, function(t)
        UIState.scriptSearch = t or ""
        UpdateContent(2)
    end)

    local listBox = Instance.new("Frame")
    listBox.Size = UDim2.new(1, 0, 0, 0)
    listBox.BackgroundTransparency = 1
    listBox.AutomaticSize = Enum.AutomaticSize.Y
    listBox.Parent = parent
    makeListLayout(listBox, 5)

    local term = (UIState.scriptSearch or ""):lower()
    local shown = 0

    for _, s in ipairs(DataStorage.Scripts) do
        if shown >= CONFIG.MaxScriptList then break end

        local matches = term == ""
            or s.Name:lower():find(term, 1, true)
            or s.Type:lower():find(term, 1, true)
            or s.Path:lower():find(term, 1, true)

        if matches then
            shown += 1
            local item = makeFrame(listBox, nil, Theme.Background)
            makeListLayout(item, 3)
            makePadding(item, 10)

            local titleRow = Instance.new("Frame")
            titleRow.Size = UDim2.new(1, 0, 0, 22)
            titleRow.BackgroundTransparency = 1
            titleRow.Parent = item

            local title = Instance.new("TextLabel")
            title.Size = UDim2.new(1, -90, 1, 0)
            title.BackgroundTransparency = 1
            title.Text = "🔹 " .. s.Name .. " [" .. s.Type .. "]"
            title.TextColor3 = Theme.Success
            title.TextSize = 13
            title.Font = Enum.Font.GothamBold
            title.TextXAlignment = Enum.TextXAlignment.Left
            title.TextTruncate = Enum.TextTruncate.AtEnd
            title.Parent = titleRow

            if s.HasSource then
                local viewBtn = Instance.new("TextButton")
                viewBtn.Size = UDim2.new(0, 80, 1, 0)
                viewBtn.Position = UDim2.new(1, -85, 0, 0)
                viewBtn.BackgroundColor3 = Theme.Accent
                viewBtn.Text = "Ver Código"
                viewBtn.TextColor3 = Theme.Text
                viewBtn.TextSize = 11
                viewBtn.Font = Enum.Font.GothamSemibold
                viewBtn.AutoButtonColor = false
                viewBtn.Parent = titleRow
                makeCorner(viewBtn, 4)
                bindHover(viewBtn, Theme.Accent)
                track(viewBtn.MouseButton1Click:Connect(function()
                    ShowScriptCode(s)
                end))
            end

            -- BUG CORRIGIDO: ternário entre parênteses
            local statusTxt = (s.Disabled and "❌ Desabilitado" or "✅ Habilitado")
            makeLabel(item, "📍 " .. s.Path, Theme.TextDim, { size = 11 })
            makeLabel(item, "📝 " .. s.Lines .. " linhas | Status: " .. statusTxt, Theme.TextDim, { size = 11 })
        end
    end

    if shown == 0 then
        makeLabel(listBox, "Nenhum resultado para '" .. term .. "'", Theme.Warning)
    elseif shown >= CONFIG.MaxScriptList and #DataStorage.Scripts > CONFIG.MaxScriptList then
        makeLabel(listBox,
            "⚠️ Mostrando " .. CONFIG.MaxScriptList
            .. " de " .. #DataStorage.Scripts .. ". Use Exportar para ver todos.",
            Theme.Warning)
    end
end

-- TAB 3: ESTRUTURA ────────────────────────────────────
TabRenderers[3] = function(parent)
    makeSection(parent, "🗂️ ESTRUTURA DO MAPA", Theme.Warning)

    if not DataStorage.MapInfo
        or not DataStorage.MapInfo.Hierarchy
        or #DataStorage.MapInfo.Hierarchy == 0 then
        makeLabel(parent, "⚠️ Execute a análise primeiro.", Theme.Warning)
        return
    end

    local statsBox = makeFrame(parent, nil, Theme.Background)
    makeListLayout(statsBox, 4)
    makePadding(statsBox, 10)

    local s = DataStorage.Statistics
    makeLabel(statsBox, "🌳 Profundidade máx: " .. s.MaxDepth)
    makeLabel(statsBox, "📂 Maior pasta: " .. s.LargestFolder)
    makeLabel(statsBox, "📦 Total de objetos: " .. #DataStorage.AllObjects)

    makeSection(parent, "📁 HIERARQUIA (limite: " .. CONFIG.MaxTreeNodes .. " nós)", Theme.Secondary)

    local treeFrame = makeFrame(parent, nil, Theme.Background)
    makeListLayout(treeFrame, 1)
    makePadding(treeFrame, 8)

    local iconFor = {
        Model         = "📁", Script   = "📜", LocalScript  = "📝",
        ModuleScript  = "📘", Tool     = "🔧", Folder       = "📂",
        SpawnLocation = "🏁", Part     = "📦", MeshPart     = "🧱",
        Light         = "💡", Sound    = "🔊",
    }

    local rendered = 0
    local truncated = false

    local function renderNode(node, depth)
        if rendered >= CONFIG.MaxTreeNodes then
            truncated = true
            return
        end
        rendered += 1

        local indent = string.rep("  ", depth)
        local icon = iconFor[node.Type] or "📦"

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(1, 0, 0, 16)
        lbl.BackgroundTransparency = 1
        lbl.Text = indent .. icon .. " " .. node.Name .. " [" .. node.Type .. "]"
        lbl.TextColor3 = depth == 0 and Theme.Success or Theme.TextDim
        lbl.TextSize = 11
        lbl.Font = Enum.Font.Code
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextTruncate = Enum.TextTruncate.AtEnd
        lbl.Parent = treeFrame

        for _, child in ipairs(node.Children or {}) do
            if rendered >= CONFIG.MaxTreeNodes then break end
            renderNode(child, depth + 1)
        end
    end

    for _, node in ipairs(DataStorage.MapInfo.Hierarchy) do
        if rendered >= CONFIG.MaxTreeNodes then break end
        renderNode(node, 0)
    end

    if truncated then
        makeLabel(treeFrame,
            "⚠️ Exibição truncada em " .. CONFIG.MaxTreeNodes
            .. " nós (total real: " .. #DataStorage.AllObjects .. "). "
            .. "Use Exportar > JSON para a árvore completa.",
            Theme.Warning, { wrap = true })
    end
end

-- TAB 4: EXPORTAR ─────────────────────────────────────
TabRenderers[4] = function(parent)
    makeSection(parent, "📋 EXPORTAÇÃO", Theme.Success)

    if not DataStorage.MapInfo or not DataStorage.MapInfo.Name then
        makeLabel(parent, "⚠️ Execute a análise primeiro.", Theme.Warning)
        return
    end

    local box = makeFrame(parent, nil, Theme.Background)
    makeListLayout(box, 6)
    makePadding(box, 10)
    makeLabel(box, "Selecione o formato:")

    local formats = {
        { name = "📄 Texto Completo (com source)", fmt = "txt" },
        { name = "📋 JSON",                        fmt = "json" },
        { name = "📊 Resumo",                      fmt = "summary" },
    }
    for _, f in ipairs(formats) do
        makeButton(box, f.name, Theme.Accent, function()
            ExportData(f.fmt)
        end)
    end

    makeButton(parent, "💾 SALVAR BACKUP NO WORKSPACE", Theme.Success, function()
        if not DataStorage.ClonedMap then
            UpdateStatus("⚠️ Clone primeiro (aba Analisar)")
            return
        end
        CreateBackup()
    end)

    local important = DataStorage.MapInfo.ImportantObjects or {}
    if #important > 0 then
        makeSection(parent, "🎯 OBJETOS IMPORTANTES (" .. #important .. ")", Theme.Warning)
        local iconFor = { Spawn = "🏁", Checkpoint = "🚩", Hazard = "⚠️", NPC = "🤖", Goal = "🎯" }

        for _, obj in ipairs(important) do
            local f = makeFrame(parent, nil, Theme.Background)
            makeListLayout(f, 2)
            makePadding(f, 8)
            local icon = iconFor[obj.Category] or "📍"
            makeLabel(f, icon .. " " .. obj.Name .. " [" .. obj.Type .. "] — " .. obj.Category)
            makeLabel(f, "📍 " .. obj.Position, Theme.TextDim, { size = 11 })
        end
    end
end

-- TAB 5: CONFIG ───────────────────────────────────────
TabRenderers[5] = function(parent)
    makeSection(parent, "⚙️ CONFIGURAÇÕES", Theme.Secondary)

    local box = makeFrame(parent, nil, Theme.Background)
    makeListLayout(box, 8)
    makePadding(box, 12)

    makeLabel(box, "🌍 Nome do Mapa em Workspace:")
    makeTextBox(box, "Ex: Map", CONFIG.MapName, function(t)
        if t and t ~= "" then
            CONFIG.MapName = t
            UpdateStatus("✅ MapName = '" .. t .. "'")
        end
    end)

    makeLabel(box, "🔢 Profundidade máxima:")
    makeTextBox(box, "50", tostring(CONFIG.MaxDepth), function(t)
        local n = tonumber(t)
        if n and n > 0 then
            CONFIG.MaxDepth = math.floor(n)
            UpdateStatus("✅ MaxDepth = " .. CONFIG.MaxDepth)
        end
    end)

    makeLabel(box, "📦 Limite de objetos:")
    makeTextBox(box, "100000", tostring(CONFIG.MaxObjects), function(t)
        local n = tonumber(t)
        if n and n > 0 then
            CONFIG.MaxObjects = math.floor(n)
            UpdateStatus("✅ MaxObjects = " .. CONFIG.MaxObjects)
        end
    end)

    makeLabel(box, "⚡ Batch size (yield a cada N objetos):")
    makeTextBox(box, "200", tostring(CONFIG.BatchSize), function(t)
        local n = tonumber(t)
        if n and n > 0 then
            CONFIG.BatchSize = math.floor(n)
            UpdateStatus("✅ BatchSize = " .. CONFIG.BatchSize)
        end
    end)

    makeLabel(box, "🌳 Máx. de nós na árvore:")
    makeTextBox(box, "2000", tostring(CONFIG.MaxTreeNodes), function(t)
        local n = tonumber(t)
        if n and n > 0 then
            CONFIG.MaxTreeNodes = math.floor(n)
            UpdateStatus("✅ MaxTreeNodes = " .. CONFIG.MaxTreeNodes)
        end
    end)

    makeSection(parent, "🎛️ AÇÕES", Theme.Accent)

    makeButton(parent, "🔄 Resetar Estatísticas", Theme.Warning, function()
        resetState()
        UpdateStatus("🔄 Estado resetado")
        UpdateContent(5)
    end)

    makeButton(parent, "🗑️ Fechar e Limpar Tudo", Theme.Danger, function()
        if DataStorage.ClonedMap then
            pcall(function() DataStorage.ClonedMap:Destroy() end)
        end
        resetState()
        disconnectAll()
        if UI.ScreenGui then UI.ScreenGui:Destroy() end
    end)
end

function UpdateContent(tabIndex)
    if not UI.ContentFrame then return end
    UIState.activeTab = tabIndex
    ClearContent()

    local renderer = TabRenderers[tabIndex]
    if not renderer then
        makeLabel(UI.ContentFrame, "❌ Aba desconhecida: " .. tostring(tabIndex), Theme.Danger)
        return
    end

    local ok, err = pcall(renderer, UI.ContentFrame)
    if not ok then
        warn("[MapaAnalyzer] Erro ao renderizar tab " .. tabIndex .. ": " .. tostring(err))
        makeLabel(UI.ContentFrame,
            "❌ Erro ao renderizar: " .. tostring(err),
            Theme.Danger, { wrap = true })
    end
end

-- ═══════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════

local function Initialize()
    CreateUI()
    UpdateContent(1)
    UpdateStatus("🔔 Pronto — aba 'Analisar' para começar")

    print("═══════════════════════════════════════")
    print("  MAPA ANALYZER — NDS EDITION (v2)")
    print("═══════════════════════════════════════")
    print("✅ UI criada")
    print("📋 Abas: Analisar | Scripts | Estrutura | Exportar | Config")
    print("🛠️  Mapa procurado em workspace: " .. CONFIG.MapName .. " (editável na aba Config)")
    print("═══════════════════════════════════════")
end

Initialize()
