from __future__ import annotations
import asyncio
import json
import queue
import threading
import time
import requests
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

app = FastAPI()

_queues = []
_lock = threading.Lock()
_log = []  # push history, max 100

GATEWAY_URL = "http://localhost:8090/gw/v1/chat/completions"  # 你的网关地址
GATE_CONFIG_FILE = "/home/ubuntu/gate_config.json"


def _log_event(event_type: str, detail: str):
    _log.append({"time": datetime.now().strftime("%m-%d %H:%M"), "type": event_type, "detail": detail})
    if len(_log) > 100:
        _log.pop(0)


@app.get("/push-api/events")
@app.get("/events")
async def events(request: Request):
    q: queue.Queue = queue.Queue()
    with _lock:
        _queues.append(q)

    async def stream():
        yield ": connected\n\n"
        try:
            while True:
                if await request.is_disconnected():
                    break
                try:
                    msg = q.get_nowait()
                    yield f"data: {json.dumps(msg, ensure_ascii=False)}\n\n"
                except queue.Empty:
                    yield ": ping\n\n"
                    await asyncio.sleep(5)
        finally:
            with _lock:
                if q in _queues:
                    _queues.remove(q)

    return StreamingResponse(stream(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@app.post("/push")
async def push(request: Request):
    """Push a proactive message to all connected clients."""
    body = await request.json()
    content = body.get("content", "")
    if not content:
        return JSONResponse({"ok": False, "error": "empty content"})

    msg = {"type": "proactive", "content": content, "time": datetime.now().strftime("%H:%M")}
    with _lock:
        for q in _queues:
            q.put(msg)
        clients = len(_queues)

    _log_event("push", content[:60])
    return {"ok": True, "clients": clients}



@app.post("/wake")
async def wake(request: Request):
    """Wake up the AI and let it generate a proactive message."""
    body = await request.json()
    reason = body.get("reason", "")
    context = body.get("context", "")

    parts = []
    if context:
        parts.append(context)
    if reason:
        parts.append(reason)
    prompt = "\n\n".join(parts) if parts else ""
    messages = [{"role": "user", "content": f"{prompt}\n\n你现在想给用户主动发一条消息。".strip()}]

    try:
        import httpx
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(GATEWAY_URL,
                headers={"Authorization": "Bearer sk-your-key", "Content-Type": "application/json"},
                json={"model": "auto", "messages": messages,
                      "max_tokens": 2000, "stream": True})

            reply = ""
            async for line in resp.aiter_lines():
                if line.startswith("data:"):
                    chunk = line[5:].strip()
                    if chunk == "[DONE]":
                        break
                    try:
                        data = json.loads(chunk)
                        reply += data.get("choices", [{}])[0].get("delta", {}).get("content", "")
                    except:
                        pass

        if reply:
            msg = {"type": "proactive", "content": reply, "time": datetime.now().strftime("%H:%M")}
            with _lock:
                for q in _queues:
                    q.put(msg)
            _log_event("wake", reply[:60])
            return {"ok": True, "content": reply}
        return {"ok": False, "error": "empty reply"}
    except Exception as e:
        _log_event("error", str(e))
        return JSONResponse({"ok": False, "error": str(e)}, status_code=500)


@app.get("/gate-config")
def get_gate_config():
    try:
        with open(GATE_CONFIG_FILE) as f:
            return json.load(f)
    except Exception:
        return {"api_url": "", "api_key": "", "model": "gemini-2.5-flash"}


@app.post("/gate-config")
async def set_gate_config(request: Request):
    body = await request.json()
    cfg = {
        "api_url": body.get("api_url", ""),
        "api_key": body.get("api_key", ""),
        "model": body.get("model", "gemini-2.5-flash"),
        "system_prompt": body.get("system_prompt", ""),
    }
    with open(GATE_CONFIG_FILE, "w") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    return {"ok": True}


@app.get("/logs")
def logs():
    return {"logs": list(reversed(_log))}


@app.get("/status")
def status():
    with _lock:
        clients = len(_queues)
    return {"clients": clients, "log_count": len(_log)}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5233)
