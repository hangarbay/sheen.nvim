# sheen.nvim

Neovim integration for sheen, the terminal HTML renderer.

## Features

- **Floating preview** of the current HTML file, rendered by sheen (vertical pane optional)
- **Auto-open** HTML files with the preview pane, without stealing focus
- **Scrollable & searchable** -- the preview is a real buffer: mouse-wheel it, `/` search it, yank from it
- **True-color ANSI rendering** -- sheen's output is snapshotted with its ANSI styling intact
- **Width-aware rendering** -- sheen re-renders at the pane width when you resize it
- **`q` to close** the preview window
- **Optional file argument** -- preview any HTML file from anywhere
- **Zero dependencies** -- no toggleterm, just sheen on your PATH

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "hangarbay/sheen.nvim",
  keys = {
    { "<leader>ch", desc = "Preview HTML in sheen" },
  },
  opts = {},
}
```

## Configuration

All options with their defaults:

```lua
require("sheen").setup({
  cmd = "sheen",             -- path to the sheen binary
  direction = "float",       -- "float" centered popup, or "vertical" right pane
  width_ratio = 0.8,         -- float width / pane width as a ratio of columns
  height_ratio = 0.85,       -- float height as a ratio of lines
  auto_open = true,          -- open the preview whenever an HTML file loads
  style = nil,               -- sheen style: "dark", "light", "notty", "ascii" (nil follows &background)
  keymaps = {
    preview = "<leader>ch",  -- open preview for current file
    close = "q",             -- close the preview window
  },
})
```

## Usage

| Mapping      | Mode       | Action                      |
| ------------ | ---------- | --------------------------- |
| `<leader>ch` | normal     | Preview current HTML file   |
| `q`          | in preview | Close the preview           |

Or run `:Sheen [path]` to preview a specific file.

## License

[MIT](LICENSE)
