---@type LazySpec
return {
  "sindrets/diffview.nvim",
  opts = {
    enhanced_diff_hl = true,
    view = {
      default = { layout = "diff2_horizontal" },
      merge_tool = { layout = "diff3_horizontal" },
    },
    file_panel = {
      listing_style = "tree",
      win_config = { width = 35 },
    },
    hooks = {
      diff_buf_read = function()
        vim.opt_local.wrap = false
        vim.opt_local.list = false
        -- Ensure treesitter highlighting is active in diff buffers
        if pcall(require, "nvim-treesitter") then vim.cmd "TSBufEnable highlight" end
      end,
    },
  },
}
