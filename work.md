- unicornに-E productionを追加
- my.cnf
    - slow_query_log
    - slow_query_log-file = /tmp/mysql-slow.sql
    - long_query_time = 1
- index
    - ALTER TABLE comments ADD INDEX index_product_id_on_comments(product_id);
    - ALTER TABLE comments ADD INDEX index_user_id_on_comments(user_id);

