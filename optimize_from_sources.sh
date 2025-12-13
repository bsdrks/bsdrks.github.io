#!/bin/bash

# Optimize images from sources/ directory to WebP format
# Target: 170x215 container, maintain aspect ratio, fit within

SOURCES_DIR="assets/images/sources"
OUTPUT_DIR="assets/images"

echo "Optimizing images from sources/ to WebP format..."
echo ""

# Function to optimize a single image
optimize_image() {
    local source="$1"
    local output="$2"
    
    if [ ! -f "$source" ]; then
        return 1
    fi
    
    # Get original dimensions
    dims=$(sips -g pixelWidth -g pixelHeight "$source" 2>/dev/null | grep -E "pixelWidth|pixelHeight" | awk '{print $2}')
    if [ -z "$dims" ]; then
        echo "  ✗ Could not get dimensions for $(basename "$source")"
        return 1
    fi
    
    orig_w=$(echo "$dims" | head -1)
    orig_h=$(echo "$dims" | tail -1)
    
    # Calculate 2x dimensions (340x430) to fit within while maintaining aspect ratio
    ratio=$(echo "scale=10; $orig_w/$orig_h" | bc)
    target_ratio=$(echo "scale=10; 170/215" | bc)
    
    if [ "$(echo "$ratio > $target_ratio" | bc)" -eq 1 ]; then
        # Image is wider - height is limiting factor (2x = 430)
        new_h=430
        new_w=$(echo "$orig_w * 430 / $orig_h" | bc | awk '{printf "%.0f", $1}')
    else
        # Image is taller - width is limiting factor (2x = 340)
        new_w=340
        new_h=$(echo "$orig_h * 340 / $orig_w" | bc | awk '{printf "%.0f", $1}')
    fi
    
    echo "  ${orig_w}x${orig_h} -> ${new_w}x${new_h} (2x resolution with sharpening)"
    
    # Use ffmpeg with:
    # - lanczos resampling for quality
    # - unsharp filter for fine detail sharpening (smaller 3x3 matrix for finer details)
    # - quality 100 for maximum WebP quality
    if ffmpeg -i "$source" \
        -vf "scale=${new_w}:${new_h}:flags=lanczos+accurate_rnd+full_chroma_int,unsharp=3:3:0.8:3:3:0.0" \
        -quality 100 \
        -y "$output" 2>/dev/null; then
        return 0
    else
        # Fallback: try with simpler unsharp
        if ffmpeg -i "$source" \
            -vf "scale=${new_w}:${new_h}:flags=lanczos+accurate_rnd+full_chroma_int,unsharp=3:3:0.8" \
            -quality 100 \
            -y "$output" 2>/dev/null; then
            return 0
        else
            # Fallback: try without unsharp if it's not available
            if ffmpeg -i "$source" \
                -vf "scale=${new_w}:${new_h}:flags=lanczos+accurate_rnd+full_chroma_int" \
                -quality 100 \
                -y "$output" 2>/dev/null; then
                return 0
            else
                # Final fallback to sips
                sips -s format webp -s formatOptions 100 --resampleHeightWidth $new_h $new_w "$source" --out "$output" >/dev/null 2>&1
                return $?
            fi
        fi
    fi
}

# Process all images in sources directory
find "$SOURCES_DIR" -type f \( -name "*.webp" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.png" \) | while read source; do
    base=$(basename "$source" | sed 's/\.[^.]*$//')
    output="$OUTPUT_DIR/${base}.webp"
    
    # Skip if output already exists and is newer
    if [ -f "$output" ] && [ "$output" -nt "$source" ]; then
        echo "Skipping $base (already optimized)"
        continue
    fi
    
    echo "Optimizing $base..."
    if optimize_image "$source" "$output"; then
        size=$(ls -lh "$output" | awk '{print $5}')
        echo "  ✓ Created ${base}.webp ($size)"
    else
        echo "  ✗ Failed to optimize $base"
    fi
    echo ""
done

echo "Optimization complete!"

