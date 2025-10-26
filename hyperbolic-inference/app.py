from flask import Flask, request, jsonify, Response, stream_with_context
import requests
import os
import json
import time
import uuid
import re

app = Flask(__name__)

# ======================
# ENV & DEFAULTS
# ======================
HYPERBOLIC_API_URL = os.getenv("HYPERBOLIC_API_URL", "https://api.hyperbolic.xyz/v1")
HYPERBOLIC_API_KEY = os.getenv("HYPERBOLIC_API_KEY", "")
HYPERBOLIC_MODEL   = os.getenv("HYPERBOLIC_MODEL", "meta-llama/Llama-3.2-3B-Instruct")

DEFAULT_TIMEOUT = 60
JSON_CT = "application/json"

# ======================
# HELPERS
# ======================
def _hyperbolic_post_chat(payload: dict) -> requests.Response:
    headers = {
        "Authorization": f"Bearer {HYPERBOLIC_API_KEY}",
        "Content-Type": JSON_CT,
    }
    return requests.post(
        f"{HYPERBOLIC_API_URL}/chat/completions",
        json=payload,
        headers=headers,
        timeout=DEFAULT_TIMEOUT,
    )

def _extract_text_from_openai(resp_json: dict) -> str:
    if isinstance(resp_json, dict):
        ch = resp_json.get("choices", [])
        if ch:
            return ch[0].get("message", {}).get("content", "") or ""
    return ""

def _words(text: str):
    return re.findall(r"\S+", text or "")

def _estimate_tokens_from_words(n_words: int) -> int:
    # kira-kira: token ≈ 1.3 * kata (biar tidak undercount)
    return max(1, int(round(n_words * 1.3)))

def _estimate_usage(messages, completion_text: str):
    prompt_words = 0
    if isinstance(messages, list):
        for m in messages:
            prompt_words += len(_words(m.get("content", "")))
    comp_words = len(_words(completion_text or ""))
    prompt_tokens = _estimate_tokens_from_words(prompt_words)
    completion_tokens = _estimate_tokens_from_words(comp_words)
    return {
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": prompt_tokens + completion_tokens
    }

def _sse_openai_chunks_per_word(text: str, model: str):
    """
    Bentuk stream SSE ala OpenAI, granular per-kata, supaya dashboard bisa menghitung Tok/s.
    Sertakan logprobs placeholder pada setiap chunk.
    """
    chunk_id = f"chatcmpl-{uuid.uuid4().hex[:24]}"
    words = _words(text)
    if not words:
        words = [text or ""]
    # kirim role hanya sekali di awal (beberapa klien suka begitu)
    first = True
    for w in words:
        delta = {"content": (w + " ")}
        if first:
            # sebagian klien senang kalau ada role di delta pertama
            delta["role"] = "assistant"
            first = False
        event = {
            "id": chunk_id,
            "object": "chat.completion.chunk",
            "created": int(time.time()),
            "model": model,
            "choices": [{
                "index": 0,
                "delta": delta,
                "logprobs": {"content": []},   # placeholder agar akses logprobs aman
                "finish_reason": None
            }]
        }
        yield "data: " + json.dumps(event) + "\n\n"
        # jangan sleep supaya kecepatan maksimal; kalau mau lebih “natural”, aktifkan:
        # time.sleep(0.005)

    final = {
        "id": chunk_id,
        "object": "chat.completion.chunk",
        "created": int(time.time()),
        "model": model,
        "choices": [{
            "index": 0,
            "delta": {},
            "logprobs": None,
            "finish_reason": "stop"
        }]
    }
    yield "data: " + json.dumps(final) + "\n\n"
    yield "data: [DONE]\n\n"

def convert_ollama_to_hyperbolic(ollama_data: dict) -> dict:
    """Map payload ala Ollama ke OpenAI-style untuk Hyperbolic."""
    if not isinstance(ollama_data, dict):
        ollama_data = {}
    messages = []
    if "prompt" in ollama_data:
        messages.append({"role": "user", "content": ollama_data.get("prompt", "")})
    elif "messages" in ollama_data and isinstance(ollama_data["messages"], list):
        messages = ollama_data["messages"]

    return {
        "model": HYPERBOLIC_MODEL,
        "messages": messages,
        "max_tokens": ollama_data.get("max_tokens", 512),
        "temperature": ollama_data.get("temperature", 0.7),
        "top_p": ollama_data.get("top_p", 0.9),
        "stream": False,  # Hyperbolic non-stream; stream disimulasikan saat perlu
    }

def convert_hyperbolic_to_ollama(hyperbolic_response: dict, original_model_name: str = None) -> dict:
    """Map respons OpenAI-style ke format minimal /api/generate Ollama."""
    try:
        original_model_name = original_model_name or HYPERBOLIC_MODEL
        content = _extract_text_from_openai(hyperbolic_response)
        return {
            "model": original_model_name,
            "response": content,
            "done": True,
            "context": [],
            "total_duration": 0,
            "load_duration": 0,
            "prompt_eval_count": 0,
            "prompt_eval_duration": 0,
            "eval_count": 0,
            "eval_duration": 0,
        }
    except Exception as e:
        return {"model": original_model_name or "unknown", "response": f"Error: {str(e)}", "done": True}

# ======================
# OLLAMA-COMPAT ROUTES
# ======================

@app.route('/api/tags', methods=['GET'])
def list_models():
    """
    Iklankan beberapa alias model (fp8/fp16 + generic) agar mudah match oleh scheduler.
    Semua alias tetap dipetakan ke HYPERBOLIC_MODEL saat infer.
    """
    m = HYPERBOLIC_MODEL
    aliases = [
        # FP8 family
        "llama-3.2-3b-instruct/fp-8",
        "llama-3.2-3b-instruct/fp8",
        # FP16 family
        "llama-3.2-3b-instruct/fp-16",
        "llama-3.2-3b-instruct/fp16",
        # generic
        "llama-3.2-3b-instruct",
        "llama3.2-3b-instruct",
        m,
    ]
    models = []
    for name in aliases:
        models.append({
            "name": name,
            "model": name,
            "modified_at": "",
            "size": 0,
            "digest": "",
            "details": {
                "format": "openai-proxy",
                "family": "meta-llama",
                "parameter_size": "3B",
                "precision": "fp8"
            }
        })
    return jsonify({"models": models})

@app.route('/api/generate', methods=['POST'])
def api_generate():
    """Ollama legacy endpoint → konversi ke Hyperbolic lalu balas gaya /api/generate."""
    try:
        ollama_data = request.get_json(force=True, silent=True) or {}
        payload = convert_ollama_to_hyperbolic(ollama_data)
        r = _hyperbolic_post_chat(payload)
        if r.status_code != 200:
            return jsonify({"error": f"Hyperbolic API error: {r.status_code}", "body": r.text}), 500
        return jsonify(convert_hyperbolic_to_ollama(r.json(), ollama_data.get("model") or HYPERBOLIC_MODEL)), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/chat', methods=['POST'])
def api_chat():
    """
    Ollama-compatible chat.
    - stream:false => balas gaya Ollama (message+done)
    - stream:true  => SSE OpenAI-style per-kata (choices[0].delta + logprobs placeholder)
    """
    try:
        payload = request.get_json(force=True, silent=True) or {}
        if "messages" not in payload and "prompt" in payload:
            payload["messages"] = [{"role": "user", "content": payload.get("prompt", "")}]
        payload["model"] = HYPERBOLIC_MODEL

        want_stream = bool(payload.get("stream"))
        hp_payload = dict(payload)
        hp_payload["stream"] = False  # Hyperbolic: non-stream

        r = _hyperbolic_post_chat(hp_payload)
        text = _extract_text_from_openai(r.json() if r.headers.get("content-type","").startswith(JSON_CT) else {})

        if not want_stream:
            usage = _estimate_usage(payload.get("messages", []), text)
            return jsonify({
                "model": HYPERBOLIC_MODEL,
                "created_at": "",
                "message": {"role": "assistant", "content": text},
                "done": True,
                "usage": usage,  # tambahan info (perkiraan)
            }), 200

        return Response(stream_with_context(_sse_openai_chunks_per_word(text, HYPERBOLIC_MODEL)),
                        mimetype="text/event-stream")

    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/pull', methods=['POST'])
def api_pull():
    """Simulasikan sukses 'pull' model (karena tidak menyimpan model lokal)."""
    body = request.get_json(force=True, silent=True) or {}
    name = body.get("name") or HYPERBOLIC_MODEL
    return jsonify({
        "status": "success",
        "name": name,
        "digest": "",
        "size": 0,
        "details": {"format": "openai-proxy"}
    }), 200

@app.route('/api/show', methods=['POST'])
def api_show():
    """Metadata minimal ala Ollama."""
    body = request.get_json(force=True, silent=True) or {}
    name = body.get("name") or HYPERBOLIC_MODEL
    return jsonify({
        "license": "",
        "modelfile": "",
        "parameters": "",
        "template": "",
        "details": {
            "parent_model": "",
            "format": "openai-proxy",
            "family": "meta-llama",
            "parameter_size": "3B",
            "precision": "fp8"
        },
        "model_info": {},
        "model": name
    }), 200

# ======================
# OPENAI-COMPAT PASSTHROUGH (+SSE per-kata)
# ======================
@app.route('/v1/chat/completions', methods=['POST'])
def chat_completions():
    """
    OpenAI-compatible.
    - stream:false => passthrough response Hyperbolic + usage (perkiraan)
    - stream:true  => sintetis SSE OpenAI-format per-kata (choices[0].delta & logprobs placeholder)
    """
    try:
        data = request.get_json(force=True, silent=True) or {}
        want_stream = bool(data.get("stream"))
        data["model"] = HYPERBOLIC_MODEL

        hp_payload = dict(data)
        hp_payload["stream"] = False  # Hyperbolic non-stream
        r = _hyperbolic_post_chat(hp_payload)

        ct = r.headers.get("content-type", "")
        resp_json = r.json() if ct.startswith(JSON_CT) else {}
        text = _extract_text_from_openai(resp_json)

        if not want_stream:
            # tambahkan usage (perkiraan) agar lebih lengkap
            usage = _estimate_usage(data.get("messages", []), text)
            # bentuk respons OpenAI-style minimal
            out = {
                "id": f"chatcmpl-{uuid.uuid4().hex[:24]}",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": HYPERBOLIC_MODEL,
                "choices": [{
                    "index": 0,
                    "message": {"role": "assistant", "content": text},
                    "finish_reason": "stop",
                    "logprobs": None
                }],
                "usage": usage
            }
            return Response(json.dumps(out), status=200, content_type=JSON_CT)

        return Response(stream_with_context(_sse_openai_chunks_per_word(text, HYPERBOLIC_MODEL)),
                        mimetype="text/event-stream")

    except Exception as e:
        return jsonify({"error": str(e)}), 500

# ======================
# HEALTH
# ======================
@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "model": HYPERBOLIC_MODEL})

# ======================
# MAIN
# ======================
if __name__ == '__main__':
    # Bind ke 0.0.0.0:11434 (compose mapping ke 11434 & alias 14444)
    app.run(host='0.0.0.0', port=11434, debug=False)
