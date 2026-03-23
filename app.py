#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import os
import json
import time
import base64
import mimetypes
import requests
from flask import Flask, render_template, request, jsonify, send_from_directory
from dotenv import load_dotenv

load_dotenv('.env')

app = Flask(__name__)
API_KEY = os.getenv('ARK_API_KEY')
API_URL = 'https://ark.cn-beijing.volces.com/api/v3/images/generations'
MODEL = 'doubao-seedream-5-0-260128'
SIZE = '2K'
IMAGES_DIR = 'images'
LOG_FILE = 'generation.log'

# Ensure images directory exists
os.makedirs(IMAGES_DIR, exist_ok=True)

def get_image_list():
    """Get list of generated images sorted by modification time"""
    images = []
    for f in os.listdir(IMAGES_DIR):
        if f.endswith('.jpg') or f.endswith('.jpeg') or f.endswith('.png'):
            path = os.path.join(IMAGES_DIR, f)
            mtime = os.path.getmtime(path)
            size = os.path.getsize(path)
            images.append({
                'filename': f,
                'path': f'/images/{f}',
                'mtime': mtime,
                'size_kb': size // 1024
            })
    # Sort by modification time, newest first
    images.sort(key=lambda x: x['mtime'], reverse=True)
    return images

def log_generation(info):
    """Append generation info to log file"""
    with open(LOG_FILE, 'a', encoding='utf-8') as f:
        f.write(f"\n===== {info['datetime']} =====\n")
        f.write(f"文件: {info['file']}\n")
        f.write(f"模型: {info['model']}\n")
        f.write(f"尺寸: {info['size']}\n")
        f.write(f"文件大小: {info['size_kb']}K\n")
        if info.get('elapsed'):
            f.write(f"耗时: {info['elapsed']}\n")
        if info.get('type') == 'edit':
            f.write(f"原图: {info['original']}\n")
            f.write(f"编辑提示词: {info['prompt']}\n")
            f.write("类型: 图生图编辑\n")
        else:
            f.write(f"提示词: {info['prompt']}\n")
        f.write("\n")

@app.route('/')
def index():
    images = get_image_list()
    return render_template('index.html', images=images)

@app.route('/images/<filename>')
def serve_image(filename):
    return send_from_directory(IMAGES_DIR, filename)

@app.route('/generate', methods=['POST'])
def generate():
    start_time = time.time()
    prompt = request.form.get('prompt', '').strip()
    if not prompt:
        return jsonify({'error': '提示词不能为空'}), 400

    # Check for uploaded image (image-to-image)
    image_file = request.files.get('image')
    is_edit = False
    original_name = None

    timestamp = int(time.time())
    date_str = time.strftime('%Y%m%d_%H%M%S')
    datetime_str = time.strftime('%Y-%m-%d %H:%M:%S')

    if image_file and image_file.filename:
        is_edit = True
        original_name = image_file.filename
        # Read image and convert to base64
        image_data = image_file.read()
        mime_type = mimetypes.guess_type(original_name)[0] or 'image/png'
        image_base64 = base64.b64encode(image_data).decode('utf-8')
        image_data_uri = f'data:{mime_type};base64,{image_base64}'

    # Build request
    payload = {
        'model': MODEL,
        'prompt': prompt,
        'sequential_image_generation': 'disabled',
        'response_format': 'url',
        'size': SIZE,
        'stream': False,
        'watermark': True
    }
    if is_edit:
        payload['image'] = image_data_uri

    try:
        response = requests.post(
            API_URL,
            headers={
                'Content-Type': 'application/json',
                'Authorization': f'Bearer {API_KEY}'
            },
            json=payload,
            timeout=300
        )
        response.raise_for_status()
        result = response.json()
    except Exception as e:
        return jsonify({'error': f'API 调用失败: {str(e)}'}), 500

    if 'error' in result:
        return jsonify({'error': result['error'].get('message', '未知错误')}), 400

    if 'data' not in result or not result['data']:
        return jsonify({'error': 'API 返回数据异常'}), 500

    image_url = result['data'][0]['url']
    image_size = result['data'][0].get('size', SIZE)

    # Download image
    filename = f'{"edited" if is_edit else "generated"}_{date_str}.jpg'
    output_path = os.path.join(IMAGES_DIR, filename)

    try:
        img_response = requests.get(image_url, timeout=60)
        img_response.raise_for_status()
        with open(output_path, 'wb') as f:
            f.write(img_response.content)
    except Exception as e:
        return jsonify({'error': f'图片下载失败: {str(e)}'}), 500

    # Copy to root for preview
    with open(output_path, 'rb') as src:
        with open('generated_image.jpg', 'wb') as dst:
            dst.write(src.read())

    # Calculate elapsed time
    elapsed = time.time() - start_time
    elapsed_str = f'{elapsed:.1f}秒'

    # Log
    file_size_kb = os.path.getsize(output_path) // 1024
    log_generation({
        'datetime': datetime_str,
        'file': os.path.join(IMAGES_DIR, filename),
        'model': MODEL,
        'size': image_size,
        'size_kb': f'{file_size_kb}K',
        'prompt': prompt,
        'type': 'edit' if is_edit else 'text-to-image',
        'original': original_name,
        'elapsed': elapsed_str
    })

    return jsonify({
        'success': True,
        'image_url': f'/images/{filename}',
        'filename': filename,
        'size': image_size,
        'size_kb': file_size_kb,
        'elapsed': elapsed_str,
        'type': '编辑' if is_edit else '文生图'
    })

@app.route('/history')
def history():
    images = get_image_list()
    return jsonify({'images': images})

if __name__ == '__main__':
    app.run(debug=True, port=5000, host='0.0.0.0')
