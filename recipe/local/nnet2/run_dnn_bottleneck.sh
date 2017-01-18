#!/bin/bash

# This script learns a bottleneck neural network, dump bn features, and then trains a tanh_nnet2 on bn (or bn+fmllr) features

stage=0
train_stage=-100
use_gpu=true
if $use_gpu; then
  parallel_opts="--gpu 1"
  num_threads=1
  minibatch_size=512
else
# with just 4 jobs this might be a little slow.
  num_threads=4
  parallel_opts="--num-threads $num_threads" 
  minibatch_size=128
fi
decode_njobs=3
gmm=exp/tri4a
gmmalign=${gmm}_ali
gmmalignTe=$gmm/decode_test_IRSTLM
expbn=exp/bn_nnet2 #Train deep bottleneck neural network
expbnf=exp/nnet2_bnf #Train deep neural network on bn features
combine_feats=true
dump_fmllr=true
feats=
#mfcc feature dir
dataTr=data/train
dataTe=data/test
#fmllr feature dir
fmllrTr=data/fmllr/train
fmllrTe=data/fmllr/test
#bn feature dir
bnTr=data/fmllr_bn/train
bnTe=data/fmllr_bn/test
#fmllr+bn feature dir
combineTr=data/combine/train
combineTe=data/combine/test

. ./path.sh
. utils/parse_options.sh

if [ $stage -le 0 ]; then
  #utils/subset_data_dir.sh data/train 500 $dataTr
  #utils/subset_data_dir.sh data/test 10 $dataTe
  if [ "$dump_fmllr" == true ]; then
    steps/nnet/make_fmllr_feats.sh --transform-dir $gmmalign $fmllrTr $dataTr $gmm $fmllrTr/{log,data}
    steps/nnet/make_fmllr_feats.sh --transform-dir $gmmalignTe $fmllrTe $dataTe $gmm $fmllrTe/{log,data}
    steps/compute_cmvn_stats.sh $fmllrTr $fmllrTr/{log,data}
    steps/compute_cmvn_stats.sh $fmllrTe $fmllrTe/{log,data}
  else
    $fmllrTr=$dataTr
    $fmllrTe=$dataTe
  fi
fi

if [ $stage -le 1 ]; then
  if [ ! -f $dir/final.mdl ]; then
    [ "$dump_fmllr" == true ] && feats="--feat-type raw"
    steps/nnet2/train_tanh_bottleneck.sh --stage $train_stage\
     --samples-per-iter 400000 \
     --parallel-opts "$parallel_opts" \
     --num-threads "$num_threads" \
     --minibatch-size "$minibatch_size" \
     --num-jobs-nnet 12  --mix-up 8000 \
     --lda-opts "$feats" --egs-opts "$feats" \
     --initial-learning-rate 0.01 --final-learning-rate 0.001 \
     --num-hidden-layers 2 --hidden-layer-dim 64 --bottleneck-dim 26 \
       $fmllrTr data/lang $gmmalign $expbn
  fi
fi

if [ $stage -le 2 ]; then
  [ "$dump_fmllr" == true ] && feats="--feat-type raw"
  mkdir -p $bnTr/{data,log}
  steps/nnet2/dump_bottleneck_features.sh $feats $fmllrTr $bnTr $expbn $bnTr/{data,log}
  mkdir -p $bnTe/{data,log}
  steps/nnet2/dump_bottleneck_features.sh $feats $fmllrTe $bnTe $expbn $bnTe/{data,log}
  if [ "$combine_feats" == true ]; then
    steps/append_feats.sh $fmllrTr $bnTr $combineTr $combineTr/{log,data}
    steps/append_feats.sh $fmllrTe $bnTe $combineTe $combineTe/{log,data}
    steps/compute_cmvn_stats.sh $combineTr $combineTr/{log,data}
    steps/compute_cmvn_stats.sh $combineTe $combineTe/{log,data}
    dataTr=$combineTr
    dataTe=$combineTe
  else
    dataTr=$bnTr
    dataTe=$bnTe
  fi
fi

if [ $stage -le 3 ]; then
    steps/nnet2/train_tanh_fast.sh --stage $train_stage \
     --samples-per-iter 400000 \
     --parallel-opts "$parallel_opts" \
     --num-threads "$num_threads" \
     --minibatch-size "$minibatch_size" \
     --feat-type raw \
     --num-jobs-nnet 4  --mix-up 8000 \
     --initial-learning-rate 0.01 --final-learning-rate 0.001 \
     --num-hidden-layers 1 --hidden-layer-dim 64 \
      $dataTr data/lang $gmmalign $expbnf
fi

if [ $stage -le 4 ]; then
  #Decoder
  for lm in ${decode_lms[*]}; do
    steps/nnet2/decode.sh --config $decode_dnn_conf --nj $decode_nj --feat-type raw \
      $gmm/graph_$lm $dataTe $expbnf/decode_test_$lm
  done
  for x in $expbnf/decode_*; do
    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
  done
fi


