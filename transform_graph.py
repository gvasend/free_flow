
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

import logging
logging.getLogger('freeflow').addHandler(logging.NullHandler())

# def extract_file1(filename,proj,doc_type,id):

# apply a transform to a graph. not fully generecised, this routine shreds a proposal. TBD make more generic.

aparser = argparse.ArgumentParser(description='Apply transform to a graph')
aparser.add_argument('--input_graph',default='*graph_output',help='Graph filename')
aparser.add_argument('-graph_output',default='tbd',help='Graph filename')
aparser.add_argument('--plot_graph',default='False',help='Plot graph (True/False')

aparser.add_argument('-output_file',help='Grahp output')

aparser.add_argument('--graph_format',default='GraphML',help='')
aparser.add_argument('--req_match',default='/home/gvasend/nfs/Simbolika/app/req_list.txt')
aparser.add_argument('--sect_match',default='/home/gvasend/nfs/Simbolika/app/sect_list.txt')

import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)

import uuid
def uid():
    return str(uuid.uuid1())

def load_graph(Filename):
    return nx.read_graphml(Filename)

def clean_label(label):
    return label.replace("_merge_","").replace("_create_","")


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


req_list = eval_file('req_list.txt')
sect_list = eval_file('sect_list.txt')

total_unk = 0
total_cat = 0
def cat_text(rules,text_in):
    text = text_in.lower()
    global total_unk, total_cat
    for match in rules:
        for regex in match['exp']:
#            print('regex:',regex)
            found = re.search(regex, text)
            if found:
                total_cat += 1
                cat_type = 'unknown'
                print('match:',text,regex,match['cat'])
                if 'type' in match:
                    cat_type = match['type']
                return match['cat'], cat_type
    total_unk += 1
    return 'sentence', 'unknown'

def shred(graph):
    for n,d in gr.nodes_iter(data=True):
#        print("n ",n,"d ",d)
        if 'label' in d and d['label'] == 'sentence':
            if 'text' in d:
                text = d['text']
                cat, req_type = cat_text(req_list,text)
                graph.node[n]['category'] = cat
                graph.node[n]['req_type'] = req_type
        for u, v, d in graph.edges([n], data=True):
            if 'label' in graph.node[v] and graph.node[v]['label'] == 'section':
                if 'title' in graph.node[v]:
                    sect_title = graph.node[v]['title']
                    print('section text ',sect_title)
                    cat, req_type = cat_text(sect_list,sect_title)
                    if not cat == 'sentence':
                        graph.node[n]['category'] = cat
                        graph.node[n]['req_type'] = req_type
    return graph
    

def transform_graph(graph):
    for n,d in gr.nodes_iter(data=True):
        print("n ",n,"d ",d)

    for u,v,d in gr.edges_iter(data=True):
        print("edge ",u,v,"data",d)
    return graph
    
if __name__ == '__main__':
    if args.output_file == None:
        setattr(args, 'output_file', "graph_out_"+str(uid())+'.'+args.graph_format.lower())


    gr = load_graph(args.input_graph)
    gr = shred(gr)
    print('total unk ',total_unk,'total cat',total_cat)
    
    if args.plot_graph == 'True':
        nx.draw(gr)
        plt.show()

    if args.graph_format == 'GEXF':
        nx.write_gexf(gr, args.output_file)
    elif args.graph_format == 'GML':
        nx.write_gml(gr, args.output_file)
    elif args.graph_format == 'GraphML':
        print("writing graphml")
        nx.write_graphml(gr, args.output_file)
    sc.write_dict({'graph_output':args.output_file})
    

