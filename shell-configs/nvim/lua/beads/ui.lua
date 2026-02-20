-- Layout, rendering, keymaps, and help overlay for beads dashboard
-- 2-pane HORIZONTAL split (top=list, bottom=detail) for narrow Zellij side pane

local M = {}

local ns = vim.api.nvim_create_namespace("beads_dashboard")

--- Status icon characters (unicode)
local STATUS_ICON_CHAR = {
    in_progress = "\u{25D0}",  -- ◐
    blocked = "!!",
    open = "\u{25CB}",         -- ○
    deferred = "\u{25CC}",     -- ◌
    closed = "\u{25CF}",       -- ●
}

--- Highlight groups (Dracula palette)
local function setup_highlights()
    local hi = vim.api.nvim_set_hl
    hi(0, "BdGroupHeader", { bold = true, fg = "#8be9fd" })
    hi(0, "BdSubHeader", { fg = "#6272a4", italic = true })
    hi(0, "BdSelected", { fg = "#f8f8f2", bold = true })
    hi(0, "BdBead", { fg = "#f8f8f2" })
    hi(0, "BdId", { fg = "#6272a4" })
    hi(0, "BdMeta", { fg = "#6272a4", italic = true })
    hi(0, "BdP0", { fg = "#ff5555", bold = true })
    hi(0, "BdP1", { fg = "#ffb86c", bold = true })
    hi(0, "BdP2", { fg = "#f1fa8c" })
    hi(0, "BdP3", { fg = "#8be9fd" })
    hi(0, "BdP4", { fg = "#6272a4" })
    hi(0, "BdInProgress", { fg = "#ffb86c" })
    hi(0, "BdBlocked", { fg = "#ff5555" })
    hi(0, "BdOpen", { fg = "#50fa7b" })
    hi(0, "BdDeferred", { fg = "#6272a4" })
    hi(0, "BdBlockedBy", { fg = "#ff5555", bold = true })
    hi(0, "BdDetailTitle", { bold = true, fg = "#f8f8f2" })
    hi(0, "BdDetailLabel", { fg = "#bd93f9", bold = true })
    hi(0, "BdCommentAuthor", { fg = "#ff79c6", bold = true })
    hi(0, "BdCommentDate", { fg = "#6272a4" })
    hi(0, "BdSeparator", { fg = "#44475a" })
    hi(0, "BdStatusLine", { fg = "#6272a4", italic = true })
end

--- Get the state module (avoids circular require at load time)
local function state()
    return require("beads.state")
end

--- Priority highlight group
---@param priority string
---@return string
local function priority_hl(priority)
    local p = (priority or ""):upper()
    if p == "P0" then return "BdP0" end
    if p == "P1" then return "BdP1" end
    if p == "P2" then return "BdP2" end
    if p == "P3" then return "BdP3" end
    return "BdP4"
end

--- Status highlight group
---@param status string
---@return string
local function status_hl(status)
    local s = (status or ""):lower()
    if s == "in_progress" then return "BdInProgress" end
    if s == "blocked" then return "BdBlocked" end
    if s == "open" then return "BdOpen" end
    if s == "deferred" then return "BdDeferred" end
    return "BdMeta"
end

--- Get status icon character
---@param status string
---@return string
local function status_icon(status)
    local s = (status or ""):lower()
    return STATUS_ICON_CHAR[s] or "?"
end

--- Write lines to a buffer with highlights
---@param buf number
---@param lines string[]
---@param highlights table[]
local function render_buf(buf, lines, highlights)
    if not vim.api.nvim_buf_is_valid(buf) then return end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, hl in ipairs(highlights) do
        pcall(vim.api.nvim_buf_add_highlight, buf, ns, hl.group, hl.line, hl.col_start or 0, hl.col_end or -1)
    end
    vim.bo[buf].modifiable = false
end

--- Set cursor line in a window
---@param win number
---@param line number 1-indexed
local function set_cursor(win, line)
    if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        local line_count = vim.api.nvim_buf_line_count(buf)
        line = math.max(1, math.min(line, line_count))
        pcall(vim.api.nvim_win_set_cursor, win, { line, 0 })
    end
end

--- Truncate string to max width
---@param str string
---@param max_width number
---@return string
local function truncate(str, max_width)
    if not str then return "" end
    if #str <= max_width then return str end
    if max_width <= 3 then return str:sub(1, max_width) end
    return str:sub(1, max_width - 3) .. "..."
end

--- Create the two-pane layout in a new tab
function M.create_layout()
    setup_highlights()
    local s = state().s

    -- Save current tab to return to on close
    s.prev_tab = vim.api.nvim_get_current_tabpage()

    -- New tab
    vim.cmd("tabnew")
    s.tab = vim.api.nvim_get_current_tabpage()

    -- Create 2 scratch buffers
    local function make_buf(name)
        local buf = vim.api.nvim_create_buf(false, true)
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].swapfile = false
        vim.bo[buf].filetype = "beads_dashboard"
        vim.api.nvim_buf_set_name(buf, "beads://" .. name)
        return buf
    end

    s.bufs = {
        list = make_buf("list"),
        detail = make_buf("detail"),
    }

    -- Top window = list (current window in new tab)
    local top_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(top_win, s.bufs.list)

    -- Create bottom split for detail
    vim.cmd("split")
    local bot_win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(bot_win, s.bufs.detail)

    s.wins = { list = top_win, detail = bot_win }

    -- Set heights: roughly 50/50
    local total_height = vim.o.lines - 2  -- subtract for command line + status line
    local list_height = math.floor(total_height * 0.45)
    vim.api.nvim_win_set_height(top_win, list_height)
    -- bottom gets the rest

    -- Window options for list pane
    vim.wo[top_win].number = false
    vim.wo[top_win].relativenumber = false
    vim.wo[top_win].cursorline = true
    vim.wo[top_win].signcolumn = "no"
    vim.wo[top_win].wrap = false
    vim.wo[top_win].winfixheight = true
    vim.wo[top_win].foldcolumn = "0"

    -- Window options for detail pane
    vim.wo[bot_win].number = false
    vim.wo[bot_win].relativenumber = false
    vim.wo[bot_win].cursorline = false
    vim.wo[bot_win].signcolumn = "no"
    vim.wo[bot_win].wrap = true
    vim.wo[bot_win].winfixheight = true
    vim.wo[bot_win].foldcolumn = "0"

    -- Focus list pane
    vim.api.nvim_set_current_win(top_win)

    -- Set keymaps
    M.set_keymaps()
end

--- Close the dashboard layout
function M.close_layout()
    local s = state().s

    -- Close the dashboard tab
    if s.tab and vim.api.nvim_tabpage_is_valid(s.tab) then
        -- Switch to previous tab first, then close the dashboard tab
        if s.prev_tab and vim.api.nvim_tabpage_is_valid(s.prev_tab) then
            vim.api.nvim_set_current_tabpage(s.prev_tab)
        end
        -- Close dashboard tab by closing its windows
        for _, win in pairs(s.wins) do
            if vim.api.nvim_win_is_valid(win) then
                pcall(vim.api.nvim_win_close, win, true)
            end
        end
    end

    s.wins = {}
    s.bufs = {}
    s.tab = nil
end

--- Render the list pane (grouped beads)
---@param s table State object
function M.render_list(s)
    if not s.bufs.list then return end

    local lines = {}
    local highlights = {}
    local items = s.flat_items
    local win_width = 40
    if s.wins.list and vim.api.nvim_win_is_valid(s.wins.list) then
        win_width = vim.api.nvim_win_get_width(s.wins.list)
    end

    -- Track which display line corresponds to which flat_item index
    -- so we can position the cursor correctly
    local cursor_line = nil

    if #items == 0 then
        table.insert(lines, "  (no beads found)")
        table.insert(highlights, { line = 0, group = "BdStatusLine" })
    end

    for idx, item in ipairs(items) do
        if item.type == "header" then
            local icon = status_icon(item.status)
            local label = (item.status or "unknown"):upper()
            local line = "  " .. icon .. " " .. label .. " (" .. item.count .. ")"
            table.insert(lines, line)
            local line_idx = #lines - 1
            table.insert(highlights, { line = line_idx, group = "BdGroupHeader" })

        elseif item.type == "sub_header" then
            local line = "    @" .. (item.owner or "?") .. " (" .. item.count .. ")"
            table.insert(lines, line)
            local line_idx = #lines - 1
            table.insert(highlights, { line = line_idx, group = "BdSubHeader" })

        elseif item.type == "bead" then
            local bead = item.data
            local is_selected = (idx == s.list_cursor)
            local marker = is_selected and "> " or "  "
            local pri = (bead.priority or "P4"):upper()
            local id = bead.id or "?"
            local title = bead.title or bead.summary or ""
            -- Truncate title to fit: "  > P1 id title..."
            local prefix = marker .. pri .. " " .. id .. " "
            local max_title = math.max(5, win_width - #prefix - 1)
            title = truncate(title, max_title)
            local line = prefix .. title
            table.insert(lines, line)

            local line_idx = #lines - 1
            if is_selected then
                cursor_line = #lines  -- 1-indexed for set_cursor
                table.insert(highlights, { line = line_idx, group = "BdSelected" })
            else
                -- Priority highlight on the priority string
                local pri_start = #marker
                local pri_end = pri_start + #pri
                table.insert(highlights, { line = line_idx, col_start = pri_start, col_end = pri_end, group = priority_hl(pri) })
                -- ID highlight
                local id_start = pri_end + 1
                local id_end = id_start + #id
                table.insert(highlights, { line = line_idx, col_start = id_start, col_end = id_end, group = "BdId" })
                -- Rest is BdBead
                table.insert(highlights, { line = line_idx, col_start = id_end + 1, group = "BdBead" })
            end

        elseif item.type == "meta" then
            local updated = item.updated or ""
            local owner = item.owner or ""
            local meta_line = "       "
            if updated ~= "" then
                meta_line = meta_line .. "updated " .. updated
            end
            if owner ~= "" then
                meta_line = meta_line .. " @" .. owner
            end
            table.insert(lines, meta_line)
            local line_idx = #lines - 1
            table.insert(highlights, { line = line_idx, group = "BdMeta" })

        elseif item.type == "blocked_by" then
            local line = "    !! blocked by " .. (item.blocker_id or "?")
            table.insert(lines, line)
            local line_idx = #lines - 1
            table.insert(highlights, { line = line_idx, group = "BdBlockedBy" })

        elseif item.type == "blank" then
            table.insert(lines, "")
        end
    end

    -- Status bar at bottom
    table.insert(lines, "")
    local mode_str = s.group_mode == "assignee" and "[assignee]" or "[status]"
    local closed_str = s.show_closed and " +closed" or ""
    local status = "  " .. #(s.beads or {}) .. " beads " .. mode_str .. closed_str
    table.insert(lines, status)
    table.insert(highlights, { line = #lines - 1, group = "BdStatusLine" })

    render_buf(s.bufs.list, lines, highlights)

    -- Position cursor on the selected bead line
    if cursor_line and s.wins.list then
        set_cursor(s.wins.list, cursor_line)
    end
end

--- Format a date string for display in detail pane
---@param iso_str string|nil
---@return string
local function format_date(iso_str)
    if not iso_str or iso_str == "" then return "" end
    local y, mo, d = iso_str:match("(%d+)-(%d+)-(%d+)")
    if not y then return iso_str end
    local months = {
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    }
    local month_name = months[tonumber(mo)] or mo
    return month_name .. " " .. tonumber(d) .. ", " .. y
end

--- Render the detail pane
---@param s table State object
function M.render_detail(s)
    if not s.bufs.detail then return end

    local lines = {}
    local highlights = {}
    local bead = s.selected_bead

    if not bead then
        table.insert(lines, "  (select a bead to view details)")
        table.insert(highlights, { line = 0, group = "BdStatusLine" })
        render_buf(s.bufs.detail, lines, highlights)
        return
    end

    local win_width = 40
    if s.wins.detail and vim.api.nvim_win_is_valid(s.wins.detail) then
        win_width = vim.api.nvim_win_get_width(s.wins.detail)
    end
    local sep_thick = string.rep("\u{2550}", win_width - 2)  -- ═
    local sep_thin = string.rep("\u{2500}", win_width - 2)   -- ─

    -- Title: ID
    local id = bead.id or "?"
    table.insert(lines, id)
    table.insert(highlights, { line = #lines - 1, group = "BdDetailTitle" })

    -- Title: full title/summary (may wrap naturally since wrap is on)
    local title = bead.title or bead.summary or ""
    table.insert(lines, title)
    table.insert(highlights, { line = #lines - 1, group = "BdDetailTitle" })

    -- Thick separator
    table.insert(lines, sep_thick)
    table.insert(highlights, { line = #lines - 1, group = "BdSeparator" })
    table.insert(lines, "")

    -- Metadata fields
    local fields = {
        { "Status", bead.status or "" },
        { "Priority", bead.priority or "" },
        { "Owner", bead.owner or bead.assignee or "" },
        { "Type", bead.type or bead.kind or "" },
        { "Created", format_date(bead.created_at) },
        { "Updated", format_date(bead.updated_at) },
    }

    for _, field in ipairs(fields) do
        if field[2] ~= "" then
            local label = field[1]
            local value = field[2]
            -- Pad label to 12 chars
            local padded_label = label .. string.rep(" ", math.max(1, 12 - #label))
            local line = padded_label .. value
            table.insert(lines, line)
            local line_idx = #lines - 1
            table.insert(highlights, { line = line_idx, col_start = 0, col_end = #padded_label, group = "BdDetailLabel" })
            -- Status value gets status color
            if label == "Status" then
                table.insert(highlights, { line = line_idx, col_start = #padded_label, group = status_hl(value) })
            elseif label == "Priority" then
                table.insert(highlights, { line = line_idx, col_start = #padded_label, group = priority_hl(value) })
            end
        end
    end

    -- Thin separator
    table.insert(lines, "")
    table.insert(lines, sep_thin)
    table.insert(highlights, { line = #lines - 1, group = "BdSeparator" })
    table.insert(lines, "")

    -- Description
    local description = bead.description or bead.body or ""
    if description ~= "" then
        table.insert(lines, "DESCRIPTION")
        table.insert(highlights, { line = #lines - 1, group = "BdDetailLabel" })
        -- Add description lines (wrap is handled by the window)
        for desc_line in description:gmatch("[^\n]*") do
            table.insert(lines, desc_line)
        end
        table.insert(lines, "")
        table.insert(lines, sep_thin)
        table.insert(highlights, { line = #lines - 1, group = "BdSeparator" })
        table.insert(lines, "")
    end

    -- Dependencies
    local deps = s.deps or { blocks = {}, blocked_by = {} }
    local has_deps = (#(deps.blocks or {}) > 0) or (#(deps.blocked_by or {}) > 0)
    if has_deps then
        table.insert(lines, "DEPENDENCIES")
        table.insert(highlights, { line = #lines - 1, group = "BdDetailLabel" })

        if #(deps.blocks or {}) > 0 then
            table.insert(lines, "Blocks:")
            table.insert(highlights, { line = #lines - 1, group = "BdDetailLabel" })
            for _, dep in ipairs(deps.blocks) do
                local dep_line = "  " .. dep.id
                if dep.status and dep.status ~= "" then
                    dep_line = dep_line .. " (" .. dep.status .. ")"
                end
                if dep.title and dep.title ~= "" then
                    dep_line = dep_line .. " " .. truncate(dep.title, win_width - #dep_line - 2)
                end
                table.insert(lines, dep_line)
                table.insert(highlights, { line = #lines - 1, col_start = 2, col_end = 2 + #dep.id, group = "BdId" })
            end
        end

        if #(deps.blocked_by or {}) > 0 then
            table.insert(lines, "Blocked by:")
            table.insert(highlights, { line = #lines - 1, group = "BdBlockedBy" })
            for _, dep in ipairs(deps.blocked_by) do
                local dep_line = "  " .. dep.id
                if dep.status and dep.status ~= "" then
                    dep_line = dep_line .. " (" .. dep.status .. ")"
                end
                if dep.title and dep.title ~= "" then
                    dep_line = dep_line .. " " .. truncate(dep.title, win_width - #dep_line - 2)
                end
                table.insert(lines, dep_line)
                table.insert(highlights, { line = #lines - 1, col_start = 2, col_end = 2 + #dep.id, group = "BdBlockedBy" })
            end
        else
            table.insert(lines, "Blocked by:")
            table.insert(highlights, { line = #lines - 1, group = "BdDetailLabel" })
            table.insert(lines, "  (none)")
            table.insert(highlights, { line = #lines - 1, group = "BdMeta" })
        end

        table.insert(lines, "")
        table.insert(lines, sep_thin)
        table.insert(highlights, { line = #lines - 1, group = "BdSeparator" })
        table.insert(lines, "")
    end

    -- Comments (newest first)
    local comments = s.comments or {}
    table.insert(lines, "COMMENTS")
    table.insert(highlights, { line = #lines - 1, group = "BdDetailLabel" })

    if #comments == 0 then
        table.insert(lines, "  (no comments)")
        table.insert(highlights, { line = #lines - 1, group = "BdMeta" })
    else
        -- Comments are displayed newest-first with box-drawing borders
        -- Sort by date descending if possible
        local sorted = {}
        for _, c in ipairs(comments) do
            table.insert(sorted, c)
        end
        table.sort(sorted, function(a, b)
            return (a.date or "") > (b.date or "")
        end)

        local comment_sep = string.rep("\u{2500}", math.max(10, win_width - 4))  -- ─

        for _, comment in ipairs(sorted) do
            local author = comment.author or "unknown"
            local date = comment.date or ""
            -- Format date for display
            local display_date = date
            if #date > 10 then
                -- Try to format nicely: "Feb 20 2026 14:32"
                local y, mo, d, h, mi = date:match("(%d+)-(%d+)-(%d+)[T ](%d+):(%d+)")
                if y then
                    local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
                    display_date = (months[tonumber(mo)] or mo) .. " " .. tonumber(d) .. " " .. y .. " " .. h .. ":" .. mi
                end
            end

            -- Top border with date and author
            local header = "\u{250C} " .. display_date .. "  @" .. author
            table.insert(lines, header)
            local line_idx = #lines - 1
            -- Highlight corner
            table.insert(highlights, { line = line_idx, col_start = 0, col_end = #("\u{250C}"), group = "BdSeparator" })
            -- Date
            local date_start = #("\u{250C} ")
            local date_end = date_start + #display_date
            table.insert(highlights, { line = line_idx, col_start = date_start, col_end = date_end, group = "BdCommentDate" })
            -- Author
            local author_start = date_end + 2  -- "  @"
            table.insert(highlights, { line = line_idx, col_start = author_start, group = "BdCommentAuthor" })

            -- Comment body lines
            local body = comment.body or ""
            for body_line in body:gmatch("[^\n]*") do
                local cline = "\u{2502} " .. body_line
                table.insert(lines, cline)
                local bl_idx = #lines - 1
                table.insert(highlights, { line = bl_idx, col_start = 0, col_end = #("\u{2502}"), group = "BdSeparator" })
            end

            -- Bottom border
            table.insert(lines, "\u{2514}" .. comment_sep)
            table.insert(highlights, { line = #lines - 1, group = "BdSeparator" })
        end
    end

    render_buf(s.bufs.detail, lines, highlights)

    -- Scroll detail to top
    if s.wins.detail and vim.api.nvim_win_is_valid(s.wins.detail) then
        set_cursor(s.wins.detail, 1)
    end
end

--- Show help overlay (floating window)
function M.show_help()
    local help_lines = {
        "  Beads Dashboard -- Help",
        "  ========================================",
        "",
        "  NAVIGATION",
        "  j / k             Navigate beads (skip headers)",
        "  J / K             Jump between groups",
        "  g / G             First / last bead",
        "  Tab / S-Tab       Cycle panes (list/detail)",
        "  q                 Close dashboard",
        "  R                 Refresh all data",
        "  ?                 This help",
        "",
        "  VIEWS",
        "  a                 Toggle assignee sub-grouping",
        "  c                 Toggle closed beads",
        "",
        "  ACTIONS",
        "  y                 Yank bead ID to clipboard",
        "  t                 Show dependency tree (floating)",
        "",
        "  Press q or <Esc> to close",
    }

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_lines)

    local width = 0
    for _, line in ipairs(help_lines) do
        if #line > width then width = #line end
    end
    width = math.max(width + 4, 46)
    local height = #help_lines

    local ui_list = vim.api.nvim_list_uis()
    local ui = ui_list[1] or { height = 24, width = 80 }
    local row = math.floor((ui.height - height) / 2)
    local col = math.floor((ui.width - width) / 2)

    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " Help ",
        title_pos = "center",
    })

    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].modifiable = false

    -- Highlights
    local help_ns = vim.api.nvim_create_namespace("bd_help")
    for i, line in ipairs(help_lines) do
        if line:match("Dashboard") then
            vim.api.nvim_buf_add_highlight(buf, help_ns, "Title", i - 1, 0, -1)
        elseif line:match("=====") then
            vim.api.nvim_buf_add_highlight(buf, help_ns, "FloatBorder", i - 1, 0, -1)
        elseif line:match("^  %u%u") then
            vim.api.nvim_buf_add_highlight(buf, help_ns, "Keyword", i - 1, 0, -1)
        end
    end

    local close = function() pcall(vim.api.nvim_win_close, win, true) end
    vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
    vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })
    vim.keymap.set("n", "?", close, { buffer = buf, silent = true })
end

--- Show dependency tree in a floating window
---@param bead_id string
function M.show_dep_tree(bead_id)
    local s = state().s
    if not bead_id or not s.root then return end

    local bd = require("beads.bd")
    bd.dep_tree(s.root, bead_id, function(text, ok)
        if not ok or not text or text == "" then
            vim.notify("No dependency tree available", vim.log.levels.INFO)
            return
        end

        local tree_lines = {}
        for line in text:gmatch("[^\n]*") do
            table.insert(tree_lines, "  " .. line)
        end

        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, tree_lines)

        local width = 0
        for _, line in ipairs(tree_lines) do
            if #line > width then width = #line end
        end
        width = math.max(width + 4, 40)
        local height = math.min(#tree_lines, 20)

        local ui_list = vim.api.nvim_list_uis()
        local ui = ui_list[1] or { height = 24, width = 80 }
        local row = math.floor((ui.height - height) / 2)
        local col = math.floor((ui.width - width) / 2)

        local win = vim.api.nvim_open_win(buf, true, {
            relative = "editor",
            width = width,
            height = height,
            row = row,
            col = col,
            style = "minimal",
            border = "rounded",
            title = " Dependency Tree: " .. bead_id .. " ",
            title_pos = "center",
        })

        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].modifiable = false

        local close = function() pcall(vim.api.nvim_win_close, win, true) end
        vim.keymap.set("n", "q", close, { buffer = buf, silent = true })
        vim.keymap.set("n", "<Esc>", close, { buffer = buf, silent = true })
    end)
end

--- Determine which pane the current window belongs to
---@return string "list" or "detail"
local function current_pane()
    local s = state().s
    local win = vim.api.nvim_get_current_win()
    if win == s.wins.detail then return "detail" end
    return "list"
end

--- Focus a specific pane
---@param name string "list" or "detail"
function M.focus_pane(name)
    local s = state().s
    local win = s.wins[name]
    if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
    end
end

--- Cycle to next/prev pane
---@param delta number 1 or -1
local function cycle_pane(delta)
    local cur = current_pane()
    if cur == "list" then
        M.focus_pane("detail")
    else
        M.focus_pane("list")
    end
end

--- Set buffer-local keymaps for all panes
function M.set_keymaps()
    local s = state().s
    local st = state()

    local all_bufs = { s.bufs.list, s.bufs.detail }

    -- Global navigation keys on all buffers
    for _, buf in ipairs(all_bufs) do
        local opts = { buffer = buf, silent = true, nowait = true }

        -- Pane cycling
        vim.keymap.set("n", "<Tab>", function() cycle_pane(1) end, opts)
        vim.keymap.set("n", "<S-Tab>", function() cycle_pane(-1) end, opts)

        -- Close
        vim.keymap.set("n", "q", function() st.close() end, opts)

        -- Refresh
        vim.keymap.set("n", "R", function() st.refresh_all() end, opts)

        -- Help
        vim.keymap.set("n", "?", function() M.show_help() end, opts)
    end

    -- List pane keymaps
    local list_opts = { buffer = s.bufs.list, silent = true, nowait = true }
    vim.keymap.set("n", "j", function() st.move_cursor(1) end, list_opts)
    vim.keymap.set("n", "k", function() st.move_cursor(-1) end, list_opts)
    vim.keymap.set("n", "J", function() st.move_group(1) end, list_opts)
    vim.keymap.set("n", "K", function() st.move_group(-1) end, list_opts)
    vim.keymap.set("n", "g", function() st.goto_first() end, list_opts)
    vim.keymap.set("n", "G", function() st.goto_last() end, list_opts)
    vim.keymap.set("n", "a", function() st.toggle_group_mode() end, list_opts)
    vim.keymap.set("n", "c", function() st.toggle_closed() end, list_opts)
    vim.keymap.set("n", "y", function() st.yank_id() end, list_opts)
    vim.keymap.set("n", "t", function()
        local bead_id = st.selected_bead_id()
        if bead_id then
            M.show_dep_tree(bead_id)
        end
    end, list_opts)

    -- Detail pane: j/k scroll (built-in works since wrap is on), but also
    -- allow navigating beads from detail pane for convenience
    local detail_opts = { buffer = s.bufs.detail, silent = true, nowait = true }
    vim.keymap.set("n", "j", function()
        -- If in detail pane, scroll down
        local win = s.wins.detail
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_call(win, function()
                vim.cmd("normal! j")
            end)
        end
    end, detail_opts)
    vim.keymap.set("n", "k", function()
        local win = s.wins.detail
        if win and vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_call(win, function()
                vim.cmd("normal! k")
            end)
        end
    end, detail_opts)
    -- Allow navigating beads from detail pane with J/K
    vim.keymap.set("n", "J", function() st.move_cursor(1) end, detail_opts)
    vim.keymap.set("n", "K", function() st.move_cursor(-1) end, detail_opts)
    vim.keymap.set("n", "y", function() st.yank_id() end, detail_opts)
    vim.keymap.set("n", "t", function()
        local bead_id = st.selected_bead_id()
        if bead_id then
            M.show_dep_tree(bead_id)
        end
    end, detail_opts)

    -- Auto-close if any dashboard window is closed externally
    vim.api.nvim_create_autocmd("WinClosed", {
        callback = function(ev)
            if not s.open then return end
            local closed_win = tonumber(ev.match)
            if closed_win == s.wins.list or closed_win == s.wins.detail then
                vim.schedule(function()
                    st.close()
                end)
            end
        end,
    })
end

return M
