#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai
# data preparation script for another organisation of data

# Begin configuration section.
apply_adaptation=false # Language model toolkit
sample_rate=16000 # Sample rate of wav file.
path=local
# End configuration section.
. utils/parse_options.sh

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 [option] <src-dir> <dst-dir>"
  echo "e.g.: $0 --apply_adaptation false /french_speech/train /data/train"
  echo "Options:"
  echo " --path 		 # Path to the dataset"
  echo " --apply_adaptation      # Apply text adaptation according to the lexicon. Default=false"
  echo " --sample_rate           # output audio file sample rate"
  exit 1
fi

src=$1
dst=$2

mkdir -p $dst || exit 1;

[ ! -d $src ] && echo "$0: no such directory $src" && exit 1;

rm -f $dst/*

wav_scp=$dst/wav.scp;
trans=$dst/text;
utt2spk=$dst/utt2spk;
spk2utt=$dst/spk2utt;
segments=$dst/segments;

find $src/ -iname "*.wav" | sort | xargs -I% basename % .wav | sort | \
      awk -v "dir=$src" -v "ext=wav" -v "sr=$sample_rate" '{printf "%s /usr/bin/sox %s/%s.%s -t wav -r %s -c 1 - |\n", $0, dir, $0, ext, sr}' >>$wav_scp|| exit 1

for file in $(find $src/ -iname "*.wav" | sort | xargs -I% basename % .wav | sort); do
	[ ! -f $src/$file.txt ] && echo "$0: no such text file $file" && exit 1
	text=$(cat $src/$file.txt)
	echo $file $text | sed 's/ ﻿/ /g'  >>$trans|| exit 1
	echo "$file $file" >>$utt2spk|| exit 1
done

$path/text_prepare.py $dst $apply_adaptation
utils/utt2spk_to_spk2utt.pl <$utt2spk >$spk2utt || exit 1

ntrans=$(wc -l <$trans)
nutt2spk=$(wc -l <$utt2spk)
! [ "$ntrans" -eq "$nutt2spk" ] && \
  echo "Inconsistent #transcripts($ntrans) and #utt2spk($nutt2spk)" && exit 1;

local/get_utt2dur.sh $dst || exit 1

cat $dst/utt2dur | awk '{print $1" "$1" 0 "$2}' > $segments

utils/validate_data_dir.sh --no-feats $dst || exit 1;

echo "Successfully prepared data in $dst"

exit 0
