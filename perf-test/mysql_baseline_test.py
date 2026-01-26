#!/usr/bin/env python3
"""
MySQL 写入基准测试脚本

直接测试 MySQL 的写入性能，绕过 scp0005。
支持单条插入和批量插入两种模式。
"""

import argparse
import time
import uuid
import threading
import mysql.connector


def create_connection(host, port, user, password, database):
    """创建单个数据库连接"""
    return mysql.connector.connect(
        host=host,
        port=port,
        user=user,
        password=password,
        database=database,
        autocommit=False
    )


def batch_insert_worker(conn, duration, worker_id, batch_size, results):
    """批量插入 worker"""
    cursor = conn.cursor()
    count = 0
    errors = 0
    start_time = time.time()

    insert_sql = """
        INSERT INTO inner_request
        (request_id, code, param_data, channel_type, serial_no, source, target, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    """

    while time.time() - start_time < duration:
        try:
            # 准备批量数据
            batch_data = []
            for i in range(batch_size):
                request_id = f"batch-{worker_id}-{uuid.uuid4().hex[:16]}"
                batch_data.append((
                    request_id,
                    'yhzx',
                    '{"test": "batch", "seq": ' + str(count + i) + '}',
                    'HTTP',
                    f'SN{count + i}',
                    'batch_test',
                    'target',
                    0
                ))

            cursor.executemany(insert_sql, batch_data)
            conn.commit()
            count += batch_size
        except Exception as e:
            errors += batch_size
            try:
                conn.rollback()
            except:
                pass

    cursor.close()
    results[worker_id] = {'count': count, 'errors': errors}


def single_insert_worker(conn, duration, worker_id, results):
    """单条插入 worker"""
    cursor = conn.cursor()
    count = 0
    errors = 0
    start_time = time.time()

    insert_sql = """
        INSERT INTO inner_request
        (request_id, code, param_data, channel_type, serial_no, source, target, status)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    """

    while time.time() - start_time < duration:
        try:
            request_id = f"single-{worker_id}-{uuid.uuid4().hex[:16]}"
            cursor.execute(insert_sql, (
                request_id,
                'yhzx',
                '{"test": "single"}',
                'HTTP',
                f'SN{count}',
                'single_test',
                'target',
                0
            ))
            conn.commit()
            count += 1
        except Exception as e:
            errors += 1

    cursor.close()
    results[worker_id] = {'count': count, 'errors': errors}


def run_test(host, port, user, password, database, duration, concurrency, batch_size):
    """运行测试"""
    mode = "批量插入" if batch_size > 1 else "单条插入"

    print("=" * 60)
    print(f"   MySQL 写入测试 ({mode})")
    print("=" * 60)
    print(f"目标: {host}:{port}/{database}")
    print(f"并发数: {concurrency}")
    print(f"持续时间: {duration}s")
    if batch_size > 1:
        print(f"批量大小: {batch_size}")
    print()

    # 创建连接
    connections = []
    for i in range(concurrency):
        try:
            conn = create_connection(host, port, user, password, database)
            connections.append(conn)
        except Exception as e:
            print(f"创建连接 {i} 失败: {e}")
            return 0

    print(f"成功创建 {len(connections)} 个连接")
    print()
    print("开始测试...")

    # 运行测试
    results = {}
    threads = []
    start_time = time.time()

    for i, conn in enumerate(connections):
        if batch_size > 1:
            t = threading.Thread(target=batch_insert_worker, args=(conn, duration, i, batch_size, results))
        else:
            t = threading.Thread(target=single_insert_worker, args=(conn, duration, i, results))
        threads.append(t)
        t.start()

    # 等待所有线程完成
    for t in threads:
        t.join()

    elapsed = time.time() - start_time

    # 统计结果
    total_count = sum(r['count'] for r in results.values())
    total_errors = sum(r['errors'] for r in results.values())
    tps = total_count / elapsed

    print()
    print("-" * 60)
    print("测试结果:")
    print(f"  总插入数: {total_count}")
    print(f"  总错误数: {total_errors}")
    print(f"  总耗时: {elapsed:.2f}s")
    print(f"  写入 TPS: {tps:.2f}")
    if total_count > 0:
        error_rate = (total_errors / (total_count + total_errors)) * 100
        print(f"  错误率: {error_rate:.2f}%")
    print("-" * 60)

    # 关闭连接
    for conn in connections:
        try:
            conn.close()
        except:
            pass

    return tps


def main():
    parser = argparse.ArgumentParser(description='MySQL 写入基准测试')
    parser.add_argument('--host', default='192.168.123.114', help='MySQL 主机地址')
    parser.add_argument('--port', type=int, default=3306, help='MySQL 端口')
    parser.add_argument('--user', default='root', help='MySQL 用户名')
    parser.add_argument('--password', default='root123', help='MySQL 密码')
    parser.add_argument('--database', default='inner_gateway', help='数据库名')
    parser.add_argument('--duration', type=int, default=60, help='测试持续时间(秒)')
    parser.add_argument('--concurrency', type=int, default=10, help='并发连接数')
    parser.add_argument('--batch-size', type=int, default=1, help='批量插入大小(默认1=单条插入)')

    args = parser.parse_args()

    print("用法: python3 mysql_baseline_test.py [选项]")
    print()
    print("选项:")
    print("  --host        MySQL 主机地址 (默认: 192.168.123.114)")
    print("  --port        MySQL 端口 (默认: 3306)")
    print("  --concurrency 并发连接数 (默认: 10)")
    print("  --duration    测试持续时间 (默认: 60秒)")
    print("  --batch-size  批量插入大小 (默认: 1，即单条插入)")
    print()
    print("示例:")
    print("  # 单条插入测试")
    print("  python3 mysql_baseline_test.py --concurrency 100 --duration 30")
    print()
    print("  # 批量插入测试 (10000+ TPS)")
    print("  python3 mysql_baseline_test.py --concurrency 50 --batch-size 100 --duration 60")
    print()

    run_test(
        args.host,
        args.port,
        args.user,
        args.password,
        args.database,
        args.duration,
        args.concurrency,
        args.batch_size
    )


if __name__ == "__main__":
    main()
