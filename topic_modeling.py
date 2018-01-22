
#!/usr/bin/env python
import argparse
import time
import sys
import topic


from py2neo import authenticate, Graph, Node, Relationship


import logging


# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Analyze text to discover topics')

aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')

aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--user',default='neo4j',help='Username')
aparser.add_argument('--password',default='N7287W06',help='credentials')
aparser.add_argument('--document',required=True,type=int,help='credentials')


import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)

import re, math
from collections import Counter

WORD = re.compile(r'\w+')




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
    query = 'MATCH (d1:sentence), where d1.iname="%s" and d2.iname = "%s" CREATE (d1)-[:%s %s]->(d2)'%(id1,id2,label,attr_str)
#    print(query)
    tx.run(query)

def compare_documents():
    global graph, tx
    authenticate(args.gdb_url, args.user, args.password)
    graph = Graph('%s%s'%(args.gdb_url,args.gdb_path))

    query = """
    MATCH (d1:document)-[:has_sentence]-(s:sentence)-[]-(sect:section) where id(d1) = {doc_id} return distinct id(sect), sect.text
    """

    tx = graph.begin()    
    doc1 = graph.run(query, doc_id=args.document)
    
    doc1_count = 0
    doc1_list = []
    doc1_sent = []
    for sent in doc1:
        doc1_count += 1
        doc1_list.extend([sent['id(sect)']])
        doc1_sent.extend([sent['sect.text']])
    print(doc1_sent)


    comparisons = 0
    matches = 0
    lda, feature_names = topic.analyze_text(len(doc1_sent),10,doc1_sent)
    print(feature_names)

    tx.commit()

compare_documents()


