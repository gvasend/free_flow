
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


# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Empirical document classification')

aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')

aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--user',default='neo4j',help='Username')
aparser.add_argument('--password',default='N7287W06',help='credentials')



import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)


def shell(cmd):
    print(cmd)
    subprocess.check_call(cmd,shell=True)

def categorize_documents():
    authenticate(args.gdb_url, args.user, args.password)
    graph = Graph('%s%s'%(args.gdb_url,args.gdb_path))


    with open('categorize_documents.txt','r') as inf:
        all_q = inf.readlines()
    for query in all_q:
        print("query:",query)
        graph.run(query)

categorize_documents()


