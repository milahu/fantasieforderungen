#! /usr/bin/env bash

# https://unix.stackexchange.com/a/799490/295986
function get_subpaths_of_path() {
  # NOTE this assumes that path is normalized
  local path="$1"
  if [ -z "$path" ]; then return; fi
  local next_path
  while true; do
    echo "$path"
    next_path=${path%/*} # remove last component
    if [ "$path" = "$next_path" ]; then return; fi
    path="$next_path"
  done
}

# scan-adf.sh
# single pass duplex scanning of multiple pages (ADF)
# with Brother ADS-3000N scanner


set -eu
# set -x # debug



scan_time=$(date +%s)



this_user_uid=$(id --user)
this_user_gid=$(id --group)

output_user_uid=1000
output_user_gid=100

tempdir="/run/user/$output_user_uid"

keep_tempfile=true # debug
keep_tempfile=false

write_logfile=true # debug
#write_logfile=false



do_chown=false

if ((output_user_uid != this_user_uid)) || ((output_user_gid != this_user_gid)); then
  do_chown=true
fi

# TODO dynamic. use "lsusb" to find the scanner device
# sudo scanimage -L
# $ sudo scanimage -L 
# device `brother5:bus1;dev3' is a Brother ADS-3000N USB scanner
# note: "dev3" does not correspond with output of lsusb
# $ lsusb | grep ADS-3000N
# Bus 001 Device 073: ID 04f9:03b8 Brother Industries, Ltd ADS-3000N
# $ sudo scanimage -L 
# device `brother4:bus4;dev1' is a Brother ADS-3000N USB scanner
# device `brother5:bus1;dev4' is a Brother ADS-3000N USB scanner
device_name="brother5:bus1;dev3"
device_name="brother5:bus1;dev4"
device_name="brother5:bus2;dev2" # Bus 002 Device 020: ID 04f9:03b8 Brother Industries, Ltd ADS-3000N
device_name="$1" # "scanimage -L" -> example: "brother5:bus2;dev2"
# shift
if [ -z "$device_name" ]; then
  echo "error: missing argument: device_name" >&2
  echo "example use: $0 brother5:bus2;dev2" >&2
  echo "hint: use this to get the device name: scanimage -L" >&2
  exit 1
fi

dst_path_full="$2" # example: "path/to/some-name" or "path/to/some-dir/"

shift 2



if [ "${dst_path_full: -1}" = "/" ]; then
  dst_path_dir="$dst_path_full"
  dst_path_name=""
else
  dst_path_dir="$(dirname "$dst_path_full")"
  dst_path_name="$(basename "$dst_path_full")"
fi

mkdir -p "$dst_path_dir"

if $do_chown; then
  # get_subpaths_of_path "$dst_path_dir" | while read -r subpath; do
  #   chown $output_user_uid:$output_user_gid "$subpath"
  # done
  get_subpaths_of_path "$dst_path_dir" |
  xargs -r -d$'\n' chown $output_user_uid:$output_user_gid
fi



# sudo scanimage --device-name="$device_name" --help
#source="Flatbed"
source="Automatic Document Feeder(left aligned,Duplex)"

# 24bit Color[Fast]
# Black & White
# True Gray
# Gray[Error Diffusion]
# mode="24bit Color[Fast]"
mode="True Gray"



# see benchmark.txt
# pnm and tiff are fastest and best quality
# png is much slower
# format=pnm
format=tiff



scanimage_extra_options=(
  --MultifeedDetection=yes
  --SkipBlankPage=yes
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

# 15 MByte png file
resolution=300



if [[ "$(id -u)" != "0" ]]; then
  echo "error: you must run this script as root. hint: sudo $0"
  exit 1
fi



# https://imagemagick.org/script/webp.php
# these produce large output:
# -define webp:alpha-compression=0
# -define webp:exact=true
# thresholds can produce ugly transparent output. example: scan.2023-10-03.10-31-42.1.webp
#   -black-threshold $bth% -white-threshold $wth%
#   -black-threshold "${lowthresh}%" -white-threshold "${highthresh}%"
# level should be enough:
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

# set profile to fix red tint (red color cast)
# https://blog.teamgeist-medien.de/2015/07/typo3-graphicsmagick-rotstich-bei-bildern-beheben-farbfehler.html
# https://legacy.imagemagick.org/discourse-server/viewtopic.php?t=22549
#large_convert_options+=( -set colorspace RGB +profile '*' )

# my document scanner adds a white bar below the scanned image. remove it by cropping
# input size: 2480x3508
crop_x=2480; crop_y=3342 # resolution=300

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
  -crop $crop_x"x"$crop_y+0+0 +repage
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



# date
date_time=$(date +%Y-%m-%d.%H-%M-%S)

mkdir -p "$tempdir"

# tempfile path format
# "%d" will be replaced by an incrementing number
temp_path_format="$tempdir/scan.$date_time.%d.$format"

# add zero-padding to the page number
# to fix the sort order of files
# without having to use "ls --sort=version" etc
# this format string is passed to printf like
# $ printf "%03d" 1
# 001
page_number_format="%03d"



# pass all args of this script to convert (TODO better?)
# example: -rotate 90
extra_convert_options=("$@")

if [ ${#extra_convert_options[@]} != 0 ]; then
  echo -n "extra magick arguments:"
  printf " %q" "${extra_convert_options[@]}"
  echo
fi



t1=$(date --utc +%s)



convert_pids=()



# https://stackoverflow.com/questions/6883363/read-user-input-inside-a-loop
# https://stackoverflow.com/questions/16854280/a-variable-modified-inside-a-while-loop-is-not-remembered
# while read n <&3; do echo n=$n; read i; echo i=$i; done 3< <(seq 3)

while read temp_path <&3; do

  echo "temp path: $temp_path"

  # add zero-padding to the page number
  # get extension
  temp_path_extension="${temp_path##*.}"
  # remove extension
  temp_path_base="${temp_path%.*}"
  # get page number
  temp_path_number="${temp_path_base##*.}"
  # remove page number
  temp_path_base="${temp_path_base%.*}"
  temp_path_new="$temp_path_base.$(printf "$page_number_format" "$temp_path_number").$temp_path_extension"
  mv -v "$temp_path" "$temp_path_new"
  temp_path="$temp_path_new"

  if [ "${dst_path_full: -1}" = "/" ]; then
    title="$dst_path_full"$(printf "$page_number_format" "$temp_path_number")
  else
    title="$dst_path_full".$(printf "$page_number_format" "$temp_path_number")
  fi

  # this is fancy but slow
  # TODO find something better to rename and rotate images
  #if false; then



  this_extra_convert_options=()



  # run "convert" processes in background
  # so they run in parallel and the loop can continue
  # we only have to keep the "$temp_path" files
  # until all "convert" are done
  # but we keep "$temp_path" anyway, so... works for now



  if $large_enable; then
    # convert large

    o="large/$title.large.webp"

    [ -d large ] || mkdir -p large
    if $do_chown; then
      chown $output_user_uid:$output_user_gid large
    fi

    if [ -e "$o" ]; then o+=".$scan_time.webp"; fi

    echo creating "$o"

    convert_args_large=(
      magick
      "$temp_path"
      "${extra_convert_options[@]}"
      "${shared_convert_options[@]}"
      "${this_extra_convert_options[@]}"
      "${large_convert_options[@]}"
      "$o"
    )
    echo "${convert_args_large[@]}"
  else
    convert_args_large=()
  fi

  if $small_enable; then
    # convert small

    o_small="$title.webp"

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
  else
    convert_args_small=()
  fi

  if $keep_tempfile; then
    echo keeping tempfile "$temp_path"
  fi

  # run "convert" in the background
  # and continue with the next image
  (
    if [ ${#convert_args_large[@]} != 0 ]; then
      "${convert_args_large[@]}"
      if $do_chown; then
        chown $output_user_uid:$output_user_gid "$o"
      fi
    fi
    if [ ${#convert_args_small[@]} != 0 ]; then
      "${convert_args_small[@]}"
      if $do_chown; then
        chown $output_user_uid:$output_user_gid "$o_small"
      fi
    fi
    if $keep_tempfile; then
      if $do_chown; then
        chown $output_user_uid:$output_user_gid "$temp_path"
      fi
    else
      echo "removing tempfile $temp_path"
      rm -f "$temp_path"
    fi
  ) &

  convert_pids+=($!)

  # the original tempfile is useful
  # to produce high-quality transformed images
  # transformed? usually rotation by 90 / 180 / 270 degrees

  # lossless rotation is only possible with jpeg images
  # not with compressed image formats like webp, jp2, ...
  # (png is an uncompressed image format)
  # but once correctly rotated, webp gives best quality for file size

  # jp2 is useful for embedding in pdf documents
  # because jp2 images are smaller than jpg images
  # and because pdf does not support webp images
  # TODO in the future, delete the tempfile when its no longer needed
  # find "$(dirname "$temp_path")" -mtime +10min -delete # ... or so

done 3< <(

  # redirect stderr to log file to keep the terminal clean
  # TODO better. buffer the output and print it as soon as possible, dont create a logfile
  if $write_logfile; then
    scanimage_log_path="$tempdir/scanimage.$(date -Is --utc).log"
    echo "writing scanimage log to $scanimage_log_path" >&2
  fi

  #set -x

  # FIXME --batch-print is not working?

  scanimage_args=(
    scanimage
    --device-name="$device_name"
    --resolution=$resolution
    --format=$format
    --batch="$temp_path_format"
    --batch-print
    --mode="$mode"
    --source="$source"
    "${scanimage_extra_options[@]}"
  )

  printf "%q " "${scanimage_args[@]}" >&2; echo >&2

  if $write_logfile; then
    "${scanimage_args[@]}" 2>"$scanimage_log_path"
  else
    "${scanimage_args[@]}" 2>/dev/null
  fi

)



echo "waiting for convert jobs..."
wait ${convert_pids[@]}



t2=$(date --utc +%s)
if [ "${dst_path_full: -1}" = "/" ]; then
  num_pages=$(find "$dst_path_dir" -name "*.$format" | wc -l)
else
  num_pages=$(find "$dst_path_dir" -name "$dst_path_name.*.$format" | wc -l)
fi
echo "done $num_pages pages in $((t2 - t1)) seconds"
