
#!/usr/bin/env python
import argparse
import time
import sys


from py2neo import authenticate, Graph, Node, Relationship


import logging


# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Text cosine on two documents')

aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')

aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--user',default='neo4j',help='Username')
aparser.add_argument('--password',default='N7287W06',help='credentials')
aparser.add_argument('--doc1',required=True,type=int,help='credentials')
aparser.add_argument('--doc2',required=True,type=int,help='credentials')
aparser.add_argument('--cutoff',type=float,default=0.5,help='credentials')
aparser.add_argument('--algorithm',default='text_cosine',help='credentials')


import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)

algorithm = args.algorithm

import re, math
from collections import Counter

WORD = re.compile(r'\w+')

def get_cosine(vec1, vec2):
     intersection = set(vec1.keys()) & set(vec2.keys())
     numerator = sum([vec1[x] * vec2[x] for x in intersection])

     sum1 = sum([vec1[x]**2 for x in vec1.keys()])
     sum2 = sum([vec2[x]**2 for x in vec2.keys()])
     denominator = math.sqrt(sum1) * math.sqrt(sum2)

     if not denominator:
        return 0.0
     else:
        return float(numerator) / denominator

def text_to_vector(text):
     words = WORD.findall(text)
     filtered_words = [word for word in words if word not in stopwords.words('english')]
#     print('filtered',filtered_words)
     return Counter(filtered_words)

from nltk.corpus import stopwords
import json
import subprocess
def trigger_dag(dag,abs_path='/',context={}):
    ctx = '"'+json.dumps(context).replace('"','\\"')+'"'
    shell('airflow trigger_dag %s --conf %s'%(dag,ctx))

def match_text(t1,t2):

    vector1 = text_to_vector(t1)
    vector2 = text_to_vector(t2)
    txtc = get_cosine(vector1,vector2)

    if txtc > args.cutoff:
        print('cosine',txtc)        
        return txtc
    return txtc

def neo_attr(dct):
    str_list = []
    for key, value in dct.items():
        str = '%s:"%s"'%(key,value)
        str_list.extend([str])
    return "{"+",".join(str_list)+"}"

def shell(cmd):
    print(cmd)
    subprocess.check_call(cmd,shell=True)

def new_edge(id1,id2,label,attr):
    global graph, tx
    attr_str = neo_attr(attr)
    query = 'MATCH (d1:sentence), (d2:sentence) where d1.iname="%s" and d2.iname = "%s" CREATE (d1)-[:%s %s]->(d2)'%(id1,id2,label,attr_str)
#    print(query)
    tx.run(query)

def compare_documents():
    global graph, tx
    authenticate(args.gdb_url, args.user, args.password)
    graph = Graph('%s%s'%(args.gdb_url,args.gdb_path))

    query = """
    MATCH (d1:document)-[:has_sentence]-(s:sentence) where id(d1) = {doc_id} return s.iname, s.text
    """

    tx = graph.begin()    
    tx.run('match (d1:document)-[]-(s:sentence)-[r:related {algorithm:"%s"}]-(s2:sentence)-[]-(d2:document) where id(d1)=%s and id(d2) = %s delete r'%(algorithm,args.doc1,args.doc2))
    doc1 = graph.run(query, doc_id=args.doc1)
    doc2 = graph.run(query, doc_id=args.doc2)
    
    doc1_count = 0
    doc2_count = 0
    doc1_list = []
    doc2_list = []
    for sent in doc1:
        doc1_count += 1
        doc1_list.extend([{'id':sent['s.iname'],'text':sent['s.text']}])
    for sent in doc2:
        doc2_count += 1
        doc2_list.extend([{'id':sent['s.iname'],'text':sent['s.text']}])

    comparisons = 0
    matches = 0
    for sent1 in doc1_list:
        for sent2 in doc2_list:
            comparisons += 1
            metric = match_text(sent1['text'],sent2['text'])
            if metric > args.cutoff:
                matches += 1
                print(sent1['id'],'match',sent2['id'])
                new_edge(sent1['id'],sent2['id'],'related',{'algorithm':algorithm,'related_metric':metric})

    print('total sentences in doc1',doc1_count,'total sentences in doc2',doc2_count,'comparisons',comparisons,'total matches',matches)    
    tx.run('match (d1:document), (d2:document) where id(d1)=%s and id(d2) = %s create (d1)-[:analyzed {algorithm:"%s"}]->(d2) '%(args.doc1,args.doc2,algorithm))

    tx.commit()

compare_documents()


