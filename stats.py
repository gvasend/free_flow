
#!/usr/bin/env python
print("extractor.py")

import argparse
import uuid
import time
import threading
import re
import networkx as nx
import json
#import stomp_bridge
# from pylinkgrammar.linkgrammar import Parser, Linkage, ParseOptions, Link
#import udp_bridge
import tika
import xmltodict
import sys
tika.initVM()
from tika import parser
import ff_mongo as mg

from py2neo import authenticate, Graph, Node, Relationship

current_sent = None

import logging

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Record statistics')

aparser.add_argument('-output_file',help='Grahp output')


aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')

aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--user',default='neo4j',help='Username')
aparser.add_argument('--password',default='N7287W06',help='credentials')





import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)

now = time.time()

def log_metric(name,value):
    fname = '/home/gvasend/nfs/Simbolika/app/freeflow/stats.log'
    now = time.time()
    with open(fname,'a') as of:
      of.write("%d,%s,%s\n"%(now,name,value))

stat_list = [
    ('ungraphed_files','match (n:file) where not (n)-[]-(:document) and exists(n.text) and not n.text="<NO_TEXT>" and not n.doc_type="unknown" return count(n) as x'),
   ('pending_sol_checks','MATCH (n:check) where n.type="download" and n.status="pending" return count(n) as x'),
   ('downloaded_files','MATCH (n:check) where n.type="download" and not n.status="pending" return count(n) as x')

    ]

def clean_label(labels):
    if len(labels) == 0:
        return 'null'
    return labels[0]
#    return label.replace("[","").replace("]","").replace('"',"")

def connect_neo():
  
    authenticate(args.gdb_url, 'neo4j', 'N7287W06')
    return Graph('%s/db/data/'%args.gdb_url)

gr = connect_neo()
res = gr.run('MATCH (n) RETURN distinct labels(n), count(*)')
stats = {}
fname = '/home/gvasend/nfs/Simbolika/app/freeflow/stats.log'
with open(fname,'a') as of:
  for row in res:
    label = row['labels(n)']
    value = row['count(*)']
#    stats['label'][time] = value
    of.write("%d,%s,%s\n"%(now,clean_label(label),value))
    
def record_stat(name,q):
    res = gr.run(q)
    for row in res:
        x = row['x']
    log_metric(name,x)

for name, q in stat_list:
    record_stat(name, q)

