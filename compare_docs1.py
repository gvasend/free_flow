
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


def test_py2neo():
    authenticate(args.gdb_url, args.user, args.password)
    grapy = Graph('%s%s'%(args.gdb_url,args.gdb_path))
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
    graph.create(Relationship(pepsi, "MAKES", mtdew))



import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)


import json
import subprocess
def trigger_dag(dag,abs_path='/',context={}):
    ctx = '"'+json.dumps(context).replace('"','\\"')+'"'
    shell('airflow trigger_dag %s --conf %s'%(dag,ctx))


def shell(cmd):
    print(cmd)
    subprocess.check_call(cmd,shell=True)

def compare_documents():
    authenticate(args.gdb_url, args.user, args.password)
    graph = Graph('%s%s'%(args.gdb_url,args.gdb_path))

    query = """
    MATCH (d1:document{doc_type:{d1_type}})-[r1:related_doc]-(pr:project)-[r:related_doc]->(d2:document{doc_type:{d2_type}}) RETURN id(d1),id(d2),d1.doc_type,d2.doc_type
    """

    data = graph.run(query, d1_type="rfp", d2_type="resume")

    for d1, d2, d1dt, d2dt in data:
        print(d1,d1dt,d2,d2dt)
        dct = {'doc1':d1,'doc2':d2,'algorithm':'text_cosine'}
        trigger_dag('document_compare',context=dct)


compare_documents()


