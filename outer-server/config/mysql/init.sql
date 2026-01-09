-- 外网数据库初始化脚本
-- 数据库：outer_gateway
-- 表：outer_response（响应表）

-- 使用数据库
USE outer_gateway;

-- 创建响应表
CREATE TABLE IF NOT EXISTS outer_response (
    id BIGINT PRIMARY KEY AUTO_INCREMENT COMMENT '自增主键',
    request_id VARCHAR(64) NOT NULL COMMENT '请求唯一ID，与请求表关联',
    response_data TEXT COMMENT '响应数据JSON',
    response_code VARCHAR(10) DEFAULT '0000' COMMENT '响应码：0000-成功，其他-失败',
    error_msg VARCHAR(500) COMMENT '错误信息',
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',

    UNIQUE KEY uk_request_id (request_id),
    INDEX idx_create_time (create_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='外网响应表';

-- 创建 Canal 用户（用于 Binlog 监听）
CREATE USER IF NOT EXISTS 'canal'@'%' IDENTIFIED BY 'canal123';
GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'canal'@'%';

-- 允许 root 远程访问
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root123';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

FLUSH PRIVILEGES;

-- 输出初始化完成信息
SELECT 'outer_gateway database initialized successfully!' AS message;
SELECT COUNT(*) AS table_count FROM information_schema.tables WHERE table_schema = 'outer_gateway';
