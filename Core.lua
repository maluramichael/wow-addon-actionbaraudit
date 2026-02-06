local addonName, addon = ...
local ActionBarAudit = LibStub("AceAddon-3.0"):NewAddon(addon, addonName, "AceEvent-3.0", "AceConsole-3.0")
_G["ActionBarAudit"] = ActionBarAudit

local defaults = {
    profile = {
        minimap = { hide = false },
    },
}

function ActionBarAudit:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("ActionBarAuditDB", defaults, true)
    self:RegisterChatCommand("aba", "SlashCommand")
    self:RegisterChatCommand("actionbaraudit", "SlashCommand")
    LibStub("AceConfig-3.0"):RegisterOptionsTable(addonName, self:GetOptionsTable())
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(addonName, "ActionBarAudit")
    self:SetupMinimapButton()
end

function ActionBarAudit:OnEnable()
end

function ActionBarAudit:SlashCommand(input)
    if input == "config" or input == "options" then
        self:OpenOptions()
    else
        self:RunAudit()
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
                self:RunAudit()
            elseif button == "RightButton" then
                OpenOptions()
            end
        end,
        OnTooltipShow = function(tt)
            tt:AddLine("ActionBarAudit")
            tt:AddLine("|cff00ff00Left-click|r audit | |cff00ff00Right-click|r options", 1, 1, 1)
        end,
    })
    if not self.db.profile.minimap then self.db.profile.minimap = { hide = false } end
    LDBIcon:Register("ActionBarAudit", dataObj, self.db.profile.minimap)
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

function ActionBarAudit:RunAudit()
    self:Print("Running action bar audit...")

    local emptySlots = 0
    local noKeybind = 0
    local totalSlots = 0

    for bar = 1, 6 do
        for slot = 1, 12 do
            local actionSlot = (bar - 1) * 12 + slot
            totalSlots = totalSlots + 1

            local actionType, id = GetActionInfo(actionSlot)
            local hasAction = actionType ~= nil

            if not hasAction then
                emptySlots = emptySlots + 1
            else
                local key = GetBindingKey("ACTIONBUTTON" .. slot)
                if bar == 1 and not key then
                    noKeybind = noKeybind + 1
                end
            end
        end
    end

    self:Print(format("Total slots: %d", totalSlots))
    self:Print(format("Empty slots: %d", emptySlots))
    self:Print(format("Main bar abilities without keybind: %d", noKeybind))
end
