
#!/usr/bin/env python
import argparse
import uuid
import time
import threading
import re
import networkx as nx
import json
import sys

import lxml

import logging
logging.getLogger('spam_application').addHandler(logging.NullHandler())

service_topic = "default.aif.infrastructure.file_manager"
topic = "default.aif.infrastructure.gdb"
doc_id = None
seq = 0

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Load xml from usaspending.com and convert to a graphing file')
aparser.add_argument('--input_xml',default='*dag_input_file',help='FBO filename')
aparser.add_argument('--dag_input_file',default='tbd',help='Graph filename')

aparser.add_argument('--graph_format',default='GraphML',help='Format to save graph as.')

aparser.add_argument('-output_file',help='Grahp output')
aparser.add_argument('--deferred_link')

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


root = load_xml(args.dag_input_file)

graph = nx.Graph()

# Nodes to convert to attribute nodes

attr_nodes1 = {'effectivedate':'DATE','contractingofficeagencyid':'CONTRACTING_OFFICE_CODE','vendorname':'VENDOR','principalnaicscode':'NAICS','piid':'SOLNBR','congressionaldistrict':'CONGRESSIONAL_DISTRICT','progsourceagency':'AGENCY'}
attr_nodes1 = []
attr_nodes = {'effectivedate':'DATE','contractingofficeagencyid':'CONTRACTING_OFFICE_CODE','vendorname':'VENDOR','principalnaicscode':'NAICS','piid':'SOLNBR','congressionaldistrict':'CONGRESSIONAL_DISTRICT','progsourceagency':'AGENCY'}


total = 1000
cnt = 0
node_cache = {}

total_nodes = 0
for elem in root.iterchildren():
    total_nodes += 1
print('total nodes',total_nodes)

from datetime import datetime
def transform(label,value):
    try:
        new_value = datetime.strptime(value, '%m/%d/%Y').strftime('%m%d%Y')
    except:
        new_value = value
    return new_value

def uid():
    return str(uuid.uuid1())

for elem0 in root.iterchildren():
  for elem in elem0.iterchildren():
    cnt += 1
#    print("new node ",elem.tag,cnt,cnt/total_nodes)
    props = {}
    link_list = []
    node_id = uid()
    for attr in elem.iterchildren():
         if not attr.text == None and not attr.tag == None:
           props[attr.tag] = transform(attr.tag,attr.text)
           link_list.extend([attr])
           if attr.tag in attr_nodes1 and args.deferred_link:

               link_node_id = uid()
               common_label = attr_nodes1[attr.tag]
# create a deferred link since nodes may already exist
               def_query = 'merge (n {iname:"%s"}) merge (n1:%s {iname:"%s"}) merge (n)-[:%s]->(n1)'%(node_id,common_label,transform(attr.tag,attr.text),'gov_transaction_'+common_label)
               graph.add_node(link_node_id, iname=link_node_id, label='deferred_link_create_', from_id=node_id, query=def_query)
         else:
             props[attr.tag] = 'None'


    graph.add_node(node_id, label='gov_transaction_create_', iname=node_id, **props)


# used to generate attribute nodes. only use this if none of the nodes already exist.
    for link_to in link_list:      # link_list
        label = link_to.tag
        if label in attr_nodes and not args.deferred_link:
#            print('create attribute node',label)
            label = attr_nodes[label]
            cust_id = transform(label,link_to.text)
            node1 = None
            if label+cust_id in node_cache:
#                print("cache hit")
                node1 = node_cache[label+cust_id]
            if node1 == None:
                graph.add_node(cust_id, label=label+"_merge_", iname=cust_id)
                node1 = cust_id
                node_cache[label+cust_id] = node1
            graph.add_edge(node_id, node1, label=label)

print('total records',cnt)

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

