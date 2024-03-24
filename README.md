# telescope-file-browser.nvim

`telescope-file-browser.nvim` is a file browser extension for telescope.nvim. It supports synchronized creation, deletion, renaming, and moving of files and folders powered by [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) and [plenary.nvim](https://github.com/nvim-lua/plenary.nvim).

![Demo](https://user-images.githubusercontent.com/39233597/149016073-6fcc9383-a761-422b-be40-17d4b854cd3c.gif)
More demo examples can be found in the [showcase issue](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53).

### Table of Contents

- [Installation](#installation)
- [Setup and Configuration](#setup-and-configuration)
- [Usage](#usage)
- [Mappings](#mappings)
- [Documentation](#documentation)
- [Workflow](#workflow)
- [Multi-Selections](#multi-selections)
- [File System Operations](#file-system-operations)
- [Exports](#exports)
- [Roadmap & Contributing](#roadmap--contributing)

---

## Installation

Install the plugin with your preferred package manager.

```lua
-- packer
use {
    "nvim-telescope/telescope-file-browser.nvim",
    requires = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" }
}

--lazy
{
    "nvim-telescope/telescope-file-browser.nvim",
    dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" }
}
```

<details>
<summary>vim-plug</summary>

```viml
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'nvim-telescope/telescope-file-browser.nvim'
```

</details>

#### Optional Dependencies

- `telescope-file-browser` optionally leverages [fd](https://github.com/sharkdp/fd) if installed for faster, more async browsing
- [`nvim-web-devicons`](https://github.com/nvim-tree/nvim-web-devicons) for file icons
- `git` to show the status of files directly in the file browser.

## Setup and Configuration

You can configure the `telescope-file-browser` like any other `telescope.nvim` picker. Please see `:h telescope-file-browser.picker` for the full set of options dedicated to the picker. Unless otherwise stated, you can pass these options either to your configuration at extension setup or picker startup. For instance, you can map `theme` and [mappings](#remappings) as you are used to from `telescope.nvim`.

```lua
-- You don't need to set any of these options.
-- IMPORTANT!: this is only a showcase of how you can set default options!
require("telescope").setup {
  extensions = {
    file_browser = {
      theme = "ivy",
      -- disables netrw and use telescope-file-browser in its place
      hijack_netrw = true,
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

<details>
<summary>Defaults</summary>

Non-primative options are commented out. See `:h telescope-file-browser.picker.file_browser()`

```lua
local fb_actions = require "telescope._extensions.file_browser.actions"

require("telescope").setup {
  extensions = {
    file_browser = {
      path = vim.loop.cwd()
      cwd = vim.loop.cwd()
      cwd_to_path = false,
      grouped = false,
      files = true,
      add_dirs = true,
      depth = 1,
      auto_depth = false,
      select_buffer = false,
      hidden = { file_browser = false, folder_browser = false },
      respect_gitignore = vim.fn.executable "fd" == 1
      no_ignore = false,
      follow_symlinks = false,
      browse_files = require("telescope._extensions.file_browser.finders").browse_files,
      browse_folders = require("telescope._extensions.file_browser.finders").browse_folders,
      hide_parent_dir = false,
      collapse_dirs = false,
      prompt_path = false,
      quiet = false,
      dir_icon = "",
      dir_icon_hl = "Default",
      display_stat = { date = true, size = true, mode = true },
      hijack_netrw = false,
      use_fd = true,
      git_status = true,
      mappings = {
        ["i"] = {
          ["<A-c>"] = fb_actions.create,
          ["<S-CR>"] = fb_actions.create_from_prompt,
          ["<A-r>"] = fb_actions.rename,
          ["<A-m>"] = fb_actions.move,
          ["<A-y>"] = fb_actions.copy,
          ["<A-d>"] = fb_actions.remove,
          ["<C-o>"] = fb_actions.open,
          ["<C-g>"] = fb_actions.goto_parent_dir,
          ["<C-e>"] = fb_actions.goto_home_dir,
          ["<C-w>"] = fb_actions.goto_cwd,
          ["<C-t>"] = fb_actions.change_cwd,
          ["<C-f>"] = fb_actions.toggle_browser,
          ["<C-h>"] = fb_actions.toggle_hidden,
          ["<C-s>"] = fb_actions.toggle_all,
          ["<bs>"] = fb_actions.backspace,
        },
        ["n"] = {
          ["c"] = fb_actions.create,
          ["r"] = fb_actions.rename,
          ["m"] = fb_actions.move,
          ["y"] = fb_actions.copy,
          ["d"] = fb_actions.remove,
          ["o"] = fb_actions.open,
          ["g"] = fb_actions.goto_parent_dir,
          ["e"] = fb_actions.goto_home_dir,
          ["w"] = fb_actions.goto_cwd,
          ["t"] = fb_actions.change_cwd,
          ["f"] = fb_actions.toggle_browser,
          ["h"] = fb_actions.toggle_hidden,
          ["s"] = fb_actions.toggle_all,
        },
      },
    },
  },
}
```

</details>

## Usage

You can use the `telescope-file-browser` as follows:

```lua
vim.keymap.set("n", "<space>fb", ":Telescope file_browser<CR>")

-- open file_browser with the path of the current buffer
vim.keymap.set("n", "<space>fb", ":Telescope file_browser path=%:p:h select_buffer=true<CR>")

-- Alternatively, using lua API
vim.keymap.set("n", "<space>fb", function()
	require("telescope").extensions.file_browser.file_browser()
end)``

## Mappings

`telescope-file-browser.nvim` comes with a lot of default mappings for discoverability. You can use `telescope`'s `which_key` (insert mode: `<C-/>`, normal mode: `?`) to list mappings attached to your picker.

- `path` denotes the folder the `file_browser` is currently in
- `fb_actions` refers to the table of provided `telescope-file-browser.actions` accessible via `require "telescope".extensions.file_browser.actions`

| Insert / Normal | fb_actions           | Description                                                                      |
| --------------- | -------------------- | -------------------------------------------------------------------------------- |
| `<A-c>/c`       | create               | Create file/folder at current `path` (trailing path separator creates folder)    |
| `<S-CR>`        | create_from_prompt   | Create and open file/folder from prompt (trailing path separator creates folder) |
| `<A-r>/r`       | rename               | Rename multi-selected files/folders                                              |
| `<A-m>/m`       | move                 | Move multi-selected files/folders to current `path`                              |
| `<A-y>/y`       | copy                 | Copy (multi-)selected files/folders to current `path`                            |
| `<A-d>/d`       | remove               | Delete (multi-)selected files/folders                                            |
| `<C-o>/o`       | open                 | Open file/folder with default system application                                 |
| `<C-g>/g`       | goto_parent_dir      | Go to parent directory                                                           |
| `<C-e>/e`       | goto_home_dir        | Go to home directory                                                             |
| `<C-w>/w`       | goto_cwd             | Go to current working directory (cwd)                                            |
| `<C-t>/t`       | change_cwd           | Change nvim's cwd to selected folder/file(parent)                                |
| `<C-f>/f`       | toggle_browser       | Toggle between file and folder browser                                           |
| `<C-h>/h`       | toggle_hidden        | Toggle hidden files/folders                                                      |
| `<C-s>/s`       | toggle_all           | Toggle all entries ignoring `./` and `../`                                       |
| `<Tab>`         | see `telescope.nvim` | Toggle selection and move to next selection                                      |
| `<S-Tab>`       | see `telescope.nvim` | Toggle selection and move to prev selection                                      |
| `<bs>/`         | backspace            | With an empty prompt, goes to parent dir. Otherwise acts normally                |

`fb_actions.create_from_prompt` requires that your terminal recognizes these keycodes (e.g. kitty). See `:h tui-input` for more information.

#### Remappings

As part of the [setup](#setup-and-configuration), you can remap actions as you like. The default mappings can also be found in this [file](https://github.com/nvim-telescope/telescope-file-browser.nvim/blob/master/lua/telescope/_extensions/file_browser.lua).

```lua
local fb_actions = require "telescope".extensions.file_browser.actions
-- mappings in file_browser extension of telescope.setup
...
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
...
```

## Documentation

The documentation of `telescope-file-browser` can be be accessed from within Neovim via:

| **Topic**      | **Vimdoc**                                      | **Comment**                   |
| -------------- | ----------------------------------------------- | ----------------------------- |
| Introduction   | `:h telescope-file-browser.nvim`                |                               |
| Picker options | `:h telescope-file-browser.picker.file_browser` | For `extension` setup         |
| Actions        | `:h telescope-file-browser.actions`             | Explore mappable actions      |
| Finders        | `:h telescope-file-browser.finders`             | Lower level for customization |

The documentation can be easily explored via `:Telescope help_tags`. Search for `fb_actions`, for instance, nicely lists available actions from within vimdocs. Very much recommended!

Please make sure to consult the docs prior to raising issues for asking questions.

## Workflow

`telescope-file-browser.nvim` unifies a `file_browser` and a `folder_browser` into a single [finder](https://github.com/nvim-telescope/telescope-file-browser.nvim/blob/master/lua/telescope/_extensions/file_browser/finders.lua) that can be toggled between:

1. `file_browser`: finds files and folders in the (currently) selected folder (denoted as `path`, default: `cwd`)
2. `folder_browser`: swiftly fuzzy find folders from `cwd` downwards to switch folders for the `file_browser` (i.e. set `path` to selected folder)

Within a single session, `path` always refers to the folder the `file_browser` is currently in and changes by selecting folders from within the `file` or `folder_browser`.

If you want to open the `file_browser` from within the folder of your current buffer, you should pass `path = "%:p:h"` to the `opts` table of the picker (Vimscript: `:Telescope file_browser path=%:p:h`) or to the extension setup configuration. Strings passed to `path` or `cwd` are expanded automatically.

By default, the `folder_browser` always launches from `cwd`, but it can be configured to launch from `path` via passing the `cwd_to_path = true` to picker `opts` table or at extension setup. The former corresponds to a more project-centric file browser workflow, whereas the latter typically facilitates file and folder browsing across the entire file system.

In practice, it mostly affects how you navigate the file system in multi-hop scenarios, for instance, when moving files from varying folders into a separate folder. The default works well in projects from which the `folder_browser` can easily reach any folder. `cwd_to_path = true` would possibly require returning to parent directories or `cwd` intermittently. However, if you move deeply through the file system, launching the `folder_browser` from `cwd` every time is tedious. Hence, it can be configured to follow `path` instead.

In general, `telescope-file-browser.nvim` intends to enable any workflow without comprise via opting in as virtually any component can be overriden.

## Multi-Selections

Multiple files and directories can be selected at the same time using default bindings (`<Tab>`/`<S-Tab>`) from `telescope.nvim`.

One distinct difference to `telescope.nvim` is that multi-selections are preserved between browsers.

Hence, whenever you (de-)select a file or folder within `{file, folder}_browser`, respectively, this change persists across browsers (in a single session).

## File System Operations

Note: `path` corresponds to the folder the `file_browser` is currently in.

**Warning:** Batch renaming or moving files with path inter-dependencies are not resolved! For instance, moving a folder somewhere while moving another file into the original folder in later order within same action will fail.

| Action (incl. GIF)                                                                                          | Docs                                       | Comment                                                                                                                   |
| ----------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| [creation](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53#issuecomment-1010221098) | `:h telescope-file-browser.actions.create` | Create file or folder (with trailing OS separator) at `path` (`file_browser`) or at selected directory (`folder_browser`) |
| [copying](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53#issuecomment-1010298556)  | `:h telescope-file-browser.actions.copy`   | Supports copying current selection & multi-selections to `path` (`file_browser`) or selected directory (`folder_browser`) |
| [moving](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53#issuecomment-1010301465)   | `:h telescope-file-browser.actions.move`   | Move multi-selected files to `path` (`file_browser`) or selected directory (`folder_browser`)                             |
| [removing](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53#issuecomment-1010315578) | `:h telescope-file-browser.actions.remove` | Remove (multi-)selected files                                                                                             |
| [renaming](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/53#issuecomment-1010323053) | `:h telescope-file-browser.actions.rename` | Rename (multi-)selected files                                                                                             |

See [fb_actions](https://github.com/nvim-telescope/telescope-file-browser.nvim/blob/master/lua/telescope/_extensions/file_browser/actions.lua) for a list of native actions and inspiration on how to write your own custom action. As additional reference, `plenary`'s [Path](https://github.com/nvim-lua/plenary.nvim/blob/master/lua/plenary/path.lua) library powers a lot of the built-in actions.

For more information on `telescope` actions and remappings, see also the [upstream documentation](https://github.com/nvim-telescope/telescope.nvim#default-mappings) and associated vimdocs at `:h telescope.defaults.mappings`.

Additional information can also be found in `telescope`'s [developer documentation](https://github.com/nvim-telescope/telescope.nvim/blob/master/developers.md).

## Exports

The extension exports the following attributes via `:lua require "telescope".extensions.file_browser`:

| Export         | Description                                             |
| -------------- | ------------------------------------------------------- |
| `file_browser` | main picker                                             |
| `actions`      | file browser actions for e.g. remapping                 |
| `finder`       | file, folder, and unified finder for user customization |
| `_picker`      | Unconfigured equivalent of `file_browser`               |

# Roadmap & Contributing

Please see the associated [issue](https://github.com/nvim-telescope/telescope-file-browser.nvim/issues/3) on more immediate open `TODOs` for `telescope-file-browser.nvim`.

That said, the primary work surrounds on enabling users to tailor the extension to their individual workflow, primarily through opting in and possibly overriding specific components.
