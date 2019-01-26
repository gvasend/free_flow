
#!/usr/bin/env python
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
logging.getLogger('spam_application').addHandler(logging.NullHandler())

service_topic = "default.aif.infrastructure.file_manager"
topic = "default.aif.infrastructure.gdb"
doc_id = None
seq = 0

# def extract_file1(filename,proj,doc_type,id):

from ffparse import FFParse

aparser = FFParse(description='Load graph')
aparser.add_argument('-graph_output',help='Graph filename') # single dash disables automatic setting of parameter from upstream data 

aparser.add_argument('--input_graph',default='*graph_output',help='Graph filename')
aparser.add_argument('--delete_all',default='False',help='Delete graph db (True/False)')
aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')
aparser.add_argument('--plot_graph',default='False',help='Plot graph (True/False')


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
    graph.create(Relationship(pepsi, "MAKES", mtdew))


aparser.all_options()

args = aparser.parse_args()
print(args)

def load_graph(Filename):
    return nx.read_graphml(Filename)

def clean_label(label):
    return label.replace("_merge_","").replace("_create_","")

def connect_neo():
    authenticate(args.gdb_url, 'neo4j', 'N7287W06')
    return Graph('http://%s/db/data/'%args.gdb_url)

def networkx_2_neo4j():
    global gr
    graph = connect_neo()
    print('connected to neo4j')
    gr = load_graph(args.input_graph)
    if args.delete_all == 'True':
        graph.delete_all()
    node_dct = {}
    for n,d in gr.nodes_iter(data=True):
    #    print("n ",n,"d ",d)
        label = 'node'
        create_node = False
        if 'label' in d:
            label = d['label']
        if not '_' in n and not '_merge_' in label:
            d['iname'] = n
            node = Node(clean_label(label),**d)
            create_node = True
        else:
            node = graph.find_one(clean_label(label),property_key='iname',property_value=n)
            if node == None:
                d['iname'] = n
                node = Node(clean_label(label), **d)
                create_node = True
#            node = find_node(iname=n)
        node_dct[n] = node
        if create_node:
            try:
                graph.create(node)
            except:
                print('error on create node')
        else:
            print('found existing node',node,label,n)
    for u,v,d in gr.edges_iter(data=True):
#        print("edge ",u,v,"data",d)
        if 'label' in d:
            label = d['label']
        else:
            label = 'related'
        graph.create(Relationship(node_dct[u], label, node_dct[v]))

networkx_2_neo4j()

if args.plot_graph == 'True':
    nx.draw(gr)
    plt.show()
