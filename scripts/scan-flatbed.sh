#!/usr/bin/env bash

# dependencies:
# sane-backends -> scanimage
# imagemagick -> convert

set -eu
set -x # debug

# date
date_time=$(date +%Y-%m-%d.%H-%M-%S)

device_name="$1"

title="$2"
title="${title%.webp}" # remove .webp file extension
if [[ -z "$title" ]]
then
  title="scan.$date_time"
fi


scanimage_extra_options=(
  # --MultifeedDetection=yes
  # --SkipBlankPage=yes
  # din a4: 210 x 297 mm
  -x 210
  -y 297
)



small_enable=true
large_enable=false

small_quality=1%
large_quality=10%

# small_scale=50%
small_scale=100% # dont scale

resolution=300



keep_tempfiles=false



#   -level ${lowthresh}x${highthresh}%

# contrast: increase contrast to remove noise in document scans
# https://superuser.com/questions/622950/is-there-a-way-to-increase-the-contrast-of-a-pdf-that-was-created-by-scanning-a
# http://www.fmwconcepts.com/imagemagick/thresholds/index.php # -t soft -l 25 -h 75
# to find these threshold values, use gimp > colors > levels
#lowthresh=15 # text is too light
lowthresh=40 # produce dark text # 40/100 = 100/256
# highthresh:
# lower = more white, less artefacts, more loss of grey lines
#highthresh=80
# 98 is better than 100
# to convert a slightly grey background to a pure white background
highthresh=98
# i need to go this low, to remove vertical grey lines produced by my ADF scanner
# see also https://github.com/ImageMagick/ImageMagick/discussions/6042
#highthresh=85
# i really need to go THIS low to remove all grey lines on all pages. oof!
# this is lossy, because my hand-written text also contains grey lines
#highthresh=66 # 66/100 = 170/256



shared_convert_options=(
  "${extra_convert_options[@]}"
  -set colorspace RGB
  +profile '*'
  # -quality $quality

  -define webp:lossless=false # ensamp the image without any loss
  -define webp:auto-filter=true # optimize the filtering strength to reach a well-balanced quality
  -define webp:image-hint=graph # hint about the image type

  # https://imagemagick.org/script/webp.php
  # For text images, consider these defines:
  # -define webp:sns-strength=0 # spatial noise shaping = decide which area of the picture should use relatively less bits
  # -define webp:filter-strength=0 # deblocking filter
  # -define webp:preprocessing=0
  # -define webp:segments=2

  # "+repage" required for webp output with "-crop"
  # "+0+0" is required for "-crop" otherwise it produces multiple images
  #   or an animated webp image with multiple frames
  # -crop $crop_x"x"$crop_y+0+0 +repage
  # "-coalesce" is required for webp output
  # https://github.com/ImageMagick/ImageMagick/issues/6041
  -coalesce
);

small_convert_options=(
  #"${shared_convert_options[@]}"
  -scale $small_scale
  -level ${lowthresh}x${highthresh}%
  -quality "$small_quality"
);

large_convert_options=(
  #"${shared_convert_options[@]}"
  -quality "$large_quality"
);



# output file
# lossy compression to webp. better than jpg
# 0.2 MByte
#o=large/scan.$date_time.large.webp
o="large/$title.large.webp"
quality=80

outdir="$(dirname "$o")"
if [[ ! -d "$outdir" ]]
then
  mkdir -p -v "$outdir"
fi

# also produce a small version
o_small="$title.webp"
small_scale=50%

# 15 MByte png file
resolution=300

mkdir /run/user/$(id --user) 2>/dev/null || true

# temp file
temp_path=/run/user/$(id --user)/scan.$date_time.tiff



# scan

echo "scanning to temp file $temp_path ..."

#sudo scanimage --device-name="$scanner" --mode=Color --resolution=$resolution --format=png --output="$temp_path" --progress
#sudo scanimage --device-name="$scanner" --mode=Color --resolution=$resolution --format=png --output="$temp_path" --progress --buffer-size=32
#sudo scanimage --device-name="$scanner" --mode=Color --resolution=$resolution --format=png --output="$temp_path" --progress --buffer-size=$((32 * 1000))
# sudo scanimage --device-name=genesys:libusb:001:013 --all-options
#  Geometry:
#    -l 0..216.07mm [0]
#        Top-left x position of scan area.
#    -t 0..299mm [0]
#        Top-left y position of scan area.
#    -x 0..216.07mm [216.07]
#        Width of scan-area.
#    -y 0..299mm [299]
#        Height of scan-area.
# DIN A4: 210 x 297 mm2
# webp: 1276x1766 = 216.07x299mm2
# 210/216.07*1276 = 1240.1536539084557
# 297/299*1766 = 1754.1872909698998
# mkdir orig-crop; for f in *.webp; do echo $f; mv $f orig-crop; convert orig-crop/$f -crop 1240x1754+0+0 $f; done
args=(
  sudo
  scanimage
  --device-name="$device_name"
  --mode=Color
  --resolution=$resolution
  --format=tiff
  --output="$temp_path"
  --progress
  --buffer-size=$((32 * 1000))
  "${scanimage_extra_options[@]}"
)
echo "${args[@]}"
"${args[@]}"

# fuzzy = wildcard -> not working
#sudo scanimage --device-name="genesys:libusb:*:*" --mode=Color --resolution=300 --format=png --output="$temp_path" --progress



# convert

if $small_enable; then
  # convert small

  # o_small="$title.webp"

  if [ -e "$o_small" ]; then o_small+=".$scan_time.webp"; fi

  echo creating "$o_small"

  convert_args_small=(
    magick
    "$temp_path"
    "${extra_convert_options[@]}"
    "${shared_convert_options[@]}"
    "${this_extra_convert_options[@]}"
    "${small_convert_options[@]}"
    "$o_small"
  )
  echo "${convert_args_small[@]}"
  "${convert_args_small[@]}"
fi

echo "done $o_small"



if $keep_tempfiles; then
  echo "keeping tempfile $temp_path"
else
  rm -f "$temp_path"
fi
