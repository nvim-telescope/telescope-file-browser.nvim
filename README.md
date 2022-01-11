# telescope-file-browser.nvim

`telescope-file-browser.nvim` is a file browser extension for telescope.nvim. It supports synchronized creation, deletion, renaming, and moving of files and folders powered by telescope.nvim and plenary.nvim.

# Demo

The demo shows multi-selecting files across various folders and then moving them to the lastly entered directory. More examples can be found in the [showcase issue](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53).

![Demo](https://user-images.githubusercontent.com/39233597/149016073-6fcc9383-a761-422b-be40-17d4b854cd3c.gif)

# Installation

## packer 

```lua
use { "nvim-telescope/telescope-file-browser.nvim" }
```

## Vim-Plug 

```viml
Plug "nvim-telescope/telescope-file-browser.nvim"
```

#### Optional Dependencies

`telescope-file-browser` optionally levers [fd](https://github.com/sharkdp/fd) if installed for more faster and async browsing, most noticeable in larger repositories.

# Setup and Configuration

You can configure the `telescope-file-browser` like any other `telescope.nvim` picker. See `:h telescope-file-browser.picker` for the full set of options dedicated to the picker. For instance, you of course can map `theme` and [mappings](#remappings) as you are accustomed to from `telescope.nvim`.

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
  ":Telescope file_browser",
  { noremap = true }
)
```

Alternatively, you can also access the picker as a function via `require "telescope".extensions.file_browser.file_browser` natively in lua.

## Documentation

The documentation of `telescope-file-browser` can be be accessed from within Neovim via:

|**What**       |  **Vimdoc**                        | **Comment**                  |
|---------------|------------------------------------|------------------------------|
|Introduction   |   `:h telescope-file-browser.nvim` |                              |
|Picker options |   `:h fb_picker.file_browser`      | For `extension` setup        |
|Actions        |   `:h fb_actions`                  | Explore mappable actions     |
|Finders        |   `:h fb_finders`                  | Lower level for customization|

The documentation can be easily explored via `:Telescope help_tags`. Search for `fb_actions`, for instance, nicely lists available actions from within vimdocs. Very much recommended!

Please make sure to consult the docs prior to raising issues for asking questions.


## Workflow

`telescope-file-browser.nvim` unifies two views into a single [finder](https://github.com/nvim-telescope/telescope-file-browser.nvim/blob/master/lua/telescope/_extensions/file_browser/finders.lua) that can be alternated between:

1. `file_browser`: find files and folders in the selected folder ("`path`", default: `cwd`)
2. `folder_browser`: swiftly fuzzy select folders from `cwd` for file system operations

The `folder_browser` by always launches from `cwd` (default: neovim `cwd`), but can be configured to follow `path` of `file_browser` via the `cwd_to_path` option. The former corresponds to a more project-centric file browser workflow, whereas the latter typically facilitates file and folder browsing across the entire file system.

In general, `telescope-file-browser.nvim` intends to enable any workflow without comprise via opting in as virtually any component can be overriden.

## Multi-Selections

One distinct difference to `telescope.nvim` is that multi-selections are preserved between browsers.

Hence, whenever you (de-)select a file or folder within `{file, folder}_browser`, respectively, this change persists across browsers (in a single session). Eventually, some means to inspect multi-selections will be provided natively (see [PR](https://github.com/nvim-telescope/telescope-file-browser.nvim/pull/48)).

## File System Operations

Note: `path` corresponds to the folder the `file_browser` is in.

**Warning:** Batch renaming or moving files with path inter-dependencies are not resolved! For instance, moving a folder somewhere while moving another file into the original folder in later order within same action will fail.

| Action (incl. GIF)| Docs                   | Comment  |
|-------------------|------------------------|----------| 
|  [creation](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53#issuecomment-1010221098)| `:h fb_action.create`| Levers `vim.ui.input`, trailing path separator (e.g. `/` on unix) creates folder |
|  [copying](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53#issuecomment-1010298556) | `:h fb_action.copy`  | Supports copying current selection in `path` & multi-selections to respective `path` |
|  [moving](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53#issuecomment-1010301465)  | `:h fb_action.move`  | Move multi-selected files to `path` |
|  [removing](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53#issuecomment-1010315578)| `:h fb_action.remove`| Remove (multi-)selected files |
|  [renaming](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53#issuecomment-1010323053)| `:h fb_action.rename`| Rename (multi-)selected files |


## Mappings

`telescope-file-browser.nvim` comes with a lot of default mappings for discoverability. You can use `telescope`'s `which_key` (insert mode: `<C-/>`, normal mode: `?`) to list mappings attached to your picker.

| Insert / Normal | Action                                                                        |
|-----------------|-------------------------------------------------------------------------------|
| `<A-c>/c`       | Create file/folder at current `path` (trailing path separator creates folder) |
| `<A-r>/r`       | Rename multi-selected files/folders                                           |
| `<A-m>/m`       | Move multi-selected files/folders to current `path`                           |
| `<A-y>/y`       | Copy (multi-)selected files/folders to current `path`                         |
| `<A-d>/d`       | Delete (multi-)selected files/folders                                         |
| `<C-o>/o`       | Open file/folder with default system application                              |
| `<C-g>/g`       | Go to parent directory                                                        |
| `<C-e>/e`       | Go to home directory                                                          |
| `<C-w>/w`       | Go to current working directory (cwd)                                         |
| `<C-t>/t`       | Change nvim's cwd to selected folder/file(parent)                             |
| `<C-f>/f`       | Toggle between file and folder browser                                        |
| `<C-h>/h`       | Toggle hidden files/folders                                                   |
| `<C-s>/s`       | Toggle all entries ignoring `./` and `../`                                    |

`path` denotes the folder the `file_browser` mode is currently in.

#### Remappings

As part of the [setup](#setup-and-configuration), you can remap actions as you like. The default mappings can also be found in this [file](https://github.com/nvim-telescope/telescope-file-browser.nvim/blob/master/lua/telescope/_extensions/file_browser.lua).

```lua
local fb_actions = require "telescope".extensions.file_browser.actions
      mappings = {
        ["i"] = {
          -- remap to going to home directory
          ["<C-h>"] = fb_actions.goto_home_dir
          ["<C-x>"] = function(prompt_bufnr)
            -- your custom function
          end
        },
        ["n"] = {
          -- unmap toggling `fb_actions.toggle_browser`
          f = false,
        },
```
See [fb_actions](https://github.com/nvim-telescope/telescope-file-browser.nvim/blob/master/lua/telescope/_extensions/file_browser/actions.lua) for a list of native actions and inspiration on how to write your own custom action. As additional reference, `plenary`'s [Path](https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/path.lua) powers a lot of the built-in actions.

For more information on `telescope` actions and remappings, see also the [upstream documentation](https://github.com/nvim-telescope/telescope.nvim#default-mappings) and associated vimdocs at `:h telescope.defaults.mappings`.

Additional information can also be found in `telescope`'s [developer documentation](https://github.com/nvim-telescope/telescope.nvim/blob/master/developers.md).

## Exports

The extension exports the following attributes via `:lua require "telescope".extensions.file_browser`:

| Export           | Description                                                                 |
|------------------|-----------------------------------------------------------------------------|
| `file_browser`   | main picker                                                                 |
| `actions`        | file browser actions (often referred to as `fb_actions`) for e.g. remapping |
| `finder`         | file, folder, and unified finder for user customization                     |
| `_picker`        | Unconfigured equivalent of `file_browser`                                   |

# Roadmap & Contributing

Please see the associated [issue](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/3) on more immediate open `TODOs` for `telescope-file-browser.nvim`.

That said, the primary work surrounds on enabling users to tailor the extension to their individual workflow, primarily through opting in and possibly overriding specific components.

<!-- # Contributing -->

<!-- Contributions are very welcome! -->

<!-- ## Submitting a new feature -->

<!-- Thanks for considering to contribute to `telescope-file-browser.nvim`! --> 
