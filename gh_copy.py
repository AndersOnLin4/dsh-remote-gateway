# -*- coding: utf-8 -*-
"""GitHub 文案优化：仓库简介、标签、Release 标题与正文（UTF-8 安全，杜绝乱码）。"""
import json
import sys

import httpx

TOKEN_FILE = r"G:\Andersonlin4-design 远控二\.github-token.txt"
REPO = "AndersOnLin4/dsh-remote-gateway"
RELEASE_ID = 371791307  # v1.3.0

REPO_DESCRIPTION = (
    "DeepSeek Harness 远程控制套件：网页、Windows 桌面端、Android App 三形态，"
    "安全网关 + 实时推送 + 多端会话管理，出门在外也能监控、回复、答题。"
)

TOPICS = [
    "deepseek-harness", "remote-control", "fastapi", "electron",
    "flutter", "tailscale", "android", "windows",
]

RELEASE_NAME = "v1.3.0 · 远程控制套件（网页 / 桌面端 / Android）"

RELEASE_BODY = """## 本次发布

一个网关、三种形态，DSH 远程控制正式成套：

- 网页版：网关自带移动端仪表盘，浏览器即用
- Windows 桌面端：托盘常驻、自动登录、进程守护
- Android App：原生界面、实时推送、备用线路切换

## 下载（按需选择）

**DSH-Gateway-Desktop-0.1.0-portable.exe**
Windows 10/11 免安装桌面端，双击即用：托盘状态灯、一键启停 DSH 与网关、崩溃自动拉起、启动自动补位、Tailscale 自动唤醒与 HTTPS 转发、窗口自动登录仪表盘、首次运行弹出手机访问信息（地址与密码一键复制）。

**DSH-Gateway-Android-0.1.5-arm64.apk**
Android 手机侧载安装（系统设置中允许"未知来源"后直接安装）：监控 / 会话 / 回复 / 选择题作答 / 日志，SSE 实时推送与本地通知，内嵌完整控制台，备用地址自动切换。

## 使用提示

- App 登录建议：主地址填 Tailscale HTTPS 域名（如 https://xxx.ts.net），备用地址填局域网地址（如 http://192.168.1.100:8080），App 会自动选择可用线路
- 网页版：仓库根目录 install.cmd 安装、start-everything.cmd 启动，终端会打印访问地址与密码
- 已装旧版网关的用户：git pull 后重启网关即可获得 /gw/events 推送、JSON gzip 压缩、尾段增量协议、探活防抖等更新

## 文档

完整说明见仓库 README 与 DSH网关-App化方案.md
"""


def main():
    with open(TOKEN_FILE, encoding="utf-8") as f:
        token = f.read().strip()
    headers = {
        "Authorization": f"token {token}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "dsh-release-script",
    }
    base = f"https://api.github.com/repos/{REPO}"

    with httpx.Client(timeout=60.0, proxy="http://127.0.0.1:7893") as c:
        r1 = c.patch(base, headers=headers, json={"description": REPO_DESCRIPTION})
        print("description:", r1.status_code)
        r2 = c.put(f"{base}/topics", headers=headers, json={"names": TOPICS})
        print("topics:", r2.status_code, [t for t in r2.json().get("names", [])])
        r3 = c.patch(
            f"{base}/releases/{RELEASE_ID}",
            headers=headers,
            json={"name": RELEASE_NAME, "body": RELEASE_BODY},
        )
        print("release:", r3.status_code)
        if r3.status_code == 200:
            j = r3.json()
            print("release name:", j.get("name"))
            print("body preview:", (j.get("body") or "")[:80].replace("\n", " "))


if __name__ == "__main__":
    main()
