#!/bin/bash

# 创建 images 目录（如果不存在）
mkdir -p images

# 加载环境变量，忽略注释行
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "错误：找不到 .env 文件，请创建 .env 文件并配置 ARK_API_KEY"
    exit 1
fi

# 检查 API Key 是否设置
if [ -z "$ARK_API_KEY" ]; then
    echo "错误：ARK_API_KEY 未在 .env 文件中配置"
    exit 1
fi

# 默认提示词
DEFAULT_PROMPT="星际穿越，黑洞，黑洞里冲出一辆快支离破碎的复古列车，抢视觉冲击力，电影大片，末日既视感，动感，对比色，oc渲染，光线追踪，动态模糊，景深，超现实主义，深蓝，画面通过细腻的丰富的色彩层次塑造主体与场景，质感真实，暗黑风背景的光影效果营造出氛围，整体兼具艺术幻想感，夸张的广角透视效果，耀光，反射，极致的光影，强引力，吞噬"

# 使用传入的提示词，否则使用默认
PROMPT="${1:-$DEFAULT_PROMPT}"

# 生成带时间戳的文件名
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DATE_TIME=$(date +"%Y-%m-%d %H:%M:%S")
OUTPUT_IMAGE="images/generated_${TIMESTAMP}.jpg"
RESPONSE_FILE="response.json"
LOG_FILE="generation.log"
MODEL="doubao-seedream-5-0-260128"
SIZE="2K"

echo "开始生成图片..."
echo "提示词: $PROMPT"
echo ""

# 使用 Python 正确生成 JSON（处理引号转义）
TEMP_JSON=$(mktemp -t request_XXXXXX.json)
python -c "
import json
data = {
    'model': '$MODEL',
    'prompt': '''$PROMPT''',
    'sequential_image_generation': 'disabled',
    'response_format': 'url',
    'size': '$SIZE',
    'stream': False,
    'watermark': True
}
json.dump(data, open('$TEMP_JSON', 'w'), ensure_ascii=False)
"

# 调用 API - 从文件读取 JSON
curl -X POST "https://ark.cn-beijing.volces.com/api/v3/images/generations" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $ARK_API_KEY" \
  --data-binary @$TEMP_JSON \
  -o $RESPONSE_FILE

# 删除临时文件
rm -f $TEMP_JSON

# 检查是否成功
if [ $? -ne 0 ]; then
    echo "API 调用失败"
    exit 1
fi

# 提取图片 URL 和尺寸
IMAGE_URL=$(grep -o '"url":"[^"]*"' $RESPONSE_FILE | cut -d'"' -f4)
IMAGE_SIZE=$(grep -o '"size":"[^"]*"' $RESPONSE_FILE | cut -d'"' -f4)

if [ -z "$IMAGE_URL" ]; then
    echo "获取图片 URL 失败，API 响应:"
    cat $RESPONSE_FILE
    exit 1
fi

echo ""
echo "获取图片 URL 成功，开始下载..."
echo "URL: $IMAGE_URL"
echo ""

# 下载图片
curl -o $OUTPUT_IMAGE "$IMAGE_URL"

if [ $? -eq 0 ]; then
    FILE_SIZE=$(du -h $OUTPUT_IMAGE | cut -f1)
    echo ""
    echo "✓ 图片已成功保存到 $OUTPUT_IMAGE"
    echo "文件大小: $FILE_SIZE"
    # 同时复制一份到根目录供 index.html 展示
    cp $OUTPUT_IMAGE generated_image.jpg
    echo "已复制最新图片到 generated_image.jpg 供网页展示"

    # 记录到日志文件
    echo "===== $DATE_TIME =====" >> "$LOG_FILE"
    echo "文件: $OUTPUT_IMAGE" >> "$LOG_FILE"
    echo "模型: $MODEL" >> "$LOG_FILE"
    echo "尺寸: ${IMAGE_SIZE:-$SIZE}" >> "$LOG_FILE"
    echo "文件大小: $FILE_SIZE" >> "$LOG_FILE"
    echo "提示词: $PROMPT" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    echo "已记录信息到 $LOG_FILE"
else
    echo "图片下载失败"
    exit 1
fi
