#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai

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


src=$1 #database directory
dataDir=$2 #save kaldi file directory

if [ ! -f $doc ]; then
  echo "$0: no such file $doc"
  exit 1;
fi

# all utterances are FLAC compressed
if ! which sox >&/dev/null; then
   echo "Please install 'sox'! and specify the path"
   exit 1
fi

mkdir -p $dataDir
rm -f $dataDir/{wav.scp,feats.scp,utt2spk,spk2utt,segments,text}

nbr=$(find $src -mindepth 1 -maxdepth 1 -type d | wc -l)
var=0
#prepare segment, utt2spk, text, wav.scp files
for folder in $(find $src -mindepth 1 -maxdepth 1 -type d | sort); do
    basename=$(basename $folder)
    folder=$basename
    [ ! -e $src/$folder/$basename.trs ] && echo "Missing $src/$folder/$basename.trs" && exit 1
    #Prepare the text for kaldi format
    var=$((var+1))
    perc=$(awk "BEGIN {printf \"%.0f\",($var/$nbr)*100}")
    mod=$(awk "BEGIN {printf \"%.0f\",($perc%10)}")
    div=$(awk "BEGIN {printf \"%d\",($perc-$mod)/10}")
    i=1
    msg=""
    while test $i -le $div; do 
	msg=$msg"=="
	i=$((i+1))
    done
    echo -ne 'Traitement progress: ['$msg'>' ${perc%.*}'%\r'
    echo -ne '\t\t\t\t\t\t]' $3'_Data\r'
    #[ ! -f $src/$folder/$basename.trs ] && echo "file does not exist" 
    $path/parseTcof.py $src/$folder/$basename.trs $basename $dataDir
    echo $basename /usr/bin/sox $src/$folder/$basename.wav -t wav -r 16000 -c 1 - "|" >> $dataDir/wav.scp
done
echo -ne '\n'

[ ! -e $dataDir/utt2spk ] && echo "Missing $dataDir/utt2spk" && exit 1
sort $dataDir/utt2spk > $dataDir/utt2spk.tmp
sort $dataDir/wav.scp > $dataDir/wav.scp.tmp
sort $dataDir/segments > $dataDir/segments.tmp
sort $dataDir/text > $dataDir/text.tmp

rm $dataDir/{wav.scp,utt2spk,segments,text}

mv $dataDir/wav.scp.tmp $dataDir/wav.scp
mv $dataDir/utt2spk.tmp $dataDir/utt2spk
mv $dataDir/segments.tmp $dataDir/segments
mv $dataDir/text.tmp $dataDir/text 

sort -k 2 $dataDir/utt2spk | utils/utt2spk_to_spk2utt.pl > $dataDir/spk2utt
local/get_utt2dur.sh $dataDir 2>/dev/null || exit 1
utils/validate_data_dir.sh --no-feats $dataDir

