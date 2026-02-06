local addonName, addon = ...
local ActionBarAudit = LibStub("AceAddon-3.0"):NewAddon(addon, addonName, "AceEvent-3.0", "AceConsole-3.0")
_G["ActionBarAudit"] = ActionBarAudit

local defaults = {
    profile = {
        minimap = { hide = false },
    },
}

-- Store audit results
local lastAuditResults = {}
local spellData = {}

-- Default action bar button names
local defaultBars = {"Action", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarRight", "MultiBarLeft"}

-- Build spell data from spellbook
local function GetSpellData()
    spellData = {}
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, numSlots = GetSpellTabInfo(tab)
        for i = offset + 1, offset + numSlots do
            local spellName, spellSubText = GetSpellBookItemName(i, BOOKTYPE_SPELL)
            if spellName and spellSubText then
                local rank = strmatch(spellSubText, "%d+")
                if rank then
                    rank = tonumber(rank)
                    if rank and rank > 0 and (not spellData[spellName] or rank > spellData[spellName].rank) then
                        spellData[spellName] = { rank = rank, bookIndex = i }
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
                        end)
                    end
                end
            end
        end
    end

    return count
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
    elseif input == "fix" then
        FixLowRankSpells()
    else
        self:Print("Scanning hotbars...")
        local count = ScanHotbars(true)
        if count == 0 then
            self:Print("|cFF00C800No low rank spells found.|r")
        else
            self:Print(format("|cFFFF6900%d|r low rank spells found. Use /aba fix to upgrade.", count))
        end
    end
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
                ScanHotbars(true)
            elseif button == "RightButton" then
                OpenOptions()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("ActionBarAudit")
            tt:AddLine("|cff00ff00Left-click|r check | |cff00ff00Right-click|r options", 1, 1, 1)
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
        local count = ScanHotbars(true)
        if count == 0 then
            print("|cFFFFFF00ActionBarAudit:|r |cFF00C800No low rank spells found.|r")
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
    return {
        name = "ActionBarAudit",
        type = "group",
        args = {
            minimap = {
                order = 1,
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
        },
    }
end
