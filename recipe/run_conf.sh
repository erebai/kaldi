#!/bin/bash
# Copyright (C) 2016, Linagora, Ilyes Rebai
# INSTALL Sox package
# INSTALL KALDI_LM; SRILM; IRSTLM

# begin configuration section
data_preparation=true
preparation_stage=0
training_decoding=false
stage_tr=0
one_stage=true
#==================< DATA PREPARATION >================
adapt=false # Set this to true if you want to make the data as the vocabulary file,
	    # example: dès que (original text) => dès_que (vocabulary word)
liaison=true # Set this to true if you want to makes lexicon while taking into account liaison for French language
sample_rate=16000
#set the path to the training, development, and evaluation folders
  data_train="../recipe/speech_data/train ../../Fr/h1/Corpus ../../Fr/h2/ACSYNT" # directory which contains the training dataset
		     # To use multiple data source for training, use space " " as a delimiter between each dataset
  data_dev="../recipe/speech_data/dev"
  data_test="../recipe/speech_data/test"
  tgt_dir=data_dir # The folder in which the generated files will be saved
#set dictionnary path
sequiture_model=conf/model-2
lexicon=lexicon
#set the language model parameters
lms_function=( IRSTLM SRILM KALDI MERGING )
lms_order=( 3 3 3 3 )
lms=( IRSTLM SRILM KALDI "IRSTLM;SRILM" )
lms_lambda=( 1 1 1 "1;.3" )
train_text=data/local/dict/corpus # LM Training file. It's the training transcription by default
perplexity_file=perplexity.txt

#NOTE: if you would like to use a pre-compiled Language Model, just pute the file in the lm directory: data/local/lm/


#set the kaldi language directories parameters
sil_prob=0.3 # silence probability used while creating l.fst (transition probability from silence state to the loop state)

#set feature type: mfcc, plp, or fbank
feat_type=mfcc
feat_nj=10
#==================< DATA PREPARATION END >================

#==================< TRAINING AND EVALUATION >================
#Global parameters
exp_dir=exp
train_nj=30
decode_nj=5
decode_lms=( IRSTLM SRILM KALDI "IRSTLM.SRILM" )
decode_conf=conf/decode.config
decode_dnn_conf=conf/decode_dnn.config
save_results_file=RESULTS.txt
context_opts="--context-width=3 --central-position=1" # triphone context, e.g. "--context-width 5 --central-position 2" for quinphone.
sub_train_data=500
#set mono parameters
sub_data=200
#set Tri1 parameters
numLeavesTri1=2500
numGaussTri1=15000
#set LDA-MLLR parameters
numLeavesMLLT=2500
numGaussMLLT=15000
sliceTri2="--left-context=3 --right-context=3"
#set SAT-fmllr parameters
numLeavesSAT=2500
numGaussSAT=15000
#set SGMM2 parameters
numGaussUBM=400
numLeavesSGMM=7000
numGaussSGMM=9000
#set DNN parameters
DNN_technique=dnn #Define the neural net technique: dnn|dbn|autoencoder
# get more information about how to set DNN nnet2 parameters: http://kaldi-asr.org/doc/dnn2.html

############### dnn configuration ################
use_gpu=true
train_stage=-100

if $use_gpu; then
  num_threads=1
  parallel_opts="--gpu 1"
  minibatch_size=512
else
  # with just 4 jobs this might be a little slow.
  num_threads=16
  parallel_opts="--num-threads $num_threads" 
  minibatch_size=128
fi

samples_per_iter=400000
initial_learning_rate=0.01
final_learning_rate=0.001
mix_up=8000

hidden_function=Pnorm # The implemented functions are: Pnorm, Tanh, Sigmoid, RectifiedLinear 
num_hidden_layers=5
hidden_layer_dim=128 #used with Tanh, Sigmoid, RectifiedLinear activation function
pnorm_input_dim=2000 #used with pnorm function
pnorm_output_dim=400 #used with pnorm function

############### dbm configuration ################
data_fmllr=data-fmllr
depth=7
learn_rate=0.008
#==================< TRAINING AND EVALUATION END >================

# end configuration section
. ./path.sh

. utils/parse_options.sh



if [ $data_preparation == true ]; then

echo ============================================================================
echo " DATA PREPARATION "
echo ============================================================================

	if [ $preparation_stage -le 1 ]; then
	  echo "$0: Preparing data as Kaldi data directories"
	  [ "$data_train" == "" ] && echo "$0: Error= No dataset is defined in the configuration !!!" && exit 1
	  #Preparing Train data
	  valid_data=""
	  i=1
	  for dir in $data_train; do
	    if [ -d $dir ]; then
		echo "$0: Start preparing $dir dataset"
		$dir/data_prepare.sh --path $dir --apply_adaptation $adapt --sample_rate $sample_rate $dir $tgt_dir/data$i
		utils/fix_data_dir.sh $tgt_dir/data$i
		valid_data="$valid_data $tgt_dir/data$i"
		i=$((i+1))
		echo "$0: Successfully preparing $dir dataset"
	    else
	        echo "$0: Error= Data directory $dir is not find !!! Please check the path to the data folder."
	    fi
	  done
	  if [ "$valid_data" != "" ]; then
	    utils/combine_data.sh data/train $valid_data
	  else
	    echo "$0: Error= No Train data is processed !!!"; exit 1
	  fi

	  #Preparing Dev data
	  if [ "$data_dev" != "" ]; then
	    $data_dev/data_prepare.sh --path $data_dev --apply_adaptation $adapt --sample_rate $sample_rate $data_dev data/dev
	    data_decode="dev test"
	  else
	    echo "$0: WARNING= No Dev data is defined in the configuration !!!"
	    data_decode="test"
	  fi
	  #Preparing Test data
	  [ "$data_test" == "" ] && echo "$0: Error= No Test data is processed !!!" && exit 1
	  $data_test/data_prepare.sh --path $data_test --apply_adaptation $adapt --sample_rate $sample_rate $data_test data/test
	
	  [ $one_stage == true ] && exit 1
	fi

: '
	if [ $preparation_stage -le 2 ]; then
	  echo "$0: Data partition into train, dev, and test"
	  if [ $(echo ${data_train}${data_dev}${data_test} | grep "^[ [:digit:] ]*$") ]; then
	    utils/subset_data_dir_tr_cv.sh 
	  else
	    echo "$0: Error= train, dev, and test variables are not in the correct format !!!"; exit 1
	  fi

	  [ $one_stage == true ] && exit 1
	fi
'

	if [ $preparation_stage -le 3 ]; then
	  ## Optional G2P training scripts.
	  #local/g2p/train_g2p.sh $lexicon conf
	  #sequiture_model=conf/model-5
	  [ $one_stage == true ] && exit 1
	fi

	if [ $preparation_stage -le 4 ]; then
	  echo "$0: Preparing dictionary"
	  local/dic_prep.sh $lexicon $sequiture_model

	  [ $one_stage == true ] && exit 1
	fi

	if [ $preparation_stage -le 5 ]; then
	  echo "$0: Preparing language model"
	  length=( ${#lms_function[@]} ${#lms_order[@]} ${#lms[@]} ${#lms_lambda[@]} )
	  min=0 max=0
	  for i in ${length[@]}; do
	      (( $i > max || max == 0)) && max=$i
	      (( $i < min || min == 0)) && min=$i
	  done

	  [ $min -ne $max ] && echo "Language model parameters are not set correctly" && exit 1

	  t=0
	  for lm in ${lms_function[*]}; do
	    local/lm_prep.sh \
		--text $train_text
		--lm_system $lm \
		--order ${lms_order[$t]} \
		--lexicon data/local/dict/lexicon.txt \
		--lms_systems "${lms[$t]}" \
		--lms_lambdas "${lms_lambda[$t]}"
	    t=$((t + 1))
	  done
	fi
	
	if [ $preparation_stage -le 6 ]; then
	  ## Optional Perplexity of the built models
	  echo "$0: evaluating the language model performance on the test data"
	  t=0
	  rm $perplexity_file
	  for lm in ${lms[*]}; do
	    local/compute_perplexity.sh --order ${lms_order[$t]} --text data/test $lm >> $perplexity_file
	    t=$((t+1))
	  done

	  [ $one_stage == true ] && exit 1
	fi

	if [ $preparation_stage -le 7 ]; then
	  echo "$0: Preparing data/lang and data/local/lang directories"
	  [ $liaison == false ] && echo "$0: No liaison is applied" && \
	    utils/prepare_lang.sh --position-dependent-phones true data/local/dict "!SIL" data/local/lang data/lang
	  [ $liaison == true ] && echo "$0: Liaison is applied in the creation of lang directories" && \
	    local/language_liaison/prepare_lang_liaison.sh --sil-prob $sil_prob data/local/dict "!SIL" data/local/lang data/lang
	  [ ! $liaison == true ] && [ ! $liaison == false ] && echo "Verify the value of the variable liaison" && exit 1
	  echo "$0: Preparing G.fst and data/{train,dev,test} directories"
	  local/format_lm.sh --liaison $liaison

	  [ $one_stage == true ] && exit 1
	fi

	if [ $preparation_stage -le 8 ]; then
	  echo "$0: Preparing acoustic features"
	  if [[ "$feat_type" == "mfcc" || "$feat_type" == "plp" || "$feat_type" == "fbank" ]]; then
	      #Feature extraction of training data
	      steps/make_$feat_type.sh --nj $feat_nj data/train $feat_type/log $feat_type || exit 1;
	      steps/compute_cmvn_stats.sh data/train $feat_type/log $feat_type || exit 1;
	      #Feature extraction of test data
	      steps/make_$feat_type.sh --nj $feat_nj data/test $feat_type/log $feat_type || exit 1;
	      steps/compute_cmvn_stats.sh data/test $feat_type/log $feat_type || exit 1;

	      if [ "$data_dev" != "" ]; then
		steps/make_$feat_type.sh --nj $feat_nj data/dev $feat_type/log $feat_type || exit 1;
	        steps/compute_cmvn_stats.sh data/dev $feat_type/log $feat_type || exit 1;
	      fi
	  else 
	    echo "$0: Error= Unkown feature type !!!" && exit 1
	  fi

	  [ $one_stage == true ] && exit 1
	fi

fi


if [ $training_decoding == true ]; then

echo ============================================================================
echo " TRAINING AND EVALUATION "
echo ============================================================================

	if [ "$sub_train_data" != "" ]; then
	  utils/subset_data_dir.sh data/train $sub_train_data data/train_$sub_train_data
	  train_dir=data/train_$sub_train_data
	else
	  train_dir=data/train
	fi

	if [ $stage_tr -le 1 ]; then
	  echo ============================================================================
	  echo " Mono-Phone Training & Decoding "
	  echo ============================================================================
	  #Train monophone model
	  if [ "$sub_data" != "" ]; then
	    utils/subset_data_dir.sh $train_dir $sub_data data/sub_train
	    steps/train_mono.sh --nj $train_nj data/sub_train data/lang $exp_dir/mono
	  else
	    steps/train_mono.sh --nj $train_nj $train_dir data/lang $exp_dir/mono
	  fi

	  #Decoder
	  for lm in ${lms[*]}; do
	    utils/mkgraph.sh --mono data/lang_test_$lm $exp_dir/mono $exp_dir/mono/graph_$lm
	    for d in $data_decode; do
	      steps/decode.sh --config $decode_conf --nj $decode_nj $exp_dir/mono/graph_$lm data/$d $exp_dir/mono/decode_${d}_$lm
	    done
	  done
	  for x in $exp_dir/mono/decode_*; do
	    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
	  done

	  [ $one_stage == true ] && exit 1
	fi


	if [ $stage_tr -le 2 ]; then
	  echo ============================================================================
	  echo " Tri-Phone Training & Decoding "
	  echo ============================================================================
	  #Align the train data using mono-phone model
	  steps/align_si.sh --nj $train_nj $train_dir data/lang $exp_dir/mono $exp_dir/mono_ali
	  #Train Deltas + Delta-Deltas model on top of monophone model
	  steps/train_deltas.sh --context-opts $context_opts \
	    $numLeavesTri1 $numGaussTri1 $train_dir data/lang $exp_dir/mono_ali $exp_dir/tri1

	  #Decoder
	  for lm in ${lms[*]}; do
	    utils/mkgraph.sh data/lang_test_$lm $exp_dir/tri1 $exp_dir/tri1/graph_$lm
	    for d in $data_decode; do
	      steps/decode.sh --config $decode_conf --nj $decode_nj $exp_dir/tri1/graph_$lm data/$d $exp_dir/tri1/decode_${d}_$lm
	    done
	  done
	  for x in $exp_dir/tri1/decode_*; do
	    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
	  done

	  [ $one_stage == true ] && exit 1
	fi

	if [ $stage_tr -le 3 ]; then
	  echo ============================================================================
	  echo " tri2b : LDA + MLLT Training & Decoding "
	  echo ============================================================================
	  #Align the train data using tri1 model
	  steps/align_si.sh --nj $train_nj $train_dir data/lang $exp_dir/tri1 $exp_dir/tri1_ali
	  #Train LDA + MLLT model based on tri1_ali
	  steps/train_lda_mllt.sh --context-opts $context_opts --splice-opts "$sliceTri2" \
	    $numLeavesMLLT $numGaussMLLT $train_dir data/lang $exp_dir/tri1_ali $exp_dir/tri2b

	  #Decoder
	  for lm in ${lms[*]}; do
	    utils/mkgraph.sh data/lang_test_$lm $exp_dir/tri2b $exp_dir/tri2b/graph_$lm
	    for d in $data_decode; do
	      steps/decode.sh --config $decode_conf --nj $decode_nj $exp_dir/tri2b/graph_$lm data/$d $exp_dir/tri2b/decode_${d}_$lm
	    done
	  done
	  for x in $exp_dir/tri2b/decode_*; do
	    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
	  done

	  [ $one_stage == true ] && exit 1
	fi

	if [ $stage_tr -le 4 ]; then
	  echo ============================================================================
	  echo " tri4a : SAT-FMLLR Training & Decoding "
	  echo ============================================================================
	  steps/align_si.sh --nj $train_nj $train_dir data/lang $exp_dir/tri2b $exp_dir/tri2b_ali
	  #Train GMM SAT model based on Tri2b_ali
	  steps/train_sat.sh $numLeavesSAT $numGaussSAT $train_dir data/lang $exp_dir/tri2b_ali $exp_dir/tri4a

	  #Decoder
	  for lm in ${lms[*]}; do
	    utils/mkgraph.sh data/lang_test_$lm $exp_dir/tri4a $exp_dir/tri4a/graph_$lm
	    for d in $data_decode; do
	      steps/decode_fmllr.sh --config $decode_conf --nj $decode_nj $exp_dir/tri4a/graph_$lm data/$d $exp_dir/tri4a/decode_${d}_$lm
	    done
	  done
	  for x in $exp_dir/tri4a/decode_*; do
	    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
	  done

	  [ $one_stage == true ] && exit 1
	fi

	if [ $stage_tr -le 5 ]; then
	  #Align the train data using tri4a model
	  steps/align_fmllr.sh --nj $train_nj $train_dir data/lang $exp_dir/tri4a $exp_dir/tri4a_ali
	  [ "$data_dev" != "" ] && steps/align_fmllr.sh --nj $train_nj data/dev data/lang $exp_dir/tri4a $exp_dir/tri4a_dev_ali

	  [ $one_stage == true ] && exit 1
	fi

	if [ $stage_tr -le 5 ]; then
	  echo ============================================================================
	  echo " SGMM : SGMM Training & Decoding "
	  echo ============================================================================
	  #Align the train data using tri4a model
	  steps/align_fmllr.sh --nj $train_nj $train_dir data/lang $exp_dir/tri4a $exp_dir/tri4a_ali
	  #Train SGMM model based on the GMM SAT model
	  steps/train_ubm.sh $numGaussUBM $train_dir data/lang $exp_dir/tri4a_ali $exp_dir/ubm
	  steps/train_sgmm2.sh $numLeavesSGMM $numGaussSGMM $train_dir data/lang $exp_dir/tri4a_ali $exp_dir/ubm/final.ubm $exp_dir/sgmm2
	  #Decoder
	  for lm in ${lms[*]}; do
	    utils/mkgraph.sh data/lang_test_$lm $exp_dir/sgmm2 $exp_dir/sgmm2/graph_$lm
	    for d in $data_decode; do
	      steps/decode_sgmm2.sh --config $decode_conf --nj $decode_nj --transform-dir $exp_dir/tri4a/decode_${d}_$lm \
	        $exp_dir/sgmm2/graph_$lm data/$d $exp_dir/sgmm2/decode_${d}_$lm
	    done
	  done
	  for x in $exp_dir/sgmm2/decode_*; do
	    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
	  done

	  [ $one_stage == true ] && exit 1
	fi

	if [ $stage_tr -le 6 ]; then
	  echo ============================================================================
	  echo "                    DNN Training & Decoding                        	"
	  echo ============================================================================
	  case "$DNN_implementation" in 
   		"dbn") local/nnet/run_dbn.sh
		;;
   		"dnn") local/nnet2/run_dnn.sh
	        ;;
   		"autoencoder") local/nnet/run_dnn_autoencoder.sh
	        ;;
   		"bottleneck") local/nnet2/run_dnn_bottleneck.sh
	        ;;
	   	*) echo "$0: Error= Unknown DNN_implementation option !!!"; exit 1
		;;
	  esac

	  [ $one_stage == true ] && exit 1
	fi


	if [ $stage_tr -le 6 ]; then
	  echo ============================================================================
	  echo " EVALUATION RESULTS "
	  echo ============================================================================
	  for x in $exp_dir/{mono,tri1,tri2b,tri4a,sgmm2,nnet/*,nnet2/*}/decode_*; do
	    [ -d $x ] && [[ $x =~ "$1" ]] && grep WER $x/wer_* | utils/best_wer.sh
	  done > $save_results_file
	fi

fi



