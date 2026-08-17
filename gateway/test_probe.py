"""验证 DSH 探活：非强制防抖（拒绝连续 4 次才判死）+ 强制单次定生死。"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from app import monitor


def main():
    refused_flag = {"v": False}

    def fake_refused():
        return refused_flag["v"]

    monitor._probe_refused = fake_refused
    monitor._PROBE.update({"running": True, "fails": 0, "at": 0.0})

    # 1) 非强制：连续 3 次拒绝 → 仍 True（防抖窗口内；每次重置缓存时间戳模拟真实间隔）
    refused_flag["v"] = True
    r = []
    for _ in range(3):
        monitor._PROBE["at"] = 0.0
        r.append(monitor.dsh_running(force=False))
    print("非强制 3 次拒绝:", r, "预期全 True", "PASS" if all(r) else "FAIL")

    # 2) 非强制：第 4 次拒绝 → False
    monitor._PROBE["at"] = 0.0
    r4 = monitor.dsh_running(force=False)
    print("非强制 4 次拒绝:", r4, "预期 False", "PASS" if not r4 else "FAIL")

    # 3) 非强制恢复：立即 True
    monitor._PROBE["at"] = 0.0
    refused_flag["v"] = False
    r5 = monitor.dsh_running(force=False)
    print("非强制恢复:", r5, "预期 True", "PASS" if r5 else "FAIL")

    # 4) 强制单次定生死：全新状态 + 拒绝 → 立即 False（不吃防抖）
    monitor._PROBE.update({"running": True, "fails": 0, "at": 0.0})
    refused_flag["v"] = True
    r6 = monitor.dsh_running(force=True)
    print("强制单次拒绝:", r6, "预期 False（立即判死）", "PASS" if not r6 else "FAIL")

    # 5) 强制恢复：立即 True
    refused_flag["v"] = False
    r7 = monitor.dsh_running(force=True)
    print("强制恢复:", r7, "预期 True", "PASS" if r7 else "FAIL")

    # 6) 缓存窗口：非强制调用在窗口内沿用上次结果
    monitor._PROBE["at"] = time.time()
    refused_flag["v"] = True
    r8 = monitor.dsh_running(force=False)
    print("缓存窗口内:", r8, "预期 True（沿用上次结果）", "PASS" if r8 else "FAIL")


if __name__ == "__main__":
    main()
