#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai

# Begin configuration section.
# End configuration section.


if [ $stage_dbn -le 0 ]; then
  # Store fMLLR features

  # train
  steps/nnet/make_fmllr_feats.sh --nj $train_nj \
     --transform-dir $exp_dir/tri4a_ali \
     $data_fmllr/train data/train $exp_dir/tri4a $data_fmllr/train/{log,data} || exit 1

  for data in $data_decode; do
    steps/nnet/make_fmllr_feats.sh --nj $decode_nj \
      --transform-dir $exp_dir/tri4a_${data}_ali \
      $data_fmllr/$data data/$data $exp_dir/tri4a $data_fmllr/$data/{log,data}
  done

  # split the data if data/dev is not specified : 90% train 10% cross-validation (held-out)
  [ "$data_dev" == "" ] && utils/subset_data_dir_tr_cv.sh $data_fmllr/train $data_fmllr/train_tr90 $data_fmllr/train_cv10
fi

if [ $stage_dbn -le 1 ]; then
  # Pre-train DBN, i.e. a stack of RBMs
  dir=$exp_dir/nnet/pretrain-${depth}dbn
  [ ! -d $dir ] && mkdir $dir
  steps/nnet/pretrain_dbn.sh --rbm-iter 1 --nn-depth $depth $data_fmllr/train $dir || exit 1;
fi


if [ $stage_dbn -le 2 ]; then
# fine-tuning of DBN parameters
  dir=$exp_dir/nnet/${depth}dbn
  ali=$exp_dir/tri4a_ali
  ali_dev=$exp_dir/tri4a_dev_ali
  feature_transform=$exp_dir/nnet/pretrain-${depth}dbn/final.feature_transform
  dbn=$exp_dir/nnet/pretrain-${depth}dbn/$depth.dbn

  if [ "$data_dev" == "" ]; then
    steps/nnet/train.sh --feature-transform $feature_transform --dbn $dbn --hid-layers 0 --learn-rate $learn_rate \
      $data_fmllr/train_tr90 $data_fmllr/train_cv10 data/lang $ali $ali $dir
  else
    steps/nnet/train.sh --feature-transform $feature_transform --dbn $dbn --hid-layers 0 --learn-rate $learn_rate \
      $data_fmllr/train $data_fmllr/dev data/lang $ali $ali_dev $dir
  fi

  #Decoder
  for lm in ${decode_lms[*]}; do
    for d in $data_decode; do
      steps/nnet/decode.sh --config $decode_dnn_conf --nj $decode_nj \
        $exp_dir/tri4a/graph_$lm $data_fmllr/$d $exp_dir/nnet/${depth}dbn/decode_${d}_$lm
    done
  done
  for x in $exp_dir/nnet/${depth}dbn/decode_*; do
    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
  done

fi
