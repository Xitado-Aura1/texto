--[[
╔══════════════════════════════════════════════════════════════╗
║          MAPA ANALYZER & CLONER - NDS EDITION               ║
║         Ferramenta de Estudo para Roblox Studio             ║
╚══════════════════════════════════════════════════════════════╝
--]]

-- ═══════════════════════════════════════════════════════════
-- CONFIGURAÇÕES
-- ═══════════════════════════════════════════════════════════

local CONFIG = {
    MaxDepth = 50,
    MaxObjects = 100000,
    ProcessDelay = 0.001,
    BatchSize = 100,
    SaveToWorkspace = true,
    AutoCleanDuplicates = true,
}

-- ═══════════════════════════════════════════════════════════
-- SERVIÇOS
-- ═══════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

-- ═══════════════════════════════════════════════════════════
-- CORES DO TEMA
-- ═══════════════════════════════════════════════════════════

local Theme = {
    Background = Color3.fromRGB(25, 25, 35),
    Secondary = Color3.fromRGB(35, 35, 50),
    Accent = Color3.fromRGB(80, 120, 255),
    Success = Color3.fromRGB(50, 200, 100),
    Warning = Color3.fromRGB(255, 180, 50),
    Danger = Color3.fromRGB(255, 70, 70),
    Text = Color3.fromRGB(255, 255, 255),
    TextDim = Color3.fromRGB(180, 180, 180),
}

-- ═══════════════════════════════════════════════════════════
-- STORAGE DE DADOS
-- ═══════════════════════════════════════════════════════════

local DataStorage = {
    ClonedMap = nil,
    MapInfo = {},
    Scripts = {},
    AllObjects = {},
    Statistics = {
        TotalParts = 0,
        TotalModels = 0,
        TotalScripts = 0,
        TotalTools = 0,
        TotalLights = 0,
        TotalParticles = 0,
        TotalDecals = 0,
        TotalNPCs = 0,
        MaxDepth = 0,
        LargestFolder = "",
        ScriptLines = 0,
    },
    ExportData = {},
}

-- ═══════════════════════════════════════════════════════════
-- INTERFACE GRÁFICA
-- ═══════════════════════════════════════════════════════════

local function CreateUI()
    -- Remove UI existente se houver
    local existingGui = LocalPlayer.PlayerGui:FindFirstChild("MapaAnalyzerUI") or game:GetService("CoreGui"):FindFirstChild("MapaAnalyzerUI")
    if existingGui then existingGui:Destroy() end

    -- GUI Principal
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "MapaAnalyzerUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local function SafeParent(parent)
        pcall(function()
            if parent == "PlayerGui" then
                ScreenGui.Parent = LocalPlayer.PlayerGui
            elseif parent == "CoreGui" then
                ScreenGui.Parent = game:GetService("CoreGui")
            else
                ScreenGui.Parent = parent
            end
        end)
        if not ScreenGui.Parent then
            ScreenGui.Parent = LocalPlayer.PlayerGui
        end
    end
    SafeParent("PlayerGui")

    -- Frame Principal
    local MainFrame = Instance.new("Frame")
    MainFrame.Name = "MainFrame"
    MainFrame.Size = UDim2.new(0, 600, 0, 500)
    MainFrame.Position = UDim2.new(0.5, -300, 0.5, -250)
    MainFrame.BackgroundColor3 = Theme.Background
    MainFrame.BorderSizePixel = 0
    MainFrame.Parent = ScreenGui

    -- Cantos arredondados
    local UICorner = Instance.new("UICorner")
    UICorner.CornerRadius = UDim.new(0, 10)
    UICorner.Parent = MainFrame

    -- Sombra
    local Shadow = Instance.new("ImageLabel")
    Shadow.Name = "Shadow"
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

    -- Header
    local Header = Instance.new("Frame")
    Header.Name = "Header"
    Header.Size = UDim2.new(1, 0, 0, 50)
    Header.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    Header.BorderSizePixel = 0
    Header.Parent = MainFrame

    local HeaderCorner = Instance.new("UICorner")
    HeaderCorner.CornerRadius = UDim.new(0, 10)
    HeaderCorner.Parent = Header

    -- Fix canto inferior do header
    local HeaderFix = Instance.new("Frame")
    HeaderFix.Size = UDim2.new(1, 0, 0, 10)
    HeaderFix.Position = UDim2.new(0, 0, 1, -10)
    HeaderFix.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
    HeaderFix.BorderSizePixel = 0
    HeaderFix.Parent = Header

    -- Título
    local Title = Instance.new("TextLabel")
    Title.Name = "Title"
    Title.Size = UDim2.new(1, -60, 1, 0)
    Title.Position = UDim2.new(0, 15, 0, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "🗺️ MAPA ANALYZER - NDS EDITION"
    Title.TextColor3 = Theme.Text
    Title.TextSize = 20
    Title.Font = Enum.Font.GothamBold
    Title.TextXAlignment = Enum.TextXAlignment.Left
    Title.Parent = Header

    -- Botão Fechar
    local CloseBtn = Instance.new("TextButton")
    CloseBtn.Name = "CloseBtn"
    CloseBtn.Size = UDim2.new(0, 40, 0, 40)
    CloseBtn.Position = UDim2.new(1, -45, 0.5, -20)
    CloseBtn.BackgroundColor3 = Theme.Danger
    CloseBtn.Text = "✕"
    CloseBtn.TextColor3 = Theme.Text
    CloseBtn.TextSize = 18
    CloseBtn.Font = Enum.Font.GothamBold
    CloseBtn.Parent = Header

    local CloseBtnCorner = Instance.new("UICorner")
    CloseBtnCorner.CornerRadius = UDim.new(0, 8)
    CloseBtnCorner.Parent = CloseBtn

    -- Tabs Container
    local TabsContainer = Instance.new("Frame")
    TabsContainer.Name = "TabsContainer"
    TabsContainer.Size = UDim2.new(1, -20, 0, 40)
    TabsContainer.Position = UDim2.new(0, 10, 0, 60)
    TabsContainer.BackgroundTransparency = 1
    TabsContainer.Parent = MainFrame

    local TabsLayout = Instance.new("UIListLayout")
    TabsLayout.FillDirection = Enum.FillDirection.Horizontal
    TabsLayout.Padding = UDim.new(0, 5)
    TabsLayout.Parent = TabsContainer

    local Tabs = {"📊 Analisar", "📜 Scripts", "🗂️ Estrutura", "📋 Exportar", "⚙️ Config"}
    local TabButtons = {}

    for i, tabName in ipairs(Tabs) do
        local TabBtn = Instance.new("TextButton")
        TabBtn.Name = "Tab_" .. i
        TabBtn.Size = UDim2.new(0, 110, 0, 35)
        TabBtn.BackgroundColor3 = i == 1 and Theme.Accent or Theme.Secondary
        TabBtn.Text = tabName
        TabBtn.TextColor3 = Theme.Text
        TabBtn.TextSize = 13
        TabBtn.Font = Enum.Font.GothamSemibold
        TabBtn.BorderSizePixel = 0
        TabBtn.Parent = TabsContainer

        local TabCorner = Instance.new("UICorner")
        TabCorner.CornerRadius = UDim.new(0, 6)
        TabCorner.Parent = TabBtn

        TabBtn.MouseButton1Click:Connect(function()
            for _, btn in ipairs(TabButtons) do
                btn.BackgroundColor3 = Theme.Secondary
            end
            TabBtn.BackgroundColor3 = Theme.Accent
            UpdateContent(i)
        end)

        table.insert(TabButtons, TabBtn)
    end

    -- Content Frame
    local ContentFrame = Instance.new("ScrollingFrame")
    ContentFrame.Name = "ContentFrame"
    ContentFrame.Size = UDim2.new(1, -20, 1, -120)
    ContentFrame.Position = UDim2.new(0, 10, 0, 110)
    ContentFrame.BackgroundColor3 = Theme.Secondary
    ContentFrame.BorderSizePixel = 0
    ContentFrame.ScrollBarThickness = 8
    ContentFrame.ScrollBarImageColor3 = Theme.Accent
    ContentFrame.CanvasSize = UDim2.new(0, 0, 5, 0)
    ContentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    ContentFrame.Parent = MainFrame

    local ContentCorner = Instance.new("UICorner")
    ContentCorner.CornerRadius = UDim.new(0, 8)
    ContentCorner.Parent = ContentFrame

    local ContentLayout = Instance.new("UIListLayout")
    ContentLayout.Padding = UDim.new(0, 5)
    ContentLayout.Parent = ContentFrame

    local ContentPadding = Instance.new("UIPadding")
    ContentPadding.PaddingLeft = UDim.new(0, 10)
    ContentPadding.PaddingRight = UDim.new(0, 10)
    ContentPadding.PaddingTop = UDim.new(0, 10)
    ContentPadding.PaddingBottom = UDim.new(0, 10)
    ContentPadding.Parent = ContentFrame

    -- Status Bar
    local StatusBar = Instance.new("Frame")
    StatusBar.Name = "StatusBar"
    StatusBar.Size = UDim2.new(1, 0, 0, 25)
    StatusBar.Position = UDim2.new(0, 0, 1, -25)
    StatusBar.BackgroundColor3 = Color3.fromRGB(30, 30, 45)
    StatusBar.BorderSizePixel = 0
    StatusBar.Parent = MainFrame

    local StatusCorner = Instance.new("UICorner")
    StatusCorner.CornerRadius = UDim.new(0, 0)
    StatusCorner.Parent = StatusBar

    local StatusText = Instance.new("TextLabel")
    StatusText.Name = "StatusText"
    StatusText.Size = UDim2.new(1, -20, 1, 0)
    StatusText.BackgroundTransparency = 1
    StatusText.Text = "🔔 Pronto para analisar"
    StatusText.TextColor3 = Theme.TextDim
    StatusText.TextSize = 12
    StatusText.Font = Enum.Font.Gotham
    StatusText.TextXAlignment = Enum.TextXAlignment.Left
    StatusText.Position = UDim2.new(0, 10, 0, 0)
    StatusText.Parent = StatusBar

    -- Funções Auxiliares

    function CreateLabel(parent, text, color, size)
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, size or 25)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = color or Theme.Text
        label.TextSize = size and 12 or 14
        label.Font = Enum.Font.Gotham
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.AutomaticSize = Enum.AutomaticSize.Y
        label.Parent = parent
        return label
    end

    function CreateButton(parent, text, callback, color)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(0.48, 0, 0, 40)
        btn.BackgroundColor3 = color or Theme.Accent
        btn.Text = text
        btn.TextColor3 = Theme.Text
        btn.TextSize = 13
        btn.Font = Enum.Font.GothamSemibold
        btn.BorderSizePixel = 0
        btn.Parent = parent

        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = btn

        btn.MouseButton1Click:Connect(callback)

        return btn
    end

    function CreateSection(parent, title, color)
        local section = Instance.new("Frame")
        section.Size = UDim2.new(1, 0, 0, 30)
        section.BackgroundColor3 = color or Theme.Accent
        section.BorderSizePixel = 0
        section.Parent = parent

        local sectionCorner = Instance.new("UICorner")
        sectionCorner.CornerRadius = UDim.new(0, 6)
        sectionCorner.Parent = section

        local sectionLabel = Instance.new("TextLabel")
        sectionLabel.Size = UDim2.new(1, 0, 1, 0)
        sectionLabel.BackgroundTransparency = 1
        sectionLabel.Text = title
        sectionLabel.TextColor3 = Theme.Text
        sectionLabel.TextSize = 14
        sectionLabel.Font = Enum.Font.GothamBold
        sectionLabel.TextXAlignment = Enum.TextXAlignment.Left
        sectionLabel.Position = UDim2.new(0, 10, 0, 0)
        sectionLabel.Parent = section

        return section
    end

    function UpdateStatus(text)
        StatusText.Text = text
    end

    function ClearContent()
        for _, child in ipairs(ContentFrame:GetChildren()) do
            if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("TextButton") then
                child:Destroy()
            end
        end
    end

    function UpdateContent(tabIndex)
        ClearContent()

        if tabIndex == 1 then
            -- TAB ANALISAR
            CreateSection(ContentFrame, "📊 ANÁLISE DO MAPA", Theme.Success)

            local infoFrame = Instance.new("Frame")
            infoFrame.Size = UDim2.new(1, 0, 0, 200)
            infoFrame.BackgroundColor3 = Theme.Background
            infoFrame.BorderSizePixel = 0
            infoFrame.Parent = ContentFrame

            local infoCorner = Instance.new("UICorner")
            infoCorner.CornerRadius = UDim.new(0, 6)
            infoCorner.Parent = infoFrame

            local infoLayout = Instance.new("UIListLayout")
            infoLayout.Padding = UDim.new(0, 8)
            infoLayout.Parent = infoFrame

            local infoPadding = Instance.new("UIPadding")
            infoPadding.PaddingAll = 10
            infoPadding.Parent = infoFrame

            CreateLabel(infoFrame, "🌍 Mapa Atual: " .. (workspace:FindFirstChild("Map") and workspace.Map.Name or "Nenhum encontrado") .. " | " .. game.JobId)
            CreateLabel(infoFrame, "👥 Jogadores: " .. #Players:GetPlayers())

            if DataStorage.MapInfo and DataStorage.MapInfo.Name then
                CreateLabel(infoFrame, "📦 Parts: " .. DataStorage.Statistics.TotalParts)
                CreateLabel(infoFrame, "📁 Models: " .. DataStorage.Statistics.TotalModels)
                CreateLabel(infoFrame, "📜 Scripts: " .. DataStorage.Statistics.TotalScripts)
                CreateLabel(infoFrame, "🔧 Tools: " .. DataStorage.Statistics.TotalTools)
                CreateLabel(infoFrame, "💡 Lights: " .. DataStorage.Statistics.TotalLights)
                CreateLabel(infoFrame, "🎨 Particles: " .. DataStorage.Statistics.TotalParticles)
                CreateLabel(infoFrame, "🖼️ Decals: " .. DataStorage.Statistics.TotalDecals)
            else
                CreateLabel(infoFrame, "⚠️ Clique em 'Analisar Mapa' para iniciar", Theme.Warning)
            end

            local btnFrame = Instance.new("Frame")
            btnFrame.Size = UDim2.new(1, 0, 0, 100)
            btnFrame.BackgroundTransparency = 1
            btnFrame.Parent = ContentFrame

            local btnLayout = Instance.new("UIListLayout")
            btnLayout.Padding = UDim.new(0, 10)
            btnLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            btnLayout.Parent = btnFrame

            local btn1 = Instance.new("TextButton")
            btn1.Size = UDim2.new(0, 250, 0, 45)
            btn1.BackgroundColor3 = Theme.Success
            btn1.Text = "🚀 INICIAR ANÁLISE COMPLETA"
            btn1.TextColor3 = Theme.Text
            btn1.TextSize = 14
            btn1.Font = Enum.Font.GothamBold
            btn1.Parent = btnFrame

            local btn1Corner = Instance.new("UICorner")
            btn1Corner.CornerRadius = UDim.new(0, 8)
            btn1Corner.Parent = btn1

            local btn2 = Instance.new("TextButton")
            btn2.Size = UDim2.new(0, 250, 0, 45)
            btn2.BackgroundColor3 = Theme.Warning
            btn2.Text = "📦 CLONAR MAPA COMPLETO"
            btn2.TextColor3 = Theme.Text
            btn2.TextSize = 14
            btn2.Font = Enum.Font.GothamBold
            btn2.Parent = btnFrame

            local btn2Corner = Instance.new("UICorner")
            btn2Corner.CornerRadius = UDim.new(0, 8)
            btn2Corner.Parent = btn2

            local btn3 = Instance.new("TextButton")
            btn3.Size = UDim2.new(0, 250, 0, 45)
            btn3.BackgroundColor3 = Theme.Danger
            btn3.Text = "🗑️ LIMPAR CLONAGEM"
            btn3.TextColor3 = Theme.Text
            btn3.TextSize = 14
            btn3.Font = Enum.Font.GothamBold
            btn3.Parent = btnFrame

            local btn3Corner = Instance.new("UICorner")
            btn3Corner.CornerRadius = UDim.new(0, 8)
            btn3Corner.Parent = btn3

            btn1.MouseButton1Click:Connect(function()
                UpdateStatus("⏳ Analisando mapa...")
                task.spawn(function()
                    AnalyzeMap()
                    UpdateStatus("✅ Análise concluída")
                    UpdateContent(1)
                end)
            end)

            btn2.MouseButton1Click:Connect(function()
                UpdateStatus("⏳ Clonando mapa...")
                task.spawn(function()
                    CloneMap()
                    UpdateStatus("✅ Mapa clonado com sucesso")
                    UpdateContent(1)
                end)
            end)

            btn3.MouseButton1Click:Connect(function()
                if DataStorage.ClonedMap then
                    DataStorage.ClonedMap:Destroy()
                    DataStorage.ClonedMap = nil
                    UpdateStatus("🗑️ Clonagem limpa")
                else
                    UpdateStatus("⚠️ Nenhuma clonagem para limpar")
                end
            end)

        elseif tabIndex == 2 then
            -- TAB SCRIPTS
            CreateSection(ContentFrame, "📜 SCRIPTS ENCONTRADOS", Theme.Accent)

            if #DataStorage.Scripts > 0 then
                local totalLines = 0
                for _, script in ipairs(DataStorage.Scripts) do
                    totalLines = totalLines + (script.Lines or 0)
                end

                local infoFrame = Instance.new("Frame")
                infoFrame.Size = UDim2.new(1, 0, 0, 60)
                infoFrame.BackgroundColor3 = Theme.Background
                infoFrame.BorderSizePixel = 0
                infoFrame.Parent = ContentFrame

                local infoCorner = Instance.new("UICorner")
                infoCorner.CornerRadius = UDim.new(0, 6)
                infoCorner.Parent = infoFrame

                local infoPadding = Instance.new("UIPadding")
                infoPadding.PaddingAll = 10
                infoPadding.Parent = infoFrame

                CreateLabel(infoFrame, "📊 Total de Scripts: " .. #DataStorage.Scripts)
                CreateLabel(infoFrame, "📝 Total de Linhas: " .. totalLines)

                for i, script in ipairs(DataStorage.Scripts) do
                    local scriptFrame = Instance.new("Frame")
                    scriptFrame.Size = UDim2.new(1, 0, 0, 80)
                    scriptFrame.BackgroundColor3 = Theme.Background
                    scriptFrame.BorderSizePixel = 0
                    scriptFrame.Parent = ContentFrame

                    local scriptCorner = Instance.new("UICorner")
                    scriptCorner.CornerRadius = UDim.new(0, 6)
                    scriptCorner.Parent = scriptFrame

                    local scriptPadding = Instance.new("UIPadding")
                    scriptPadding.PaddingAll = 10
                    scriptPadding.Parent = scriptFrame

                    local scriptTitle = Instance.new("TextLabel")
                    scriptTitle.Size = UDim2.new(1, 0, 0, 25)
                    scriptTitle.BackgroundTransparency = 1
                    scriptTitle.Text = "🔹 " .. script.Name .. " (" .. script.Type .. ")"
                    scriptTitle.TextColor3 = Theme.Success
                    scriptTitle.TextSize = 14
                    scriptTitle.Font = Enum.Font.GothamBold
                    scriptTitle.TextXAlignment = Enum.TextXAlignment.Left
                    scriptTitle.Parent = scriptFrame

                    CreateLabel(scriptFrame, "📍 Caminho: " .. script.Path)
                    CreateLabel(scriptFrame, "📝 Linhas de código: " .. (script.Lines or 0) .. " | Status: " .. script.Disabled and "❌ Desabilitado" or "✅ Habilitado")

                    if i <= 20 then
                        local expandBtn = Instance.new("TextButton")
                        expandBtn.Size = UDim2.new(0, 100, 0, 25)
                        expandBtn.Position = UDim2.new(1, -105, 0, 10)
                        expandBtn.BackgroundColor3 = Theme.Accent
                        expandBtn.Text = "Ver Código"
                        expandBtn.TextColor3 = Theme.Text
                        expandBtn.TextSize = 11
                        expandBtn.Font = Enum.Font.GothamSemibold
                        expandBtn.BorderSizePixel = 0
                        expandBtn.Parent = scriptFrame

                        local expandBtnCorner = Instance.new("UICorner")
                        expandBtnCorner.CornerRadius = UDim.new(0, 4)
                        expandBtnCorner.Parent = expandBtn

                        expandBtn.MouseButton1Click:Connect(function()
                            ShowScriptCode(script)
                        end)
                    end
                end

                if #DataStorage.Scripts > 20 then
                    CreateLabel(ContentFrame, "📋 Mostrando 20 de " .. #DataStorage.Scripts .. " scripts. Use a função de exportar para ver todos.", Theme.Warning)
                end
            else
                CreateLabel(ContentFrame, "⚠️ Nenhum script encontrado. Execute a análise primeiro.", Theme.Warning)

                local btn = Instance.new("TextButton")
                btn.Size = UDim2.new(0, 200, 0, 40)
                btn.BackgroundColor3 = Theme.Accent
                btn.Text = "🔍 Analisar Scripts"
                btn.TextColor3 = Theme.Text
                btn.TextSize = 14
                btn.Font = Enum.Font.GothamSemibold
                btn.Parent = ContentFrame

                local btnCorner = Instance.new("UICorner")
                btnCorner.CornerRadius = UDim.new(0, 6)
                btnCorner.Parent = btn

                btn.MouseButton1Click:Connect(function()
                    task.spawn(function()
                        AnalyzeMap()
                        UpdateContent(2)
                    end)
                end)
            end

        elseif tabIndex == 3 then
            -- TAB ESTRUTURA
            CreateSection(ContentFrame, "🗂️ ESTRUTURA DO MAPA", Theme.Warning)

            if DataStorage.MapInfo and DataStorage.MapInfo.Hierarchy then
                local statsFrame = Instance.new("Frame")
                statsFrame.Size = UDim2.new(1, 0, 0, 100)
                statsFrame.BackgroundColor3 = Theme.Background
                statsFrame.BorderSizePixel = 0
                statsFrame.Parent = ContentFrame

                local statsCorner = Instance.new("UICorner")
                statsCorner.CornerRadius = UDim.new(0, 6)
                statsCorner.Parent = statsFrame

                local statsPadding = Instance.new("UIPadding")
                statsPadding.PaddingAll = 10
                statsPadding.Parent = statsFrame

                CreateLabel(statsFrame, "🌳 Profundidade máxima: " .. DataStorage.Statistics.MaxDepth)
                CreateLabel(statsFrame, "📂 Maior pasta: " .. DataStorage.Statistics.LargestFolder)
                CreateLabel(statsFrame, "📦 Total de objetos: " .. #DataStorage.AllObjects)

                CreateSection(ContentFrame, "📁 HIERARQUIA COMPLETA", Theme.Secondary)

                local treeFrame = Instance.new("ScrollingFrame")
                treeFrame.Size = UDim2.new(1, 0, 0, 300)
                treeFrame.BackgroundTransparency = 1
                treeFrame.ScrollBarThickness = 5
                treeFrame.CanvasSize = UDim2.new(0, 0, 10, 0)
                treeFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
                treeFrame.Parent = ContentFrame

                local treeLayout = Instance.new("UIListLayout")
                treeLayout.Padding = UDim.new(0, 2)
                treeLayout.Parent = treeFrame

                local function CreateTreeNode(parent, node, depth)
                    local indent = string.rep("    ", depth)
                    local icon = "📦"
                    if node.Type == "Model" then icon = "📁"
                    elseif node.Type == "Script" then icon = "📜"
                    elseif node.Type == "LocalScript" then icon = "📝"
                    elseif node.Type == "Tool" then icon = "🔧"
                    elseif node.Type == "Folder" then icon = "📂"
                    elseif node.Type == "Light" then icon = "💡"
                    end

                    local label = Instance.new("TextLabel")
                    label.Size = UDim2.new(1, 0, 0, 20)
                    label.BackgroundTransparency = 1
                    label.Text = indent .. icon .. " " .. node.Name .. " [" .. node.Type .. "]"
                    label.TextColor3 = depth == 0 and Theme.Success or Theme.TextDim
                    label.TextSize = 11
                    label.Font = Enum.Font.Code
                    label.TextXAlignment = Enum.TextXAlignment.Left
                    label.AutomaticSize = Enum.AutomaticSize.Y
                    label.Parent = parent

                    for _, child in ipairs(node.Children or {}) do
                        CreateTreeNode(parent, child, depth + 1)
                    end
                end

                for _, node in ipairs(DataStorage.MapInfo.Hierarchy or {}) do
                    CreateTreeNode(treeFrame, node, 0)
                end
            else
                CreateLabel(ContentFrame, "⚠️ Execute a análise primeiro para ver a estrutura.", Theme.Warning)
            end

        elseif tabIndex == 4 then
            -- TAB EXPORTAR
            CreateSection(ContentFrame, "📋 EXPORTAÇÃO DE DADOS", Theme.Success)

            local exportFrame = Instance.new("Frame")
            exportFrame.Size = UDim2.new(1, 0, 0, 150)
            exportFrame.BackgroundColor3 = Theme.Background
            exportFrame.BorderSizePixel = 0
            exportFrame.Parent = ContentFrame

            local exportCorner = Instance.new("UICorner")
            exportCorner.CornerRadius = UDim.new(0, 6)
            exportCorner.Parent = exportFrame

            local exportPadding = Instance.new("UIPadding")
            exportPadding.PaddingAll = 10
            exportPadding.Parent = exportFrame

            CreateLabel(exportFrame, "Selecione o formato de exportação:")

            local exportBtns = Instance.new("Frame")
            exportBtns.Size = UDim2.new(1, 0, 0, 100)
            exportBtns.BackgroundTransparency = 1
            exportBtns.Parent = exportFrame

            local exportLayout = Instance.new("UIListLayout")
            exportLayout.FillDirection = Enum.FillDirection.Horizontal
            exportLayout.Padding = UDim.new(0, 10)
            exportLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            exportLayout.Parent = exportBtns

            local formats = {
                {Name = "📄 Texto", Format = "txt"},
                {Name = "📋 JSON", Format = "json"},
                {Name = "📊 Resumo", Format = "summary"},
            }

            for _, fmt in ipairs(formats) do
                local expBtn = Instance.new("TextButton")
                expBtn.Size = UDim2.new(0, 120, 0, 40)
                expBtn.BackgroundColor3 = Theme.Accent
                expBtn.Text = fmt.Name
                expBtn.TextColor3 = Theme.Text
                expBtn.TextSize = 12
                expBtn.Font = Enum.Font.GothamSemibold
                expBtn.BorderSizePixel = 0
                expBtn.Parent = exportBtns

                local expBtnCorner = Instance.new("UICorner")
                expBtnCorner.CornerRadius = UDim.new(0, 6)
                expBtnCorner.Parent = expBtn

                expBtn.MouseButton1Click:Connect(function()
                    ExportData(fmt.Format)
                end)
            end

            CreateSection(ContentFrame, "📦 OBJETOS IMPORTANTES IDENTIFICADOS", Theme.Warning)

            if DataStorage.MapInfo and DataStorage.MapInfo.ImportantObjects then
                local important = DataStorage.MapInfo.ImportantObjects

                if #important > 0 then
                    for _, obj in ipairs(important) do
                        local objFrame = Instance.new("Frame")
                        objFrame.Size = UDim2.new(1, 0, 0, 50)
                        objFrame.BackgroundColor3 = Theme.Background
                        objFrame.BorderSizePixel = 0
                        objFrame.Parent = ContentFrame

                        local objCorner = Instance.new("UICorner")
                        objCorner.CornerRadius = UDim.new(0, 6)
                        objCorner.Parent = objFrame

                        local objPadding = Instance.new("UIPadding")
                        objPadding.PaddingAll = 8
                        objPadding.Parent = objFrame

                        local objIcon = "🎯"
                        if obj.Category == "Spawn" then objIcon = "🏁"
                        elseif obj.Category == "Checkpoint" then objIcon = "🚩"
                        elseif obj.Category == "Hazard" then objIcon = "⚠️"
                        elseif obj.Category == "NPC" then objIcon = "🤖"
                        elseif obj.Category == "Goal" then objIcon = "🎯"
                        end

                        CreateLabel(objFrame, objIcon .. " " .. obj.Name .. " [" .. obj.Type .. "] - " .. obj.Category)
                        CreateLabel(objFrame, "📍 Posição: " .. obj.Position, Theme.TextDim)
                    end
                else
                    CreateLabel(ContentFrame, "Nenhum objeto importante identificado.", Theme.TextDim)
                end
            else
                CreateLabel(ContentFrame, "⚠️ Execute a análise primeiro.", Theme.Warning)
            end

        elseif tabIndex == 5 then
            -- TAB CONFIG
            CreateSection(ContentFrame, "⚙️ CONFIGURAÇÕES", Theme.Secondary)

            local configFrame = Instance.new("Frame")
            configFrame.Size = UDim2.new(1, 0, 0, 200)
            configFrame.BackgroundColor3 = Theme.Background
            configFrame.BorderSizePixel = 0
            configFrame.Parent = ContentFrame

            local configCorner = Instance.new("UICorner")
            configCorner.CornerRadius = UDim.new(0, 6)
            configCorner.Parent = configFrame

            local configPadding = Instance.new("UIPadding")
            configPadding.PaddingAll = 10
            configPadding.Parent = configFrame

            CreateLabel(configFrame, "🔧 Profundidade máxima: " .. CONFIG.MaxDepth)
            CreateLabel(configFrame, "📦 Limite de objetos: " .. CONFIG.MaxObjects)
            CreateLabel(configFrame, "⏱️ Delay de processamento: " .. CONFIG.ProcessDelay)
            CreateLabel(configFrame, "💾 Salvar no Workspace: " .. (CONFIG.SaveToWorkspace and "Sim" or "Não"))

            CreateSection(ContentFrame, "🎛️ AJUSTES", Theme.Accent)

            local adjustFrame = Instance.new("Frame")
            adjustFrame.Size = UDim2.new(1, 0, 0, 150)
            adjustFrame.BackgroundTransparency = 1
            adjustFrame.Parent = ContentFrame

            local adjustLayout = Instance.new("UIListLayout")
            adjustLayout.Padding = UDim.new(0, 10)
            adjustLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
            adjustLayout.Parent = adjustFrame

            CreateButton(adjustFrame, "🔄 Resetar Estatísticas", function()
                DataStorage.Statistics = {
                    TotalParts = 0,
                    TotalModels = 0,
                    TotalScripts = 0,
                    TotalTools = 0,
                    TotalLights = 0,
                    TotalParticles = 0,
                    TotalDecals = 0,
                    TotalNPCs = 0,
                    MaxDepth = 0,
                    LargestFolder = "",
                    ScriptLines = 0,
                }
                DataStorage.Scripts = {}
                DataStorage.MapInfo = {}
                DataStorage.AllObjects = {}
                UpdateStatus("🔄 Estatísticas resetadas")
                UpdateContent(5)
            end, Theme.Warning)

            CreateButton(adjustFrame, "📦 Criar Backup no Workspace", function()
                CreateBackup()
                UpdateStatus("📦 Backup criado no Workspace")
            end, Theme.Success)

            CreateButton(adjustFrame, "🗑️ Limpar Tudo", function()
                if DataStorage.ClonedMap then
                    DataStorage.ClonedMap:Destroy()
                end
                DataStorage = {
                    ClonedMap = nil,
                    MapInfo = {},
                    Scripts = {},
                    AllObjects = {},
                    Statistics = {
                        TotalParts = 0,
                        TotalModels = 0,
                        TotalScripts = 0,
                        TotalTools = 0,
                        TotalLights = 0,
                        TotalParticles = 0,
                        TotalDecals = 0,
                        TotalNPCs = 0,
                        MaxDepth = 0,
                        LargestFolder = "",
                        ScriptLines = 0,
                    },
                    ExportData = {},
                }
                UpdateStatus("🗑️ Tudo limpo")
                UpdateContent(5)
            end, Theme.Danger)
        end
    end

    function ShowScriptCode(scriptData)
        local codeGui = Instance.new("ScreenGui")
        codeGui.Name = "CodeViewer"
        codeGui.Parent = LocalPlayer.PlayerGui

        local codeFrame = Instance.new("Frame")
        codeFrame.Size = UDim2.new(0.8, 0, 0.8, 0)
        codeFrame.Position = UDim2.new(0.1, 0, 0.1, 0)
        codeFrame.BackgroundColor3 = Theme.Background
        codeFrame.BorderSizePixel = 0
        codeFrame.Parent = codeGui

        local codeCorner = Instance.new("UICorner")
        codeCorner.CornerRadius = UDim.new(0, 10)
        codeCorner.Parent = codeFrame

        local codeHeader = Instance.new("Frame")
        codeHeader.Size = UDim2.new(1, 0, 0, 50)
        codeHeader.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
        codeHeader.BorderSizePixel = 0
        codeHeader.Parent = codeFrame

        local codeTitle = Instance.new("TextLabel")
        codeTitle.Size = UDim2.new(1, -60, 1, 0)
        codeTitle.BackgroundTransparency = 1
        codeTitle.Text = "📜 " .. scriptData.Name
        codeTitle.TextColor3 = Theme.Text
        codeTitle.TextSize = 16
        codeTitle.Font = Enum.Font.GothamBold
        codeTitle.TextXAlignment = Enum.TextXAlignment.Left
        codeTitle.Position = UDim2.new(0, 15, 0, 0)
        codeTitle.Parent = codeHeader

        local closeCode = Instance.new("TextButton")
        closeCode.Size = UDim2.new(0, 40, 0, 40)
        closeCode.Position = UDim2.new(1, -45, 0.5, -20)
        closeCode.BackgroundColor3 = Theme.Danger
        closeCode.Text = "✕"
        closeCode.TextColor3 = Theme.Text
        closeCode.TextSize = 16
        closeCode.Font = Enum.Font.GothamBold
        closeCode.Parent = codeHeader

        local closeCodeCorner = Instance.new("UICorner")
        closeCodeCorner.CornerRadius = UDim.new(0, 8)
        closeCodeCorner.Parent = closeCode

        closeCode.MouseButton1Click:Connect(function()
            codeGui:Destroy()
        end)

        local codeScroll = Instance.new("ScrollingFrame")
        codeScroll.Size = UDim2.new(1, -20, 1, -70)
        codeScroll.Position = UDim2.new(0, 10, 0, 60)
        codeScroll.BackgroundTransparency = 1
        codeScroll.ScrollBarThickness = 8
        codeScroll.ScrollBarImageColor3 = Theme.Accent
        codeScroll.CanvasSize = UDim2.new(0, 0, 10, 0)
        codeScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        codeScroll.Parent = codeFrame

        local codeText = Instance.new("TextLabel")
        codeText.Size = UDim2.new(1, 0, 0, 2000)
        codeText.BackgroundTransparency = 1
        codeText.Text = scriptData.Source or "-- Código não disponível"
        codeText.TextColor3 = Color3.fromRGB(200, 200, 200)
        codeText.TextSize = 11
        codeText.Font = Enum.Font.Code
        codeText.TextXAlignment = Enum.TextXAlignment.Left
        codeText.TextYAlignment = Enum.TextYAlignment.Top
        codeText.AutomaticSize = Enum.AutomaticSize.Y
        codeText.Parent = codeScroll
    end

    function ExportData(format)
        if not DataStorage.MapInfo or not next(DataStorage.MapInfo) then
            UpdateStatus("⚠️ Execute a análise primeiro")
            return
        end

        if format == "txt" then
            local text = "═══════════════════════════════════════════\n"
            text = text .. "       RELATÓRIO DE ANÁLISE DO MAPA       \n"
            text = text .. "═══════════════════════════════════════════\n\n"
            text = text .. "Mapa: " .. (DataStorage.MapInfo.Name or "N/A") .. "\n"
            text = text .. "Job ID: " .. game.JobId .. "\n"
            text = text .. "Data: " .. os.date() .. "\n\n"
            text = text .. "── ESTATÍSTICAS ──\n"
            text = text .. "Parts: " .. DataStorage.Statistics.TotalParts .. "\n"
            text = text .. "Models: " .. DataStorage.Statistics.TotalModels .. "\n"
            text = text .. "Scripts: " .. DataStorage.Statistics.TotalScripts .. "\n"
            text = text .. "Tools: " .. DataStorage.Statistics.TotalTools .. "\n"
            text = text .. "Lights: " .. DataStorage.Statistics.TotalLights .. "\n"
            text = text .. "Particles: " .. DataStorage.Statistics.TotalParticles .. "\n"
            text = text .. "Decals: " .. DataStorage.Statistics.TotalDecals .. "\n"
            text = text .. "Profundidade: " .. DataStorage.Statistics.MaxDepth .. "\n\n"
            text = text .. "── SCRIPTS ──\n"
            for _, script in ipairs(DataStorage.Scripts) do
                text = text .. "\n[" .. script.Type .. "] " .. script.Name .. "\n"
                text = text .. "Path: " .. script.Path .. "\n"
                text = text .. "Linhas: " .. (script.Lines or 0) .. "\n"
                text = text .. "Status: " .. (script.Disabled and "Desabilitado" or "Habilitado") .. "\n"
                if script.Source then
                    text = text .. "Código: \n" .. script.Source .. "\n"
                end
            end

            setclipboard(text)
            UpdateStatus("📋 Relatório copiado para a área de transferência!")

        elseif format == "json" then
            local jsonData = {
                MapName = DataStorage.MapInfo.Name,
                JobId = game.JobId,
                Statistics = DataStorage.Statistics,
                Scripts = DataStorage.Scripts,
                ImportantObjects = DataStorage.MapInfo.ImportantObjects or {},
                Hierarchy = DataStorage.MapInfo.Hierarchy or {},
            }

            local success, encoded = pcall(HttpService.JSONEncode, HttpService, jsonData)
            if success then
                setclipboard(encoded)
                UpdateStatus("📋 JSON copiado para a área de transferência!")
            else
                UpdateStatus("❌ Erro ao gerar JSON")
            end

        elseif format == "summary" then
            local summary = "MAPA: " .. (DataStorage.MapInfo.Name or "N/A") .. "\n"
            summary = summary .. "═══════════════════════════════════════\n"
            summary = summary .. "📦 Parts: " .. DataStorage.Statistics.TotalParts .. "\n"
            summary = summary .. "📁 Models: " .. DataStorage.Statistics.TotalModels .. "\n"
            summary = summary .. "📜 Scripts: " .. DataStorage.Statistics.TotalScripts .. "\n"
            summary = summary .. "🔧 Tools: " .. DataStorage.Statistics.TotalTools .. "\n"
            summary = summary .. "💡 Lights: " .. DataStorage.Statistics.TotalLights .. "\n"
            summary = summary .. "🎨 Particles: " .. DataStorage.Statistics.TotalParticles .. "\n"
            summary = summary .. "🖼️ Decals: " .. DataStorage.Statistics.TotalDecals .. "\n"
            summary = summary .. "🗂️ Maior pasta: " .. DataStorage.Statistics.LargestFolder .. "\n"
            summary = summary .. "🌳 Profundidade: " .. DataStorage.Statistics.MaxDepth .. "\n"

            setclipboard(summary)
            UpdateStatus("📋 Resumo copiado para a área de transferência!")
        end
    end

    function CreateBackup()
        if DataStorage.ClonedMap then
            local backupContainer = workspace:FindFirstChild("MapAnalyzerBackup")
            if backupContainer then backupContainer:Destroy() end

            local backup = Instance.new("Folder")
            backup.Name = "MapAnalyzerBackup"
            backup.Parent = workspace

            local mapCopy = DataStorage.ClonedMap:Clone()
            mapCopy.Parent = backup

            local report = Instance.new("ModuleScript")
            report.Name = "AnalysisReport"
            report.Parent = backup

            local reportModule = {}
            reportModule.Data = DataStorage.MapInfo
            reportModule.Statistics = DataStorage.Statistics
            reportModule.Scripts = DataStorage.Scripts

            local reportSource = "return " .. HttpService:JSONEncode(reportModule)
            report.Source = reportSource

            UpdateStatus("📦 Backup salvo em Workspace > MapAnalyzerBackup")
        else
            UpdateStatus("⚠️ Clone o mapa primeiro")
        end
    end

    -- ═══════════════════════════════════════════════════════════
    -- FUNÇÕES PRINCIPAIS DE ANÁLISE E CLONAGEM
    -- ═══════════════════════════════════════════════════════════

    function AnalyzeMap()
        local map = workspace:FindFirstChild("Map")
        if not map then
            UpdateStatus("❌ Mapa não encontrado")
            return
        end

        UpdateStatus("⏳ Analisando estrutura...")

        -- Reset dados
        DataStorage.MapInfo = {
            Name = map.Name,
            FullPath = map:GetFullName(),
        }
        DataStorage.Scripts = {}
        DataStorage.AllObjects = {}
        DataStorage.MapInfo.Hierarchy = {}
        DataStorage.MapInfo.ImportantObjects = {}

        local folderCounts = {}
        local objectCount = 0

        local function ProcessObject(obj, parentTable, depth, path)
            if objectCount > CONFIG.MaxObjects then return end
            if depth > CONFIG.MaxDepth then return end

            objectCount = objectCount + 1
            table.insert(DataStorage.AllObjects, {
                Name = obj.Name,
                Type = obj.ClassName,
                Path = path,
            })

            -- Estatísticas
            if obj:IsA("BasePart") then
                DataStorage.Statistics.TotalParts = DataStorage.Statistics.TotalParts + 1
            elseif obj:IsA("Model") then
                DataStorage.Statistics.TotalModels = DataStorage.Statistics.TotalModels + 1
            elseif obj:IsA("Script") then
                DataStorage.Statistics.TotalScripts = DataStorage.Statistics.TotalScripts + 1
                DataStorage.Statistics.ScriptLines = DataStorage.Statistics.ScriptLines + #obj:GetChildren()

                local source = ""
                pcall(function() source = obj.Source end)

                table.insert(DataStorage.Scripts, {
                    Name = obj.Name,
                    Type = "Script",
                    Path = path,
                    Lines = #source:gsub("[^\n]", ""),
                    Disabled = not obj.Enabled,
                    Source = source,
                })
            elseif obj:IsA("LocalScript") then
                DataStorage.Statistics.TotalScripts = DataStorage.Statistics.TotalScripts + 1

                local source = ""
                pcall(function() source = obj.Source end)

                table.insert(DataStorage.Scripts, {
                    Name = obj.Name,
                    Type = "LocalScript",
                    Path = path,
                    Lines = #source:gsub("[^\n]", ""),
                    Disabled = not obj.Enabled,
                    Source = source,
                })
            elseif obj:IsA("ModuleScript") then
                DataStorage.Statistics.TotalScripts = DataStorage.Statistics.TotalScripts + 1

                local source = ""
                pcall(function() source = obj.Source end)

                table.insert(DataStorage.Scripts, {
                    Name = obj.Name,
                    Type = "ModuleScript",
                    Path = path,
                    Lines = #source:gsub("[^\n]", ""),
                    Disabled = false,
                    Source = source,
                })
            elseif obj:IsA("Tool") then
                DataStorage.Statistics.TotalTools = DataStorage.Statistics.TotalTools + 1
            elseif obj:IsA("Light") or obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
                DataStorage.Statistics.TotalLights = DataStorage.Statistics.TotalLights + 1
            elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") then
                DataStorage.Statistics.TotalParticles = DataStorage.Statistics.TotalParticles + 1
            elseif obj:IsA("Decal") or obj:IsA("Texture") then
                DataStorage.Statistics.TotalDecals = DataStorage.Statistics.TotalDecals + 1
            end

            -- Identificar objetos importantes
            local nameLower = obj.Name:lower()
            local category = nil

            if nameLower:match("spawn") or obj:IsA("SpawnLocation") then
                category = "Spawn"
            elseif nameLower:match("checkpoint") then
                category = "Checkpoint"
            elseif nameLower:match("hazard") or nameLower:match("danger") or nameLower:match("kill") then
                category = "Hazard"
            elseif nameLower:match("npc") or nameLower:match("character") or (obj:IsA("Model") and obj:FindFirstChildWhichIsA("Humanoid")) then
                category = "NPC"
                DataStorage.Statistics.TotalNPCs = DataStorage.Statistics.TotalNPCs + 1
            elseif nameLower:match("goal") or nameLower:match("finish") or nameLower:match("win") then
                category = "Goal"
            end

            if category then
                local pos = "N/A"
                if obj:IsA("BasePart") then
                    pos = string.format("%.1f, %.1f, %.1f", obj.Position.X, obj.Position.Y, obj.Position.Z)
                end

                table.insert(DataStorage.MapInfo.ImportantObjects, {
                    Name = obj.Name,
                    Type = obj.ClassName,
                    Category = category,
                    Position = pos,
                })
            end

            -- Contagem de pastas
            if obj:IsA("Folder") or obj:IsA("Model") then
                folderCounts[obj.Name] = (folderCounts[obj.Name] or 0) + 1
            end

            -- Atualizar profundidade máxima
            if depth > DataStorage.Statistics.MaxDepth then
                DataStorage.Statistics.MaxDepth = depth
            end

            -- Construir hierarquia
            local node = {
                Name = obj.Name,
                Type = obj.ClassName,
                Children = {},
            }
            table.insert(parentTable, node)

            -- Processar filhos
            for _, child in ipairs(obj:GetChildren()) do
                task.wait()
                ProcessObject(child, node.Children, depth + 1, path .. "/" .. child.Name)
            end
        end

        ProcessObject(map, DataStorage.MapInfo.Hierarchy, 0, "Workspace/" .. map.Name)

        -- Encontrar maior pasta
        local maxCount = 0
        for name, count in pairs(folderCounts) do
            if count > maxCount then
                maxCount = count
                DataStorage.Statistics.LargestFolder = name .. " (" .. count .. "x)"
            end
        end

        UpdateStatus("✅ Análise completa: " .. objectCount .. " objetos processados")
    end

    function CloneMap()
        local map = workspace:FindFirstChild("Map")
        if not map then
            UpdateStatus("❌ Mapa não encontrado")
            return
        end

        UpdateStatus("⏳ Clonando mapa...")

        -- Limpar clonagem anterior
        if DataStorage.ClonedMap then
            DataStorage.ClonedMap:Destroy()
        end

        -- Criar container
        local cloneContainer = Instance.new("Folder")
        cloneContainer.Name = "NDS_ClonedMap_" .. os.time()
        cloneContainer.Parent = workspace

        -- Clonar mapa
        local mapClone = map:Clone()
        mapClone.Parent = cloneContainer

        DataStorage.ClonedMap = cloneContainer

        UpdateStatus("✅ Mapa clonado com sucesso! Total de objetos: " .. #mapClone:GetDescendants())
    end

    -- ═══════════════════════════════════════════════════════════
    -- DRAG FUNCTIONALITY
    -- ═══════════════════════════════════════════════════════════

    local dragging = false
    local dragStart = Vector2.new(0, 0)
    local startPos = UDim2.new(0, 0, 0, 0)

    MainFrame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = MainFrame.Position
        end
    end)

    MainFrame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)

    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    CloseBtn.MouseButton1Click:Connect(function()
        ScreenGui:Destroy()
    end)

    -- Inicializar
    UpdateContent(1)
    UpdateStatus("🔔 Pronto - Use a aba 'Analisar' para começar")

    return ScreenGui
end

-- ═══════════════════════════════════════════════════════════
-- INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════

local function Initialize()
    -- Verificar se já existe UI
    local existingGui = LocalPlayer.PlayerGui:FindFirstChild("MapaAnalyzerUI") or game:GetService("CoreGui"):FindFirstChild("MapaAnalyzerUI")
    if existingGui then
        existingGui:Destroy()
        print("UI anterior removida")
    end

    -- Criar nova UI
    local ui = CreateUI()
    print("═══════════════════════════════════════")
    print("  MAPA ANALYZER - NDS EDITION CARREGADO")
    print("═══════════════════════════════════════")
    print("✅ UI criada com sucesso")
    print("📋 Abas disponíveis:")
    print("   1. Analisar - Análise geral do mapa")
    print("   2. Scripts - Lista de scripts encontrados")
    print("   3. Estrutura - Hierarquia completa")
    print("   4. Exportar - Exportar dados")
    print("   5. Config - Configurações")
    print("═══════════════════════════════════════")
end

Initialize()