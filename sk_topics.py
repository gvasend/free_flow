
from __future__ import print_function

import argparse

import scrape as sc

# general parameters



parser = argparse.ArgumentParser(description='Translate text file into tfidf')

sc.model_options(parser)
sc.all_options(parser)

#parser.add_argument('--output_file',default='*output_file',help='file containing output feature data')
parser.add_argument('--corpus',default='log.txt',help='file containing text data. one line for each document with first field as label.')


# SVC parameters

sc.output_options(parser)

from scrape import write_dict
from scrape import load_file

args = sc.parse_args(parser)

from time import time

from sklearn.datasets import dump_svmlight_file

from sklearn.feature_extraction.text import TfidfVectorizer, CountVectorizer

n_features = 1000

global lines
with open(args.corpus, 'r') as f:
    lines = f.readlines()

data_samples = [line.split("\t")[1]  for line in lines]
labels = [line.split("\t")[0]  for line in lines]

# Use tf-idf features for NMF.

tfidf_vectorizer = TfidfVectorizer(max_df=0.95, min_df=2,
                                   max_features=n_features,
                                   stop_words='english')
t0 = time()
tfidf = tfidf_vectorizer.fit_transform(data_samples)


if args.output_file == None:
    setattr(args, 'output_file', "sk_ff_"+str(uuid.uuid1()))+'.libsvm'
    


y = [1.0 for idx in range(len(data_samples))]
#dump_svmlight_file(tfidf, y, 'test.svm')

dump_svmlight_file(tfidf,y,args.output_file,zero_based=args.zero_based,query_id=args.query_id,multilabel=args.multilabel,comment=args.comment)
    
