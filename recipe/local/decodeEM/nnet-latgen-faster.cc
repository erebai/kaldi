// nnet2bin/nnet-latgen-faster.cc

// Copyright 2009-2012   Microsoft Corporation
//                       Johns Hopkins University (author: Daniel Povey)
//                2014   Guoguo Chen

// See ../../COPYING for clarification regarding multiple authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
// THIS CODE IS PROVIDED *AS IS* BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, EITHER EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION ANY IMPLIED
// WARRANTIES OR CONDITIONS OF TITLE, FITNESS FOR A PARTICULAR PURPOSE,
// MERCHANTABLITY OR NON-INFRINGEMENT.
// See the Apache 2 License for the specific language governing permissions and
// limitations under the License.


#include "base/kaldi-common.h"
#include "util/common-utils.h"
#include "tree/context-dep.h"
#include "hmm/transition-model.h"
#include "fstext/kaldi-fst-io.h"
#include "decoder/decoder-wrappers.h"
#include "nnet2/decodable-am-nnet.h"
#include "base/timer.h"

inline std::string trim(std::string& str)
{
str.erase(0, str.find_first_not_of(' '));       //prefixing spaces
str.erase(str.find_last_not_of(' ')+1);         //surfixing spaces
return str;
}

int main(int argc, char *argv[]) {
  try {
    using namespace kaldi;
    using namespace kaldi::nnet2;
    typedef kaldi::int32 int32;
    using fst::SymbolTable;
    using fst::VectorFst;
    using fst::StdArc;

    const char *usage =
        "Generate lattices using neural net model.\n"
        "Usage: nnet-latgen-faster [options] <nnet-in> <fst-in|fsts-rspecifier> <features-rspecifier>"
        " <lattice-wspecifier> [ <words-wspecifier> [<alignments-wspecifier>] ]\n";
    ParseOptions po(usage);
    Timer timer;
    bool allow_partial = false;
    std::string combine_function="avg";
    BaseFloat acoustic_scale = 0.1;
    LatticeFasterDecoderConfig config;

    char delim = ' ';
    char delim1 = '#';
    std::vector<std::string> models;
    std::vector<std::string> feats;
    std::stringstream ss,ee;
    std::string item;
    int nbr;

    std::string word_syms_filename;
    config.Register(&po);
    po.Register("combine-function", &combine_function, "Function used to combine the acoustic likelihoods: sum, avg, maxone, argmax");
    po.Register("acoustic-scale", &acoustic_scale, "Scaling factor for acoustic likelihoods");
    po.Register("word-symbol-table", &word_syms_filename, "Symbol table for words [for debug output]");
    po.Register("allow-partial", &allow_partial, "If true, produce output even if end state was not reached.");
    
    po.Read(argc, argv);
    
    if (po.NumArgs() < 4 || po.NumArgs() > 6) {
      po.PrintUsage();
      exit(1);
    }

    std::string model_in_filename = po.GetArg(1),
        fst_in_str = po.GetArg(2),
        feature_rspecifier = po.GetArg(3),
        lattice_wspecifier = po.GetArg(4),
        words_wspecifier = po.GetOptArg(5),
        alignment_wspecifier = po.GetOptArg(6);






    ss.str(model_in_filename);
    while (std::getline(ss, item, delim)) {
      models.push_back(item);
    }
    ee.str(feature_rspecifier);
    while (std::getline(ee, item, delim1)) {
      feats.push_back(item);
    }
    if(models.size() != feats.size()) {
      KALDI_ERR << "Number of feature specifier is " << feats.size() << " but number of models is " << models.size();
    }
    nbr=models.size();
    TransitionModel trans_model[nbr];
    AmNnet am_nnet[nbr];
    {
      for(int i=0;i<nbr;i++) {
        bool binary;
        Input ki(models[i], &binary);
        trans_model[i].Read(ki.Stream(), binary);
        am_nnet[i].Read(ki.Stream(), binary);
      }
    }

    bool determinize = config.determinize_lattice;
    CompactLatticeWriter compact_lattice_writer;
    LatticeWriter lattice_writer;
    if (! (determinize ? compact_lattice_writer.Open(lattice_wspecifier)
           : lattice_writer.Open(lattice_wspecifier)))
      KALDI_ERR << "Could not open table for writing lattices: "
                 << lattice_wspecifier;

    Int32VectorWriter words_writer(words_wspecifier);

    Int32VectorWriter alignment_writer(alignment_wspecifier);

    fst::SymbolTable *word_syms = NULL;
    if (word_syms_filename != "") 
      if (!(word_syms = fst::SymbolTable::ReadText(word_syms_filename)))
        KALDI_ERR << "Could not read symbol table from file "
                   << word_syms_filename;


    double tot_like = 0.0;
    kaldi::int64 frame_count = 0;
    int num_success = 0, num_fail = 0;
 
    if (ClassifyRspecifier(fst_in_str, NULL, NULL) == kNoRspecifier) {

      SequentialBaseFloatCuMatrixReader feature[nbr];
      for(int i=0;i<nbr;i++) {
	feature[i].Open(trim(feats[i]));
      }

      // Input FST is just one FST, not a table of FSTs.
      VectorFst<StdArc> *decode_fst = fst::ReadFstKaldi(fst_in_str);

      {
        LatticeFasterDecoder decoder(*decode_fst, config);
    
        for (; !feature[0].Done(); feature[0].Next()) {
          std::string utt = feature[0].Key();
          const CuMatrix<BaseFloat> &features (feature[0].Value());

          if (features.NumRows() == 0) {
            KALDI_WARN << "Zero-length utterance: " << utt;
            num_fail++;
            continue;
          }
          bool pad_input = true;
          DecodableAmNnet nnet_decodable(trans_model[0],
                                         am_nnet[0],
                                         features,
                                         pad_input,
                                         acoustic_scale);

      int frames=nnet_decodable.NumFramesReady();
      int nbr_pdf=nnet_decodable.FrameLogLikelihood(0).Dim();
      Matrix<BaseFloat> matrix(nbr*frames,nbr_pdf);
      for(int f=0;f<frames;f++)
        matrix.CopyRowFromVec(nnet_decodable.FrameLogLikelihood(f),f*nbr);



	  //KALDI_LOG << nnet_decodable.LogLikelihood(0,0);
	  //KALDI_LOG << nnet_decodable.FrameLogLikelihood(0);

	  for (int i=1;i<nbr;i++) {
            const CuMatrix<BaseFloat> &features_tmp (feature[i].Value());
            DecodableAmNnet nnet_decodable_tmp(trans_model[i],
                                           am_nnet[i],
                                           features_tmp,
                                           pad_input,
                                           acoustic_scale);
	    //KALDI_LOG << nnet_decodable_tmp.FrameLogLikelihood(0);
	    //KALDI_LOG << nnet_decodable.LogLikelihood(0,0);
            for(int f=0;f<nnet_decodable.NumFramesReady();f++) {
              matrix.CopyRowFromVec(nnet_decodable_tmp.FrameLogLikelihood(f),(f*nbr)+i);
	      SubVector<BaseFloat> v(nnet_decodable.FrameLogLikelihood(f));
	      SubVector<BaseFloat> v_tmp(nnet_decodable_tmp.FrameLogLikelihood(f));
	      if(combine_function == "avg" || combine_function == "sum"){ v.AddVec(1,v_tmp); } //sum the log_prob of all models 
	      else if(combine_function == "maxone") {
		//KALDI_LOG << v.Max();
                for(int p=0;p<v.Dim();p++) {
		  if(v(p)<v.Max()){v(p)=-1;} else {v(p)=1;} 
		}
	      }
	      else if(combine_function == "argmax") {
                for(int p=0;p<v.Dim();p++) {
		  if(v(p)<v_tmp(p)){v(p)=v_tmp(p);} 
		}
	      } else { KALDI_ERR << "Undefined combination function"; break; }
	      nnet_decodable.SetLogLikelihood(v,f);
	    }
	    //KALDI_LOG << nnet_decodable_tmp.LogLikelihood(0,0);
	  }

          if(combine_function == "avg"){ 
            for(int f=0;f<nnet_decodable.NumFramesReady();f++) {
              SubVector<BaseFloat> v(nnet_decodable.FrameLogLikelihood(f));
              Vector<BaseFloat> v_tmp(v);
              v.CopyFromVec(v_tmp);
              v_tmp.Set(nbr);
              v.DivElements(v_tmp);
	      nnet_decodable.SetLogLikelihood(v,f);
            }
	  }

	  //KALDI_LOG << nnet_decodable.FrameLogLikelihood(0);
	  //KALDI_LOG << nnet_decodable.LogLikelihood(0,0);


          double like;
          if (DecodeUtteranceLatticeFaster(
                  decoder, nnet_decodable, trans_model[0], word_syms, utt,
                  acoustic_scale, determinize, allow_partial, &alignment_writer,
                  &words_writer, &compact_lattice_writer, &lattice_writer,
                  &like)) {
            tot_like += like;
            frame_count += features.NumRows();
            num_success++;
          } else num_fail++;

	  for (int i=1;i<nbr;i++) { feature[i].Next(); }

        }
      }
      delete decode_fst; // delete this only after decoder goes out of scope.
    } else { // We have different FSTs for different utterances.
      SequentialTableReader<fst::VectorFstHolder> fst_reader(fst_in_str);
      RandomAccessBaseFloatCuMatrixReader feature[nbr];
      for(int i=0;i<nbr;i++) {
	feature[i].Open(trim(feats[i]));
      }

      RandomAccessBaseFloatCuMatrixReader feature_reader(feature_rspecifier);          

      for (; !fst_reader.Done(); fst_reader.Next()) {
        std::string utt = fst_reader.Key();
        if (!feature[0].HasKey(utt)) {
          KALDI_WARN << "Not decoding utterance " << utt
                     << " because no features available.";
          num_fail++;
          continue;
        }
        const CuMatrix<BaseFloat> &features = feature[0].Value(utt);
        if (features.NumRows() == 0) {
          KALDI_WARN << "Zero-length utterance: " << utt;
          num_fail++;
          continue;
        }
        
        LatticeFasterDecoder decoder(fst_reader.Value(), config);

        bool pad_input = true;
        DecodableAmNnet nnet_decodable(trans_model[0],
                                       am_nnet[0],
                                       features,
                                       pad_input,
                                       acoustic_scale);

	//KALDI_LOG << nnet_decodable.LogLikelihood(0,0);
	for (int i=1;i<nbr;i++) {
          const CuMatrix<BaseFloat> &features_tmp (feature[i].Value(utt));
          DecodableAmNnet nnet_decodable_tmp(trans_model[i],
                                             am_nnet[i],
                                             features_tmp,
                                             pad_input,
                                             acoustic_scale);
          for(int f=0;f<nnet_decodable.NumFramesReady();f++) {
	    SubVector<BaseFloat> v(nnet_decodable.FrameLogLikelihood(f));
	    SubVector<BaseFloat> v_tmp(nnet_decodable_tmp.FrameLogLikelihood(f));
	    v.AddVec(1,v_tmp); //sum the log_prob of all models
	    nnet_decodable.SetLogLikelihood(v,f);
	  }
	  //KALDI_LOG << nnet_decodable_tmp.LogLikelihood(0,0);
	}
	//KALDI_LOG << nnet_decodable.LogLikelihood(0,0);

        double like;
        if (DecodeUtteranceLatticeFaster(
                decoder, nnet_decodable, trans_model[0], word_syms, utt,
                acoustic_scale, determinize, allow_partial, &alignment_writer,
                &words_writer, &compact_lattice_writer, &lattice_writer,
                &like)) {
          tot_like += like;
          frame_count += features.NumRows();
          num_success++;
        } else num_fail++;
      }
    }
      
    double elapsed = timer.Elapsed();
    KALDI_LOG << "Time taken "<< elapsed
              << "s: real-time factor assuming 100 frames/sec is "
              << (elapsed*100.0/frame_count);
    KALDI_LOG << "Done " << num_success << " utterances, failed for "
              << num_fail;
    KALDI_LOG << "Overall log-likelihood per frame is " << (tot_like/frame_count) << " over "
              << frame_count<<" frames.";

    delete word_syms;
    if (num_success != 0) return 0;
    else return 1;
  } catch(const std::exception &e) {
    std::cerr << e.what();
    return -1;
  }
}
