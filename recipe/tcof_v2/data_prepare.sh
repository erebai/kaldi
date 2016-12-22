#!/bin/bash


# Copyright (C) 2016, Linagora, Ilyes Rebai

# Begin configuration section.
apply_adaptation=false # Language model toolkit
sample_rate=16000 # Sample rate of wav file.
# End configuration section.
. utils/parse_options.sh


if [ $# -ne 3 ]; then
  echo "Usage: $0 [option] <database-dir> <train_file> <data-dir>"
  echo "e.g.: $0 --apply_adaptation false tcof_speech train.txt data/train"
  echo "Options:"
  echo " --apply_adaptation      # Apply text adaptation according to the lexicon. Default=false"
  echo " --sample_rate           # output audio file sample rate"
  exit 1;
fi


Dir=$1 #database directory
doc=$2 #file path
dataDir=$3 #save kaldi file directory
lexicon=local/other_data/xml/lexicon.mdf #lexicon file for combined words
dtdfile=local/other_data/xml/trans-14.dtd #DTD file for XML transcriptions
XMLSTARLET=xmlstarlet

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

nbr=$(wc -l < $doc)
var=0
#prepare segment, utt2spk, text, wav.scp files
cat $doc | while read folder; do 
    basename=$(basename $folder)
    [ ! -e $Dir/$folder/$basename.trs ] && echo "Missing $Dir/$folder/$basename.trs"
    [ ! -e $Dir/$folder/trans-14.dtd ] && cp $dtdfile $Dir/$folder
    [ ! -e $Dir/$folder/trans-14.dtd ] && echo "Missing $Dir/$folder/trans-14.dtd" && exit 1
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
    $XMLSTARLET ed -d '//Section/Turn/Event' -d '//Section/Turn/Background' -d '//Section/Turn/Comment' -d '//Section/Turn/Who' -d '//Section/Turn/Vocal' -a '//Section/Turn/Sync' -t text -n string -v '$%%$' -d '//Section/Turn/Sync' $Dir/$folder/$basename.trs > $Dir/$folder/$basename.modified.trs
    $XMLSTARLET sel -t -m '//Section' -m "Turn" -n -v  "concat(text(),'')" $Dir/$folder/$basename.modified.trs > $Dir/$folder/$basename.text
    sed -i '/^ *$/d' $Dir/$folder/$basename.text

    $XMLSTARLET sel -t -m '//Section' -m "Turn" -n -v  "concat(@speaker,' ',@startTime,' ',@endTime,' ')" -m "Sync" -v "concat(@time,' ')" $Dir/$folder/$basename.trs | sed '/^$/d' > $Dir/$folder/$basename.txt 
    local/other_data/xml/file_prepare.py $basename $dataDir $Dir/$folder/$basename.text < $Dir/$folder/$basename.txt
    echo $basename /usr/bin/sox $Dir/$folder/$basename.wav -t wav -r 16000 -c 1 - "|" >> $dataDir/wav.scp
    rm $Dir/$folder/$basename.modified.trs $Dir/$folder/$basename.text $Dir/$folder/$basename.txt
done
echo -ne '\n'

[ ! -e $dataDir/utt2spk ] && echo "Missing $dataDir/utt2spk" && exit 1
sort $dataDir/utt2spk > $dataDir/utt2spk.tmp
sort $dataDir/wav.scp > $dataDir/wav.scp.tmp
sort $dataDir/segments > $dataDir/segments.tmp
cat $dataDir/text > $dataDir/text.tmp

rm $dataDir/{wav.scp,utt2spk,segments,text}

mv $dataDir/wav.scp.tmp $dataDir/wav.scp
mv $dataDir/utt2spk.tmp $dataDir/utt2spk
mv $dataDir/segments.tmp $dataDir/segments
mv $dataDir/text.tmp $dataDir/text 

sort -k 2 $dataDir/utt2spk | utils/utt2spk_to_spk2utt.pl > $dataDir/spk2utt
local/get_utt2dur.sh $dataDir 2>/dev/null || exit 1
utils/validate_data_dir.sh --no-feats $dataDir

