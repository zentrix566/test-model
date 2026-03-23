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

# 检查参数
if [ $# -lt 1 ]; then
    echo "用法: ./edit_image.sh \"提示词\" [原图路径]"
    echo "示例: ./edit_image.sh \"将图中蓝色框内的发带变成粉红色，去掉绿色框内的胡子，在红色框内增加一只站在肩膀上的鹦鹉\" input.jpg"
    exit 1
fi

PROMPT="$1"
INPUT_IMAGE="${2:-input.jpg}"

# 检查原图是否存在
if [ ! -f "$INPUT_IMAGE" ]; then
    echo "错误：原图 $INPUT_IMAGE 不存在"
    exit 1
fi

# 生成带时间戳的文件名
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DATE_TIME=$(date +"%Y-%m-%d %H:%M:%S")
OUTPUT_IMAGE="images/edited_${TIMESTAMP}.jpg"
RESPONSE_FILE="response.json"
LOG_FILE="generation.log"
MODEL="doubao-seedream-5-0-260128"
SIZE="2K"

echo "开始图生图编辑..."
echo "原图: $INPUT_IMAGE"
echo "编辑提示词: $PROMPT"
echo ""

# 需要将图片转 base64 并加上 data URI 前缀
MIME_TYPE=$(file -b --mime-type "$INPUT_IMAGE")
IMAGE_BASE64=$(base64 -w 0 "$INPUT_IMAGE")
IMAGE_DATA_URI="data:$MIME_TYPE;base64,$IMAGE_BASE64"

# 使用 Python 正确生成 JSON（处理引号转义）
TEMP_JSON=$(mktemp -t request_XXXXXX.json)
python -c "
import json
data = {
    'model': '$MODEL',
    'prompt': '''$PROMPT''',
    'image': '$IMAGE_DATA_URI',
    'sequential_image_generation': 'disabled',
    'response_format': 'url',
    'size': '$SIZE',
    'stream': False,
    'watermark': True
}
json.dump(data, open('$TEMP_JSON', 'w'), ensure_ascii=False)
"

# 调用 API (图生图模式) - 从文件读取 JSON
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
    echo "✓ 编辑后的图片已保存到 $OUTPUT_IMAGE"
    echo "文件大小: $FILE_SIZE"
    # 同时复制一份到根目录供 index.html 展示
    cp $OUTPUT_IMAGE generated_image.jpg
    echo "已复制最新图片到 generated_image.jpg 供网页展示"

    # 记录到日志文件
    echo "===== $DATE_TIME =====" >> "$LOG_FILE"
    echo "文件: $OUTPUT_IMAGE"
    echo "模型: $MODEL" >> "$LOG_FILE"
    echo "尺寸: ${IMAGE_SIZE:-$SIZE}" >> "$LOG_FILE"
    echo "文件大小: $FILE_SIZE" >> "$LOG_FILE"
    echo "原图: $INPUT_IMAGE" >> "$LOG_FILE"
    echo "编辑提示词: $PROMPT" >> "$LOG_FILE"
    echo "类型: 图生图编辑" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    echo "已记录信息到 $LOG_FILE"
else
    echo "图片下载失败"
    exit 1
fi
