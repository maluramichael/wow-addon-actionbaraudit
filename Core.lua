local addonName, addon = ...
local ActionBarAudit = LibStub("AceAddon-3.0"):NewAddon(addon, addonName, "AceEvent-3.0", "AceConsole-3.0")
_G["ActionBarAudit"] = ActionBarAudit

local defaults = {
    profile = {
        minimap = { hide = false },
    },
    char = {
        ignoredSpells = {},
    },
}

-- Store audit results
local lastAuditResults = {}
local spellData = {}
local rankedSpells = {} -- All spells with ranks for the ignore list

-- Default action bar button names
local defaultBars = {"Action", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft"}

-- Check if a spell is ignored
local function IsSpellIgnored(spellName)
    return ActionBarAudit.db and ActionBarAudit.db.char.ignoredSpells[spellName]
end

-- Build spell data from spellbook
local function GetSpellData(debug)
    spellData = {}
    rankedSpells = {}
    for tab = 1, GetNumSpellTabs() do
        local tabName, _, offset, numSlots = GetSpellTabInfo(tab)
        if debug then
            print(format("Tab %d: %s, offset=%d, numSlots=%d", tab, tabName or "?", offset, numSlots))
        end
        for i = offset + 1, offset + numSlots do
            local spellName, spellSubText = GetSpellBookItemName(i, BOOKTYPE_SPELL)
            if spellName then
                local _, spellID = GetSpellBookItemInfo(i, BOOKTYPE_SPELL)

                -- Try to get rank from subtext first
                local rank = spellSubText and strmatch(spellSubText, "%d+")

                -- If no rank in subtext, try GetSpellSubtext with spellID
                if not rank and spellID and GetSpellSubtext then
                    local subtext = GetSpellSubtext(spellID)
                    if subtext then
                        rank = strmatch(subtext, "%d+")
                    end
                end

                if debug then
                    print(format("  [%d] %s - subtext: '%s', rank: %s",
                        i, spellName, tostring(spellSubText), tostring(rank)))
                end

                if rank then
                    rank = tonumber(rank)
                    if rank and rank > 0 then
                        local icon = (spellID and GetSpellTexture(spellID)) or "Interface\\Icons\\INV_Misc_QuestionMark"

                        -- Track max rank for scanning
                        if not spellData[spellName] or rank > spellData[spellName].rank then
                            spellData[spellName] = { rank = rank, bookIndex = i }
                        end

                        -- Track all ranked spells for ignore list
                        if not rankedSpells[spellName] then
                            rankedSpells[spellName] = {
                                name = spellName,
                                icon = icon,
                                maxRank = rank,
                            }
                        else
                            -- Update max rank
                            if rank > rankedSpells[spellName].maxRank then
                                rankedSpells[spellName].maxRank = rank
                            end
                        end
                    end
                end
            end
        end
    end
    return spellData
end

-- Scan hotbars for low rank spells
local function ScanHotbars(printResults)
    lastAuditResults = {}
    local data = GetSpellData()
    local count = 0
    local ignoredCount = 0

    for barIndex, barName in ipairs(defaultBars) do
        for i = 1, 12 do
            local button = _G[barName .. "Button" .. i]
            if button then
                local slot = button.action or 0
                if slot and HasAction(slot) then
                    local spellID = 0
                    local actionType, id = GetActionInfo(slot)
                    if actionType == "macro" then
                        spellID = GetMacroSpell(id)
                    elseif actionType == "spell" then
                        spellID = id
                    end
                    if spellID and spellID > 0 then
                        local spell = Spell:CreateFromSpellID(spellID)
                        spell:ContinueOnSpellLoad(function()
                            local spellName = spell:GetSpellName()
                            local spellSubText = spell:GetSpellSubtext()
                            local rank = strmatch(spellSubText or "", "%d+")
                            if rank then
                                rank = tonumber(rank)
                                if rank and data[spellName] and rank < data[spellName].rank then
                                    -- Check if spell is ignored
                                    if IsSpellIgnored(spellName) then
                                        ignoredCount = ignoredCount + 1
                                        if printResults then
                                            local text = format("|cFF888888Bar %d Slot %d:|r %s |cFF888888(Rank %d) - Ignored|r",
                                                barIndex, i, spellName, rank)
                                            print(text)
                                        end
                                    else
                                        count = count + 1
                                        tinsert(lastAuditResults, {
                                            name = spellName,
                                            current = rank,
                                            max = data[spellName].rank,
                                            bookIndex = data[spellName].bookIndex,
                                            slot = slot,
                                            bar = barIndex,
                                            barSlot = i,
                                        })
                                        if printResults then
                                            local text = format("|cFFFFFF00Bar %d Slot %d:|r %s |cFF9CD6DE(Rank %d)|r |cFFFF6900-> Max Rank %d|r",
                                                barIndex, i, spellName, rank, data[spellName].rank)
                                            print(text)
                                        end
                                    end
                                end
                            end
                        end)
                    end
                end
            end
        end
    end

    return count, ignoredCount
end

-- Fix all low rank spells
local function FixLowRankSpells()
    if #lastAuditResults == 0 then
        print("|cFFFFFF00ActionBarAudit:|r No low rank spells to fix. Click Check first.")
        return
    end

    if InCombatLockdown() then
        print("|cFFFFFF00ActionBarAudit:|r |cFFFF0000Cannot fix spells during combat|r")
        return
    end

    local fixed = 0
    for _, spell in ipairs(lastAuditResults) do
        if spell.bookIndex then
            ClearCursor()
            PickupSpellBookItem(spell.bookIndex, BOOKTYPE_SPELL)
            PlaceAction(spell.slot)
            ClearCursor()
            fixed = fixed + 1
            print(format("|cFF00C800Fixed:|r %s Rank %d -> %d", spell.name, spell.current, spell.max))
        end
    end

    lastAuditResults = {}
    print(format("|cFFFFFF00ActionBarAudit:|r Fixed %d spells.", fixed))
end

-- Fix a specific spell by name
function ActionBarAudit:FixSpecificSpell(targetSpellName)
    if InCombatLockdown() then
        print("|cFFFFFF00ActionBarAudit:|r |cFFFF0000Cannot fix spells during combat|r")
        return
    end

    local data = GetSpellData()
    local found = false

    for barIndex, barName in ipairs(defaultBars) do
        for i = 1, 12 do
            local button = _G[barName .. "Button" .. i]
            if button then
                local slot = button.action or 0
                if slot and HasAction(slot) then
                    local spellID = 0
                    local actionType, id = GetActionInfo(slot)
                    if actionType == "macro" then
                        spellID = GetMacroSpell(id)
                    elseif actionType == "spell" then
                        spellID = id
                    end
                    if spellID and spellID > 0 then
                        local spellName = GetSpellInfo(spellID)
                        if spellName == targetSpellName and data[spellName] then
                            ClearCursor()
                            PickupSpellBookItem(data[spellName].bookIndex, BOOKTYPE_SPELL)
                            PlaceAction(slot)
                            ClearCursor()
                            print(format("|cFF00C800Fixed:|r %s on Bar %d Slot %d", spellName, barIndex, i))
                            found = true
                        end
                    end
                end
            end
        end
    end

    if not found then
        print(format("|cFFFFFF00ActionBarAudit:|r %s not found on action bars or already max rank", targetSpellName))
    end
end

function ActionBarAudit:ShowIgnorePanel()
    -- Open the AceConfig options panel which includes the ignore list
    local AceConfigDialog = LibStub("AceConfigDialog-3.0")
    AceConfigDialog:Open(addonName)
end

function ActionBarAudit:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ActionBarAuditDB", defaults, true)
    self:RegisterChatCommand("aba", "SlashCommand")
    self:RegisterChatCommand("actionbaraudit", "SlashCommand")
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, self:GetOptionsTable())
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, "ActionBarAudit")
    self:SetupMinimapButton()
    self:CreateSpellbookButtons()
end

function ActionBarAudit:OnEnable()
end

function ActionBarAudit:SlashCommand(input)
    if input == "config" or input == "options" then
        self:OpenOptions()
    elseif input == "ignore" or input == "ignores" then
        self:ShowIgnorePanel()
    elseif input == "fix" then
        FixLowRankSpells()
    elseif input == "debug" then
        self:Print("Debug: Scanning spellbook...")
        GetSpellData(true)
        self:Print(format("Found %d ranked spells", self:CountTable(rankedSpells)))
    else
        self:Print("Scanning hotbars...")
        local count, ignoredCount = ScanHotbars(true)
        if count == 0 and ignoredCount == 0 then
            self:Print("|cFF00C800No low rank spells found.|r")
        elseif count == 0 then
            self:Print(format("|cFF00C800No low rank spells found.|r |cFF888888(%d ignored)|r", ignoredCount))
        else
            self:Print(format("|cFFFF6900%d|r low rank spells found. Use /aba fix to upgrade.", count))
        end
    end
end

function ActionBarAudit:CountTable(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local function OpenOptions()
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("ActionBarAudit")
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory("ActionBarAudit")
        InterfaceOptionsFrame_OpenToCategory("ActionBarAudit")
    end
end

function ActionBarAudit:OpenOptions()
    OpenOptions()
end

function ActionBarAudit:SetupMinimapButton()
    local LDB = LibStub("LibDataBroker-1.1", true)
    local LDBIcon = LibStub("LibDBIcon-1.0", true)
    if not LDB or not LDBIcon then return end

    local dataObj = LDB:NewDataObject("ActionBarAudit", {
        type = "launcher",
        icon = "Interface\\Icons\\INV_Misc_Gear_01",
        OnClick = function(_, button)
            if button == "LeftButton" then
                if IsShiftKeyDown() then
                    -- Shift+left click: scan and fix
                    ScanHotbars(false)
                    C_Timer.After(0.1, function()
                        FixLowRankSpells()
                    end)
                else
                    ScanHotbars(true)
                end
            elseif button == "RightButton" then
                self:ShowIgnorePanel()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("ActionBarAudit")
            tt:AddLine("|cff00ff00Left-click|r check", 1, 1, 1)
            tt:AddLine("|cff00ff00Shift+Left-click|r fix all", 1, 1, 1)
            tt:AddLine("|cff00ff00Right-click|r ignore list", 1, 1, 1)
        end,
    })
    if not self.db.profile.minimap then self.db.profile.minimap = { hide = false } end
    LDBIcon:Register("ActionBarAudit", dataObj, self.db.profile.minimap)
end

function ActionBarAudit:CreateSpellbookButtons()
    -- Check button
    local checkButton = CreateFrame("Button", "ActionBarAuditCheckButton", SpellBookFrame, "UIPanelButtonTemplate")
    checkButton:SetPoint("TOPRIGHT", SpellBookFrame, "TOPRIGHT", -56, -30)
    checkButton:SetWidth(70)
    checkButton:SetHeight(24)
    checkButton:SetScale(0.9)
    checkButton:SetText("Check")
    checkButton:SetScript("OnClick", function()
        print("|cFFFFFF00ActionBarAudit:|r Scanning hotbars...")
        local count, ignoredCount = ScanHotbars(true)
        if count == 0 and ignoredCount == 0 then
            print("|cFFFFFF00ActionBarAudit:|r |cFF00C800No low rank spells found.|r")
        elseif count == 0 then
            print(format("|cFFFFFF00ActionBarAudit:|r |cFF00C800No low rank spells found.|r |cFF888888(%d ignored)|r", ignoredCount))
        else
            print(format("|cFFFFFF00ActionBarAudit:|r |cFFFF6900%d|r low rank spells found.", count))
        end
    end)
    checkButton:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Check Hotbar Ranks")
        GameTooltip:AddLine("Scan all action bars for low rank spells", 1, 1, 1)
        GameTooltip:Show()
    end)
    checkButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Fix button
    local fixButton = CreateFrame("Button", "ActionBarAuditFixButton", SpellBookFrame, "UIPanelButtonTemplate")
    fixButton:SetPoint("RIGHT", checkButton, "LEFT", -4, 0)
    fixButton:SetWidth(70)
    fixButton:SetHeight(24)
    fixButton:SetScale(0.9)
    fixButton:SetText("Fix All")
    fixButton:SetScript("OnClick", function()
        FixLowRankSpells()
    end)
    fixButton:SetScript("OnEnter", function(btn)
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Fix Low Rank Spells")
        GameTooltip:AddLine("Upgrade all detected low rank spells to max rank", 1, 1, 1)
        GameTooltip:Show()
    end)
    fixButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

function ActionBarAudit:GetOptionsTable()
    local options = {
        name = "ActionBarAudit",
        type = "group",
        args = {
            generalHeader = {
                order = 1,
                type = "header",
                name = "General Settings",
            },
            minimap = {
                order = 2,
                type = "toggle",
                name = "Show Minimap Button",
                desc = "Toggle minimap button visibility",
                get = function() return not self.db.profile.minimap.hide end,
                set = function(_, value)
                    self.db.profile.minimap.hide = not value
                    if value then
                        LibStub("LibDBIcon-1.0"):Show("ActionBarAudit")
                    else
                        LibStub("LibDBIcon-1.0"):Hide("ActionBarAudit")
                    end
                end,
            },
            actionsHeader = {
                order = 3,
                type = "header",
                name = "Actions",
            },
            checkBtn = {
                order = 4,
                type = "execute",
                name = "Check Hotbars",
                desc = "Scan action bars for low rank spells",
                func = function()
                    print("|cFFFFFF00ActionBarAudit:|r Scanning hotbars...")
                    local count, ignoredCount = ScanHotbars(true)
                    if count == 0 and ignoredCount == 0 then
                        print("|cFFFFFF00ActionBarAudit:|r |cFF00C800No low rank spells found.|r")
                    elseif count == 0 then
                        print(format("|cFFFFFF00ActionBarAudit:|r |cFF00C800No low rank spells found.|r |cFF888888(%d ignored)|r", ignoredCount))
                    else
                        print(format("|cFFFFFF00ActionBarAudit:|r |cFFFF6900%d|r low rank spells found.", count))
                    end
                end,
            },
            fixBtn = {
                order = 5,
                type = "execute",
                name = "Fix All",
                desc = "Upgrade all low rank spells to max rank",
                func = function()
                    ScanHotbars(false)
                    C_Timer.After(0.1, function()
                        FixLowRankSpells()
                    end)
                end,
            },
            ignoreHeader = {
                order = 10,
                type = "header",
                name = "Ignored Spells (won't trigger warnings)",
            },
            ignoreDesc = {
                order = 11,
                type = "description",
                name = "Toggle spells you want to keep at lower ranks (e.g., for mana efficiency).\n",
            },
        },
    }

    -- Dynamically add spell toggles
    GetSpellData()
    local sortedSpells = {}
    for spellName, data in pairs(rankedSpells) do
        tinsert(sortedSpells, { name = spellName, icon = data.icon, maxRank = data.maxRank })
    end
    table.sort(sortedSpells, function(a, b) return a.name < b.name end)

    for i, spell in ipairs(sortedSpells) do
        local key = "spell_" .. i
        options.args[key] = {
            order = 100 + i,
            type = "toggle",
            name = format("|T%s:16|t %s (Rank %d)", spell.icon, spell.name, spell.maxRank),
            desc = format("Ignore %s when checking for low rank spells", spell.name),
            width = "full",
            get = function() return self.db.char.ignoredSpells[spell.name] or false end,
            set = function(_, value)
                if value then
                    self.db.char.ignoredSpells[spell.name] = true
                else
                    self.db.char.ignoredSpells[spell.name] = nil
                end
            end,
        }
    end

    return options
end
