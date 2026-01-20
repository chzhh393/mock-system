#!/usr/bin/env python3
"""
高并发压力测试脚本 - 使用 asyncio + aiohttp
用于测试 scp0006 下游调用 RPS
"""

import asyncio
import aiohttp
import time
import json
import sys

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
    def __init__(self, target_url, concurrency=100, duration=60):
        """
        target_url: 目标地址
        concurrency: 并发数（同时发起的请求数）
        duration: 测试持续时间（秒）
        """
        self.target_url = target_url
        self.concurrency = concurrency
        self.duration = duration
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
        print("   异步高并发压力测试")
        print("=" * 50)
        print(f"目标URL: {self.target_url}")
        print(f"并发数: {self.concurrency}")
        print(f"持续时间: {self.duration}s")
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
        print("测试结果:")
        print(f"  总请求数: {self.request_count}")
        print(f"  成功请求: {self.success_count}")
        print(f"  错误请求: {self.error_count}")
        print(f"  总耗时: {elapsed:.2f}s")
        print(f"  端到端 RPS: {rps:.2f}")
        if self.request_count > 0:
            success_rate = (self.success_count / self.request_count) * 100
            print(f"  成功率: {success_rate:.2f}%")
        print("-" * 50)

        return rps


async def main():
    # 解析参数
    concurrency = int(sys.argv[1]) if len(sys.argv) > 1 else 500
    duration = int(sys.argv[2]) if len(sys.argv) > 2 else 60
    target_url = sys.argv[3] if len(sys.argv) > 3 else "http://192.168.123.66:8080"
    stats_url = "http://192.168.123.81:8083/api/stats"

    tester = AsyncLoadTester(target_url, concurrency=concurrency, duration=duration)

    # 重置统计
    print("重置 target-service 统计...")
    try:
        async with aiohttp.ClientSession() as session:
            await session.post(f"{stats_url}/reset", timeout=aiohttp.ClientTimeout(total=5))
    except:
        pass

    # 运行测试
    rps = await tester.run_test()

    # 获取下游统计
    print()
    print("target-service 统计:")
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(stats_url, timeout=aiohttp.ClientTimeout(total=5)) as resp:
                stats = await resp.json()
                print(json.dumps(stats, indent=2, ensure_ascii=False))

                total = stats.get('data', {}).get('totalRequests', 0)
                downstream_rps = total / duration

                print()
                print("=" * 50)
                print(f"   下游调用 RPS: {downstream_rps:.2f}")
                print(f"   端到端 RPS: {rps:.2f}")
                print("=" * 50)
    except Exception as e:
        print(f"获取统计失败: {e}")


if __name__ == "__main__":
    print("用法: python3 load_test.py [并发数] [持续时间] [目标URL]")
    print("示例: python3 load_test.py 500 60 http://192.168.123.66:8080")
    print()
    asyncio.run(main())
