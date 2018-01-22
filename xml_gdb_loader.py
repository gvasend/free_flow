
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

import lxml

import logging
logging.getLogger('spam_application').addHandler(logging.NullHandler())

service_topic = "default.aif.infrastructure.file_manager"
topic = "default.aif.infrastructure.gdb"
doc_id = None
seq = 0

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Load FBOFULLXML file into graph database')
aparser.add_argument('--input_graph',default='*graph_output',help='FBO filename')
aparser.add_argument('-graph_output',help='Graph filename')
aparser.add_argument('--delete_all',default='False',help='Delete graph db (True/False)')
aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')


import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)

def load_graph(Filename):
    return nx.read_graphml(Filename)


from io import StringIO, BytesIO
from lxml import etree

def load_xml(filename):
    tree = etree.parse(filename)
    root = tree.getroot()
    print(str(root))
    return root

authenticate(args.gdb_url, 'neo4j', 'N7287W06')
graph = Graph('%s/db/data/'%args.gdb_url)

if args.delete_all == 'True':
    graph.delete_all()

root = load_xml(args.graph_output)
authenticate(args.gdb_url, 'neo4j', 'N7287W06')
graph = Graph('%s/db/data/'%args.gdb_url)

attr_nodes = ['SOLNBR','NAICS','OFFICE','CONTACT','AGENCY','DATE','CLASSCOD','SETASIDE']

total = 1000
cnt = 0
node_cache = {}

total_nodes = 0
for elem in root.iterchildren():
    total_nodes += 1
print('total nodes',total_nodes)


for elem in root.iterchildren():
    cnt += 1
    print("new node ",elem.tag,cnt,cnt/total_nodes)
    props = {}
    link_list = []
    for attr in elem.iterchildren():
        props[attr.tag] = attr.text
        link_list.extend([attr])
#        print('attribute',attr.tag)
#    print('+++++++++++++++++++++++++++++end attr')
    node = Node(elem.tag, **props)
    graph.create(node)
    for link_to in link_list:
        label = link_to.tag
        if label in attr_nodes:
#            print('create attribute node',label)
            cust_id = link_to.text
            if label+cust_id in node_cache:
#                print("cache hit")
                node1 = node_cache[label+cust_id]
            else:
                node1 = graph.find_one(label,property_key='iname',property_value=cust_id)
            if node1 == None:
                node1 = Node(label, iname=cust_id)
                graph.create(node1)
                node_cache[label+cust_id] = node1
            graph.create(Relationship(node, label, node1))
#        else:
#            print('label node attribute',label)





def fbo_graphml(filename):
    tree = etree.parse(filename)
    root = tree.getroot()
    print(str(root))
    return root

authenticate(args.gdb_url, 'neo4j', 'N7287W06')
graph = Graph('%s/db/data/'%args.gdb_url)

if args.delete_all == 'True':
    graph.delete_all()

root = load_xml(args.graph_output)
authenticate(args.gdb_url, 'neo4j', 'N7287W06')
graph = Graph('%s/db/data/'%args.gdb_url)

attr_nodes = ['SOLNBR','NAICS','OFFICE','CONTACT','AGENCY','DATE','CLASSCOD','SETASIDE']

total = 1000
cnt = 0
node_cache = {}

total_nodes = 0
for elem in root.iterchildren():
    total_nodes += 1
print('total nodes',total_nodes)


for elem in root.iterchildren():
    cnt += 1
    print("new node ",elem.tag,cnt,cnt/total_nodes)
    props = {}
    link_list = []
    for attr in elem.iterchildren():
        props[attr.tag] = attr.text
        link_list.extend([attr])
#        print('attribute',attr.tag)
#    print('+++++++++++++++++++++++++++++end attr')
    node = Node(elem.tag, **props)
    graph.create(node)
    for link_to in link_list:
        label = link_to.tag
        if label in attr_nodes:
#            print('create attribute node',label)
            cust_id = link_to.text
            if label+cust_id in node_cache:
#                print("cache hit")
                node1 = node_cache[label+cust_id]
            else:
                node1 = graph.find_one(label,property_key='iname',property_value=cust_id)
            if node1 == None:
                node1 = Node(label, iname=cust_id)
                graph.create(node1)
                node_cache[label+cust_id] = node1
            graph.create(Relationship(node, label, node1))
#        else:
#            print('label node attribute',label)




