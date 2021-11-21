# telescope-file-browser.nvim

`telescope-file-browser.nvim` is a file browser extension for telescope.nvim. It supports synchronized creation, deletion, renaming, and moving of files and folders powered by telescope.nvim and plenary.nvim.

**The project is currently unstable. Please see [roadmap](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/3) to keep informed with the status of the project.**

# Demo

The demo shows multi-selecting files across various folders and then moving them to the lastly entered directory.

![Demo](./media/fb-demo.gif)

# Installation

### packer 

```lua
use { "nvim-telescope/telescope-file-browser.nvim" }
```

### Vim-Plug 

```viml
Plug "nvim-telescope/telescope-file-browser.nvim"
```

# Setup and Configuration

You configure the `telescope-file-browser` like any other `telescope.nvim` picker. See `:h telescope-file-browser.picker` for the full set of options dedicated to the picker. In addition, you of course can map `theme` and `mappings` as you are accustomed to from `telescope.nvim`.

```lua
-- You don't need to set any of these options.
-- IMPORTANT!: this is only a showcase of how you can set default options!
require("telescope").setup {
  extensions = {
    file_browser = {
      theme = "ivy",
      mappings = {
        ["i"] = {
          -- your custom insert mode mappings
        },
        ["n"] = {
          -- your custom normal mode mappings
        },
      },
    },
  },
}
-- To get telescope-file-browser loaded and working with telescope,
-- you need to call load_extension, somewhere after setup function:
require("telescope").load_extension "file_browser"
```

# Usage

You can use the `telescope-file-browser` as follows:

```lua
vim.api.nvim_set_keymap(
  "n",
  "<space>fb",
  "<cmd>lua require 'telescope'.extensions.file_browser.file_browser()<CR>",
  {noremap = true}
)
```

## Mappings

| Insert / Normal  | Action                                               |
|------------------|------------------------------------------------------|
| `<C-f>/f`        | Toggle between file and folder browser               |
| `<C-y>/y`        | Copy (multi-selected) files or folders to cwd        |
| `<C-d>/dd`       | Delete (multi-selected) files or folders             |
| `<C-r>/r`        | Rename (multi-selected) files                        |
| `--/m`           | Move multi-selected files to cwd                     |
| `<C-h>/h`        | Toggle hidden files                                  |
| `<C-o>/o`        | Open file with default system application            |

Copying and moving files first requires you to multi-select your files and folders and then moving to the target directory to copy and move the selections to (cf. [demo](#demo)). Renaming multi-selected files or folders launches batch renaming, which enables to user to rename or move multiple files at once, as moving files is analogous to renaming the file.

## Documentation

The documentation of `telescope-file-browser` can be be accessed from within Neovim via:

`:h telescope-file-browser.nvim`\
`:h telescope-file-browser.picker`\
`:h telescope-file-browser.actions`\
`:h telescope-file-browser.finders`


<!-- # Contributing -->

<!-- Contributions are very welcome! -->

<!-- ## Submitting a new feature -->

<!-- Thanks for considering to contribute to `telescope-file-browser.nvim`! --> 
