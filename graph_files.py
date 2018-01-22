
#!/usr/bin/env python
import argparse
import uuid
import time
import re
import networkx as nx
#import stomp_bridge
# from pylinkgrammar.linkgrammar import Parser, Linkage, ParseOptions, Link
#import udp_bridge
from pubsub import pub
import xmltodict
import sys
import matplotlib.pyplot as plt

import logging
logging.getLogger('spam_application').addHandler(logging.NullHandler())

service_topic = "default.aif.infrastructure.file_manager"
topic = "default.aif.infrastructure.gdb"
doc_id = None
seq = 0

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='convert fbo file listing into a graph')
aparser.add_argument('--input_file',default='/home/gvasend/nfs/Simbolika/fedbiz/fbo_files.txt',help='FBO filenames')

aparser.add_argument('--graph_format',default='GraphML',help='')

aparser.add_argument('-output_file',help='Grahp output')
aparser.add_argument('--deferred_link',default=False,type=bool)

import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)

import uuid
def uid():
    return str(uuid.uuid1())

def eval_file(fname):
    lst = []
    with open(fname, 'r') as inf:
        lines = inf.readlines()
        for line in lines:
            print('line:',line)
            dct = eval(line)
            lst.extend([dct])
#        print('eval:',st)
        return lst


fcat_list = eval_file('fcat_list.txt')


def fcat(fname):
    global total_unk, total_cat
    for match in fcat_list:
        for regex in match['exp']:
#            print('regex:',regex)
            found = re.search(regex, fname)
            if found:
                total_cat += 1
                return match['cat']
            if regex in fname:
                total_cat += 1
                return match['cat']

    total_unk += 1            
    return 'unknown'

import networkx as nx

graph = nx.Graph()

total_rows = 0
total_files = 0
total_unk = 0
total_cat = 0

with open(args.input_file, "r", encoding='cp1252') as infile:
   total_rows += 1
   lines = infile.readlines()
file_set = set(lines)

for line in file_set:
    total_rows += 1
    line = line.replace("&amp;","&").replace("\n","")
    fields = line.split("\\")
    solnbr = fields[3]
    graph.add_node(solnbr, label='SOLNBR_merge_', iname=solnbr, short_solnbr=solnbr.replace("-",""))
    fname = None
    if len(fields) > 4:
        total_files += 1
        fname = fields[4]
        abs_fname = line.replace("\\","/").replace("Z:","/home/gvasend/nfs/Simbolika")
        dtype = fcat(fname)
        graph.add_node(abs_fname, label='file_merge_', filename=fname, iname=abs_fname, doc_type=dtype)
        graph.add_edge(solnbr, abs_fname, label='hasFile')



print('total rows',total_rows,'total files',total_files,'unknown',total_unk,'categorized',total_cat)

if __name__ == '__main__':
    if args.output_file == None:
        setattr(args, 'output_file', "graph_out_"+str(uid())+'.'+args.graph_format.lower())
    
    if args.graph_format == 'GEXF':
        nx.write_gexf(graph, args.output_file)
    elif args.graph_format == 'GML':
        nx.write_gml(gr, args.output_file)
    elif args.graph_format == 'GraphML':
        print("writing graphml")
        nx.write_graphml(graph, args.output_file)
    sc.write_dict({'graph_output':args.output_file})

