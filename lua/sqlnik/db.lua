local M = {}

M.fk_lookup_queries = {
    postgresql = [[
        SELECT
            tc.constraint_name,
            kcu.column_name,
            ccu.table_name AS foreign_table_name,
            ccu.column_name AS foreign_column_name
        FROM
            information_schema.table_constraints AS tc
        JOIN information_schema.key_column_usage AS kcu
            ON tc.constraint_name = kcu.constraint_name AND tc.table_schema = kcu.table_schema
        JOIN information_schema.constraint_column_usage AS ccu
            ON ccu.constraint_name = tc.constraint_name AND ccu.table_schema = tc.table_schema
        WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_name = '%s';
    ]],
    mysql = [[
        SELECT
            kcu.constraint_name,
            kcu.column_name,
            kcu.referenced_table_name,
            kcu.referenced_column_name
        FROM
            information_schema.key_column_usage AS kcu
        JOIN information_schema.table_constraints AS tc
            ON kcu.constraint_name = tc.constraint_name AND kcu.table_schema = tc.table_schema
        WHERE
            tc.constraint_type = 'FOREIGN KEY'
            AND kcu.table_schema = DATABASE()
            AND kcu.table_name = '%s';
    ]],
    sqlite = "PRAGMA foreign_key_list('%s');"
}

return M
