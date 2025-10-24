from flask import Flask, request, jsonify, Response
import requests
import os
import json

app = Flask(__name__)

HYPERBOLIC_API_URL = os.getenv("HYPERBOLIC_API_URL", "https://api.hyperbolic.xyz/v1")
HYPERBOLIC_API_KEY = os.getenv("HYPERBOLIC_API_KEY", "")
HYPERBOLIC_MODEL = os.getenv("HYPERBOLIC_MODEL", "meta-llama/Llama-3.2-3B-Instruct")

def convert_ollama_to_hyperbolic(ollama_data):
    messages = []
    
    if "prompt" in ollama_data:
        messages.append({"role": "user", "content": ollama_data["prompt"]})
    elif "messages" in ollama_data:
        messages = ollama_data["messages"]
    
    return {
        "model": HYPERBOLIC_MODEL,
        "messages": messages,
        "max_tokens": ollama_data.get("max_tokens", 512),
        "temperature": ollama_data.get("temperature", 0.7),
        "top_p": ollama_data.get("top_p", 0.9),
        "stream": ollama_data.get("stream", False)
    }

def convert_hyperbolic_to_ollama(hyperbolic_response, original_model_name="llama2"):
    try:
        choices = hyperbolic_response.get("choices", [])
        content = choices[0].get("message", {}).get("content", "") if choices else ""
            
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
            "eval_duration": 0
        }
    except Exception as e:
        return {"model": original_model_name, "response": f"Error: {str(e)}", "done": True}

@app.route('/api/generate', methods=['POST'])
def generate():
    try:
        ollama_data = request.get_json()
        hyperbolic_data = convert_ollama_to_hyperbolic(ollama_data)
        
        headers = {
            "Authorization": f"Bearer {HYPERBOLIC_API_KEY}",
            "Content-Type": "application/json"
        }
        
        response = requests.post(
            f"{HYPERBOLIC_API_URL}/chat/completions",
            json=hyperbolic_data,
            headers=headers,
            timeout=60
        )
        
        if response.status_code != 200:
            return jsonify({"error": f"Hyperbolic API error: {response.status_code}"}), 500
        
        hyperbolic_response = response.json()
        ollama_response = convert_hyperbolic_to_ollama(hyperbolic_response, ollama_data.get("model", "llama2"))
        return jsonify(ollama_response)
            
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/tags', methods=['GET'])
def list_models():
    return jsonify({
        "models": [{
            "name": HYPERBOLIC_MODEL,
            "model": HYPERBOLIC_MODEL,
            "modified_at": "2024-01-01T00:00:00Z",
            "size": 3000000000,
            "digest": "hyperbolic-llama3.2-3b",
            "details": {"format": "gguf", "family": "llama", "parameter_size": "3B"}
        }]
    })

@app.route('/v1/chat/completions', methods=['POST'])
def chat_completions():
    try:
        data = request.get_json()
        headers = {
            "Authorization": f"Bearer {HYPERBOLIC_API_KEY}",
            "Content-Type": "application/json"
        }
        
        data["model"] = HYPERBOLIC_MODEL
        response = requests.post(f"{HYPERBOLIC_API_URL}/chat/completions", json=data, headers=headers, timeout=60)
        
        return Response(response.content, status=response.status_code, content_type=response.headers.get('content-type', 'application/json'))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy", "model": HYPERBOLIC_MODEL})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=11434, debug=False)
