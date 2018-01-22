
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

aparser = argparse.ArgumentParser(description='Trigger document injestion for a given solicitation')

aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')

aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--user',default='neo4j',help='Username')
aparser.add_argument('--password',default='N7287W06',help='credentials')
aparser.add_argument('--dag_run',help='dag run id')
aparser.add_argument('--solicitation',help='solicitation number to process')


import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)


import json
import subprocess
def trigger_dag(dag,abs_path='/',context={}):
    ctx = '"'+json.dumps(context).replace('"','\\"')+'"'
    shell('airflow trigger_dag %s --conf %s'%(dag,ctx))

def test_py2neo():
    authenticate('localhost:7474', 'neo4j', 'N7287W06')
    grapy = Graph('localhost:7474/db/data/')
    nicole = Node("Person", name="Nicole", age=24)
    drew = Node("Person", name="Drew", age=20)

    mtdew = Node("Drink", name="Mountain Dew", calories=9000)
    cokezero = Node("Drink", name="Coke Zero", calories=0)

    coke = Node("Manufacturer", name="Coca Cola")
    pepsi = Node("Manufacturer", name="Pepsi")

    graph.create(nicole | drew | mtdew | cokezero | coke | pepsi)

    graph.create(Relationship(nicole, "LIKES", cokezero))
    graph.create(Relationship(nicole, "LIKES", mtdew))
    graph.create(Relationship(drew, "LIKES", mtdew))
    graph.create(Relationship(coke, "MAKES", cokezero))
 

def shell(cmd):
    print(cmd)
    subprocess.check_call(cmd,shell=True)

def neo_query(graph,q):
    print('neoq',q)
    return graph.run(q)

def get_sol_node(graph,sol):
    data = neo_query(graph,'MATCH (s:SOLNBR)  where s.iname="%s" return s'%(sol))
    sol_node = None
    for s in data:
        sol_node = s['s']
    print('lookup sol',sol_node)
    return sol_node

import os
def process_sol(sol):
    authenticate(args.gdb_url, args.user, args.password)
    graph = Graph('%s%s'%(args.gdb_url,args.gdb_path))

    sol_node = get_sol_node(graph,sol)
    if sol_node == None:
        print('solicitation node does not exist')
        sys.exit(1)

    indir = '/home/gvasend/nfs/Simbolika/fedbiz/Files/%s'%sol
    print('sol dir:',indir)
    for root, dirs, filenames in os.walk(indir):
        for f in filenames:
            fname = os.path.join(root, f)
            finame = fname+"_file"
            data = neo_query(graph,'MATCH (s:SOLNBR)-[]-(f:file) where s.iname="%s" and f.iname="%s" return count(f)'%(sol,finame))
            print(data)
            file_exists = 0
            for cnt in data:
                file_exists = cnt['count(f)']
            print('file exists:',file_exists)
            if file_exists == 0:
                fnode = Node("File", iname=finame, filename=fname)
                graph.create(fnode)
                graph.create(Relationship(sol_node, "has_file", fnode))

                trigger_dag('graph_doc1',context={'document':fname})


process_sol(args.solicitation)


