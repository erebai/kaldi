#!/usr/bin/env python
# -*- coding: utf-8 -*-

from xml.dom import minidom
from unicodedata import normalize
from sys import argv

import re

def transformation_text(text):
    bool=True
    if "###" in text or "(" in text: # "voir - amorces"
        bool=False
    else:
        #print "detecter (///|/|<|>)"
        text = re.sub(r"(\+|[*]+|///|/|<|>)", "", text.strip())
        text= re.sub(r"-|_|\."," ",text.strip())
        text = re.sub(r"(O K | O K|^O K$)", " ok ", text)
        text=re.sub(r"{[^{]+}"," ",text.strip())
        #text=re.sub(r"¤[^¤]+¤","",text.strip())
        text=re.sub(r"¤[^ ]+|[^ ]+¤|¤","",text.strip())
        text=re.sub(r" +"," ",text.strip())
        text=re.sub(r" 4x4 "," quatre fois quatre ",text)
    return bool,text

if __name__=="__main__":
    file_xml=argv[1]
    file_name=argv[2]
    outdir=argv[3]
    segments_file = open(outdir + '/segments', 'a')
    utt2spk_file = open(outdir + '/utt2spk', 'a')
    text_file = open(outdir + '/text', 'a')
    xmldoc= minidom.parse(file_xml)
    #Read all Elements By Tag
    Turnlist= xmldoc.getElementsByTagName('Turn')
    a=""
    count=1
    for Turn in Turnlist:
        # Get id_spkr
	if Turn.hasAttribute('speaker') and len(re.findall(r"spk",Turn.attributes['speaker'].value)) == 1:
		att_spk=Turn.attributes['speaker'].value
		spkr=normalize('NFKD', att_spk).encode('utf-8', 'ignore')
		# Get StartSegment
		att_startTime=Turn.attributes['startTime'].value
		startTime=normalize('NFKD', att_startTime).encode('utf-8', 'ignore')
		#Get EndSegment
		att_endTime=Turn.attributes['endTime'].value
		endTime=normalize('NFKD', att_endTime).encode('utf-8', 'ignore')
		# Get Text
		field_text="".join(t.nodeValue for t in Turn.childNodes if t.nodeType == t.TEXT_NODE)
		#print field_text.encode('utf-8','ignore')
		#a=a.decode('unicode_escape').encode('utf-8','ignore').split()
		_text=field_text.encode('utf-8','ignore').split()
		text=""
		for x in _text:
		    text=text+' '+x
		# Function Transformation à faire
		bool,text=transformation_text(text)
		seg_id='%s_spk-%03d_seg-%07d' % (str(file_name),int(spkr.split('spk')[1]), int(count))
		spkr_id=str(file_name)+'_spk-%03d' % int(spkr.split('spk')[1])

                if bool and text!="":
		    print >> segments_file, '%s %s %s %s' % (seg_id, file_name, startTime, endTime)
		    print >> utt2spk_file, '%s %s' % (seg_id, spkr_id) 
		    print >> text_file, '%s %s' % (seg_id, text)
		    count=count+1

    segments_file.close()
    utt2spk_file.close()
    text_file.close()
