# 临时 mock：模拟 Antifox 管理 API，用于端到端验证 pierce-install.ps1
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "requests.log")
AGENTS = [{"id": "1", "key": "planner"}, {"id": "2", "key": "worker"}, {"id": "3", "key": "mainagent"}]
SKILLS = set()
PROMPTS = {k: [{"version": 1, "template_text": "BASE PROMPT for %s {{.Goal}}" % k}] for a in AGENTS for k in [a["key"]]}


def log(line):
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


class H(BaseHTTPRequestHandler):
    def _send(self, code, obj):
        b = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        return raw.decode("utf-8")

    def log_message(self, *a):
        pass

    def do_GET(self):
        p = self.path.split("?")[0]
        log("GET " + p)
        if p == "/api/health":
            return self._send(200, {"ok": True})
        if p == "/api/agents":
            return self._send(200, {"agents": AGENTS})
        if p == "/api/skills":
            return self._send(200, {"skills": [{"name": s, "description": "x", "files": ["SKILL.md"]} for s in sorted(SKILLS)]})
        if p.startswith("/api/agents/") and p.endswith("/prompts"):
            key = p.split("/")[3]
            return self._send(200, {"versions": sorted(PROMPTS.get(key, []), key=lambda x: -x["version"])})
        if p.startswith("/api/visibility/skill/"):
            return self._send(200, {"agents": [1, 2, 3]})
        return self._send(404, {"error": "not found " + p})

    def do_POST(self):
        p = self.path.split("?")[0]
        body = self._body()
        log("POST %s %s" % (p, body[:300]))
        if p == "/api/auth/login":
            d = json.loads(body or "{}")
            if d.get("username") == "admin":
                return self._send(200, {"token": "mock-token"})
            return self._send(401, {"error": "bad creds"})
        if p == "/api/skills":
            d = json.loads(body or "{}")
            name = d.get("name", "")
            if name in SKILLS:
                return self._send(409, {"error": "skill already exists"})
            SKILLS.add(name)
            log("  -> created skill %s desc_len=%d instr_len=%d" % (name, len(d.get("description", "")), len(d.get("instructions", ""))))
            return self._send(201, {"name": name})
        if p == "/api/visibility/skill/toggle":
            d = json.loads(body or "{}")
            log("  -> visibility %s agent_id=%s visible=%s" % (d.get("skill_name"), d.get("agent_id"), d.get("visible")))
            return self._send(200, {"ok": True})
        return self._send(404, {"error": "not found " + p})

    def do_PUT(self):
        p = self.path.split("?")[0]
        body = self._body()
        if "/files/" in p:
            d = json.loads(body or "{}")
            log("PUT %s content_len=%d" % (p, len(d.get("content", ""))))
            return self._send(200, {"ok": True})
        if p.startswith("/api/agents/") and p.endswith("/prompt"):
            key = p.split("/")[3]
            d = json.loads(body or "{}")
            t = d.get("template", "")
            log("PUT %s template_len=%d note=%s has_marker=%s" % (p, len(t), d.get("note"), "PIERCE-CORE" in t))
            ver = len(PROMPTS.get(key, [])) + 1
            PROMPTS.setdefault(key, []).append({"version": ver, "template_text": t})
            return self._send(200, {"version": ver})
        return self._send(404, {"error": "not found " + p})


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 18080
    if os.path.exists(LOG):
        os.remove(LOG)
    print("mock listening on %d" % port)
    HTTPServer(("127.0.0.1", port), H).serve_forever()
