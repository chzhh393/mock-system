#!/usr/bin/env python3
"""
高并发压力测试脚本 - 使用 asyncio + aiohttp

支持两种测试模式：
1. 端到端模式（默认）：测试完整请求响应，用于下游 RPS
2. 写入模式（--write-only）：只测试上游写入 TPS，不等待响应
"""

import asyncio
import aiohttp
import time
import json
import sys
import argparse
from urllib.parse import urlparse, urlunparse

# 服务分布配置（模拟真实流量比例）
CODES = [
    "fast", "fast", "fast",      # 30% 快速服务
    "normal", "normal",          # 20% 普通服务
    "yhzx", "yhzx",              # 20% 用户中心
    "zdzx",                      # 10% 账单中心
    "slow",                      # 10% 慢速服务
    "unstable"                   # 10% 不稳定服务
]

class AsyncLoadTester:
    def __init__(self, target_url, concurrency=100, duration=60, write_only=False):
        """
        target_url: 目标地址
        concurrency: 并发数（同时发起的请求数）
        duration: 测试持续时间（秒）
        write_only: 是否只测试写入（不等待响应）
        """
        self.target_url = target_url
        self.concurrency = concurrency
        self.duration = duration
        self.write_only = write_only
        self.request_count = 0
        self.success_count = 0
        self.error_count = 0
        self.stop_flag = False

    async def make_request(self, session, worker_id):
        """单个 worker 持续发送请求"""
        counter = 0
        while not self.stop_flag:
            counter += 1
            code = CODES[(worker_id + counter) % len(CODES)]
            url = f"{self.target_url}/inner/c1/{code}"
            body = f'code={code}&paramData={{"test":"perf","seq":{counter},"worker":{worker_id}}}'

            try:
                if self.write_only:
                    # 写入模式：极短超时，只关心请求是否被接收
                    async with session.post(
                        url,
                        data=body,
                        headers={'Content-Type': 'application/x-www-form-urlencoded'},
                        timeout=aiohttp.ClientTimeout(total=0.5, connect=0.3)
                    ) as response:
                        self.request_count += 1
                        # 写入模式下，只要服务端接收了请求就算成功
                        self.success_count += 1
                else:
                    # 端到端模式：等待完整响应
                    async with session.post(
                        url,
                        data=body,
                        headers={'Content-Type': 'application/x-www-form-urlencoded'},
                        timeout=aiohttp.ClientTimeout(total=30)
                    ) as response:
                        self.request_count += 1
                        if response.status == 200:
                            self.success_count += 1
                        else:
                            self.error_count += 1
            except asyncio.TimeoutError:
                self.request_count += 1
                if self.write_only:
                    # 写入模式下超时是预期的（我们不等待响应）
                    self.success_count += 1
                else:
                    self.error_count += 1
            except Exception as e:
                self.request_count += 1
                self.error_count += 1

    async def stop_after_duration(self):
        """定时停止"""
        await asyncio.sleep(self.duration)
        self.stop_flag = True

    async def run_test(self):
        """运行测试"""
        print("=" * 50)
        if self.write_only:
            print("   上游写入 TPS 测试（Write-Only 模式）")
        else:
            print("   异步高并发压力测试（端到端模式）")
        print("=" * 50)
        print(f"目标URL: {self.target_url}")
        print(f"并发数: {self.concurrency}")
        print(f"持续时间: {self.duration}s")
        print(f"测试模式: {'写入模式' if self.write_only else '端到端模式'}")
        print()

        # 创建连接池
        connector = aiohttp.TCPConnector(
            limit=self.concurrency,      # 连接池大小
            limit_per_host=self.concurrency,
            keepalive_timeout=30
        )

        start_time = time.time()

        async with aiohttp.ClientSession(connector=connector) as session:
            # 启动定时器
            timer_task = asyncio.create_task(self.stop_after_duration())

            # 启动所有 worker
            workers = [
                asyncio.create_task(self.make_request(session, i))
                for i in range(self.concurrency)
            ]

            # 等待定时器结束
            await timer_task

            # 等待所有 worker 完成当前请求
            await asyncio.sleep(0.5)

            # 取消所有 worker
            for w in workers:
                w.cancel()

        elapsed = time.time() - start_time
        rps = self.request_count / elapsed

        print("-" * 50)
        print("客户端测试结果:")
        print(f"  总请求数: {self.request_count}")
        print(f"  成功请求: {self.success_count}")
        print(f"  错误请求: {self.error_count}")
        print(f"  总耗时: {elapsed:.2f}s")
        if self.write_only:
            print(f"  客户端发送 RPS: {rps:.2f}")
        else:
            print(f"  端到端 RPS: {rps:.2f}")
        if self.request_count > 0:
            success_rate = (self.success_count / self.request_count) * 100
            print(f"  成功率: {success_rate:.2f}%")
        print("-" * 50)

        return rps


async def main():
    # 解析命令行参数
    parser = argparse.ArgumentParser(description='高并发压力测试脚本')
    parser.add_argument('concurrency', type=int, nargs='?', default=500, help='并发数')
    parser.add_argument('duration', type=int, nargs='?', default=60, help='持续时间(秒)')
    parser.add_argument('target_url', type=str, nargs='?', default='http://192.168.123.66:8080', help='目标URL')
    parser.add_argument('--write-only', '-w', action='store_true', help='写入模式：只测试上游写入TPS，不等待响应')

    args = parser.parse_args()

    concurrency = args.concurrency
    duration = args.duration
    target_url = args.target_url
    write_only = args.write_only

    # 根据 target_url 动态生成上游统计 URL
    parsed_target = urlparse(target_url)
    upstream_stats_url = urlunparse(parsed_target._replace(path='/api/stats'))


    tester = AsyncLoadTester(target_url, concurrency=concurrency, duration=duration, write_only=write_only)

    # 重置统计
    print("重置统计...")
    try:
        async with aiohttp.ClientSession() as session:
            # 重置上游 scp0005 统计
            await session.post(f"{upstream_stats_url}/reset", timeout=aiohttp.ClientTimeout(total=5))

    except:
        pass

    # 运行测试
    client_rps = await tester.run_test()

    # 获取上游 scp0005 统计（写入 TPS）
    print()
    print("scp0005 上游统计:")
    write_tps = 0
    try:
        connector = aiohttp.TCPConnector(force_close=True)
        async with aiohttp.ClientSession(connector=connector) as session:
            async with session.get(upstream_stats_url, timeout=aiohttp.ClientTimeout(total=5)) as resp:
                stats = await resp.json()
                print(json.dumps(stats, indent=2, ensure_ascii=False))

                data = stats.get('data', {})
                metrics = data.get('metrics', {})
                mysql_write_success = metrics.get('mysqlWriteSuccess', 0)
                mysql_write_fail = metrics.get('mysqlWriteFail', 0)
                duration_sec = data.get('durationSeconds', duration)

                if duration_sec > 0:
                    write_tps = mysql_write_success / duration_sec
    except Exception as e:
        print(f"获取上游统计失败: {e}")

    if write_only:
        # 写入模式：只显示写入 TPS
        print()
        print("=" * 50)
        print(f"   ★ 上游写入 TPS: {write_tps:.2f}")
        print(f"   客户端发送 RPS: {client_rps:.2f}")
        print("=" * 50)



if __name__ == "__main__":
    print("用法: python3 load_test.py [并发数] [持续时间] [目标URL] [--write-only]")
    print()
    print("示例:")
    print("  # 端到端模式（测试完整请求响应）")
    print("  python3 load_test.py 500 60 http://192.168.123.66:8080")
    print()
    print("  # 写入模式（只测试上游写入 TPS，推荐用于第一阶段优化）")
    print("  python3 load_test.py 1000 60 http://192.168.123.113:8080 --write-only")
    print()
    asyncio.run(main())
