#! /bin/bash

HELP=""
DRYRUN=""
FFMPEG="ffmpeg"
FFMPEG_ARGS="-acodec copy -vcodec copy"
FORMAT='%02d - %s.%s'
NAMEFN='$numf - $name.$ext'

TIMESPEC='([0-9]+:)+[0-9]+(\.[0-9]*)?'
NUMBERSPEC='[0-9]+'
SEPSPEC='[:,.-]+'
REGEXP="
s/^/--name /;
s/\$/ --endname/;	# mark start and end of current stanza, for later augmentation
# front loop: extract any timespec in the beggining
: frontrep
s/--name (\\s*-+\\s*)?($TIMESPEC)\\b(.*) --endname/--timespec \\2\\n--name \\5 --endname/g;
t frontrep
# back loop: extract any timespec at the end
: backrep
s/--name (.*)\\b($TIMESPEC)(\\s*-+\\s*)? --endname/--name \\1 --endname\\n--timespec \\2/g;
t backrep
# Last stanza only: add an extra timespec to correctly position last track
\$s/\$/\\n--timespec -0:00/
s/--name \\s*($SEPSPEC\\s+)?\\b/--name /g;	# remove any separators, spaces
s/--name $NUMBERSPEC$SEPSPEC\\s*/--name /;	# and track number. Bash will correctly count later
# put all timespecs in the beggining of the record for later proper parsing
s/^(.*)--name (.*) --endname(.*)\$/\\1\\n\\3\\n--name \\2 --endname\\n/;
# remove the optional final timespec added previously, if not necessary
s/--timespec (.*)\\n--timespec (.*)\\n--timespec -0:00/--timespec \\1\\n--timespec \\2/;
s/ --endname//g; 			# remove end marker
s/^/--record\\n/;			# mark start of the record
s/\\n\\s*\\n/\\n/g;			# delete any remaining middle blank lines
s/(^\\s*\\n|\\n\\s*\$)//;	# delete a first or last blank line
/--timespec [0-9]/p			# print only if record has at least one valid timespec
"

EXTRACT_AUDIO=""
PARSE_INDEX=""

while [[ $# -gt 0 ]]; do
	
	case "$1" in
	--src|-s)
		shift; SRC="$1";
		;;
	--index|-i)
		shift; IND="$1";
		;;
	--help|-h)
		HELP=HELP
		;;
	--dry-run|-d)
		DRYRUN="1"
		;;
	--ffmpeg)
		shift; FFMPEG="$1"
		;;
	--format|-f)
		shift; NAMEFN="$1"
		;;
	--ffmpeg-opts|-a)
		shift; FFMPEG_ARGS="$1"
		;;
	-x|--extract-audio)
		FFMPEG_ARGS="-vn -acodec copy";
		EXTRACT_AUDIO="yes";
		if test ! -x $(which extract-audio.sh); then
			echo "$0: Could not find extract-audio.sh executable." >&2; exit 1;
		fi;;
	-p|--parse-index)
		PARSE_INDEX="yes"
		;;
	-*)
		echo "$0: Argument $1 unknown." >&2; exit 1
		;;
	*)
		SRC="$1";
		base="${SRC%.*}"; IND="$base.index"
		;;
	esac
	shift;
done


if test -n "$HELP"; then
	
	cat <<HELP

$0: Multimedia splitter. 
This script splits a source multimedia file.
Directions (time/names) are contained in an index file.
An index file is produced by the following rules

<indexfile>		->	<line> \\n
<line>			->	<itemno>? <timeinfo> <space>* <name> 	# left assoc.
				| <itemno>? <name> <space>* <timeinfo>	# right assoc.
<itemno>		->	([0-9]+) [:,.-]? <space>*
<timeinfo>		->	<starttime> 
				| <starttime> <space>* -+ <space>* <endtime>
<starttime>		->	<timespec>
<endtime>		->	<timespec>
<timespec>		->	([0-9]+:)+[0-9]+(\.[0-9]*)?
<name>			->	.*
<space>			->	[ \\t]

Every <line> describes a part of the file. It must contain either one
<timespec> which is interpreted as the starting time of the part, or two
<timespec> which are the starting and ending point of the part, respectively.
If <line> starts with a number (which is not time) this number is considered
to be an index counter and is dropped. <name> is what remains after parsing
all other symbols and it is the name of the part. Name must further comply
to filesystem restrictions (eg, if <name> contains a '/' character splitting
behaviour will be undefined) and must lead to unique filenames.

This script may optionally copy-extract audio from multimedia file, and guess
the correct codec and extension for the parts.

INVOCATION:
$0 [--help] 
   [--dry-run] [--ffmpeg <program>] [--ffmpeg-args <ffmpeg-args>]  
   [--format <format spec>] [-p|--parse-index] [-x|--extract-audio]
   [--src] <source stream> --ind <index file> 
   
<source stream>         is the source multimedia stream
<index file>            is the file with the split directions. If not given
			file will be guessed from source file, replacing
			its extension with the \`.index' extension.
--help                  nothing is done; only this help test shows
--dry-run               only echo the commands to be run
--ffmpeg                defaults to ffmpeg. Any compatible program can
                        be given here
--parse-index		Debug: Parse index file only
--extract-audio		Try to extract audio from a video
--ffmpeg-opts           extra arguments to ffmpeg program
--format <format spec>  if given, the target filenames of the parts
                        are taken by eval'ing the <format spec> argument
                        There are available the following variables:
                        \$num      is the counter
                        \$numf     formatted version %02d of \$num
                        \$name     <name of the part> as in index file
                        \$ext      the extension of the source file
                        The default <format spec> is:
                        '\$numf - \$name.\$ext'
	                        
HELP
	exit 0;
fi

if test '!' '(' -r "$IND" ')'; then
	echo "$0: Index file $IND not readable." >&2; exit 1;
fi
if [[ -n "$PARSE_INDEX" ]]; then
	exec sed -rn "$REGEXP" "$IND"
fi
if test '!' '(' -r "$SRC" ')'; then
	echo "$0: Source file $SRC not readable." >&2; exit 1;
fi

if [[ -n "$EXTRACT_AUDIO" ]]; then
	ext="$(extract-audio.sh -x "$SRC")"; status=$?
	[[ $status -gt 0 ]] && exit $status;
else
	ext="${SRC##*.}";
fi


from=""; to=""; name=""; num=0; ctime=0;
sed -nr "$REGEXP" < "$IND" |\
	while read op arg; do
		case $op in
		--record)
			;;
		--timespec)
			from="$to";
			to="$arg";
			;;
		--name)
			name="$arg"
			;;
		*)
			echo "$0: sed output invalid record: \`$op $arg'" >&2; exit 1;
			;;
		esac
		if [[ -n "$name" ]] && [[ -n "$from" ]] && [[ -n "$to" ]]; then 
			num=$((num + 1));
			numf=$(printf '%02d' $num)
			if test "$to" = "-0:00"; then 
				toarg=""
			else
				toarg="-to $to"
			fi;
			eval target=\""$NAMEFN"\"
			if test -n "$DRYRUN"; then
				set -x
				true $FFMPEG -nostdin -i "$SRC" -ss "$from" $toarg $FFMPEG_ARGS "$target"
				set +x
			else
				$FFMPEG -nostdin -i "$SRC" -ss "$from" $toarg $FFMPEG_ARGS "$target" || exit 1
			fi
			name="";
			from="";
		fi
	done
