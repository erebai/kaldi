#!/bin/bash

. path.sh

# CONFIGURATION
dir=$exp_dir/autoencoder
dir_nnet=$exp_dir/autoencoder_nnet
output_dir=$nnet_dir/data_autoencoded
#END

if [ $stage -le 1 ]; then
  # Store fMLLR features

  # train
  steps/nnet/make_fmllr_feats.sh --nj $train_nj \
     --transform-dir $exp_dir/tri4a_ali \
     $data_fmllr/train $train_dir $exp_dir/tri4a $data_fmllr/train/{log,data} || exit 1
  steps/compute_cmvn_stats.sh $data_fmllr/train $data_fmllr/train/{log,data}

  for data in $data_decode; do
    steps/nnet/make_fmllr_feats.sh --nj $decode_nj \
      --transform-dir $exp_dir/tri4a_${data}_ali \
      $data_fmllr/$data data/$data $exp_dir/tri4a $data_fmllr/$data/{log,data}
    steps/compute_cmvn_stats.sh $data_fmllr/$data $data_fmllr/$data/{log,data}
  done

  # split the data if data/dev is not specified : 90% train 10% cross-validation (held-out)
  [ "$data_dev" == "" ] && utils/subset_data_dir_tr_cv.sh $data_fmllr/train $data_fmllr/train_tr90 $data_fmllr/train_cv10
fi

if [ $stage -le 2 ]; then
labels="ark:feat-to-post scp:$data_fmllr/train/feats.scp ark:- |"
numTgt=$(feat-to-dim "ark:copy-feats scp:$data_fmllr/train/feats.scp ark:- |" -)
  if [ "$data_dev" == "" ]; then
    run.pl $dir/log/train_nnet.log \
	  steps/nnet/train.sh --hid-layers $hid_layers --hid-dim $hid_dim --learn-rate $learn_rate \
	      --labels "$labels" --num-tgt $numTgt --train-tool "nnet-train-frmshuff --objective-function=mse" \
	          --proto-opts "--no-softmax --activation-type=<Tanh> --hid-bias-mean=-1.0 --hid-bias-range=1.0 --param-stddev-factor=0.01" \
		    $data_fmllr/train_tr90 $data_fmllr/train_cv10 dummy-dir dummy-dir dummy-dir $dir || exit 1;
  else
    run.pl $dir/log/train_nnet.log \
	  steps/nnet/train.sh --hid-layers $hid_layers --hid-dim $hid_dim --learn-rate $learn_rate \
	      --labels "$labels" --num-tgt $numTgt --train-tool "nnet-train-frmshuff --objective-function=mse" \
	          --proto-opts "--no-softmax --activation-type=<Tanh> --hid-bias-mean=-1.0 --hid-bias-range=1.0 --param-stddev-factor=0.01" \
		    $data_fmllr/train $data_fmllr/dev dummy-dir dummy-dir dummy-dir $dir || exit 1;
  fi
fi

if [ $stage -le 3 ]; then
  steps/nnet/make_bn_feats.sh --nj $train_nj --remove-last-components $remove_last_components \
	  $output_dir/train $data_fmllr/train $dir $output_dir/train/{log,data} || exit 1

  for data in $data_decode; do
    steps/nnet/make_bn_feats.sh --nj $decode_nj --remove-last-components $remove_last_components \
	  $output_dir/$data $data_fmllr/$data $dir $output_dir/$data/{log,data} || exit 1
  done
fi

if [ $stage  -le 4 ]; then
  if [ "$data_dev" == "" ]; then
    steps/nnet/train.sh --hid-layers $hid_layers --hid-dim $hid_dim --learn-rate $learn_rate \
      $data_fmllr/train_tr90 $data_fmllr/train_cv10 data/lang exp/tri4a_ali exp/tri4a_test_ali $dir_nnet
  else
    steps/nnet/train.sh --hid-layers $hid_layers --hid-dim $hid_dim --learn-rate $learn_rate \
      $data_fmllr/train $data_fmllr/dev data/lang exp/tri4a_ali exp/tri4a_dev_ali $dir_nnet
  fi
fi

if [ $stage -le 5 ]; then

  for lm in ${decode_lms[*]}; do
    for d in $data_decode; do
      steps/nnet/decode.sh --config $decode_dnn_conf --nj $decode_nj \
        $exp_dir/tri4a/graph_$lm $output_dir/$d $dir_nnet/decode_test_$lm
    done
  done
  for x in $dir_nnet/decode_test_*; do
    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
  done

fi
