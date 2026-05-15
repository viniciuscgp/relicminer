#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./pack_terrain3d_texture.sh [options] TEXTURE_DIR [OUTPUT_NAME] [OUTPUT_DIR]

Examples:
  ./pack_terrain3d_texture.sh textures/terrain/Ground103_1K-PNG
  ./pack_terrain3d_texture.sh textures/terrain/Ground103_1K-PNG Ground103

Options:
  --invert-normal-y     Force DirectX normal map (-Y) to OpenGL (+Y) conversion.
  --invert-roughness    Force smoothness/gloss map to roughness conversion.

Creates:
  OUTPUT_DIR/OUTPUT_NAME_alb_ht.png
  OUTPUT_DIR/OUTPUT_NAME_nrm_rgh.png
  TEXTURE_DIR/source/.gdignore

Automatic behavior:
  - OUTPUT_NAME is inferred from TEXTURE_DIR when omitted.
  - If TEXTURE_DIR/source exists, source maps are read from there.
  - NormalGL/OpenGL maps are preferred.
  - NormalDX/DirectX maps are converted automatically when no OpenGL normal exists.
  - Roughness maps are preferred.
  - Smoothness/gloss maps are inverted automatically when no roughness map exists.
  - Missing height, normal, or roughness maps are replaced by neutral defaults.

After packing, original texture files are moved to TEXTURE_DIR/source.
The .gdignore file keeps that source folder out of Godot imports/exports.
EOF
}

invert_normal_y=false
invert_roughness=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --invert-normal-y|--directx-normal)
      invert_normal_y=true
      shift
      ;;
    --invert-roughness|--smoothness|--gloss)
      invert_roughness=true
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 || $# -gt 3 ]]; then
  usage >&2
  exit 2
fi

texture_dir="${1%/}"

if [[ ! -d "$texture_dir" ]]; then
  echo "Texture directory not found: $texture_dir" >&2
  exit 1
fi

if ! command -v convert >/dev/null 2>&1; then
  echo "ImageMagick 'convert' command not found." >&2
  exit 1
fi

if ! command -v identify >/dev/null 2>&1; then
  echo "ImageMagick 'identify' command not found." >&2
  exit 1
fi

infer_output_name() {
  local base="$1"
  local inferred

  base="$(basename "$base")"
  inferred="$(
    printf '%s\n' "$base" |
      sed -E \
        -e 's/([_-]?[0-9]+K)?[_-]?(PNG|JPG|JPEG|TIF|TIFF|EXR|WEBP)$//I' \
        -e 's/[_-]?(PBR|Texture|Textures|Material|Maps)$//I' \
        -e 's/[_-]+$//'
  )"

  if [[ -z "$inferred" ]]; then
    inferred="$base"
  fi

  printf '%s\n' "$inferred"
}

output_name="${2:-$(infer_output_name "$texture_dir")}"
output_dir="${3:-$texture_dir}"
source_assets_dir="$texture_dir/source"
maps_dir="$texture_dir"

if [[ -d "$source_assets_dir" ]]; then
  maps_dir="$source_assets_dir"
fi

texture_files() {
  find "$maps_dir" -maxdepth 1 -type f \
    \( -iname "*.png" -o -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.tga" -o -iname "*.webp" \) \
    ! -iname "*_alb_ht.png" \
    ! -iname "*_nrm_rgh.png" \
    -print0 |
    sort -z
}

find_map() {
  local pattern="$1"
  local exclude_pattern="${2:-}"

  texture_files |
    awk -v RS='\0' -v pattern="$pattern" -v exclude_pattern="$exclude_pattern" '
      BEGIN { IGNORECASE = 1 }
      $0 ~ pattern && (exclude_pattern == "" || $0 !~ exclude_pattern) {
        print
        exit
      }
    '
}

color_map="$(find_map '(^|[_ /.-])(color|basecolor|base_color|albedo|diffuse|diff)([_ .-]|$)')"
height_map="$(find_map '(^|[_ /.-])(displacement|height|heightmap|depth|disp)([_ .-]|$)')"

normal_gl_map="$(find_map '(^|[_ /.-])(normalgl|normal_gl|opengl|normal_ogl)([_ .-]|$)')"
normal_dx_map="$(find_map '(^|[_ /.-])(normaldx|normal_dx|directx|normal_dx11)([_ .-]|$)')"
normal_plain_map="$(find_map '(^|[_ /.-])(normal|nrm)([_ .-]|$)' '(normaldx|normal_dx|directx|normalgl|normal_gl|opengl|normal_ogl)')"

roughness_map="$(find_map '(^|[_ /.-])(roughness|rough|rgh)([_ .-]|$)')"
smoothness_map="$(find_map '(^|[_ /.-])(smoothness|smooth|gloss|glossiness)([_ .-]|$)')"

if [[ -z "$color_map" ]]; then
  echo "Missing required albedo/color map in: $maps_dir" >&2
  exit 1
fi

normal_map=""
normal_source_kind="generated"
if [[ -n "$normal_gl_map" ]]; then
  normal_map="$normal_gl_map"
  normal_source_kind="OpenGL"
elif [[ -n "$normal_dx_map" ]]; then
  normal_map="$normal_dx_map"
  normal_source_kind="DirectX"
  invert_normal_y=true
elif [[ -n "$normal_plain_map" ]]; then
  normal_map="$normal_plain_map"
  normal_source_kind="plain"
fi

roughness_input_map=""
roughness_source_kind="generated"
if [[ -n "$roughness_map" ]]; then
  roughness_input_map="$roughness_map"
  roughness_source_kind="roughness"
elif [[ -n "$smoothness_map" ]]; then
  roughness_input_map="$smoothness_map"
  roughness_source_kind="smoothness"
  invert_roughness=true
fi

mkdir -p "$output_dir"

tmp_dir=""
cleanup() {
  if [[ -n "$tmp_dir" ]]; then
    rm -rf "$tmp_dir"
  fi
}
trap cleanup EXIT

ensure_tmp_dir() {
  if [[ -z "$tmp_dir" ]]; then
    tmp_dir="$(mktemp -d)"
  fi
}

image_size() {
  identify -format '%wx%h' "$1"
}

color_size="$(image_size "$color_map")"
normal_size="$color_size"

if [[ -n "$normal_map" ]]; then
  normal_size="$(image_size "$normal_map")"
fi

prepare_height_alpha() {
  local output="$1"

  ensure_tmp_dir
  if [[ -n "$height_map" ]]; then
    convert "$height_map" -resize "${color_size}!" -colorspace Gray -depth 8 "$output"
  else
    convert -size "$color_size" xc:gray50 -depth 8 "$output"
  fi
}

prepare_normal_rgb() {
  local output="$1"

  ensure_tmp_dir
  if [[ -n "$normal_map" ]]; then
    if [[ "$invert_normal_y" == true ]]; then
      convert "$normal_map" -resize "${normal_size}!" -alpha off -channel G -negate +channel -depth 8 "$output"
    else
      convert "$normal_map" -resize "${normal_size}!" -alpha off -depth 8 "$output"
    fi
  else
    convert -size "$normal_size" 'xc:rgb(128,128,255)' -depth 8 "$output"
  fi
}

prepare_roughness_alpha() {
  local output="$1"

  ensure_tmp_dir
  if [[ -n "$roughness_input_map" ]]; then
    if [[ "$invert_roughness" == true ]]; then
      convert "$roughness_input_map" -resize "${normal_size}!" -colorspace Gray -negate -depth 8 "$output"
    else
      convert "$roughness_input_map" -resize "${normal_size}!" -colorspace Gray -depth 8 "$output"
    fi
  else
    convert -size "$normal_size" xc:white -depth 8 "$output"
  fi
}

ensure_tmp_dir
height_alpha="$tmp_dir/height_alpha.png"
normal_rgb="$tmp_dir/normal_rgb.png"
roughness_alpha="$tmp_dir/roughness_alpha.png"

prepare_height_alpha "$height_alpha"
prepare_normal_rgb "$normal_rgb"
prepare_roughness_alpha "$roughness_alpha"

alb_ht="$output_dir/${output_name}_alb_ht.png"
nrm_rgh="$output_dir/${output_name}_nrm_rgh.png"

echo "Texture dir: $texture_dir"
echo "Maps dir:    $maps_dir"
echo "Name:        $output_name"
echo "Color:       $color_map"
echo "Height:      ${height_map:-generated neutral gray}"
echo "Normal:      ${normal_map:-generated flat normal} ($normal_source_kind)"
echo "Roughness:   ${roughness_input_map:-generated white roughness} ($roughness_source_kind)"
echo "Output:      $alb_ht"
echo "Output:      $nrm_rgh"

if [[ "$normal_source_kind" == "DirectX" && "$invert_normal_y" == true ]]; then
  echo "Converted normal map from DirectX (-Y) to OpenGL (+Y)."
elif [[ "$invert_normal_y" == true && -n "$normal_map" ]]; then
  echo "Applied forced normal Y inversion."
fi

if [[ "$roughness_source_kind" == "smoothness" && "$invert_roughness" == true ]]; then
  echo "Converted smoothness/gloss map to roughness."
elif [[ "$invert_roughness" == true && -n "$roughness_input_map" ]]; then
  echo "Applied forced roughness inversion."
fi

convert "$color_map" "$height_alpha" \
  -resize "${color_size}!" -alpha off -compose CopyOpacity -composite -depth 8 \
  "$alb_ht"

convert "$normal_rgb" "$roughness_alpha" \
  -alpha off -compose CopyOpacity -composite -depth 8 \
  "$nrm_rgh"

write_import() {
  local texture_path="$1"
  local uid="$2"
  local project_root
  local absolute_texture_path
  local res_path
  local import_hash
  local existing_uid

  project_root="$(pwd -P)"
  absolute_texture_path="$(realpath -m "$texture_path")"

  if [[ "$absolute_texture_path" != "$project_root"/* ]]; then
    echo "Skipping .import outside project: $texture_path" >&2
    return
  fi

  res_path="res://${absolute_texture_path#"$project_root"/}"
  import_hash="$(printf '%s' "$res_path" | md5sum | cut -c1-32)"

  if [[ -f "${texture_path}.import" ]]; then
    existing_uid="$(awk -F'"' '/^uid="/ { print $2; exit }' "${texture_path}.import")"
    if [[ -n "$existing_uid" ]]; then
      uid="$existing_uid"
    fi
  fi

  cat > "${texture_path}.import" <<EOF
[remap]

importer="texture"
type="CompressedTexture2D"
uid="$uid"
path="res://.godot/imported/$(basename "$texture_path")-${import_hash}.ctex"
metadata={
"vram_texture": false
}

[deps]

source_file="$res_path"
dest_files=["res://.godot/imported/$(basename "$texture_path")-${import_hash}.ctex"]

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=0
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=1
EOF
}

write_import "$alb_ht" "uid://$(printf '%s_alb_ht' "$output_name" | sha1sum | cut -c1-13)"
write_import "$nrm_rgh" "uid://$(printf '%s_nrm_rgh' "$output_name" | sha1sum | cut -c1-13)"

move_to_source() {
  local source_path="$1"
  local source_import="${source_path}.import"
  local target_path="$source_assets_dir/$(basename "$source_path")"
  local target_import="${target_path}.import"
  local absolute_source_path
  local absolute_alb_ht
  local absolute_nrm_rgh

  if [[ "$source_path" == "$source_assets_dir"/* ]]; then
    return
  fi

  absolute_source_path="$(realpath -m "$source_path")"
  absolute_alb_ht="$(realpath -m "$alb_ht")"
  absolute_nrm_rgh="$(realpath -m "$nrm_rgh")"

  if [[ "$absolute_source_path" == "$absolute_alb_ht" || "$absolute_source_path" == "$absolute_nrm_rgh" ]]; then
    return
  fi

  if [[ -e "$target_path" ]]; then
    echo "Source already exists, keeping original in place: $target_path" >&2
    return
  fi

  mv "$source_path" "$target_path"

  if [[ -e "$source_import" && ! -e "$target_import" ]]; then
    mv "$source_import" "$target_import"
  fi
}

mkdir -p "$source_assets_dir"
touch "$source_assets_dir/.gdignore"

if [[ "$maps_dir" != "$source_assets_dir" ]]; then
  while IFS= read -r -d '' source_texture; do
    move_to_source "$source_texture"
  done < <(texture_files)
fi

echo "Source maps moved to: $source_assets_dir"
echo "Done. Reimport the generated PNGs in Godot before adding them to Terrain3DAssets."
