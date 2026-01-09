-- 内网数据库初始化脚本
-- 数据库：inner_gateway
-- 表：inner_request（请求表）

-- 使用数据库
USE inner_gateway;

-- 创建请求表
CREATE TABLE IF NOT EXISTS inner_request (
    id BIGINT PRIMARY KEY AUTO_INCREMENT COMMENT '自增主键',
    request_id VARCHAR(64) NOT NULL COMMENT '请求唯一ID',
    code VARCHAR(32) NOT NULL COMMENT '服务编码/穿透码',
    param_data TEXT NOT NULL COMMENT '请求参数JSON',
    channel_type VARCHAR(50) COMMENT '通道类型',
    serial_no VARCHAR(64) COMMENT '流水号',
    source VARCHAR(50) COMMENT '来源',
    target VARCHAR(50) COMMENT '目标（省码）',
    status TINYINT DEFAULT 0 COMMENT '状态：0-待处理 1-处理中 2-已完成 3-失败',
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',

    UNIQUE KEY uk_request_id (request_id),
    INDEX idx_status (status),
    INDEX idx_create_time (create_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='内网请求表';

-- 创建服务路由配置表
CREATE TABLE IF NOT EXISTS service_route (
    id BIGINT PRIMARY KEY AUTO_INCREMENT COMMENT '自增主键',
    code VARCHAR(32) NOT NULL COMMENT '服务编码',
    service_url VARCHAR(500) NOT NULL COMMENT '目标服务URL',
    service_name VARCHAR(100) COMMENT '服务名称',
    enabled TINYINT DEFAULT 1 COMMENT '是否启用：1-启用 0-禁用',
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',

    UNIQUE KEY uk_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='服务路由配置表';

-- 插入默认路由配置
INSERT INTO service_route (code, service_url, service_name) VALUES
('0000', 'http://target-service:8017/inner/c17/f01', '默认测试服务'),
('yhzx', 'http://target-service:8017/inner/c17/f01', '用户中心服务'),
('zdzx', 'http://target-service:8017/inner/c17/f01', '账单中心服务');

-- 创建 Canal 用户（用于 Binlog 监听）
CREATE USER IF NOT EXISTS 'canal'@'%' IDENTIFIED BY 'canal123';
GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'canal'@'%';

-- 允许 root 远程访问
CREATE USER IF NOT EXISTS 'root'@'%' IDENTIFIED BY 'root123';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;

FLUSH PRIVILEGES;

-- 输出初始化完成信息
SELECT 'inner_gateway database initialized successfully!' AS message;
SELECT COUNT(*) AS table_count FROM information_schema.tables WHERE table_schema = 'inner_gateway';
