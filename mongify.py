#!/usr/bin/python 
print("extractor.py")

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


print("extractor")

fo = None

seq = 0

# def extract_file1(filename,proj,doc_type,id):
from ffparse import FFParse

aparser = FFParse(description='Convert text properties to mongo strings')

aparser.add_argument('--node_label',required=True,help='Label to convert')
aparser.add_argument('--property',required=True,help='property to convert')
aparser.add_argument('--max_length',default=100,type=int,help='convert this size or larger')
aparser.add_argument('--limit',type=int,default=10000,help='max number of conversions')

aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')

aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--user',default='neo4j',help='Username')
aparser.add_argument('--password',default='N7287W06',help='credentials')

aparser.all_options()

args = aparser.parse_args()

def uid():
    return str(uuid.uuid1())

def n_lower_chars(string):
    return sum(1 for c in string if c.islower())



import os

def connect_neo():
  
    authenticate(args.gdb_url, args.user, args.password)
    return Graph(args.gdb_url+args.gdb_path)
        

def mongify():
    graph = connect_neo()


    res = graph.run('match (n:%s) where exists(n.%s) and length(n.%s) > %d and not n.%s=~ "mongo:.*" return id(n), n limit %d'%(args.node_label, args.property, args.property, args.max_length, args.property, args.limit))
    total_nodes = 0
    for row in res:
        total_nodes += 1
        print('extracting ',total_nodes,row['id(n)'])
        try:
#            print('text ',row['n']['text'])
            row['n'][args.property] = mg.create_text(row['n'][args.property].encode())
            row['n'].push()
        except:
            print('mongify error')

def extract_text_file(fname):
    text = get_text(fname)
    print(text)
        




gr = None
if __name__ == '__main__':

    mongify()

#    outf.close()
    
