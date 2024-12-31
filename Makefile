.PHONY: docgen test clean

DEPS_DIR := .deps
PLENARY_DIR := $(DEPS_DIR)/plenary.nvim
TELESCOPE_DIR := $(DEPS_DIR)/telescope.nvim

define git_clone_or_pull
@mkdir -p $(dir $1)
@if [ ! -d "$1" ]; then \
	git clone --depth 1 $2 $1; \
else \
	git -C "$1" pull; \
fi
endef

$(DEPS_DIR):
	@mkdir -p $@

plenary: | $(DEPS_DIR)
	$(call git_clone_or_pull,$(PLENARY_DIR),https://github.com/nvim-lua/plenary.nvim)

test-deps: plenary | $(DEPS_DIR)
	$(call git_clone_or_pull,$(TELESCOPE_DIR),https://github.com/nvim-telescope/telescope.nvim)

docgen: $(DEPS_DIR)
	nvim -l scripts/gendocs.lua

test: test-deps
	nvim --headless --noplugin -u scripts/minimal_init.vim -c "PlenaryBustedDirectory lua/tests/ { minimal_init = './scripts/minimal_init.vim' }"

clean:
	@rm -rf $(DEPS_DIR)
