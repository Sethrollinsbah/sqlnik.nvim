vim.keymap.set("n", "<leader>ms", function()
  require("sqlnik").run_picker()
end, {
  noremap = true,
  silent = true,
  desc = "PSQL: Run query from buffer",
})

vim.api.nvim_create_user_command(
    'SQLnik',
    function()
  require("sqlnik").run_picker()
    end,
    { nargs = '?', complete = 'file' } -- Allows optional table name argument
)

