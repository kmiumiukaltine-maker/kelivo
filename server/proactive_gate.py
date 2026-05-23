"""
每30分钟运行，用 AI 判断要不要唤醒主动说话。
"""
import json
import os
import requests
from datetime import datetime

GATE_CONFIG_FILE = "/home/ubuntu/gate_config.json"
KALTINE_URL = "https://kaltine.zeabur.app/mcp"
KALTINE_TOKEN = ""  # 填你的 kaltine token
PUSH_URL = "http://localhost:5233/wake"

def load_gate_config():
    try:
        with open(GATE_CONFIG_FILE) as f:
            return json.load(f)
    except Exception:
        return {
            "api_url": "https://你的API地址/v1/chat/completions",
            "api_key": "sk-你的key",
            "model": "gemini-2.5-flash",
        }

def get_recent_feels():
    try:
        headers = {"Authorization": f"Bearer {KALTINE_TOKEN}", "Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        r = requests.post(KALTINE_URL, headers=headers, json={"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"gate","version":"1.0"}}}, timeout=15)
        sid = r.headers.get("mcp-session-id")
        if not sid:
            return ""
        headers["mcp-session-id"] = sid
        r2 = requests.post(KALTINE_URL, headers=headers, json={"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"breath","arguments":{"max_results":5}}}, timeout=30)
        for line in r2.text.split("\n"):
            if line.startswith("data:"):
                try:
                    d = json.loads(line[5:].strip())
                    content = d.get("result",{}).get("content",[])
                    if content:
                        return content[0].get("text","")[:1000]
                except:
                    pass
    except:
        pass
    return ""

def should_wake(feels, hour):
    cfg = load_gate_config()
    now_str = datetime.now().strftime("%Y-%m-%d %H:%M")
    prompt = f"""现在是{now_str}（北京时间），小时={hour}。

AI 伴侣最近的 feel 记录：
{feels or '暂无记录'}

判断：AI 现在适不适合主动给用户发一条消息？

规则：
- 深夜0-7点：不要打扰，用户在睡觉
- 一天内不超过3次主动消息
- 如果feel里有未说完的情绪或想法，可以主动
- 如果距离上次对话很久了，可以主动
- 保持随机性，不要太规律

只回答JSON：{{"wake": true/false, "reason": "一句话原因"}}"""

    api_url = cfg["api_url"].rstrip("/")
    if not api_url.endswith("/chat/completions"):
        api_url += "/chat/completions"
    try:
        import re
        r = requests.post(api_url, headers={"Authorization": f"Bearer {cfg['api_key']}", "Content-Type": "application/json"},
            json={"model": cfg["model"], "messages": [{"role": "user", "content": prompt}], "max_tokens": 1000, "stream": True}, timeout=90, stream=True)
        text = ""
        for line in r.iter_lines(decode_unicode=True):
            if not line:
                continue
            if line.startswith("data:"):
                chunk = line[5:].strip()
                if chunk == "[DONE]":
                    break
                try:
                    data = json.loads(chunk)
                    text += data.get("choices", [{}])[0].get("delta", {}).get("content", "")
                except:
                    pass
        m = re.search(r'\{.*\}', text, re.DOTALL)
        if m:
            d = json.loads(m.group())
            return d.get("wake", False), d.get("reason", "")
    except Exception as e:
        print(f"gate error: {e}")
    return False, ""

def main():
    hour = datetime.now().hour
    print(f"[gate] running at hour={hour}")

    feels = get_recent_feels()
    wake, reason = should_wake(feels, hour)
    print(f"[gate] wake={wake} reason={reason}")

    if wake:
        r = requests.post(PUSH_URL, json={"reason": reason, "context": feels[:300]}, timeout=90)
        print(f"[gate] wake result: {r.json()}")

if __name__ == "__main__":
    main()
