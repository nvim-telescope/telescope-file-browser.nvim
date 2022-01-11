# telescope-file-browser.nvim

`telescope-file-browser.nvim` is a file browser extension for telescope.nvim. It supports synchronized creation, deletion, renaming, and moving of files and folders powered by telescope.nvim and plenary.nvim.

**The project is currently unstable. Please see [roadmap](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/3) to keep informed with the status of the project.**

# Demo

The demo shows multi-selecting files across various folders and then moving them to the lastly entered directory.

![Demo](./media/fb-demo.gif)

# Installation

## packer 

```lua
use { "nvim-telescope/telescope-file-browser.nvim" }
```

## Vim-Plug 

```viml
Plug "nvim-telescope/telescope-file-browser.nvim"
```

## Optional Dependencies

`telescope-file-browser` optionally levers [fd](https://github.com/sharkdp/fd) if installed primarily for more async but also generally faster file and folder browsing, which is most noticeable in larger repositories.

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

## Documentation

The documentation of `telescope-file-browser` can be be accessed from within Neovim via:

|**What**       |  **Vimdoc**                        | **Comment**                  |
|---------------|------------------------------------|------------------------------|
|Introduction   |   `:h telescope-file-browser.nvim` |                              |
|Picker options |   `:h fb_picker.file_browser`      | For `extension` setup        |
|Actions        |   `:h fb_actions`                  | Explore mappable actions     |
|Finders        |   `:h fb_finders`                  | Lower level for customization|

The documentation can be easily accessed/explored via `:Telescope help_tags`. This, for instance, nicely lists available actions from within vimdocs. Very much recommended!

## Launching

You can use the `telescope-file-browser` as follows:

```lua
vim.api.nvim_set_keymap(
  "n",
  "<space>fb",
  "<cmd>lua require 'telescope'.extensions.file_browser.file_browser()<CR>",
  {noremap = true}
)
```

## General

`telescope-file-browser.nvim` unifies two views into a single [finder](https://github.com/nvim-telescope/telescope-file-browser.nvim/blob/master/lua/telescope/_extensions/file_browser/finders.lua) that can be alternated between:

1. `file_browser`: find files and folders in the selected folder ("`path`", default: `cwd`)
2. `folder_browser`: swiftly fuzzy select folders from `cwd` for file system operations

The `folder_browser` currently always launches from `cwd` (default: neovim `cwd`), but will be made configurable to follow `path`.

## Multi-Selections

One distinct difference to `telescope.nvim` is that multi-selections are preserved between browsers. Hence, whenever you (de-)select a file or folder within `{file, folder}_browser`, respectively, this change persists across browsers (in a single session). Eventually, a view of multi-selections will be provided (see [PR](https://github.com/nvim-telescope/telescope-file-browser.nvim/pull/48))

## File System Operations

| Action (incl. GIF)| Docs                   | Comment  |
|-------------------|------------------------|----------| 
|  [creation]()     | `:h fb_action.create`  | Levers `vim.ui.input`, trailing `/` creats folder |
|  [copying]()      | `:h fb_action.copy`    | Supports copying current selection in `path` & multi-selections to respective `path` |
|  [removing]()     | `:h fb_action.remove`  |
|  [renaming]()     | `:h fb_action.rename`  |
|  [moving]()       | `:h fb_action.move`    |

## Mappings

**Notice:** Please note that the below keymappings most likely will change soon, see this [PR](https://github.com/nvim-telescope/telescope-file-browser.nvim/pull/49). While the key mappings are not yet set in stone, there will be likely a separation between `Alt` for file system operations and `Ctrl` for `telescope-file-browser`-specific actions. This will coincide with fully removing the file browser from telescope and updated docs for a first rather stable release.

| Insert / Normal  | Action                                                |
|------------------|-------------------------------------------------------|
| `<C-f>/f`        | Toggle between file and folder browser                |
| `<C-y>/y`        | Copy (multi-selected) files or folders to cwd         |
| `<C-d>/dd`       | Delete (multi-selected) files or folders              |
| `<C-r>/r`        | Rename (multi-selected) files                         |
| `<C-e>/e`        | Add File/Folder at cwd; trailing `/` creates folder   |
| `--/m`           | Move multi-selected files to cwd                      |
| `<C-h>/h`        | Toggle hidden files                                   |
| `<C-o>/o`        | Open file with default system application             |
| `<C-g>/g`        | Go to parent directory                                |
| `<C-s>/s`        | Go to home directory                                  |
| `<C-t>/t`        | Change nvim's cwd to selected folder or file (parent) |
| `<C-w>/w`        | Go to current working directory                       |
| `<A-e>/--`       | Toggle all entires ignoring `./` and `../`            |

Copying and moving files typically requires you to multi-select your files and folders and then moving to the target directory to copy and move the selections to (cf. [demo](#demo)).

Renaming multi-selected files or folders launches batch renaming, which enables to user to rename or move multiple files at once, as moving files is analogous to renaming the file. **Warning:** Batch renaming or moving files with path inter-dependencies are not resolved! For instance, moving a folder somewhere while moving another file into the original folder in later order with fail.

As a tip: you can use telescope's `which_key` action mapped by default to `<C-/>` and `?` in insert and normal mode, respectively, to inspect the mappings attached to the picker from within telescope.


<!-- # Contributing -->

<!-- Contributions are very welcome! -->

<!-- ## Submitting a new feature -->

<!-- Thanks for considering to contribute to `telescope-file-browser.nvim`! --> 
