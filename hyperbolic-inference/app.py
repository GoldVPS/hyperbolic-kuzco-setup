from flask import Flask, request, jsonify, Response, stream_with_context
import requests, os, json, time

app = Flask(__name__)

# =========[ ENV ]=========
HYPERBOLIC_API_URL = os.getenv("HYPERBOLIC_API_URL", "https://api.hyperbolic.xyz/v1")
HYPERBOLIC_API_KEY = os.getenv("HYPERBOLIC_API_KEY", "")
HYPERBOLIC_MODEL   = os.getenv("HYPERBOLIC_MODEL", "meta-llama/Llama-3.2-3B-Instruct")

JSON_CT = "application/json"
DEFAULT_TIMEOUT = 300

# =========[ HELPERS ]=========
def _headers():
    return {
        "Authorization": f"Bearer {HYPERBOLIC_API_KEY}",
        "Content-Type": JSON_CT,
    }

def _post_chat(payload: dict) -> requests.Response:
    return requests.post(
        f"{HYPERBOLIC_API_URL}/chat/completions",
        json=payload,
        headers=_headers(),
        timeout=DEFAULT_TIMEOUT,
    )

def _stream_chat(payload: dict):
    """
    SSE passthrough dari Hyperbolic (OpenAI-compatible).
    """
    with requests.post(
        f"{HYPERBOLIC_API_URL}/chat/completions",
        json=payload,
        headers=_headers(),
        stream=True,
        timeout=DEFAULT_TIMEOUT,
    ) as r:
        r.raise_for_status()
        for line in r.iter_lines(decode_unicode=True):
            if line is None:
                continue
            # pastikan selalu prefix 'data: '
            yield (line if line.startswith("data:") else f"data: {line}") + "\n"
        # just in case upstream tidak mengirim [DONE]
        yield "data: [DONE]\n"

def _extract_text(resp_json: dict) -> str:
    try:
        ch = resp_json.get("choices", [])
        if ch:
            return ch[0].get("message", {}).get("content", "") or ""
    except Exception:
        pass
    return ""

@app.after_request
def _no_buffer(resp):
    # bantu proxy/nginx agar tidak buffer SSE
    resp.headers["X-Accel-Buffering"] = "no"
    resp.headers["Cache-Control"] = "no-store"
    return resp

# =========[ OLLAMA-COMPAT ]=========
@app.route('/api/tags', methods=['GET'])
def list_models():
    """
    Iklankan beberapa alias agar router gampang match.
    Upstream model tetap dikunci oleh HYPERBOLIC_MODEL.
    """
    m = HYPERBOLIC_MODEL
    aliases = [
        "llama-3.2-3b-instruct/fp-16",
        "llama-3.2-3b-instruct/fp16",
        "llama-3.2-3b-instruct/fp-8",
        "llama-3.2-3b-instruct/fp8",
        "llama-3.2-3b-instruct",
        "llama3.2-3b-instruct",
        m,
    ]
    models = [{
        "name": name,
        "model": name,
        "modified_at": "",
        "size": 0,
        "digest": "",
        "details": {
            "format": "openai-proxy",
            "family": "meta-llama",
            "parameter_size": "3B",
            "precision": "fp16"
        }
    } for name in aliases]
    return jsonify({"models": models})

@app.route('/api/generate', methods=['POST'])
def api_generate():
    """
    Ollama legacy /api/generate → panggil upstream non-stream lalu balas gaya Ollama minimal.
    """
    try:
        body = request.get_json(force=True, silent=True) or {}
        messages = body.get("messages") or [{"role": "user", "content": body.get("prompt", "")}]
        payload = {
            "model": HYPERBOLIC_MODEL,
            "messages": messages,
            "max_tokens": body.get("max_tokens", 512),
            "temperature": body.get("temperature", 0.7),
            "top_p": body.get("top_p", 0.9),
            "stream": False
        }
        r = _post_chat(payload)
        if r.status_code != 200:
            return jsonify({"error": f"Hyperbolic API error: {r.status_code}", "body": r.text}), 500
        text = _extract_text(r.json())
        return jsonify({
            "model": body.get("model") or HYPERBOLIC_MODEL,
            "response": text,
            "done": True,
            "context": [],
            "total_duration": 0,
            "load_duration": 0,
            "prompt_eval_count": 0,
            "prompt_eval_duration": 0,
            "eval_count": 0,
            "eval_duration": 0
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/chat', methods=['POST'])
def api_chat():
    """
    Ollama-compatible chat. stream:true → SSE passthrough.
    """
    try:
        req = request.get_json(force=True, silent=True) or {}
        if "messages" not in req and "prompt" in req:
            req["messages"] = [{"role": "user", "content": req.get("prompt", "")}]
        want_stream = bool(req.get("stream"))
        hp = dict(req); hp["model"] = HYPERBOLIC_MODEL

        if want_stream:
            hp["stream"] = True
            return Response(stream_with_context(_stream_chat(hp)), mimetype="text/event-stream")

        hp["stream"] = False
        r = _post_chat(hp)
        return Response(r.content, status=r.status_code, content_type=r.headers.get('content-type', JSON_CT))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# =========[ OPENAI-COMPAT ]=========
@app.route('/v1/chat/completions', methods=['POST'])
def chat_completions():
    """
    OpenAI-compatible. stream:true → SSE passthrough.
    """
    try:
        data = request.get_json(force=True, silent=True) or {}
        want_stream = bool(data.get("stream"))
        hp = dict(data); hp["model"] = HYPERBOLIC_MODEL

        if want_stream:
            hp["stream"] = True
            return Response(stream_with_context(_stream_chat(hp)), mimetype="text/event-stream")

        hp["stream"] = False
        r = _post_chat(hp)
        return Response(r.content, status=r.status_code, content_type=r.headers.get('content-type', JSON_CT))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# =========[ EXTRA KOMPAT (hindari 404) ]=========
@app.route('/api/openai/chat/completions', methods=['POST'])
def api_openai_chat_completions():
    """
    Beberapa worker memanggil jalur ini.
    """
    try:
        data = request.get_json(force=True, silent=True) or {}
        want_stream = bool(data.get("stream"))
        hp = dict(data); hp["model"] = HYPERBOLIC_MODEL
        if want_stream:
            hp["stream"] = True
            return Response(stream_with_context(_stream_chat(hp)), mimetype="text/event-stream")
        hp["stream"] = False
        r = _post_chat(hp)
        return Response(r.content, status=r.status_code, content_type=r.headers.get('content-type', JSON_CT))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/version', methods=['GET'])
def api_version():
    return jsonify({"version": "0.1.0", "engine": "openai-proxy"}), 200

@app.route('/api/embeddings', methods=['POST'])
def api_embeddings():
    """
    Jika upstream mendukung /embeddings, teruskan; jika tidak, balas 501 agar jelas.
    """
    try:
        body = request.get_json(force=True, silent=True) or {}
        url = f"{HYPERBOLIC_API_URL}/embeddings"
        r = requests.post(url, json=body, headers=_headers(), timeout=DEFAULT_TIMEOUT)
        if r.status_code == 404:
            return jsonify({"error": "embeddings not supported by upstream"}), 501
        return Response(r.content, status=r.status_code, content_type=r.headers.get('content-type', JSON_CT))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/', methods=['GET'])
def root_ok():
    return jsonify({"ok": True, "service": "hyperbolic-ollama-proxy"}), 200

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "model": HYPERBOLIC_MODEL})

# =========[ MAIN ]=========
if __name__ == '__main__':
    # Gunicorn akan handle di container; ini untuk dev/tes lokal.
    app.run(host='0.0.0.0', port=11434, debug=False)
