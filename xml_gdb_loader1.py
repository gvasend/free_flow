
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

aparser.add_argument('--graph_format',default='GraphML',help='')

aparser.add_argument('--output_file',help='Grahp output')

import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)

def load_graph(Filename):
    return nx.read_graphml(Filename)

import networkx as nx
from io import StringIO, BytesIO
from lxml import etree

def load_xml(filename):
    tree = etree.parse(filename)
    root = tree.getroot()
    print(str(root))
    return root


root = load_xml(args.graph_output)

graph = nx.Graph()

attr_nodes = ['SOLNBR','NAICS','OFFICE','CONTACT','AGENCY','DATE','CLASSCOD','SETASIDE']

total = 1000
cnt = 0
node_cache = {}

total_nodes = 0
for elem in root.iterchildren():
    total_nodes += 1
print('total nodes',total_nodes)

def uid():
    return str(uuid.uuid1())


for elem in root.iterchildren():
    cnt += 1
#    print("new node ",elem.tag,cnt,cnt/total_nodes)
    props = {}
    link_list = []
    for attr in elem.iterchildren():
         if not attr.text == None and not attr.tag == None:
           props[attr.tag] = attr.text
           link_list.extend([attr])
#        print('attribute',attr.tag)
#    print('+++++++++++++++++++++++++++++end attr')
    node_id = uuid.uuid1()
    graph.add_node(node_id, label=attr.tag, **props)
#    print(attr.tag,props)


    for link_to in []:      # link_list
        label = link_to.tag
        if label in attr_nodes:
#            print('create attribute node',label)
            cust_id = link_to.text
            node1 = None
            if label+cust_id in node_cache:
#                print("cache hit")
                node1 = node_cache[label+cust_id]
            if node1 == None:
                graph.add_node(cust_id, label=label, iname=cust_id)
                node1 = cust_id
                node_cache[label+cust_id] = node1
            graph.add_edge(node_id, node1, label=label)


if __name__ == '__main__':
    if args.output_file == None:
        setattr(args, 'output_file', "graph_out_"+str(uid())+'.'+args.graph_format.lower())

#    outf = open(args.output_file,'w')
    
    if args.graph_format == 'GEXF':
        nx.write_gexf(gr, args.output_file)
    elif args.graph_format == 'GML':
        nx.write_gml(gr, args.output_file)
    elif args.graph_format == 'GraphML':
        print("writing graphml")
        nx.write_graphml(graph, args.output_file)
    sc.write_dict({'graph_output':args.output_file})

