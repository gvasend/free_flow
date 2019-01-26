
#!/usr/bin/env python
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
from pubsub import pub
import xmltodict
import sys
import matplotlib.pyplot as plt

from py2neo import authenticate, Graph, Node, Relationship


import logging

from ffparse import FFParse

parser = FFParse(description='Empirical document classification')


parser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')

parser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
parser.add_argument('--gdb_user',default='neo4j',help='Username')
parser.add_argument('--gdb_password',default='N7287W06',help='credentials')
parser.add_argument('--file_label',default='File',help='file node label')
parser.add_argument('--filename',default='name',help='file node name attribute')
parser.add_argument('--node_id',type=int,default=-1,help='Node to be categorized')

parser.all_options()

args = parser.parse_args()


def shell(cmd):
    print(cmd)
    subprocess.check_call(cmd,shell=True)

def categorize_documents():
    print('authenticate(%s, %s, %s)' % (args.gdb_url, args.gdb_user, args.gdb_password))
    print('Graph(%s%s)'%(args.gdb_url,args.gdb_path))
    authenticate(args.gdb_url, args.gdb_user, args.gdb_password)
    graph = Graph('http://%s%s'%(args.gdb_url,args.gdb_path))


    with open('categorize_documents.txt','r') as inf:
        all_q = inf.readlines()
    for query in all_q:
      if not '[off]' in query and not '[comment]' in query:
        if args.node_id > -1:
            query = query.replace('where','where id(f)=%d AND ' % args.node_id)
        query_final = query % (args.file_label)
        print("query:",query_final)
        graph.run(query_final)
    graph.run('MATCH (n) WHERE id(n)=%d SET n.doc_type=n.doc_type_temp' % (args.node_id)) # set the prop with the final value

categorize_documents()


