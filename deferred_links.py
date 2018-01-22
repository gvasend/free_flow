
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
logging.getLogger('spam_application').addHandler(logging.NullHandler())

service_topic = "default.aif.infrastructure.file_manager"
topic = "default.aif.infrastructure.gdb"
doc_id = None
seq = 0

# def extract_file1(filename,proj,doc_type,id):

aparser = argparse.ArgumentParser(description='Process deferred links')
aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--delete_failed',default=True,type=bool)



import scrape as sc

sc.all_options(aparser)

args = sc.parse_args(aparser)
print(args)


def process_def_links():
    authenticate(args.gdb_url, 'neo4j', 'N7287W06')
    graph = Graph('%s/db/data/'%args.gdb_url)

    query = """
    MATCH (n) where EXISTS(n.deferred_link_) RETURN id(n), n, n.deferred_link_
    """

    data = graph.run(query)

    for node_id, node, link in data:
        print(node_id,link)
        query = link
        print('linking ',query)
        try:
            graph.run(query, node_id=node_id)
        except:
            print('failed',query)
    graph.run('match (n) remove n.deferred_link_')
    
    query = """
    MATCH (n:deferred_link) RETURN id(n), n.from_id, n.query
    """

    data = graph.run(query)

    for df_id, node_id, link in data:
        print(node_id,link)
        query = link
        print('linking ',query)
        graph.run(query, node_id=node_id)
        try:
            graph.run(query, node_id=node_id)
        except:
            print('failed',query)
    graph.run('match (n:deferred_link) delete n')

process_def_links()


