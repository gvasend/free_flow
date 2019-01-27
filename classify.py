from ffparse import FFParse
import sys

from py2neo import authenticate, Graph, Node, Relationship

import logging

aparser = FFParse(description='Apply a classifier to node')

aparser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')
aparser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
aparser.add_argument('--gdb_user',default='neo4j')
aparser.add_argument('--gdb_password',default='')
aparser.add_argument('--node_id',type=int,default=0,help='node id')
aparser.add_argument('--class_id',type=int,help='id of the class node that was just applied')
aparser.add_argument('--classifier',help='Name of the classifier')

aparser.all_options()

args = aparser.parse_args()


def connect_neo():
    authenticate(args.gdb_url, args.gdb_user, args.gdb_password)
    return Graph('http://%s%s'%(args.gdb_url,args.gdb_path))
    
gr = connect_neo()


def apply_empirical_class():
    query = """
    MATCH (node)-[r:INSTANCE_OF]->(class_node:class) WHERE id(node)=%d and id(class_node)=%d MATCH (class_node)-[:APPLY]->(cl:Classifier {type:"empirical"})-[:CLASSIFY_AS]->(c2:class) 
     WITH c2, cl.rule as rule, id(node) as nid call apoc.cypher.run("match (node:instance) WHERE id(node)=nid AND "+rule+" return node",{nid:nid}) yield value 
     WITH nid, c2
     call apoc.periodic.submit("job","MATCH (node:instance) WHERE id(node)="+nid+" MATCH (c:class) WHERE id(c)="+id(c2)+" MERGE (node)-[:INSTANCE_OF]->(c)") yield name, delay, rate, done, cancelled  RETURN c2
    """ % (args.node_id,args.class_id)
    gr.run(query)
    

apply_empirical_class()
