std = "lua51"
codes = true
quiet = 1
max_line_length = false
exclude_files = { ".release/", "libs/", "Libs/" }
unused_args = false

globals = { "ActionBarAudit", "_G" }

read_globals = {
    "LibStub", "CreateFrame", "UIParent", "GameTooltip", "Settings",
    "GetActionInfo", "GetBindingKey", "GetTime",
    "InterfaceOptionsFrame_OpenToCategory",
    "pairs", "ipairs", "select", "string", "table", "math", "format", "date",
    "tonumber", "tostring", "type", "unpack",
}
