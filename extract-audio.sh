#!/bin/bash

PREFIX=""
HELP=""
FFMPEG="ffmpeg"
FFPROBE="ffprobe"
MODE="normal"
IGNORE_ERRORS="";

function extract_audio() {

		vid=$1; shift; 

		# Have video/audio?
		acodec="$($FFPROBE -v error -show_entries stream=codec_type,codec_name -print_format flat "$vid" | sed -nr '
			s/^.*codec_type="(video|audio)".*$/type \1/p
			s/^.*codec_name="([^\.]+)".*/name \1/p
		' | awk '
			BEGIN 	{ a = 0; v = 0; e = 0; acodec=""; }
			NR % 2 == 1 { ccodec = ""; cname = ""; }
			$1 ~ /type/	{ ctype = $2; }
			$1 ~ /name/ { cname = $2; }
			NR % 2 == 0 { if (ctype ~ /video/) v = 1; else if (ctype ~ /audio/ && a == 0) {a = 1; acodec=cname; } else e = 1; }
			END 		{ if ( (a+v >= 2) && (e == 0) ) print acodec; else exit 1; }
		')";
		status=$?

		if [[ $status -ne 0 ]]; then echo "$0: \`$vid' Audio only or video only or could not probe." 1>&2; return $status; fi
		if [[ -z "$acodec" ]]; then return 1; fi

		#convert codec name to extension
		case $acodec in
			8svx_exp*)	ext=8svx;;
			aac*)		ext=aac;;
			ac3*)		ext=ac3;;
			adpcm*)		ext=adpcm;;
			alac*)		ext=m4a;;
			amr*)		ext=3ga;;
			ape)		ext=ape;;
			atrac*)		ext=aa3;;
			avc*)		ext=avc;;
			binkaudio_dct)	ext=dct;;
			binkaudio_rdft)	ext=rdft;;
			cook*)		ext=cook;;
			bmv*)		ext=bmv;;
			dsd*)		ext=dsd;;
			dss*)		ext=dss;;
			dts*)		ext=dts;;
			flac*)		ext=flac;;
			mp1*)		ext=mp1;;
			mp2*)		ext=mp2;;
			mp3*)		ext=mp3;;
			mp4als)		ext=als;;
			musepack7)	ext=mpc7;;
			musepack8)	ext=mpc8;;
			opus*)		ext=opus;;
			pcm*)		ext=pcm;;
			wma*)		ext=wma;;
			xan_dpcm*)	ext=dpcm;;
			ra_*)		ext=ra;;
			ralf*)		ext=ralf;;
			vorbis)		ext=oga;;
			*)			ext=$acodec;;
		esac

		oldext="${vid##*.}"		# old extension
		basename="${vid%.*}"	# base name

		# do raw stream copy
		case $MODE in
		DRY_RUN)
			set -x
			true $FFMPEG -nostdin -i "$vid" -vn -acodec copy "$PREFIX$basename.$ext" 
			set +x
			return 0;;
		ONLYEXT)
			echo $ext; 
			return 0;;
		*)
			$FFMPEG -nostdin -i "$vid" -vn -acodec copy "$PREFIX$basename.$ext"
			return $?
		esac
}

function help() {
	cat <<-HELP
		$0: Audio extract from simple videos.
		This script will try to raw-extract audio stream from simple video files
		(aka with one audio stream), guessing the codec used and choosing the correct
		new file extension and format.

		Syntax:
		$0 [(-p|--prefix) <prefix>] [-h|--help] [-d|--dry-run]
		[-i|--ignore-errors] <video files...>
HELP
}

while [[ $# -gt 0 ]]; do
	
	case "$1" in
		-p|--prefix)
			shift;
			PREFIX="$1";;
		-h|--help)
			HELP="yes";
			help; exit 0;;
		--dry-run|-d)
			MODE="DRY_RUN";;
		-x|--extension-only)
			MODE="ONLYEXT";;
		--ignore-errors|-i)
			IGNORE_ERRORS="yes";;
		-*)
			echo "$0: Invalid option: \`$1'" 1>&2; exit 1;;
		*)
			extract_audio "$1"; status=$?;
			if test -z "$IGNORE_ERRORS" -a $status -gt 0; then exit $status; fi
	esac
	shift;
done
