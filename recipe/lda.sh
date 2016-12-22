
data=/media/storage0/data-nnet-combine/data
logdir=/media/storage0/data-nnet-combine/data/log
#feats_nn_paste="ark:paste-feats ark:/media/storage0/data-nnet-combine/train/data_1/raw_fea_train.JOB.ark \
#	                        ark:/media/storage0/data-nnet-combine/train/data_2/raw_fea_train.JOB.ark \
#	                        ark:- |"
feats_nn_paste="ark:paste-feats ark:/media/storage0/kaldi.4layers/train.ark ark:/media/storage0/kaldi.5layers/train.ark ark:- |"
align_dir="exp/nnet2_gpu/pnorm/4layers_ali" #check the align directory
silphonelist=`cat data/lang/phones/silence.csl`
randprune=4.0
dim=3111 #check the dimension of the matrix
nj=50
cmd=run.pl
#Compute LDA matrix
echo "Accumulating LDA statistics."
$cmd JOB=1:$nj $logdir/lda_acc.JOB.log \
  ali-to-post "ark:gunzip -c $align_dir/ali.JOB.gz|" ark:- \| \
  weight-silence-post 0.0 $silphonelist $align_dir/final.mdl ark:- ark:- \| \
  acc-lda --rand-prune=$randprune $align_dir/final.mdl \"$feats_nn_paste\" ark,s,cs:- \
    $data/lda.JOB.acc

echo "Estimate LDA matrix."
est-lda --write-full-matrix=$data/full.mat --dim=$dim $data/0.mat $data/lda.*.acc 2>$data/log/lda_est.log

#rm $data/lda.*.acc
