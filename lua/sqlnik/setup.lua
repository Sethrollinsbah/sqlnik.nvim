local M = {}

-- Merges user options with the defaults
function M.setup(user_opts)
    M.opts = vim.tbl_deep_extend("force", M.opts, user_opts or {})

    -- Set up autocommands for better terminal handling
    vim.api.nvim_create_autocmd(
        "TermOpen",
        {
            pattern = "*",
            callback = function()
                vim.opt_local.number = false
                vim.opt_local.relativenumber = false
                vim.opt_local.signcolumn = "no"
                vim.opt_local.scrolloff = 0
                vim.cmd("startinsert")
            end
        }
    )
end

return M
