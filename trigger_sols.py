
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

aparser = argparse.ArgumentParser(description='Load graph')

aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')

aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--user',default='neo4j',help='Username')
aparser.add_argument('--password',default='N7287W06',help='credentials')
aparser.add_argument('--dag_run',help='dag run id')
aparser.add_argument('--ts',help='task start time')


import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)

import dateutil
now = dateutil.parser.parse(args.ts) 

from time import strftime
date_id = now.strftime("%m%d%Y")
print('date id',date_id)

import json
import subprocess
def trigger_dag(dag,abs_path='/',context={}):
    ctx = '"'+json.dumps(context).replace('"','\\"')+'"'
    shell('airflow trigger_dag %s --conf %s'%(dag,ctx))


def shell(cmd):
    print(cmd)
    subprocess.check_call(cmd,shell=True)

def process_date(date_id):
    authenticate(args.gdb_url, args.user, args.password)
    graph = Graph('%s%s'%(args.gdb_url,args.gdb_path))

    query = 'MATCH (d:DATE)-[]-()-[]-(s:SOLNBR) where d.iname="%s" return s.iname'%(date_id)
    print(query)
    data = graph.run(query)

    for sol in data:
        sln = sol['s.iname']
        print('sol ',sln)
        trigger_dag('trigger_sol',context={'solicitation':sln})


process_date(date_id)


