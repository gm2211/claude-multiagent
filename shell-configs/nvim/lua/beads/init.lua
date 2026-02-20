-- Beads Dashboard -- Public API
-- Thin wrapper over state/ui/bd modules

local M = {}

local bd = require("beads.bd")

--- Open the beads dashboard
function M.open()
    -- Check bd is available
    if not bd.is_available() then
        vim.notify("bd command not found. Install beads CLI first.", vim.log.levels.ERROR)
        return
    end

    -- Find beads root
    local root = bd.find_beads_root()
    if not root then
        vim.notify("No beads database found (.beads/ directory)", vim.log.levels.WARN)
        return
    end

    local state = require("beads.state")
    if state.s.open then
        -- Already open -- just focus it
        if state.s.tab and vim.api.nvim_tabpage_is_valid(state.s.tab) then
            vim.api.nvim_set_current_tabpage(state.s.tab)
        end
        return
    end

    state.open(root)
end

--- Close the beads dashboard
function M.close()
    require("beads.state").close()
end

--- Setup leader keymaps (optional, for non-dashboard use)
function M.setup_keymaps()
    vim.keymap.set("n", "<leader>bb", M.open, { desc = "Beads dashboard" })
end

return M
