local M = {}
local help = require("sqlnik.help")
local db = require("sqlnik.db")

-- Default options
M.opts = {
    -- The name of the file to search for the DATABASE_URL
    env_file = ".env",
    -- Terminal settings
    toggleterm = {
        close_on_exit = false,
        start_in_insert = true,
        direction = "float",
        size = function(term)
            if term.direction == "horizontal" then
                return vim.o.lines * 0.4
            elseif term.direction == "vertical" then
                return vim.o.columns * 0.4
            end
        end
    },
    -- Matrix loading animation settings
    matrix = {
        enabled = true, -- Set to false to disable matrix loading
        duration = 1500, -- milliseconds
        chars = "ﾊﾐﾋｰｳｼﾅﾓﾆｻﾜﾂｵﾘｱﾎﾃﾏｹﾒｴｶｷﾑﾕﾗｾﾈｽﾀﾇﾍ01",
        width = 50,
        height = 12
    },
    -- Foreign key detection settings
    foreign_keys = {
        enabled = true,
        -- 'manual_mapping' is now the only configurable fallback.
        manual_mapping = {},
    },
    -- Handlers for different database drivers.
    -- Users can add their own here.
    db_handlers = {
        postgresql = {
            executable = "psql",
            build_command = function(url, query)
                -- Create a temporary file for the SQL query
                local sql_temp_file = vim.fn.tempname() .. ".sql"
                local psql_script_content =
                    string.format(
                    [[
\pset border 1
\pset format aligned
\pset tuples_only off
\timing on
\echo
\echo '--- Executing Query ---'
\echo
%s
]],
                    query
                )

                local file = io.open(sql_temp_file, "w")
                if not file then
                    vim.notify("❌ Could not create temporary SQL file.", vim.log.levels.ERROR)
                    return nil
                end
                file:write(psql_script_content)
                file:close()

                -- Create a temporary shell script to run the command
                local runner_temp_file = vim.fn.tempname() .. ".sh"
                local runner_script_content =
                    string.format(
                    [[
#!/bin/sh
set -e
if [ -f .env ]; then
  . ./.env
fi
psql --quiet --no-psqlrc --pset pager=off "%s" -f %s
rm -f %s
]],
                    url,
                    vim.fn.shellescape(sql_temp_file),
                    vim.fn.shellescape(sql_temp_file)
                )

                local runner_file = io.open(runner_temp_file, "w")
                if not runner_file then
                    vim.notify("❌ Could not create temporary runner script.", vim.log.levels.ERROR)
                    return nil
                end
                runner_file:write(runner_script_content)
                runner_file:close()

                vim.fn.setfperm(runner_temp_file, "rwx------")

                -- The final command executes the runner script and then cleans it up
                return string.format(
                    "sh %s; rm -f %s",
                    vim.fn.shellescape(runner_temp_file),
                    vim.fn.shellescape(runner_temp_file)
                )
            end
        },
        mysql = {
            executable = "mysql",
            build_command = function(url, query)
                local dbname = url:match("/([^/]+)$")
                if not dbname then
                    vim.notify("Could not parse database name from MySQL URL.", vim.log.levels.ERROR)
                    return nil
                end
                -- Enhanced MySQL command with better formatting
                return "source .env && mysql " ..
                    dbname .. " --table --column-names -vvv -e " .. vim.fn.shellescape(query)
            end
        },
        sqlite = {
            executable = "sqlite3",
            build_command = function(url, query)
                local db_path = url:match("sqlite://(.+)")
                if not db_path then
                    vim.notify("Could not parse database path from SQLite URL.", vim.log.levels.ERROR)
                    return nil
                end
                -- Enhanced SQLite command with better formatting
                return 'sqlite3 -header -column -column -nullvalue "NULL" ' ..
                    db_path .. " " .. vim.fn.shellescape(query)
            end
        }
    }
}

-- Matrix animation variables
local matrix_timer = nil
local matrix_buf = nil
local matrix_win = nil

-- Create matrix loading animation
function M.show_matrix_loading()
    if not M.opts.matrix.enabled then
        return
    end

    -- Create a new buffer for the matrix animation
    matrix_buf = vim.api.nvim_create_buf(false, true)

    -- Set buffer options
    vim.bo[matrix_buf].bufhidden = "wipe"
    vim.bo[matrix_buf].buftype = "nofile"
    vim.bo[matrix_buf].swapfile = false
    vim.bo[matrix_buf].modifiable = false

    -- Calculate window dimensions and position
    local width = M.opts.matrix.width
    local height = M.opts.matrix.height
    local row = math.floor((vim.o.lines - height) / 2) - 2
    local col = math.floor((vim.o.columns - width) / 2)

    -- Create floating window
    matrix_win =
        vim.api.nvim_open_win(
        matrix_buf,
        false,
        {
            relative = "editor",
            width = width,
            height = height,
            row = row,
            col = col,
            style = "minimal",
            border = "rounded",
            title = " ⚡ Executing SQL Query ⚡ ",
            title_pos = "center"
        }
    )

-- Set window highlight
vim.wo[matrix_win].winhl = "Normal:Normal,FloatBorder:Special"

    -- Matrix animation variables
    local columns = {}
    for i = 1, width do
        columns[i] = {
            chars = {},
            speed = math.random(1, 4),
            counter = 0
        }
    end

    -- Animation function
    local function animate()
        if not vim.api.nvim_buf_is_valid(matrix_buf) or not vim.api.nvim_win_is_valid(matrix_win) then
            return
        end

        -- Update matrix columns
        for i = 1, width do
            local col = columns[i]
            col.counter = col.counter + 1

            if col.counter >= col.speed then
                col.counter = 0

                -- Add new character at top
                table.insert(
                    col.chars,
                    1,
                    {
                        char = M.opts.matrix.chars:sub(
                            math.random(1, #M.opts.matrix.chars),
                            math.random(1, #M.opts.matrix.chars)
                        ),
                        age = 0
                    }
                )

                -- Age existing characters
                for j = 1, #col.chars do
                    col.chars[j].age = col.chars[j].age + 1
                end

                -- Remove old characters
                while #col.chars > height do
                    table.remove(col.chars)
                end
            end
        end

        -- Render matrix to buffer
        local lines = {}
        for row_idx = 1, height do
            local line = ""
            for col_idx = 1, width do
                local char_data = columns[col_idx].chars[row_idx]
                if char_data then
                    line = line .. char_data.char
                else
                    line = line .. " "
                end
            end
            table.insert(lines, line)
        end

        -- Update buffer content-- Update buffer content
vim.bo[matrix_buf].modifiable = true
vim.api.nvim_buf_set_lines(matrix_buf, 0, -1, false, lines) -- This function is correct and not deprecated
vim.bo[matrix_buf].modifiable = false

        -- Set syntax highlighting for matrix effect
        vim.api.nvim_buf_call(
            matrix_buf,
            function()
                -- Clear existing syntax
                vim.cmd("syntax clear")

                -- Define highlights with better terminal compatibility
                vim.api.nvim_set_hl(
                    0,
                    "MatrixGreen",
                    {
                        fg = "#00ff41",
                        ctermfg = 46, -- Bright green
                        bold = true
                    }
                )

                vim.api.nvim_set_hl(
                    0,
                    "MatrixBright",
                    {
                        fg = "#00ff00",
                        ctermfg = 82, -- Light green
                        bold = true
                    }
                )

                -- Apply syntax matching
                vim.cmd("syntax match MatrixGreen /./")
            end
        )
    end

    -- Start animation timer
    matrix_timer = vim.loop.new_timer()
    matrix_timer:start(0, 80, vim.schedule_wrap(animate))
end

-- Hide matrix loading animation
function M.hide_matrix_loading()
    if matrix_timer then
        matrix_timer:stop()
        matrix_timer:close()
        matrix_timer = nil
    end

    if matrix_win and vim.api.nvim_win_is_valid(matrix_win) then
        vim.api.nvim_win_close(matrix_win, true)
        matrix_win = nil
    end

    if matrix_buf and vim.api.nvim_buf_is_valid(matrix_buf) then
        vim.api.nvim_buf_delete(matrix_buf, {force = true})
        matrix_buf = nil
    end
end

--- A robust parser that finds table boundaries before processing data.
-- @param output The raw string output from the psql command.
-- @return A table with headers, rows, timing, and row_count.
local function parse_psql_output(output)
    local lines = vim.split(output, "\n")
    local data, headers = {}, {}
    local timing_info, row_count = "", 0
    local header_separator_idx = 0
    local header_line_idx = 0

    -- First pass: find the separator line and extract footer info
    for i, line in ipairs(lines) do
        -- The separator line is composed of dashes, pluses, and spaces
        if header_separator_idx == 0 and line:match("^%s*%-+[-%+%s]*%-+%s*$") then
            header_separator_idx = i
        end
        if line:match("^Time:") then
            timing_info = line
        end
        local count_match = line:match("%((%d+) rows?%)")
        if count_match then
            row_count = tonumber(count_match)
        end
    end

    -- If no separator was found, we cannot parse the table.
    if header_separator_idx == 0 then
        return {headers = {}, rows = {}, timing = timing_info, row_count = row_count}
    end

    -- Second pass: find the actual header line by looking backwards from separator
    -- The header line should contain column names separated by |
    for i = header_separator_idx - 1, 1, -1 do
        local line = lines[i]
        -- Skip empty lines or lines that are just whitespace
        if line:match("%S") then
            -- Check if this line contains | characters (column separators)
            if line:match("|") and not line:match("^%s*%-") then
                header_line_idx = i
                break
            end
        end
    end

    -- If we couldn't find a proper header line, return empty
    if header_line_idx == 0 then
        return {headers = {}, rows = {}, timing = timing_info, row_count = row_count}
    end

    -- Use the separator line to find column boundaries
    local separator_line = lines[header_separator_idx]
    local col_boundaries = {}

    -- Find all positions where columns start/end by looking for + and - patterns
    local pos = 1
    while pos <= #separator_line do
        local start_pos = separator_line:find("[+%-]", pos)
        if not start_pos then
            break
        end

        -- Find the end of this column boundary marker
        local end_pos = start_pos
        while end_pos <= #separator_line and separator_line:sub(end_pos, end_pos):match("[+%-]") do
            end_pos = end_pos + 1
        end

        table.insert(col_boundaries, start_pos)
        pos = end_pos
    end

    -- If we don't have proper boundaries, fall back to splitting by |
    if #col_boundaries < 2 then
        -- Fallback: split by | character
        local header_line = lines[header_line_idx]
        headers = vim.split(header_line, "|", {plain = true})

        -- Clean up headers
        for i, header in ipairs(headers) do
            headers[i] = vim.trim(header)
        end

        -- Remove empty headers at beginning/end
        while #headers > 0 and headers[1] == "" do
            table.remove(headers, 1)
        end
        while #headers > 0 and headers[#headers] == "" do
            table.remove(headers, #headers)
        end

        -- Parse data rows the same way
        for i = header_separator_idx + 1, #lines do
            local line = lines[i]
            if line:match("%(%d+ rows?%)") or line:match("^Time:") then
                break
            end

            if line:match("%S") and line:match("|") then
                local row_data = vim.split(line, "|", {plain = true})

                -- Clean up row data
                for j, cell in ipairs(row_data) do
                    row_data[j] = vim.trim(cell)
                end

                -- Remove empty cells at beginning/end
                while #row_data > 0 and row_data[1] == "" do
                    table.remove(row_data, 1)
                end
                while #row_data > 0 and row_data[#row_data] == "" do
                    table.remove(row_data, #row_data)
                end

                -- Only add rows that have the same number of columns as headers
                if #row_data == #headers then
                    table.insert(data, row_data)
                end
            end
        end
    else
        -- Use boundary-based parsing (original method with fixes)
        local function slice_line_into_cells(line)
            local cells = {}
            for i = 1, #col_boundaries - 1 do
                local start_pos = col_boundaries[i]
                local end_pos = col_boundaries[i + 1] - 1
                local cell_text = line:sub(start_pos, end_pos)

                -- Clean up cell text by removing | characters and trimming
                cell_text = cell_text:gsub("|", "")
                table.insert(cells, vim.trim(cell_text))
            end
            return cells
        end

        -- Parse the header line
        headers = slice_line_into_cells(lines[header_line_idx])

        -- Parse data rows
        for i = header_separator_idx + 1, #lines do
            local line = lines[i]
            if line:match("%(%d+ rows?%)") or line:match("^Time:") then
                break
            end

            if line:match("%S") then
                local row_data = slice_line_into_cells(line)
                if #row_data == #headers then
                    table.insert(data, row_data)
                end
            end
        end
    end

    return {
        headers = headers,
        rows = data,
        timing = timing_info,
        row_count = row_count
    }
end

-- Store database context for foreign key lookups
local current_db_context = {}

-- In sqlnik/lua/sqlnik/config.lua

---
--- 💡 REVISED: Foreign key analysis now ONLY uses the schema cache or manual mapping.
---
local function analyze_foreign_keys(headers)
    local foreign_keys = {}
    if not M.opts.foreign_keys.enabled or not headers or #headers == 0 then
        return foreign_keys
    end

    for i, header in ipairs(headers) do
        local fk_info = nil

        -- Strategy 1: Check the schema cache (most accurate method).
        if schema_cache and schema_cache[header] then
            -- Use the first match if a column name is a foreign key in multiple tables.
            local info = schema_cache[header][1]
            fk_info = {
                column_name = header,
                referenced_table = info.foreign_table,
                referenced_column = info.foreign_column,
                source = "schema_cache",
            }
        -- Strategy 2: Fallback to user-defined manual mapping.
        elseif M.opts.foreign_keys.manual_mapping[header] then
            fk_info = {
                column_name = header,
                referenced_table = M.opts.foreign_keys.manual_mapping[header],
                referenced_column = "id", -- Assume 'id' for manual mappings
                source = "manual_mapping",
            }
        end

        if fk_info then
            foreign_keys[i] = fk_info
        end
    end

    return foreign_keys
end
-- First, let's add a comprehensive debug function to see what's happening
function M.debug_foreign_keys()
    vim.notify("=== FOREIGN KEY DEBUG INFO ===", vim.log.levels.INFO)
    vim.notify("current_db_context: " .. vim.inspect(current_db_context), vim.log.levels.INFO)
    vim.notify("M.opts.foreign_keys: " .. vim.inspect(M.opts.foreign_keys), vim.log.levels.INFO)
    
    -- Test FK detection with current headers if available
    if headers and #headers > 0 then
        vim.notify("Current headers: " .. vim.inspect(headers), vim.log.levels.INFO)
        local test_fks = analyze_foreign_keys(current_db_context.query or "", headers)
        vim.notify("Detected foreign keys: " .. vim.inspect(test_fks), vim.log.levels.INFO)
    end
end

-- Fixed version of the main execution function that properly sets context
function M.execute_sql_query(query, database_url)
    -- Detect database type from URL
    local db_type = nil
    if database_url:match("^postgres://") or database_url:match("^postgresql://") then
        db_type = "postgresql"
    elseif database_url:match("^mysql://") then
        db_type = "mysql"
    elseif database_url:match("^sqlite://") then
        db_type = "sqlite"
    else
        vim.notify("Could not detect database type from URL: " .. database_url, vim.log.levels.ERROR)
        return
    end
    
    -- CRITICAL: Set database context BEFORE executing query
    current_db_context = {
        url = database_url,
        type = db_type,
        query = query
    }
    
    vim.notify("Database context set: " .. vim.inspect(current_db_context), vim.log.levels.DEBUG)
    
    local handler = M.opts.db_handlers[db_type]
    if not handler then
        vim.notify("No handler for database type: " .. db_type, vim.log.levels.ERROR)
        return
    end
    
    local cmd = handler.build_command(database_url, query)
    if cmd then
        local title = "SQL Results"
        M.run_in_terminal_with_matrix(cmd, title, query)
    else
        vim.notify("Failed to build command", vim.log.levels.ERROR)
    end
end
-- Improved foreign key analysis with better debugging
local function analyze_foreign_keys_from_query(query, headers)
    local foreign_keys = {}
    local referenced_tables = {}
    
    vim.notify("Analyzing FK for query: " .. (query or "nil"), vim.log.levels.DEBUG)
    vim.notify("Headers to analyze: " .. vim.inspect(headers), vim.log.levels.DEBUG)
    
    if not query or not headers then
        vim.notify("Missing query or headers for FK analysis", vim.log.levels.DEBUG)
        return foreign_keys
    end
    
    -- Extract table names with improved patterns
    local query_lower = query:lower()
    
    -- Enhanced table detection patterns
    local table_patterns = {
        "from%s+([%w_]+)",              -- FROM table
        "join%s+([%w_]+)",              -- JOIN table
        "left%s+join%s+([%w_]+)",       -- LEFT JOIN
        "right%s+join%s+([%w_]+)",      -- RIGHT JOIN
        "inner%s+join%s+([%w_]+)",      -- INNER JOIN
        "update%s+([%w_]+)",            -- UPDATE table
        "insert%s+into%s+([%w_]+)",     -- INSERT INTO
        "into%s+([%w_]+)%s+%(.*%)",     -- INSERT INTO table (cols)
        "from%s+([%w_]+)%s+[%w_]+",     -- FROM table alias
    }
    
    for _, pattern in ipairs(table_patterns) do
        for table_name in query_lower:gmatch(pattern) do
            referenced_tables[table_name] = true
            vim.notify("Found table in query: " .. table_name, vim.log.levels.DEBUG)
        end
    end
    
    -- Analyze each header
    for i, header in ipairs(headers) do
        local header_lower = header:lower()
        local is_foreign_key = false
        local referenced_table = nil
        local confidence = "low"
        
        vim.notify("Analyzing header: " .. header, vim.log.levels.DEBUG)
        
        -- Check manual mapping first
        if M.opts.foreign_keys and M.opts.foreign_keys.manual_mapping then
            for mapped_col, mapped_table in pairs(M.opts.foreign_keys.manual_mapping) do
                if header_lower == mapped_col:lower() then
                    is_foreign_key = true
                    referenced_table = mapped_table
                    confidence = "high"
                    vim.notify("FK found via manual mapping: " .. header .. " -> " .. mapped_table, vim.log.levels.DEBUG)
                    break
                end
            end
        end
        
        -- Check configured patterns
        if not is_foreign_key and M.opts.foreign_keys and M.opts.foreign_keys.patterns then
            for _, pattern in ipairs(M.opts.foreign_keys.patterns) do
                if header_lower:match(pattern:lower()) then
                    is_foreign_key = true
                    vim.notify("FK pattern matched: " .. header .. " matches " .. pattern, vim.log.levels.DEBUG)
                    
                    if M.opts.foreign_keys.derive_table_name then
                        referenced_table = M.opts.foreign_keys.derive_table_name(header_lower)
                        confidence = "medium"
                        vim.notify("Derived table name: " .. (referenced_table or "nil"), vim.log.levels.DEBUG)
                    end
                    break
                end
            end
        end
        -- Store FK info
        if is_foreign_key then
            foreign_keys[i] = {
                column_index = i,
                column_name = header,
                referenced_table = referenced_table,
                confidence = confidence
            }
            
            vim.notify("FK registered: " .. header .. " -> " .. (referenced_table or "unknown"), vim.log.levels.INFO)
        end
    end
    
    vim.notify("Total foreign keys detected: " .. vim.tbl_count(foreign_keys), vim.log.levels.DEBUG)
    return foreign_keys
end

-- Enhanced create_table_viewer function with foreign key support
-- Replace your existing create_table_viewer function with this version:
local function create_table_viewer(parsed_data, title, db_url, db_type, original_query)
    local buf = vim.api.nvim_create_buf(false, true)
    local current_row, current_col = 1, 1
    local col_display_offset, scroll_offset_y = 0, 0
    local last_search = {term = "", matches = {}, current = 0}
    local ns_id = vim.api.nvim_create_namespace("sql_viewer_highlight")
    local fk_ns_id = vim.api.nvim_create_namespace("sql_viewer_fk_highlight")
    local highlight_extmark = nil

    -- Store database context
    current_db_context = {url = db_url, type = db_type, query = original_query}
    -- CRITICAL: Ensure database context is set with all required fields
    if not current_db_context.url then
        current_db_context.url = db_url
    end
    if not current_db_context.type then
        current_db_context.type = db_type
    end
    if not current_db_context.query then
        current_db_context.query = original_query
    end
    
    vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(buf, "swapfile", false)
    vim.api.nvim_buf_set_option(buf, "filetype", "sqlresult")

    local headers, rows = parsed_data.headers or {}, parsed_data.rows or {}
    local FIXED_COL_WIDTH = 20

    -- Analyze foreign keys from query context
    local foreign_keys = {}
    if M.opts.foreign_keys.enabled and original_query then
        foreign_keys = analyze_foreign_keys_from_query(original_query, headers)
    end

    local function format_cell_content(content)
        local str = tostring(content or "")
        if #str > FIXED_COL_WIDTH then
            return str:sub(1, FIXED_COL_WIDTH - 3) .. "..."
        end
        return str .. string.rep(" ", FIXED_COL_WIDTH - #str)
    end

    local function render_table()
        local win = vim.api.nvim_get_current_win()
        if not vim.api.nvim_win_is_valid(win) then
            return
        end
        local win_width, win_height = vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win)
        local lines = {}

        if #headers == 0 then
            table.insert(lines, "No results returned.")
        else
            local available_width = win_width - 4
            local max_visible_cols = math.max(1, math.floor(available_width / (FIXED_COL_WIDTH + 3)))
            if current_col <= col_display_offset then
                col_display_offset = current_col - 1
            end
            if current_col > col_display_offset + max_visible_cols then
                col_display_offset = current_col - max_visible_cols
            end
            col_display_offset = math.max(0, math.min(col_display_offset, #headers - max_visible_cols))
            local start_col, end_col = col_display_offset + 1, math.min(col_display_offset + max_visible_cols, #headers)

            local visible_rows_count = win_height - 5
            if current_row < scroll_offset_y + 1 then
                scroll_offset_y = current_row - 1
            end
            if current_row > scroll_offset_y + visible_rows_count then
                scroll_offset_y = current_row - visible_rows_count
            end

            -- Clear previous foreign key highlights
            vim.api.nvim_buf_clear_namespace(buf, fk_ns_id, 0, -1)

            local border_parts, header_parts, sep_parts = {}, {}, {}
            for i = start_col, end_col do
                local header_text = format_cell_content(headers[i])
                
                -- Add FK indicator to header if it's a foreign key
                if foreign_keys[i] then
                    local confidence_symbol = foreign_keys[i].confidence == "high" and "🔗" or "🔗?"
                    header_text = confidence_symbol .. " " .. header_text:sub(3) -- Replace first 2 chars with FK symbol
                end
                
                table.insert(border_parts, string.rep("─", FIXED_COL_WIDTH + 2))
                table.insert(header_parts, " " .. header_text .. " ")
                table.insert(sep_parts, string.rep("─", FIXED_COL_WIDTH + 2))
            end
            table.insert(lines, "┌" .. table.concat(border_parts, "┬") .. "┐")
            table.insert(lines, "│" .. table.concat(header_parts, "│") .. "│")
            table.insert(lines, "├" .. table.concat(sep_parts, "┼") .. "┤")

            local start_row_idx, end_row_idx =
                scroll_offset_y + 1,
                math.min(scroll_offset_y + visible_rows_count, #rows)
            for i = start_row_idx, end_row_idx do
                local row_parts = {}
                for j = start_col, end_col do
                    local cell_content = format_cell_content(rows[i][j])
                    
                    -- Highlight foreign key cells differently
                    if foreign_keys[j] then
                        -- Add subtle FK highlighting to cell content
                        cell_content = "→ " .. cell_content:sub(3) -- Replace first 2 chars with arrow
                    end
                    
                    table.insert(row_parts, " " .. cell_content .. " ")
                end
                table.insert(lines, "│" .. table.concat(row_parts, "│") .. "│")
            end
            table.insert(lines, "└" .. table.concat(border_parts, "┴") .. "┘")
            
            -- Enhanced footer with FK info
            local fk_indicator = foreign_keys[current_col] and " [FK]" or ""
            local footer =
                string.format(
                "Rows: %d/%d | Cell: (%d,%d)%s | Cols: %d-%d/%d | FK: K | Help: ? | Quit: q",
                current_row,
                #rows,
                current_row,
                current_col,
                fk_indicator,
                start_col,
                end_col,
                #headers
            )
            table.insert(lines, footer:sub(1, win_width - 2))
        end

        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.bo[buf].modifiable = false
        
        -- Update current cell highlight
        if highlight_extmark then
            vim.api.nvim_buf_del_extmark(buf, ns_id, highlight_extmark)
        end
        -- Calculate the screen position of the current cell
        local line_to_hl = (current_row - scroll_offset_y) + 2 -- +2 for border and header
        local col_to_hl_start = 3 -- start after the first border
        for i = 1, current_col - (col_display_offset + 1) do
            col_to_hl_start = col_to_hl_start + FIXED_COL_WIDTH + 5
        end
        local col_to_hl_end = col_to_hl_start + FIXED_COL_WIDTH + 2

        -- Use different highlight for foreign key cells
        local highlight_group = foreign_keys[current_col] and "SqlResultForeignKey" or "SqlResultSelected"
        
        highlight_extmark =
            vim.api.nvim_buf_set_extmark(
            buf,
            ns_id,
            line_to_hl,
            col_to_hl_start,
            {
                end_col = col_to_hl_end,
                hl_group = highlight_group,
                strict = false
            }
        )
    end

    local win =
        vim.api.nvim_open_win(
        buf,
        true,
        {
            relative = "editor",
            width = math.floor(vim.o.columns * 0.9),
            height = math.floor(vim.o.lines * 0.8),
            row = math.floor(vim.o.lines * 0.1),
            col = math.floor(vim.o.columns * 0.05),
            style = "minimal",
            border = "rounded",
            title = " " .. title .. " ",
            title_pos = "center"
        }
    )

    -- Helper function for navigation
    local function jump_to_match(direction)
        if #last_search.matches == 0 then
            return
        end
        last_search.current = last_search.current + direction
        if last_search.current > #last_search.matches then
            last_search.current = 1
        end
        if last_search.current < 1 then
            last_search.current = #last_search.matches
        end
        local match = last_search.matches[last_search.current]
        current_row, current_col = match.row, match.col
        render_table()
    end

    -- Navigation keymaps
    local opts = {buffer = buf, noremap = true, silent = true}
    vim.keymap.set("n", "j", function()
        current_row = math.min(current_row + vim.v.count1, #rows)
        render_table()
    end, opts)
    
    vim.keymap.set("n", "k", function()
        current_row = math.max(current_row - vim.v.count1, 1)
        render_table()
    end, opts)
    
    vim.keymap.set("n", "l", function()
        current_col = math.min(current_col + vim.v.count1, #headers)
        render_table()
    end, opts)
    
    vim.keymap.set("n", "h", function()
        current_col = math.max(current_col - vim.v.count1, 1)
        render_table()
    end, opts)

    -- Page navigation
    vim.keymap.set("n", "<C-d>", function()
        local p = math.floor((vim.api.nvim_win_get_height(win) - 5))
        current_row = math.min(current_row + p, #rows)
        render_table()
    end, opts)
    
    vim.keymap.set("n", "<C-u>", function()
        local p = math.floor((vim.api.nvim_win_get_height(win) - 5))
        current_row = math.max(current_row - p, 1)
        render_table()
    end, opts)

    -- Jump to start/end
    vim.keymap.set("n", "gg", function()
        current_row = 1
        render_table()
    end, opts)
    
    vim.keymap.set("n", "G", function()
        current_row = #rows
        render_table()
    end, opts)
    
    vim.keymap.set("n", "0", function()
        current_col = 1
        render_table()
    end, opts)
    
    vim.keymap.set("n", "$", function()
        current_col = #headers
        render_table()
    end, opts)

-- Enhanced foreign key lookup function with better debugging and error handling
vim.keymap.set("n", "K", function()
    local header = headers[current_col]
    local cell_value = rows[current_row] and rows[current_row][current_col]
    
    -- Debug: Print current state
    vim.notify("DEBUG: Attempting FK lookup for column '" .. header .. "' with value '" .. tostring(cell_value) .. "'", vim.log.levels.DEBUG)
    
    if not cell_value or cell_value == "" or cell_value == "NULL" then
        vim.notify("No value in current cell to lookup", vim.log.levels.WARN)
        return
    end
    
    local fk_info = foreign_keys[current_col]
    if not fk_info then
        vim.notify("Column '" .. header .. "' is not detected as a foreign key. Available FKs: " .. vim.inspect(foreign_keys), vim.log.levels.INFO)
        return
    end
    
    if not fk_info.referenced_table then
        vim.notify("Cannot lookup: referenced table unknown for '" .. header .. "'", vim.log.levels.WARN)
        return
    end
    
    -- Debug: Check database context
    if not current_db_context or not current_db_context.url or not current_db_context.type then
        vim.notify("ERROR: Database context not available: " .. vim.inspect(current_db_context), vim.log.levels.ERROR)
        return
    end
    
    vim.notify("DEBUG: Database context: " .. vim.inspect(current_db_context), vim.log.levels.DEBUG)
    
    -- Show loading notification
    vim.notify("Looking up " .. fk_info.referenced_table .. " record with id: " .. cell_value, vim.log.levels.INFO)
    
    -- Build query to fetch related record
    local fetch_query = string.format(
        "SELECT * FROM %s WHERE id = %s LIMIT 1;",
        fk_info.referenced_table,
        cell_value
    )
    
    vim.notify("DEBUG: Executing query: " .. fetch_query, vim.log.levels.DEBUG)
    
    -- Execute the query using the same database handler
    local handler = M.opts.db_handlers[current_db_context.type]
    if not handler then
        vim.notify("No handler for database type: " .. current_db_context.type, vim.log.levels.ERROR)
        return
    end
    
    local cmd = handler.build_command(current_db_context.url, fetch_query)
    if cmd then
        local title = string.format("FK: %s → %s.id=%s", header, fk_info.referenced_table, cell_value)
        vim.notify("DEBUG: Executing command: " .. cmd, vim.log.levels.DEBUG)
        M.run_in_terminal_with_matrix(cmd, title, fetch_query)
    else
        vim.notify("ERROR: Failed to build command", vim.log.levels.ERROR)
    end
end, opts)

-- Enhanced run_in_terminal_with_matrix function to ensure database context is preserved

-- Enhanced run_in_terminal_with_matrix function to ensure database context is preserved
function M.run_in_terminal_with_matrix(cmd_string, title, original_query)
    -- Ensure we have database context
    if not current_db_context.url then
        vim.notify("ERROR: No database URL available", vim.log.levels.ERROR)
        return
    end
    
    if not current_db_context.type then
        vim.notify("ERROR: No database type available", vim.log.levels.ERROR)
        return
    end
    
    if M.opts.matrix.enabled then
        M.show_matrix_loading()
        vim.notify("Running: " .. title, vim.log.levels.INFO)

        if vim.system then
            vim.system({"sh", "-c", cmd_string}, {}, function(result)
                vim.schedule(function()
                    M.hide_matrix_loading()

                    if result.code ~= 0 then
                        vim.notify("Query failed with exit code: " .. result.code, vim.log.levels.ERROR)
                        if result.stderr and result.stderr ~= "" then
                            vim.notify("Error: " .. result.stderr, vim.log.levels.ERROR)
                        end
                        return
                    end

                    local output = result.stdout or ""
                    local parsed_data = parse_psql_output(output)
                    
                    -- Pass all necessary context including database info
                    create_table_viewer(parsed_data, title, current_db_context.url, current_db_context.type, original_query)

                    vim.notify("Query execution completed", vim.log.levels.INFO)
                end)
            end)
        else
            -- Fallback for older Neovim versions
            local output_lines = {}
            local stderr_lines = {}

            local job_id = vim.fn.jobstart({"sh", "-c", cmd_string}, {
                stdout_buffered = true,
                stderr_buffered = true,
                on_stdout = function(_, data)
                    if data then
                        vim.list_extend(output_lines, data)
                    end
                end,
                on_stderr = function(_, data)
                    if data then
                        vim.list_extend(stderr_lines, data)
                    end
                end,
                on_exit = function(_, exit_code)
                    vim.schedule(function()
                        M.hide_matrix_loading()

                        if exit_code ~= 0 then
                            vim.notify("Query failed with exit code: " .. exit_code, vim.log.levels.ERROR)
                            if #stderr_lines > 0 then
                                vim.notify("Error: " .. table.concat(stderr_lines, "\n"), vim.log.levels.ERROR)
                            end
                            return
                        end

                        local output = table.concat(output_lines, "\n")
                        local parsed_data = parse_psql_output(output)
                        
                        -- Pass all necessary context
                        create_table_viewer(parsed_data, title, current_db_context.url, current_db_context.type, original_query)

                        vim.notify("Query execution completed", vim.log.levels.INFO)
                    end)
                end
            })

            if job_id <= 0 then
                M.hide_matrix_loading()
                vim.notify("Failed to start job", vim.log.levels.ERROR)
            end
        end
    end
end

-- Enhanced function to initialize database context properly
function M.execute_query_with_context(query, db_url, db_type)
    -- Store the database context BEFORE executing
    current_db_context = {
        url = db_url,
        type = db_type,
        query = query
    }
    
    local handler = M.opts.db_handlers[db_type]
    if not handler then
        vim.notify("No handler for database type: " .. db_type, vim.log.levels.ERROR)
        return
    end
    
    local cmd = handler.build_command(db_url, query)
    if cmd then
        local title = "SQL Results"
        M.run_in_terminal_with_matrix(cmd, title, query)
    else
        vim.notify("Failed to build command", vim.log.levels.ERROR)
    end
end    -- Help keymap
    vim.keymap.set("n", "?", help.show_help_modal, opts)

    -- Yank keymaps with context
    vim.keymap.set("n", "yc", function()
        local header = headers[current_col] or ("Column " .. current_col)
        local cell_content = tostring(rows[current_row][current_col] or "")
        local formatted_yank = header .. ": " .. cell_content
        vim.fn.setreg("+", formatted_yank)
        vim.notify("Yanked to system clipboard: " .. formatted_yank)
    end, opts)

    vim.keymap.set("n", "yy", function()
        local row_data = rows[current_row]
        local formatted_lines = {}
        for i, header in ipairs(headers) do
            table.insert(formatted_lines, header .. ": " .. tostring(row_data[i] or ""))
        end
        local formatted_yank = table.concat(formatted_lines, "\n")
        vim.fn.setreg("+", formatted_yank)
        vim.notify("Yanked row " .. current_row .. " to system clipboard")
    end, opts)

    -- Search keymaps
    vim.keymap.set("n", "/", function()
        vim.ui.input({prompt = "/"}, function(input)
            if not input or input == "" then
                return
            end
            last_search = {term = input, matches = {}, current = 0}
            for r_idx, row in ipairs(rows) do
                for c_idx, cell in ipairs(row) do
                    if tostring(cell):lower():find(input:lower(), 1, true) then
                        table.insert(last_search.matches, {row = r_idx, col = c_idx})
                    end
                end
            end
            vim.notify(#last_search.matches .. " matches found for '" .. input .. "'")
            jump_to_match(1)
        end)
    end, opts)
    
    vim.keymap.set("n", "n", function()
        jump_to_match(1)
    end, opts)
    
    vim.keymap.set("n", "N", function()
        jump_to_match(-1)
    end, opts)

    -- Exit keymaps
    vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(win, true)
    end, opts)
    
    vim.keymap.set("n", "<Esc>", function()
        vim.api.nvim_win_close(win, true)
    end, opts)

    -- Set up highlighting
    vim.api.nvim_set_hl(0, "SqlResultNormal", {fg = "#AAAAAA", bg = "#1e1e1e"})
    vim.api.nvim_set_hl(0, "SqlResultSelected", {fg = "#FFFFFF", bg = "#3e3e3e", bold = true})
    vim.api.nvim_set_hl(0, "SqlResultForeignKey", {fg = "#FFD700", bg = "#3e3e3e", bold = true}) -- Gold highlight for FK
    vim.api.nvim_set_hl(0, "SqlResultBorder", {fg = "#444444"})
    
    vim.wo[win].winhl = "Normal:SqlResultNormal,FloatBorder:SqlResultBorder"
    vim.wo[win].conceallevel = 2

    render_table()
end



-- Update the run_in_terminal_with_matrix function to pass the original query
-- Add this parameter to store the original query when calling create_table_viewer
function M.run_in_terminal_with_matrix(cmd_string, title, original_query)
    if M.opts.matrix.enabled then
        M.show_matrix_loading()
        vim.notify("🚀 Running: " .. title, vim.log.levels.INFO)

        if vim.system then
            vim.system({ "sh", "-c", cmd_string }, { text = true }, function(result)
                vim.schedule(function()
                    M.hide_matrix_loading()

                    if result.code ~= 0 then
                        vim.notify("❌ Query failed with exit code: " .. result.code, vim.log.levels.ERROR)
                        if result.stderr and result.stderr ~= "" then
                            vim.notify("Error: " .. result.stderr, vim.log.levels.ERROR)
                        end
                        return
                    end

                    local output = result.stdout or ""
                    local parsed_data = parse_psql_output(output)
                    
                    -- Pass original query and database context
                    create_table_viewer(parsed_data, title, current_db_context, original_query)

                    vim.notify("✅ Query execution completed", vim.log.levels.INFO)
                end)
            end)
        end
    end
end

local setup = require("sqlnik.setup")
M.setup = setup.setup

return M
