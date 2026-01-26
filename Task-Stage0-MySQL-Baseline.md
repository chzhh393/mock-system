# 第零阶段：MySQL 写入基准测试与优化

## 目标

你需要进行真实的优化，而不是只提方案，最终将 MySQL 写入 TPS 优化至 **≥ 10000 TPS**。

---
### 当前情况

```
客户端 → scp0005 (外网网关) → MySQL(B) 请求表
                                    ↓
                              当前 ~340 TPS
```

本阶段绕过 scp0005，直接测试 MySQL 的写入性能。

### 网络配置

| 机器 | 角色 | IP 地址 | MySQL 端口 |
|------|------|---------|-----------|
| 机器 A | 外网 | 192.168.123.66 | - |
| 机器 B | 内网 | 192.168.123.81 | 3306 |

MySQL 连接信息：
- Host: 192.168.123.81
- Port: 3306
- Database: inner_gateway
- User: root
- Password: root123

---



## 达标标准

| 指标 | 目标值 |
|------|--------|
| MySQL 写入 TPS | ≥ 10000 |
| 错误率 | < 1% |

---

## 测试表结构

使用与 scp0005 相同的 `inner_request` 表：

```sql
USE inner_gateway;

CREATE TABLE IF NOT EXISTS inner_request (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    request_id VARCHAR(64) NOT NULL,
    code VARCHAR(32) NOT NULL,
    param_data TEXT NOT NULL,
    channel_type VARCHAR(50),
    serial_no VARCHAR(64),
    source VARCHAR(50),
    target VARCHAR(50),
    status TINYINT DEFAULT 0,
    create_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    update_time DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_request_id (request_id),
    INDEX idx_status (status),
    INDEX idx_create_time (create_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

## 构建与测试

```bash
# 1. 安装依赖
pip3 install mysql-connector-python

# 2. 运行基准测试（在 perf-test 目录下）
cd perf-test
python3 mysql_baseline_test.py --host 192.168.123.81 --duration 60

# 3. 清理测试数据
mysql -h 192.168.123.81 -u root -proot123 inner_gateway \
  -e "DELETE FROM inner_request WHERE request_id LIKE 'baseline-%';"
```

---

## 重要约束

1. 每轮优化后，必须将优化内容和本轮优化效果追加到 `perf-test/mysql-optimization-iterations.md`
2. 测试期间不要运行其他压测任务
3. 本阶段仅优化 MySQL 写入，不涉及 scp0005 代码

---

## 参考：检查 MySQL 配置

```sql
-- 查看连接数限制
SHOW VARIABLES LIKE 'max_connections';

-- 查看 InnoDB 缓冲池
SHOW VARIABLES LIKE 'innodb_buffer_pool_size';

-- 查看当前连接数
SHOW STATUS LIKE 'Threads_connected';

-- 查看写入相关参数
SHOW VARIABLES LIKE 'innodb_flush_log_at_trx_commit';
SHOW VARIABLES LIKE 'sync_binlog';
```

---
