-- Central state object for beads dashboard
-- Manages data, cursor positions, pane coordination, polling

local bd = require("beads.bd")

local M = {}

--- The global dashboard state
---@class BdState
M.s = {
    open = false,
    root = nil,            -- beads root dir
    beads = {},            -- flat list from bd list
    blocked_map = {},      -- id -> list of blockers {id, ...}
    flat_items = {},       -- flattened: {type="header"|"sub_header"|"bead"|"meta"|"blocked_by"|"blank", ...}
    selected_bead = nil,   -- from bd show (full detail)
    comments = {},         -- from bd comments
    deps = {},             -- from bd dep list
    list_cursor = 1,       -- index into flat_items (bead items only)
    detail_scroll = 0,
    group_mode = "status", -- "status" | "assignee"
    show_closed = false,
    prev_tab = nil,
    tab = nil,
    wins = {},
    bufs = {},
    generation = 0,
    timer = nil,
}

--- Priority sort order (lower = higher priority)
local PRIORITY_ORDER = {
    P0 = 0, P1 = 1, P2 = 2, P3 = 3, P4 = 4,
    p0 = 0, p1 = 1, p2 = 2, p3 = 3, p4 = 4,
}

--- Status group ordering
local STATUS_ORDER = {
    in_progress = 1, IN_PROGRESS = 1,
    blocked = 2, BLOCKED = 2,
    open = 3, OPEN = 3,
    deferred = 4, DEFERRED = 4,
    closed = 5, CLOSED = 5,
}

--- Convert ISO 8601 timestamp to relative time string
---@param iso_str string|nil
---@return string
local function relative_time(iso_str)
    if not iso_str or iso_str == "" then
        return ""
    end
    -- Parse ISO 8601: "2026-02-20T14:32:00Z" or "2026-02-20 14:32:00"
    local y, mo, d, h, mi, s = iso_str:match("(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):?(%d*)")
    if not y then
        -- Try date-only: "2026-02-20"
        y, mo, d = iso_str:match("(%d+)-(%d+)-(%d+)")
        h, mi, s = 0, 0, 0
    end
    if not y then
        return iso_str
    end
    s = tonumber(s) or 0
    local then_ts = os.time({
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = s,
    })
    local now = os.time()
    local diff = now - then_ts
    if diff < 0 then diff = 0 end

    if diff < 60 then
        return "just now"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. "m ago"
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. "h ago"
    elseif diff < 604800 then
        return math.floor(diff / 86400) .. "d ago"
    elseif diff < 2592000 then
        return math.floor(diff / 604800) .. "w ago"
    elseif diff < 31536000 then
        return math.floor(diff / 2592000) .. "mo ago"
    else
        return math.floor(diff / 31536000) .. "y ago"
    end
end

-- Expose for use by ui.lua
M.relative_time = relative_time

--- Get the bead at the current list cursor (from flat_items)
---@return table|nil
function M.selected_bead_item()
    local item = M.s.flat_items[M.s.list_cursor]
    if item and item.type == "bead" then
        return item.data
    end
    return nil
end

--- Find the bead ID at the current cursor
---@return string|nil
function M.selected_bead_id()
    local bead = M.selected_bead_item()
    if bead then
        return bead.id
    end
    return nil
end

--- Initialize dashboard state and populate data
---@param root string
function M.open(root)
    local ui = require("beads.ui")
    M.s.root = root
    M.s.open = true
    M.s.generation = 0
    M.s.list_cursor = 1
    M.s.detail_scroll = 0
    M.s.group_mode = "status"
    M.s.show_closed = false
    M.s.beads = {}
    M.s.flat_items = {}
    M.s.selected_bead = nil
    M.s.comments = {}
    M.s.deps = {}
    M.s.blocked_map = {}

    -- Create layout
    ui.create_layout()

    -- Load data
    M.refresh_all()

    -- Start poll timer
    M.start_poll_timer()
end

--- Close the dashboard
function M.close()
    if not M.s.open then return end
    M.s.open = false
    M.s.generation = M.s.generation + 1

    -- Stop timer
    if M.s.timer then
        M.s.timer:stop()
        M.s.timer:close()
        M.s.timer = nil
    end

    local ui = require("beads.ui")
    ui.close_layout()
end

--- Refresh all data: beads list + blocked info
function M.refresh_all()
    if not M.s.open then return end

    M.s.generation = M.s.generation + 1
    local gen = M.s.generation

    local list_opts = {}
    if M.s.show_closed then
        list_opts.all = true
    end

    -- Load beads list
    bd.list_beads(M.s.root, list_opts, function(data, ok)
        if gen ~= M.s.generation then return end
        if ok and data then
            M.s.beads = data
        end
        -- Also load blocked info
        bd.blocked(M.s.root, function(blocked_data, blocked_ok)
            if gen ~= M.s.generation then return end
            if blocked_ok and blocked_data then
                -- Build blocked_map: bead_id -> list of blocker ids
                M.s.blocked_map = {}
                if type(blocked_data) == "table" then
                    for _, entry in ipairs(blocked_data) do
                        if entry.id and entry.blocked_by then
                            M.s.blocked_map[entry.id] = entry.blocked_by
                        end
                    end
                end
            end
            M.rebuild_groups()
            local ui = require("beads.ui")
            if M.s.open then
                ui.render_list(M.s)
            end
            -- Load detail for first bead if we have one
            M.refresh_detail()
        end)
    end)
end

--- Rebuild flat_items from beads grouped by status (and optionally assignee)
function M.rebuild_groups()
    local items = {}
    local beads = M.s.beads or {}

    -- Group beads by normalized status
    local groups = {}
    local status_names = {}

    for _, bead in ipairs(beads) do
        local status = (bead.status or "open"):lower()
        if not groups[status] then
            groups[status] = {}
            table.insert(status_names, status)
        end
        table.insert(groups[status], bead)
    end

    -- Sort status groups by defined order
    table.sort(status_names, function(a, b)
        local oa = STATUS_ORDER[a] or 99
        local ob = STATUS_ORDER[b] or 99
        return oa < ob
    end)

    -- Sort beads within each group by priority then updated_at
    for _, group in pairs(groups) do
        table.sort(group, function(a, b)
            local pa = PRIORITY_ORDER[(a.priority or "P4")] or 4
            local pb = PRIORITY_ORDER[(b.priority or "P4")] or 4
            if pa ~= pb then return pa < pb end
            -- Sort by updated_at descending (newest first)
            return (a.updated_at or "") > (b.updated_at or "")
        end)
    end

    -- Build flat_items
    for i, status in ipairs(status_names) do
        local group = groups[status]

        -- Add blank separator between groups (not before first)
        if i > 1 then
            table.insert(items, { type = "blank" })
        end

        -- Group header
        table.insert(items, {
            type = "header",
            status = status,
            count = #group,
        })

        if M.s.group_mode == "assignee" then
            -- Sub-group by owner within this status group
            local by_owner = {}
            local owner_names = {}
            for _, bead in ipairs(group) do
                local owner = bead.owner or bead.assignee or "(unassigned)"
                if not by_owner[owner] then
                    by_owner[owner] = {}
                    table.insert(owner_names, owner)
                end
                table.insert(by_owner[owner], bead)
            end
            table.sort(owner_names)

            for _, owner in ipairs(owner_names) do
                local owner_beads = by_owner[owner]
                table.insert(items, {
                    type = "sub_header",
                    owner = owner,
                    count = #owner_beads,
                })
                for _, bead in ipairs(owner_beads) do
                    table.insert(items, { type = "bead", data = bead })
                    -- Meta line (second line of bead)
                    table.insert(items, {
                        type = "meta",
                        data = bead,
                        updated = relative_time(bead.updated_at),
                        owner = bead.owner or bead.assignee or "",
                    })
                    -- Show blocked_by if this bead is blocked
                    local blockers = M.s.blocked_map[bead.id]
                    if blockers and #blockers > 0 then
                        for _, blocker_id in ipairs(blockers) do
                            table.insert(items, {
                                type = "blocked_by",
                                blocker_id = blocker_id,
                            })
                        end
                    end
                end
            end
        else
            -- Simple: just list beads under status header
            for _, bead in ipairs(group) do
                table.insert(items, { type = "bead", data = bead })
                -- Meta line
                table.insert(items, {
                    type = "meta",
                    data = bead,
                    updated = relative_time(bead.updated_at),
                    owner = bead.owner or bead.assignee or "",
                })
                -- Show blocked_by if this bead is blocked
                local blockers = M.s.blocked_map[bead.id]
                if blockers and #blockers > 0 then
                    for _, blocker_id in ipairs(blockers) do
                        table.insert(items, {
                            type = "blocked_by",
                            blocker_id = blocker_id,
                        })
                    end
                end
            end
        end
    end

    M.s.flat_items = items

    -- Ensure cursor points to a bead item
    M.clamp_cursor()
end

--- Clamp list cursor to a valid bead item
function M.clamp_cursor()
    local items = M.s.flat_items
    if #items == 0 then
        M.s.list_cursor = 1
        return
    end

    -- If current cursor is on a bead, keep it
    local cur = items[M.s.list_cursor]
    if cur and cur.type == "bead" then
        return
    end

    -- Find the nearest bead item
    -- Search forward first, then backward
    for i = M.s.list_cursor, #items do
        if items[i].type == "bead" then
            M.s.list_cursor = i
            return
        end
    end
    for i = M.s.list_cursor, 1, -1 do
        if items[i].type == "bead" then
            M.s.list_cursor = i
            return
        end
    end
    -- No beads found
    M.s.list_cursor = 1
end

--- Refresh detail pane for the currently selected bead
function M.refresh_detail()
    local bead_id = M.selected_bead_id()
    if not bead_id then
        M.s.selected_bead = nil
        M.s.comments = {}
        M.s.deps = { blocks = {}, blocked_by = {} }
        local ui = require("beads.ui")
        if M.s.open then ui.render_detail(M.s) end
        return
    end

    M.s.generation = M.s.generation + 1
    local gen = M.s.generation

    -- Load bead detail
    bd.show_bead(M.s.root, bead_id, function(data, ok)
        if gen ~= M.s.generation then return end
        if ok and data then
            M.s.selected_bead = data
        end
        local ui = require("beads.ui")
        if M.s.open then ui.render_detail(M.s) end
    end)

    -- Load comments
    bd.comments(M.s.root, bead_id, function(data, ok)
        if gen ~= M.s.generation then return end
        if ok then
            M.s.comments = data or {}
        end
        local ui = require("beads.ui")
        if M.s.open then ui.render_detail(M.s) end
    end)

    -- Load deps
    bd.dep_list(M.s.root, bead_id, function(data, ok)
        if gen ~= M.s.generation then return end
        if ok then
            M.s.deps = data or { blocks = {}, blocked_by = {} }
        end
        local ui = require("beads.ui")
        if M.s.open then ui.render_detail(M.s) end
    end)
end

--- Move cursor by delta, skipping non-bead items, trigger refresh_detail
---@param delta number +1 or -1
function M.move_cursor(delta)
    local items = M.s.flat_items
    if #items == 0 then return end

    local cursor = M.s.list_cursor
    local start = cursor

    -- Move in direction, skipping non-bead items
    repeat
        cursor = cursor + delta
        -- Clamp (don't wrap)
        if cursor < 1 then cursor = 1; break end
        if cursor > #items then cursor = #items; break end
    until items[cursor].type == "bead"

    -- Only update if we landed on a bead
    if items[cursor] and items[cursor].type == "bead" then
        M.s.list_cursor = cursor
    end

    local ui = require("beads.ui")
    if M.s.open then
        ui.render_list(M.s)
    end

    -- Refresh detail if cursor changed
    if M.s.list_cursor ~= start then
        M.refresh_detail()
    end
end

--- Jump to next/prev group header
---@param delta number +1 or -1
function M.move_group(delta)
    local items = M.s.flat_items
    if #items == 0 then return end

    local cursor = M.s.list_cursor

    -- Find current group header (search backward from cursor)
    local current_header = nil
    for i = cursor, 1, -1 do
        if items[i].type == "header" then
            current_header = i
            break
        end
    end

    if delta > 0 then
        -- Find next header after current_header
        local start = (current_header or cursor) + 1
        for i = start, #items do
            if items[i].type == "header" then
                -- Find first bead after this header
                for j = i + 1, #items do
                    if items[j].type == "bead" then
                        M.s.list_cursor = j
                        local ui = require("beads.ui")
                        if M.s.open then ui.render_list(M.s) end
                        M.refresh_detail()
                        return
                    elseif items[j].type == "header" then
                        break
                    end
                end
            end
        end
    else
        -- Find prev header before current_header
        if not current_header or current_header <= 1 then return end
        for i = current_header - 1, 1, -1 do
            if items[i].type == "header" then
                -- Find first bead after this header
                for j = i + 1, #items do
                    if items[j].type == "bead" then
                        M.s.list_cursor = j
                        local ui = require("beads.ui")
                        if M.s.open then ui.render_list(M.s) end
                        M.refresh_detail()
                        return
                    elseif items[j].type == "header" then
                        break
                    end
                end
            end
        end
    end
end

--- Toggle between status and assignee grouping
function M.toggle_group_mode()
    if M.s.group_mode == "status" then
        M.s.group_mode = "assignee"
    else
        M.s.group_mode = "status"
    end
    M.rebuild_groups()
    local ui = require("beads.ui")
    if M.s.open then
        ui.render_list(M.s)
    end
end

--- Toggle showing closed beads
function M.toggle_closed()
    M.s.show_closed = not M.s.show_closed
    M.refresh_all()
end

--- Start the poll timer (every 10 seconds)
function M.start_poll_timer()
    if M.s.timer then
        M.s.timer:stop()
        M.s.timer:close()
    end
    local timer = (vim.uv or vim.loop).new_timer()
    M.s.timer = timer
    timer:start(10000, 10000, vim.schedule_wrap(function()
        if M.s.open then
            M.refresh_all()
        else
            timer:stop()
            timer:close()
            M.s.timer = nil
        end
    end))
end

--- Yank the selected bead ID to clipboard
function M.yank_id()
    local bead_id = M.selected_bead_id()
    if not bead_id then return end
    vim.fn.setreg("+", bead_id)
    vim.notify("Yanked: " .. bead_id)
end

--- Jump to first bead
function M.goto_first()
    for i, item in ipairs(M.s.flat_items) do
        if item.type == "bead" then
            M.s.list_cursor = i
            local ui = require("beads.ui")
            if M.s.open then ui.render_list(M.s) end
            M.refresh_detail()
            return
        end
    end
end

--- Jump to last bead
function M.goto_last()
    for i = #M.s.flat_items, 1, -1 do
        if M.s.flat_items[i].type == "bead" then
            M.s.list_cursor = i
            local ui = require("beads.ui")
            if M.s.open then ui.render_list(M.s) end
            M.refresh_detail()
            return
        end
    end
end

return M
