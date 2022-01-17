local from_entry = require "telescope.from_entry"
local Path = require "plenary.path"
local conf = require("telescope.config").values

local fb_previewer = {}
local buffer_previewer = require("telescope.previewers.buffer_previewer").cat
local term_previewer = require "telescope.previewers.term_previewer"

local action_state = require "telescope.actions.state"

local function defaulter(f, default_opts)
  default_opts = default_opts or {}
  return {
    new = function(opts)
      if conf.preview == false and not opts.preview then
        return false
      end
      opts.preview = type(opts.preview) ~= "table" and {} or opts.preview
      if type(conf.preview) == "table" then
        for k, v in pairs(conf.preview) do
          opts.preview[k] = vim.F.if_nil(opts.preview[k], v)
        end
      end
      return f(opts)
    end,
    __call = function()
      local ok, err = pcall(f(default_opts))
      if not ok then
        error(debug.traceback(err))
      end
    end,
  }
end

fb_previewer.previewer = defaulter(function(opts)
  return setmetatable({
    _buffer_previewer = buffer_previewer.new(opts),
    _term_previewer = term_previewer.new_termopen_previewer {
      get_command = function(entry)
        local p = from_entry.path(entry, true)
        if p == nil or p == "" then
          return
        end
        return opts.dir_preview(p)
      end,
    },
    preview = function(self, entry, status)
      if opts.dir_preview and entry and entry.Path:is_dir() then
        self._term_previewer.preview(self._term_previewer, entry, status)
      else
        self._buffer_previewer.preview(self._buffer_previewer, entry, status)
      end
    end,
    scroll_fn = function(self, direction)
      local entry = action_state.get_selected_entry()
      if opts.dir_preview and entry and entry.Path:is_dir() then
        self._term_previewer.scroll_fn(self._term_previewer, direction)
      else
        self._buffer_previewer.scroll_fn(self._buffer_previewer, direction)
      end
    end,
    teardown = function(self)
      if self._buffer_previewer._teardown_func then
        self._buffer_previewer._teardown_func(self._buffer_previewer)
      end
      if self._term_previewer._teardown_func then
        self._term_previewer._teardown_func(self._term_previewer)
      end
    end,
  }, {
    __index = function(self, key, ...)
      return self._buffer_previewer[key]
    end,
  })
end, {})

return fb_previewer
