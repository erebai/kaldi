#!/bin/bash

# Copyright (C) 2016, Linagora, Ilyes Rebai


# Begin configuration section.
dir=$exp_dir/nnet2/${hidden_function}_${num_hidden_layers}layers
num_utts_subset="--num-utts-subset 100" # number of utterances for validation
# End configuration section.


if [ ! -f $dir/final.mdl ]; then
  if [ "$hidden_function" == "Pnorm" ]; then
    steps/nnet2/train_pnorm_fast.sh --stage $train_stage --egs-opts "$num_utts_subset" \
     --samples-per-iter $samples_per_iter \
     --parallel-opts "$parallel_opts" \
     --num-threads "$num_threads" \
     --minibatch-size "$minibatch_size" \
     --num-jobs-nnet $train_nj  --mix-up $mix_up \
     --initial-learning-rate $initial_learning_rate --final-learning-rate $final_learning_rate \
     --num-hidden-layers $num_hidden_layers \
     --pnorm-input-dim $pnorm_input_dim --pnorm-output-dim $pnorm_output_dim \
      $train_dir data/lang $exp_dir/tri4a_ali $dir
  else
    local/nnet2/train_dnn_fast.sh --stage $train_stage --egs-opts "$num_utts_subset" \
     --samples-per-iter $samples_per_iter \
     --parallel-opts "$parallel_opts" \
     --num-threads "$num_threads" \
     --minibatch-size "$minibatch_size" \
     --num-jobs-nnet $train_nj --mix-up $mix_up \
     --initial-learning-rate $initial_learning_rate --final-learning-rate $final_learning_rate \
     --num-hidden-layers $num_hidden_layers --hidden-layer-dim $hidden_layer_dim \
     --activation-function $hidden_function \
      $train_dir data/lang $exp_dir/tri4a_ali $dir
  fi
fi

#Decoder
for lm in ${decode_lms[*]}; do
  for d in $data_decode; do
    steps/nnet2/decode.sh --config $decode_dnn_conf --nj $decode_nj --transform-dir $exp_dir/tri4a_${d}_ali \
     $exp_dir/tri4a/graph_$lm data/$d $dir/decode_${d}_$lm
  done
done
for x in $dir/decode_${d}_*; do
  [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
done
