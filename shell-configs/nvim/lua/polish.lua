-- This will run last in the setup process.

-- Clean diff filler lines (no dashes)
vim.opt.fillchars:append({ diff = " " })

-- Auto-prompt Diffview when opening nvim in a git repo with local changes
vim.api.nvim_create_autocmd("UIEnter", {
  callback = function()
    if vim.fn.argc() > 0 then
      return
    end
    local output = vim.fn.system("git status --porcelain 2>/dev/null")
    if vim.v.shell_error ~= 0 or output == "" then
      return
    end
    vim.defer_fn(function()
      vim.cmd("redraw")
      local choice = vim.fn.confirm("Local changes detected. Open Diffview?", "&Yes\n&No", 2)
      if choice == 1 then
        vim.cmd("DiffviewOpen")
      end
    end, 200)
  end,
})
