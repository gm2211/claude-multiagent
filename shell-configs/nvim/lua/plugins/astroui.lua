---@type LazySpec
return {
  "AstroNvim/astroui",
  ---@type AstroUIOpts
  opts = {
    colorscheme = "catppuccin",
    highlights = {
      init = {
        -- Catppuccin mocha tabline overrides
        TabLineFill = { bg = "#181825" }, -- mantle
        TabLine = { fg = "#a6adc8", bg = "#313244" }, -- subtext0 on surface0
        TabLineSel = { fg = "#b4befe", bg = "#45475a", bold = true }, -- lavender on surface1
      },
    },
  },
}
