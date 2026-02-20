-- bd CLI wrappers for beads dashboard
-- All shell operations go through this module

local M = {}

local uv = vim.uv or vim.loop

--- Async helper: run a command and call cb(stdout, ok) on vim.schedule
---@param cmd string[]
---@param cwd string
---@param cb fun(stdout: string, ok: boolean)
local function async_cmd(cmd, cwd, cb)
    vim.system(cmd, { text = true, cwd = cwd }, function(obj)
        vim.schedule(function()
            cb(obj.stdout or "", obj.code == 0)
        end)
    end)
end

--- Find the beads root directory by walking up from cwd looking for .beads/
---@param path? string Starting path (defaults to cwd)
---@return string|nil
function M.find_beads_root(path)
    path = path or vim.fn.getcwd()
    local current = path
    while current ~= "/" do
        local stat = uv.fs_stat(current .. "/.beads")
        if stat and stat.type == "directory" then
            return current
        end
        current = vim.fn.fnamemodify(current, ":h")
    end
    return nil
end

--- Parse JSON safely, returning nil on failure
---@param str string
---@return table|nil
local function parse_json(str)
    if not str or str == "" then
        return nil
    end
    local ok, data = pcall(vim.json.decode, str)
    if ok and data then
        return data
    end
    return nil
end

--- List beads (async)
--- Calls bd list --json --limit 0, optionally with --all for closed beads
---@param root string Beads root directory
---@param opts table {all: boolean}
---@param cb fun(data: table|nil, ok: boolean)
function M.list_beads(root, opts, cb)
    local cmd = { "bd", "list", "--json", "--limit", "0" }
    if opts and opts.all then
        table.insert(cmd, "--all")
    end
    async_cmd(cmd, root, function(stdout, ok)
        if not ok then
            cb(nil, false)
            return
        end
        local data = parse_json(stdout)
        cb(data, data ~= nil)
    end)
end

--- Show a single bead (async)
---@param root string
---@param id string Bead ID
---@param cb fun(data: table|nil, ok: boolean)
function M.show_bead(root, id, cb)
    async_cmd({ "bd", "show", id, "--json" }, root, function(stdout, ok)
        if not ok then
            cb(nil, false)
            return
        end
        local data = parse_json(stdout)
        cb(data, data ~= nil)
    end)
end

--- Get comments for a bead (async)
--- Comments may not support --json, so parse text output
---@param root string
---@param id string
---@param cb fun(data: table[], ok: boolean)
function M.comments(root, id, cb)
    async_cmd({ "bd", "comments", id }, root, function(stdout, ok)
        if not ok then
            cb({}, false)
            return
        end
        -- Try JSON first
        local json_data = parse_json(stdout)
        if json_data then
            cb(json_data, true)
            return
        end
        -- Parse text output: lines like "2026-02-20 14:32 @author: body..."
        -- or block format. We try a flexible parse.
        local comments = {}
        local current = nil
        for line in stdout:gmatch("[^\n]+") do
            -- Try to match a comment header: date/time + author
            local date, author, body = line:match("^(%d%d%d%d%-%d%d%-%d%d[T ]%d%d:%d%d[:%d]*)%s+@(%S+)%s*(.*)")
            if not date then
                -- Alternative: "## @author - date" format
                date, author = line:match("^##%s+@(%S+)%s+%-?%s*(.+)")
                if date then
                    -- swap: in this pattern author came first
                    date, author = author, date
                end
            end
            if date and author then
                if current then
                    table.insert(comments, current)
                end
                current = { date = date, author = author, body = body or "" }
            elseif current then
                -- Continuation line
                if current.body == "" then
                    current.body = line
                else
                    current.body = current.body .. "\n" .. line
                end
            end
        end
        if current then
            table.insert(comments, current)
        end
        cb(comments, true)
    end)
end

--- List dependencies for a bead (async)
---@param root string
---@param id string
---@param cb fun(data: table, ok: boolean)
function M.dep_list(root, id, cb)
    async_cmd({ "bd", "dep", "list", id }, root, function(stdout, ok)
        if not ok then
            cb({ blocks = {}, blocked_by = {} }, false)
            return
        end
        -- Try JSON first
        local json_data = parse_json(stdout)
        if json_data then
            cb(json_data, true)
            return
        end
        -- Parse text output
        local deps = { blocks = {}, blocked_by = {} }
        local section = nil
        for line in stdout:gmatch("[^\n]+") do
            local trimmed = vim.trim(line)
            if trimmed:lower():match("^blocks") then
                section = "blocks"
            elseif trimmed:lower():match("^blocked") then
                section = "blocked_by"
            elseif section and trimmed ~= "" and trimmed ~= "(none)" then
                -- Parse "id (status) title..."
                local dep_id, dep_status, dep_title = trimmed:match("^(%S+)%s+%((%S+)%)%s+(.*)")
                if not dep_id then
                    dep_id = trimmed:match("^(%S+)")
                    dep_status = ""
                    dep_title = ""
                end
                if dep_id then
                    table.insert(deps[section], {
                        id = dep_id,
                        status = dep_status or "",
                        title = dep_title or "",
                    })
                end
            end
        end
        cb(deps, true)
    end)
end

--- List blocked beads (async)
---@param root string
---@param cb fun(data: table|nil, ok: boolean)
function M.blocked(root, cb)
    async_cmd({ "bd", "blocked", "--json" }, root, function(stdout, ok)
        if not ok then
            cb(nil, false)
            return
        end
        local data = parse_json(stdout)
        cb(data, data ~= nil)
    end)
end

--- Get dependency tree output (async, text)
---@param root string
---@param id string
---@param cb fun(text: string, ok: boolean)
function M.dep_tree(root, id, cb)
    async_cmd({ "bd", "dep", "tree", id }, root, function(stdout, ok)
        cb(stdout, ok)
    end)
end

--- Check if bd is available
---@return boolean
function M.is_available()
    return vim.fn.executable("bd") == 1
end

return M
