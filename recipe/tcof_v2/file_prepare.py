#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This script appends utterances dumped out from XML to a Kaldi datadir

import sys, re
from xml.sax.saxutils import unescape

basename=sys.argv[1]
outdir = sys.argv[2]
text = sys.argv[3]

if len(sys.argv) > 4:
    lexicon = sys.argv[4]
    flexicon = open(lexicon,'r')
else:
    lexicon = None


# open the output files in append mode
segments_file = open(outdir + '/segments', 'a')
utt2spk_file = open(outdir + '/utt2spk', 'a')
text_file = open(outdir + '/text', 'a')
ftext = open(text,'r')
fdigit = open('local/other_data/xml/chiffre.mdf','r')



#load the transcription
text = ''
for m in ftext:
	text = text + ' ' + m

#load the digit transcription
digit = []
for m in fdigit:
	d = m.split()
	c = ' '.join([unescape(w) for w in d[1:]])
	digit.append([d[0],c])

#Prepare the transcription
text = text.replace("\n", " ")
t = text.split('$%%$')
words = []
for m in range(len(t)):
	if m > 0:
		line = re.sub(r"(&lt;|&gt;|\+|\*|///|-|_|\.|\\)", " ", t[m].strip())
		line = re.sub(r"\(|\)","", line)
		line = re.sub(r"¤[^¤]+¤|¤\w+\d+ |¤\w+\d+$"," ¤ ", line)
		line = re.sub(r"¤"," ¤ ", line)
		line = re.sub(r"(O K | O K|^O K$)", " ok ", line)
		line = re.sub(r"^¤$", "", line)
		line = re.sub(r"^( *¤ *)+$"," ¤ ", line)
		line = re.sub(r" 4x4 ", " 4 fois 4 ", line)
		line = re.sub(r" 36ème ", " trente sixième ", line)
		line = re.sub(r" 7ème ", " septième ", line)
		line = re.sub(r'18h40',' 18 heures 40 ',line)
		line = re.sub(r"\[mic\]", "¤", line)
		line = re.sub(r"\[sic\]|{sic}", " ", line)
		line = re.sub(r"&amp;", "-", line)

		for i in re.findall(r"\[.+\]", line):
			if len(re.findall(r"=",i)) == 1:
				line = line.replace(i,' ')
			elif len(re.findall(r",",i)) == 1:
				xx = i.split(',')
				line = line.replace(i, xx[0])
		for i in re.findall(r"/[^/]+;[^/]+/", line):
			xx = i.split(';')
			line = line.replace(i, xx[0])

		for i in re.findall(r"/[^/]+,[^/]+/", line):
			xx = i.split(',')
			xxx = xx[0].replace('/','')
			if xxx <> '0':
				line = line.replace(i, xxx)
			else:
				line = line.replace(i, " ")

		line = re.sub(r"\$|:|!|\?|\[|\]|/|~|\^|=|,|#|\"", " ", line)
		line = re.sub(r"'", "' ", line)
		line = re.sub(r" ' ", " ", line)
		line = re.sub(r" +", " ", line.strip())
		words.append(' '+line.lower()+' ')

#check if the text file and the segments are equal
#if the length is equal, so continue the creation of the segment, text, utt2spk files
inputfile = []
for m in sys.stdin:
  m = re.sub(r" +", " ", m.strip())
  if m.find("spk") == -1:
	inputfile.append('spk0 '+m)
  else:
	inputfile.append(m.strip())

nbr = 0
for m in inputfile:
  nspk = len(re.findall(r"spk",m))
  t = m.split(' ')
  times = [unescape(w) for w in t[(2+nspk):len(t)]]
  nbr = nbr + len(times)

if nbr <> len(words):
	print 'Error: Their is an error occurred while creating the segment, text, and utt2spk files. Please check the (.trs) files'
	print 'File='+basename+' Lines='+str(len(words))+' Sync='+str(nbr)
	sys.exit()

#If lexicon file is specified, so apply the transformation to the text: make the text conforms to the lexicon file
#load the lexicon while modifying the text
if lexicon <> None:
	lexicons = []
	lexicons_ = []
	for m in flexicon:
		ss = m.strip()
		lexicons_.append(ss)
		lexicons.append(re.sub(r'(_|-)',' ',ss))
	for i in range(len(words)):
		for j in re.findall(r"[^ ]\d+", words[i]):
			k = re.findall(r"\d+",j)
			w = j.split(k[0])
			words[i] = words[i].replace(' '+j+' ','  '+w[0]+'  '+k[0]+'  ')

		for j in digit:
			words[i] = words[i].replace(' '+j[0]+' ',' '+j[1]+' ')

		words[i] = re.sub(r"^ *¤ *$","",words[i])

	for i in range(len(lexicons)):
		for j in range(len(words)):
			words[j] = words[j].replace(' '+lexicons[i]+' ',' '+lexicons_[i]+' ')
			words[j] = re.sub(r" +", " ", words[j].strip())


#Create segment, text, and utt2spk files
i=0
for m in inputfile:

    if len(re.findall(r"spk",m)) == 1:
        t = m.split(' ')
	spk = t[0].split('spk')
        start = float(t[1])
        end = float(t[2])

        times = [unescape(w) for w in t[3:len(t)]]
	if float(times[0]) <> start:
	   print 'error'
	   sys.exit()

	for x in range(len(times)):
		if x <> 0:
			if len(words[i]) <> 0:
				segId = '%s_spk-%03d_seg-%07d:%07d' % (basename, int(spk[1]), float(times[x-1])*100, float(times[x])*100)
				spkId = '%s_spk-%03d' % (basename, int(spk[1]))
				print >> segments_file, '%s %s %.3f %.3f' % (segId, basename, float(times[x-1]), float(times[x]))
				print >> utt2spk_file, '%s %s' % (segId, spkId)
				print >> text_file, '%s %s' % (segId, words[i].strip())
			i = i + 1

	if len(words[i]) <> 0:
		segId = '%s_spk-%03d_seg-%07d:%07d' % (basename, int(spk[1]), float(times[len(times)-1])*100, end*100)
		spkId = '%s_spk-%03d' % (basename, int(spk[1]))
		print >> segments_file, '%s %s %.3f %.3f' % (segId, basename, float(times[len(times)-1]), end)
		print >> utt2spk_file, '%s %s' % (segId, spkId)	
		print >> text_file, '%s %s' % (segId, words[i].strip())
	i = i + 1
    else:
	i = i + 1

segments_file.close()
utt2spk_file.close()
text_file.close()


