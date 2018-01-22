
#!/usr/bin/env python
import uuid
import sys

import py2neo
from py2neo import authenticate, Graph, Node, Relationship
from py2neo import remote

import logging


# def extract_file1(filename,proj,doc_type,id):


gdb_url = "localhost:7474"
user = "neo4j"
password = "N7287W06"
gdb_path = "/db/data/"


import json

from lxml import etree

def format_node(rnode,node):
    root = etree.Element("mxCell")
    id = remote(node)._id
    root.set("id",str(id))
    root.set("customId",str(id))
    root.set("vertex","1")
    root.set("parent","1")
    root.set("value","test")
    geo = etree.Element("mxGeometry")
    geo.set("x","0")
    geo.set("y","0")
    geo.set("height","80")
    geo.set("width","70")
    geo.set("as","geometry")
    root.append(geo)
    rnode.append(root)
    return root
#    return etree.tostring(root).decode('utf-8')
#    node_xml = dicttoxml({'mxCell':{'id':remote(node)._id}},root=False,attr_type=False)

def format_rel(rnode,edge):
    root = etree.Element("mxCell")
    id = str(uuid.uuid1())
    root.set("id",str(id))
    root.set("customId",str(id))
    root.set("edge","1")
    root.set("parent","1")
    root.set("value","test")
    n1 = remote(edge.start_node())._id
    n2 = remote(edge.end_node())._id
    root.set("source",str(n1))
    root.set("target",str(n2))
    geo = etree.Element("mxGeometry")
    geo.set("relative","1")
    geo.set("as","geometry")
    root.append(geo)
    rnode.append(root)
    return root
#    return etree.tostring(root).decode("utf-8")



#    <mxCell id="6" customId="6" value="&lt;img src=&quot;editors/images/overlays/workplace.png&quot;&gt;&lt;br&gt;&lt;b&gt;Workplace&lt;/b&gt;&lt;br&gt;Status&lt;br&gt;Info" vertex="1" parent="1">
#      <mxGeometry x="0" y="0" width="80" height="70" as="geometry"/>
#    </mxCell>

#    <mxCell id="edge-5" customId="edge-5" value="&lt;img src=&quot;editors/images/overlays/check.png&quot;&gt; Access" edge="1" parent="1" source="6" target="8">
#      <mxGeometry relative="1" as="geometry"/>
#    </mxCell>

records = []
def collect_graph(rnode,dat):
    global records
    for item in dat:
        if type(item) == py2neo.types.Node:
#            print('node:',type(item),remote(item)._id,item.labels(),item.properties)
            rec = format_node(rnode,item)
        else:
#        if type(item) == py2neo.types.Relationship:
#            print('edge:',type(item),remote(item)._id,item.type(),item.properties)
            rec = format_rel(rnode,item)
#        print(rec)
#        records.extend([rec])


def q():
    authenticate(gdb_url, user, password)
    graph = Graph('%s%s'%(gdb_url,gdb_path))

    query = """
    MATCH (d:folder)-[r]-(f:file) RETURN d,r,f
    """

    data = graph.run(query)

    root = etree.Element("mxGraphModel")
    root1 = etree.Element("root")
    root.append(root1)
    cell0 = etree.Element("mxCell")
    cell0.set("id","0")
    cell1 = etree.Element("mxCell")
    cell1.set("id","1")
    cell1.set("parent","0")
    root.append(root1)
    root1.append(cell0)
    root1.append(cell1)
    
    for dat in data:
        collect_graph(root1,dat)
    print(etree.tostring(root))

        



q()


