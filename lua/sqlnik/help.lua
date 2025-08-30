-- File: .../sqlnik.nvim/lua/sqlnik/help.lua

local M = {}

local help_win = nil -- Keep track of the help window

-- Function to create and display the help modal
function M.show_help_modal()
    if help_win and vim.api.nvim_win_is_valid(help_win) then
        vim.api.nvim_win_close(help_win, true)
        help_win = nil
        return
    end

    local help_lines = {
        "┌─────────────────────────────────────────────┐",
        "│                 Keybindings                 │",
        "├─────────────────────────────────────────────┤",
        "│ j/k,              - Move row                │",
        "│ h/l,              - Move column             │",
        "│                                             │",
        "│ gg / G            - Go to start/end         │",
        "│ 0 / $             - Go to first/last column │",
        "│ <C-d> / <C-u>     - Page down/up            │",
        "│                                             │",
        "│ /                 - Search                  │",
        "│ n / N             - Next/prev match         │",
        "│                                             │",
        "│ K                 - Lookup foreign key      │",
        "│ <C-k>             - Show FK info (hover)    │",
        "│                                             │",
        "│ yc                - Yank cell               │",
        "│ yy                - Yank row                │",
        "│                                             │",
        "│ ?                 - Toggle this help        │",
        "│ q, <Esc>          - Close window            │",
        "└─────────────────────────────────────────────┘"
    }

    local help_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(help_buf, 0, -1, false, help_lines)

    local parent_win = vim.api.nvim_get_current_win()
    local parent_width = vim.api.nvim_win_get_width(parent_win)
    local parent_height = vim.api.nvim_win_get_height(parent_win)

    local modal_width = 47
    local modal_height = #help_lines

    help_win = vim.api.nvim_open_win(
        help_buf,
        true,
        {
            relative = "win",
            win = parent_win,
            width = modal_width,
            height = modal_height,
            row = parent_height - modal_height - 2, -- Position above the footer
            col = parent_width - modal_width - 2, -- Position in the bottom-right corner
            style = "minimal",
            border = "none"
        }
    )

    vim.api.nvim_set_hl(0, "SqlHelp", {fg = "#FFFFFF", bg = "#2E3440"})
    vim.api.nvim_win_set_option(help_win, "winhl", "Normal:SqlHelp")

    local help_opts = {buffer = help_buf, noremap = true, silent = true}
    local close_help = function()
        if help_win and vim.api.nvim_win_is_valid(help_win) then
            vim.api.nvim_win_close(help_win, true)
            help_win = nil
        end
    end
    vim.keymap.set("n", "q", close_help, help_opts)
    vim.keymap.set("n", "<Esc>", close_help, help_opts)
    vim.keymap.set("n", "?", close_help, help_opts)
end

return M
