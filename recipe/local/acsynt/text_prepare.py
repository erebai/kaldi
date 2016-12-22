#!/usr/bin/env python
# -*- coding: utf-8 -*-

# This script appends utterances dumped out from XML to a Kaldi datadir

import sys, re
from xml.sax.saxutils import unescape
dir = sys.argv[1]
adapt = sys.argv[2]

# open the output files in append mode
ftext = open(dir + '/text','r')

#load the transcription
text = []
code = []
for m in ftext:
	x = m.split(' ')
	code.append(x[0])
	text.append(' '.join([unescape(w) for w in x[1:]]))

ftext.close()

text_n = open(dir + '/text', 'w')


#Prepare the transcription
words = []
for m in range(len(text)):
		line = re.sub(r"(&lt;|&gt;|\+|\*|///|-|_|\.|\\)", " ", text[m].strip())
		line = re.sub(r"\(|\)","", line)
		line = re.sub(r"\$|:|!|\?|\[|\]|/|~|\^|=|,|#", " ", line)
		line = re.sub(r"'", "' ", line)
		line = re.sub(r"", " ", line)
		line = re.sub(r" ﻿ ", " ", line)
		line = re.sub(r" ' ", " ", line)
		line = re.sub(r" +", " ", line.strip())
		words.append(line.lower())

#If lexicon file is specified, so apply the transformation to the text: make the text conforms to the lexicon file
#load the lexicon while modifying the text
if adapt == "true":
	flexicon = open('lexicon/lex','r')
	lexicons = []
	lexicons_ = []
	for m in flexicon:
		ss = m.strip()
		lexicons_.append(ss)
		lexicons.append(re.sub(r'(_|-)',' ',ss))
	for i in range(len(lexicons)):
		for j in range(len(words)):
			words[j] = words[j].replace(' '+lexicons[i]+' ',' '+lexicons_[i]+' ')
			words[j] = re.sub(r" +", " ", words[j].strip())

for m in range(len(words)):
	print >> text_n, "%s %s" % (code[m],words[m].strip())


text_n.close()


