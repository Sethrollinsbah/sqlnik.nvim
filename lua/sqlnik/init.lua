local config = require("sqlnik.config")
local M = {}

-- Private function to run a command in a terminal with matrix loading
local function run_in_terminal(cmd_string, title)
    config.run_in_terminal_with_matrix(cmd_string, title)
end

-- Private function to find DATABASE_URL and determine the DB driver
local function get_db_info()
    local file = io.open(config.opts.env_file, "r")
    if not file then
        return nil, nil
    end

    for line in file:lines() do
        local url = line:match('^%s*DATABASE_URL%s*=%s*[\'"]?([^\'"]+)[\'"]?%s*$')
        if url then
            file:close()
            local driver = url:match("^(%w+):")
            return url, driver
        end
    end

    file:close()
    return nil, nil
end

-- Enhanced function to validate query before execution
local function validate_query(query)
    -- Remove comments and whitespace for validation
    local cleaned_query = query:gsub("%-%-[^\n]*", ""):gsub("%s+", " "):match("^%s*(.-)%s*$")

    if cleaned_query == "" then
        return false, "Query is empty after removing comments"
    end

    -- Check for potentially dangerous operations (optional safety check)
    local dangerous_patterns = {
        "DROP%s+DATABASE",
        "DROP%s+SCHEMA",
        "TRUNCATE%s+TABLE"
    }

    for _, pattern in ipairs(dangerous_patterns) do
        if cleaned_query:upper():match(pattern) then
            -- Ask for confirmation on dangerous operations
            local choice = vim.fn.confirm("⚠️ Potentially destructive query detected. Continue?", "&Yes\n&No", 2)
            if choice ~= 1 then
                return false, "Query execution cancelled by user"
            end
            break
        end
    end

    return true, nil
end

-- Function to run the query picker from the buffer
function M.run_picker()
    local db_url, db_driver = get_db_info()
    if not db_url then
        vim.notify("❌ No " .. config.opts.env_file .. " file found or DATABASE_URL is missing.", vim.log.levels.WARN)
        return
    end

    local handler = config.opts.db_handlers[db_driver]
    if not handler then
        vim.notify("❌ Unsupported database driver: " .. db_driver, vim.log.levels.ERROR)
        return
    end

    if vim.fn.executable(handler.executable) == 0 then
        vim.notify("❌ `" .. handler.executable .. "` command not found in your PATH.", vim.log.levels.ERROR)
        return
    end

    -- Find named queries in buffer
    local function find_named_queries_in_buffer()
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        local queries = {}
        local current_query_lines = nil
        local current_name = nil
        local current_params = nil
        local current_description = nil

        for line_num, line in ipairs(lines) do
            local name_match = line:match("^--%s*[Nn]ame:%s*(.+)$")
            local desc_match = line:match("^--%s*[Dd]esc:%s*(.+)$") or line:match("^--%s*[Dd]escription:%s*(.+)$")
            local param_match_num, param_match_val = line:match("^--%s*%$([0-9]+):%s*(.+)$")

            if name_match then
                -- Save previous query if exists
                if current_name and current_query_lines and #current_query_lines > 0 then
                    table.insert(
                        queries,
                        {
                            name = current_name,
                            query = table.concat(current_query_lines, "\n"),
                            params = current_params or {},
                            description = current_description,
                            line_number = line_num
                        }
                    )
                end

                current_name = name_match:match("^%s*(.-)%s*$")
                current_query_lines = {}
                current_params = {}
                current_description = nil
            elseif desc_match and current_name then
                current_description = desc_match:match("^%s*(.-)%s*$")
            elseif param_match_num and current_params then
                local param_value = param_match_val:match("^%s*(.-)%s*$")
                current_params[tonumber(param_match_num)] = param_value
            elseif current_name then
                -- Skip empty lines at the beginning of query
                if #current_query_lines > 0 or line:match("%S") then
                    table.insert(current_query_lines, line)
                end
            end
        end

        -- Don't forget the last query
        if current_name and current_query_lines and #current_query_lines > 0 then
            table.insert(
                queries,
                {
                    name = current_name,
                    query = table.concat(current_query_lines, "\n"),
                    params = current_params or {},
                    description = current_description,
                    line_number = #lines
                }
            )
        end

        return queries
    end

    local queries = find_named_queries_in_buffer()
    if #queries == 0 then
        vim.notify("⚠️ No named queries found. Use '-- Name: Your Query Name' to label a query.", vim.log.levels.WARN)
        return
    end

    vim.ui.select(
        queries,
        {
            prompt = "⚡ Select a query to run:",
            format_item = function(item)
                local display = "📋 " .. item.name
                if item.description then
                    display = display .. " - " .. item.description
                end
                if item.params and next(item.params) then
                    display = display .. " 🔧"
                end
                return display
            end
        },
        function(choice)
            if not choice then
                return
            end

            local query_to_run = choice.query

            -- Validate query before execution
            local is_valid, error_msg = validate_query(query_to_run)
            if not is_valid then
                vim.notify("❌ " .. error_msg, vim.log.levels.ERROR)
                return
            end

            -- Handle SQL parameter substitution
            local function sql_format_value(value)
                local inner_str = value:match('^"(.*)"$') or value:match("^'(.*)'$")
                if inner_str then
                    return "'" .. inner_str:gsub("'", "''") .. "'"
                end
                -- Handle numeric values
                if tonumber(value) then
                    return tostring(value)
                end
                -- Default to quoted string
                return "'" .. tostring(value):gsub("'", "''") .. "'"
            end

            if choice.params and next(choice.params) ~= nil then
                for i = #choice.params, 1, -1 do
                    local val = choice.params[i]
                    if val then
                        query_to_run = query_to_run:gsub("%$" .. i, sql_format_value(val))
                    end
                end
            end

            local final_cmd = handler.build_command(db_url, query_to_run)
            if final_cmd then
                run_in_terminal(final_cmd, "📋 " .. choice.name)
            end
        end
    )
end

-- Function to run the currently visually selected query
function M.run_visual_selection()
    local start_row, start_col = unpack(vim.api.nvim_buf_get_mark(0, "<"))
    local end_row, end_col = unpack(vim.api.nvim_buf_get_mark(0, ">"))
    local lines = vim.api.nvim_buf_get_lines(0, start_row - 1, end_row, false)

    if #lines == 0 then
        vim.notify("⚠️ No lines selected.", vim.log.levels.WARN)
        return
    end

    -- Handle visual selection properly
    if #lines == 1 then
        lines[1] = string.sub(lines[1], start_col + 1, end_col + 1)
    else
        lines[#lines] = string.sub(lines[#lines], 1, end_col + 1)
        lines[1] = string.sub(lines[1], start_col + 1)
    end

    local query_to_run = table.concat(lines, "\n")

    -- Validate the visual selection
    local is_valid, error_msg = validate_query(query_to_run)
    if not is_valid then
        vim.notify("❌ " .. error_msg, vim.log.levels.WARN)
        return
    end

    local db_url, db_driver = get_db_info()
    if not db_url then
        vim.notify("❌ No " .. config.opts.env_file .. " file found or DATABASE_URL is missing.", vim.log.levels.WARN)
        return
    end

    local handler = config.opts.db_handlers[db_driver]
    if not handler then
        vim.notify("❌ Unsupported database driver: " .. db_driver, vim.log.levels.ERROR)
        return
    end

    if vim.fn.executable(handler.executable) == 0 then
        vim.notify("❌ `" .. handler.executable .. "` command not found in your PATH.", vim.log.levels.ERROR)
        return
    end

    local final_cmd = handler.build_command(db_url, query_to_run)
    if final_cmd then
        run_in_terminal(final_cmd, "🎯 Visual Selection")
    end
end

-- Function to run query under cursor (new feature)
function M.run_query_under_cursor()
    -- Find the nearest named query above the cursor
    local current_line = vim.api.nvim_win_get_cursor(0)[1]
    local lines = vim.api.nvim_buf_get_lines(0, 0, current_line, false)

    local query_start = nil
    local query_name = nil

    -- Search backwards for the nearest query name
    for i = #lines, 1, -1 do
        local line = lines[i]
        local name_match = line:match("^--%s*[Nn]ame:%s*(.+)$")
        if name_match then
            query_start = i
            query_name = name_match:match("^%s*(.-)%s*$")
            break
        end
    end

    if not query_start or not query_name then
        vim.notify("⚠️ No named query found above cursor.", vim.log.levels.WARN)
        return
    end

    -- Find all queries and execute the one we found
    local queries = {}
    local all_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local current_query_lines = nil
    local current_name = nil
    local found_target = false

    for _, line in ipairs(all_lines) do
        local name_match = line:match("^--%s*[Nn]ame:%s*(.+)$")
        if name_match then
            if current_name and current_query_lines and #current_query_lines > 0 then
                table.insert(queries, {name = current_name, query = table.concat(current_query_lines, "\n")})
                if current_name == query_name then
                    found_target = true
                    break
                end
            end
            current_name = name_match:match("^%s*(.-)%s*$")
            current_query_lines = {}
        elseif current_name and not line:match("^--%s*%$[0-9]+:") then
            table.insert(current_query_lines, line)
        end
    end

    -- Handle the last query
    if not found_target and current_name == query_name and current_query_lines and #current_query_lines > 0 then
        table.insert(queries, {name = current_name, query = table.concat(current_query_lines, "\n")})
        found_target = true
    end

    if not found_target then
        vim.notify("❌ Could not find query: " .. query_name, vim.log.levels.ERROR)
        return
    end

    -- Execute the found query
    local target_query = nil
    for _, q in ipairs(queries) do
        if q.name == query_name then
            target_query = q
            break
        end
    end

    if target_query then
        local db_url, db_driver = get_db_info()
        if not db_url then
            vim.notify(
                "❌ No " .. config.opts.env_file .. " file found or DATABASE_URL is missing.",
                vim.log.levels.WARN
            )
            return
        end

        local handler = config.opts.db_handlers[db_driver]
        if not handler then
            vim.notify("❌ Unsupported database driver: " .. db_driver, vim.log.levels.ERROR)
            return
        end

        local final_cmd = handler.build_command(db_url, target_query.query)
        if final_cmd then
            run_in_terminal(final_cmd, "🎯 " .. target_query.name)
        end
    end
end

-- The main setup function for the plugin
function M.setup(user_opts)
    config.setup(user_opts)
end

return M

