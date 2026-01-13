#!/bin/bash
set -e

if [ $# -ne 3 ]; then
    echo "Usage: $0 <network> <node_type> <mode>"
    echo "Available options:"
    echo "  Network: heimdall, bor, erigon, avail"
    echo "  Node type: mainnet, amoy"
    echo "  Mode: stateless, full, archive, pruned"
    echo "Example: $0 bor mainnet stateless"
    exit 1
fi

network=$1
node_type=$2
mode=$3

snapshot_list_url="https://snap.stakepool.work/snapshots-stakepool/list_snapshots.txt"

case $mode in
    stateless)
        relevant_snapshots=$(curl -s "$snapshot_list_url" | grep "$network" | grep "$node_type" | grep stateless)
        ;;
    full)
        relevant_snapshots=$(curl -s "$snapshot_list_url" | grep "$network" | grep "$node_type" | grep -v stateless | grep -v pruned | grep -v archive)
        ;;
    archive)
        relevant_snapshots=$(curl -s "$snapshot_list_url" | grep "$network" | grep "$node_type" | grep archive)
        ;;
    pruned)
        relevant_snapshots=$(curl -s "$snapshot_list_url" | grep "$network" | grep "$node_type" | grep pruned)
        ;;
    *)
        echo "❌ Unknown mode: $mode"
        exit 1
        ;;
esac

if [ -z "$relevant_snapshots" ]; then
    echo "❌ No snapshots found for $network - $node_type - $mode."
    exit 1
fi

latest_snapshot=$(echo "$relevant_snapshots" | sort -k1,1r -k2,2r | head -n 1)
snapshot_file=$(echo "$latest_snapshot" | awk '{print $4}')
snapshot_size=$(echo "$latest_snapshot" | awk '{print $3}')

snapshot_gb=$((snapshot_size / 1000000000))

url="https://snap.stakepool.work/snapshots-stakepool/$snapshot_file"

available_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
available_human=$(df -h . | awk 'NR==2 {print $4}')

echo "================================================"
echo "📊 SPACE CHECK"
echo "================================================"
echo "Snapshot: ${snapshot_file}"
echo "Snapshot size: ~${snapshot_gb}GB"
echo "Your free space: ${available_human} (${available_gb}GB)"
echo ""

if [ "$available_gb" -lt "$snapshot_gb" ]; then
    echo "❌ ERROR: Not enough space for compressed snapshot!"
    echo "❌ Need at least ${snapshot_gb}GB, but only have ${available_gb}GB"
    echo "❌ Try: ./$0 $network $node_type pruned   (for smaller snapshot)"
    exit 1
fi

if [ "$available_gb" -lt "$((snapshot_gb * 13 / 10))" ]; then
    echo "⚠️  WARNING: Space may be tight"
    echo "⚠️  Decompressed size could be larger than compressed"
    echo "⚠️  Recommended: Have 1.3x snapshot size (${snapshot_gb}GB → $((snapshot_gb * 13 / 10))GB)"
fi

echo "================================================"
echo ""
read -p "Continue? (y/N): " -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Operation cancelled."
    exit 1
fi

echo "🚀 Starting download + extraction..."
echo "URL: $url"

hours_min=$((snapshot_gb / 100))  
hours_max=$((snapshot_gb / 20))   

if [ $hours_min -lt 1 ]; then
    hours_min=1
fi
if [ $hours_max -lt 1 ]; then
    hours_max=1
fi

echo "⏱️  Estimated time: ${hours_min}-${hours_max} hours"
echo "💡 Monitor with: watch -n 30 'df -h .'"

(
    warning_gb=$((snapshot_gb / 5))
    if [ $warning_gb -lt 50 ]; then
        warning_gb=50
    fi
    
    emergency_gb=$((snapshot_gb / 10))
    if [ $emergency_gb -lt 20 ]; then
        emergency_gb=20
    fi
    
    echo "📈 Space monitor active: Warning <${warning_gb}GB, Emergency <${emergency_gb}GB"
    
    while true; do
        current_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
        
        if [ "$current_gb" -lt "$emergency_gb" ]; then
            echo ""
            echo "💀 EMERGENCY: Only ${current_gb}GB left!"
            echo "💀 Stopping in 5 seconds..."
            sleep 5
            pkill -f "wget.*${snapshot_file}" 2>/dev/null || true
            exit 1
        elif [ "$current_gb" -lt "$warning_gb" ]; then
            echo ""
            echo "⚠️  Warning: ${current_gb}GB remaining"
        fi
        
        sleep 30
    done
) &
monitor_pid=$!

trap "echo 'Stopping...'; kill $monitor_pid 2>/dev/null; exit 1" INT TERM

case "$snapshot_file" in
    *.tar.zst)
        echo "🔧 Using zstd decompression..."
        
        if ! command -v zstd >/dev/null 2>&1; then
            echo "❌ zstd not installed. Install with:"
            echo "   Ubuntu/Debian: sudo apt install zstd"
            echo "   RHEL/CentOS: sudo yum install zstd"
            kill $monitor_pid 2>/dev/null
            exit 1
        fi
        
        wget -c --retry-connrefused --timeout=60 \
             --read-timeout=300 --inet4-only \
             --show-progress \
             "$url" -O - | \
        zstdcat --memory=512M 2>/dev/null | \
        tar -xf - 2>/dev/null
        ;;
        
    *.tar.lz4)
        echo "🔧 Using lz4 decompression..."
        
        if ! command -v lz4 >/dev/null 2>&1; then
            echo "❌ lz4 not installed. Install with:"
            echo "   Ubuntu/Debian: sudo apt install lz4"
            echo "   RHEL/CentOS: sudo yum install lz4"
            kill $monitor_pid 2>/dev/null
            exit 1
        fi
        
        wget -c --retry-connrefused --timeout=60 \
             --read-timeout=120 --inet4-only \
             --show-progress \
             "$url" -O - | \
        lz4 -dc 2>/dev/null | \
        tar -xf - 2>/dev/null
        ;;
        
    *)
        echo "❌ Unknown snapshot format: $snapshot_file"
        kill $monitor_pid 2>/dev/null
        exit 1
        ;;
esac

kill $monitor_pid 2>/dev/null

end_time=$SECONDS
hours=$((end_time / 3600))
minutes=$(( (end_time % 3600) / 60 ))
seconds=$((end_time % 60))

echo ""
echo "================================================"
echo "✅ SUCCESS! Snapshot extracted."
echo "⏱️  Time: ${hours}h ${minutes}m ${seconds}s"
echo "💾 Final free space: $(df -h . | awk 'NR==2 {print $4}')"
echo "================================================"

echo ""
echo "📁 Extracted contents:"
ls -la | head -10
if [ $(ls -1 | wc -l) -gt 10 ]; then
    echo "... and $(($(ls -1 | wc -l) - 10)) more items"
fi
