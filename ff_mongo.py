#!/usr/bin/env python
import subprocess
import uuid
import time
import sys
from bson.objectid import ObjectId
import logging
import json
import shutil
import glob
import time
from ffparse import FFParse
from neo4j.v1 import GraphDatabase
import pprint
import errno
import es_index as es

"""
put_file
    - local filename
    - base filename
    - target directory
    - topic
    - key value
    
get_file - locate file by search parameters and then download into target directory


scenarios:
    - put file x 1
          ffm --op put_file --filename xxx 
    - put file with notification p 1
          ffm --op put_file --notify immediate
    - put file and extracted text  2
          ffm --op put_file --text_store mongo --filename xxx # puts a file in mongo and also extracts text and stores in mongo
    - get file to working dir  x 1
          ffm --op get_file --filename xxx --target_dir .
    - get file to target directory p 1
          ffm --op get_file --filename xxx
    - get file when already exists x 1
    - delete file 2
          ffm --op delete --filename xxx
    - specify file filter for get, etc. filename, topic, kwargs, checksum, etc. 1
    - list files x 1
          ffm --op file_list
    - select mongo and/or elasticsearch text storage 2
        ffm --op get_text --text_store es --filename xxx
    - delete all expired files 2
    - update file 1
    
    
    test 
        - list files in mongo x
        - put file into mongo with target
        - extract text from file
        - print file text
        - get file to target
        - delete file
        - execute service
        - put file with notification
        
        
    scenarios
        - push a file into production
            - dag 
            - service
        - execute service
"""

args = None
mg_connected = False
print('args',sys.argv)
if __name__ == '__main__':
    parser = FFParse(description='read and write from mongo')

    parser.add_argument('--mongo_host',default='73.180.97.70',help='mongo url')
    parser.add_argument('--mongo_port',type=int,default=27017,help='mongo port')
    parser.add_argument('--mongo_db',default='aif_document_db')
    parser.add_argument('--mongo_text',default='text_collection')
    parser.add_argument('--collection',default='config',help='mongo collection')
    parser.add_argument('--op',default='read',choices=['read','write','update','delete','put_file','get_file','get_file_id','list','list_files','service'],help='operation')
    parser.add_argument('--key',default='key',help='key')
    parser.add_argument('--value',default='{}',help='value')
    parser.add_argument('--topic')
    parser.add_argument('--filename')
    parser.add_argument('--target')
    parser.add_argument('--version',default='keep')
    parser.add_argument('--overwrite',help='overwrite target')
    parser.add_argument('--notify',choices=['immediate'],help='notification method')
    parser.add_argument('--text_store',default='mongo')
    parser.add_argument('--file_key',default='full_path')

    parser.all_options()

    args = parser.parse_args()

text_store = 'mongo'
def uid():
    return str(uuid.uuid1())

# **************************Mongo Support*************************************************

from pymongo import MongoClient
import gridfs


def set_namespace(ns):
    global args
    args = ns
    print('setting namespace=',args)

def md5sum(filename):
    hash = md5()
    with open(filename, "rb") as f:
        for chunk in iter(lambda: f.read(128 * hash.block_size), b""):
            hash.update(chunk)
    return hash.hexdigest()

text_collection = None
config = None

def connect_if_not():
    if mg_connected:
        return
    connect_service()

def connect_service(targs=None):
    global args
    if targs:
        args = targs
    ip = args.mongo_host
    port = args.mongo_port
    global fs, client, db, config, mg_connected, text_collection, user_db
    print('connect:',ip,port,args.mongo_text)
    client = MongoClient(ip, port)
    if args.config_key:
        user_mongo_db = args.config_key+"_db"
    else:
        user_mongo_db = 'aif_document_db'
    print('global db',args.mongo_db,'user db',user_mongo_db,'text collection',args.mongo_text)
    db      = eval("client.%s" % (args.mongo_db))
    user_db = eval("client.%s" % (user_mongo_db))
#    text_collection = db.text_collection
    text_collection = eval('user_db.%s' % (args.mongo_text))
    config = eval('user_db.%s' % ('config'))
    fs = gridfs.GridFS(db)
    mg_connected = True
    print('connect complete')

    
def reset_ff_db():
    db.text_collection.delete_many({})
    db.posts.delete_many({})

def mongo_notify(type,subtype,data):
    dct = {'type':type,'subtype':subtype, 'config_key':args.config_key}
    dct.update(data)
    db.change_log.insert_one(dct)


def delete_old_file(search):
    if not args.version == 'keep':
        return
    for grid_out in fs.find(search,
                            no_cursor_timeout=True):
        print('delete',grid_out)
        fs.delete(grid_out._id)
    
# API - enters document into AIF 
def add_document(fname,iname=None,target='.',topic=None,kwargs={}):
    print('add document',fname, iname, target,topic)
    connect_if_not()
    rid = None
    tid = None
    retain_until = -1                       # by default keep the file indefinitely 
    if 'ti' in kwargs:
        logging.info("%s"%kwargs['ti'])
        tid = kwargs['ti'].task_id
    if 'dag_run' in kwargs:
        logging.info("%s"%kwargs['dag_run'])
        rid = kwargs['dag_run'].run_id
    if 'retain_until' in kwargs:
        logging.info("%s"%kwargs['retain_until'])
        retain_until = kwargs['retain_until']
    csum = md5sum(fname)
    global fs

    filename, file_extension = os.path.splitext(fname)

    uid = str(uuid.uuid1())+file_extension
    logging.info("add document %s %s %s"%(fname, iname, uid))
    delete_old_file({"full_path":fname})
    with open(fname, 'rb') as inpf:
#        fid = fs.put(inpf, filename=iname, checksum=csum)
         fs.put(inpf, filename=uid, full_path=fname, key_name=iname, run_id=rid, task_id=tid, checksum=csum, retain_until=retain_until, target_dir=target, topic_name=topic)
         fid = uid
         logging.info("added file %s %s"%(fid, inpf))
    logging.info("add_document %s %s %s"%(fid,fname,iname))
#    dir_lst = get_document_directory()
#    logging.info("%s"%dir_lst)
    mongo_notify('new','file',{"fid":fid})
    return fid

# API - localizes a file within AIF so tools that require the file to be on the local file system can operate on the file
import os.path

def exists(fname):
    connect_if_not()
    search_keys= {"filename":fname}
    fileid = fs.find_one(search_keys)
    return fileid
    
def get_document_name(full_name,output_dir=None,search_keys=None,file_key='full_path', overwrite=False):
    global fs
    connect_if_not()
    dirname = os.path.dirname(full_name)
    fname = os.path.basename(full_name)
    if search_keys == None:
        print('search keys not provided, using filename')
        search_keys= {file_key:fname}
    fileid = fs.find_one(search_keys)
    print('search ',search_keys,fileid)
    filedct = fileid.__dict__
    filedct = filedct['_file']
    if output_dir:
        out_dir = output_dir
    else:
        out_dir = filedct.get('target_dir','.')
    out_name = filedct.get('full_path',full_name)
    full_path = out_dir+"/"+out_name
    print('output name ',out_dir, out_name)
    if os.path.exists(full_path) and not overwrite:
        print('file already on local drive')
        return full_path
    else:
        print('overwrite',full_path)
    try:
        os.makedirs(out_dir)
    except OSError as e:
        if e.errno != errno.EEXIST:
            raise
    print('open',full_path)
    with open(full_path, 'wb') as bf:
        print('target ',full_path)
        if fileid == None:
            print('file not found in db ',fname)
            return full_path
        logging.info("get doc %s %s"%(full_path,fname))
#        file = fs.get(fname)
        shutil.copyfileobj(fileid, bf)
    return full_path

def extract_text(fname):
    return "this is text" # TODO

def update_meta(fid,meta):
    return # TODO

def extract_text_from_file(fname):
    fileid = get_document_name(fname)
    try:
        txt = fileid.text
    except:
        txt = None
    if not txt or args.overwrite == 'yes':
        text = extract_text(fname)
        textobj = create_text(text)
        update_meta(fileid,{"text":textobj})
    else:
        print('already has extracted text')

from hashlib import md5
def create_text(text, node_id=None):
    connect_if_not()
#    id = uid()
    if 'mongo:' in text:
        return text
    try:
        if b'<NO_TEXT>' in text:
            return text
    except:
        if '<NO_TEXT>' in text:
            return text
    if True:
        try:
            post_id = text_collection.insert_one({'text_value':text,'value_type':'text','node_id':node_id}).inserted_id
            return_str = "mongo:"+str(post_id)
        except Exception as e:
            print('exception storing text in mongo',e)
            return_str =  "db_fail:"+text
    if 'es' in text_store:
        es.set_namespace(args)
        try:
            es.index_text(node_id, 'label', text)
        except:
            print('unable to index text')
    return return_str

def read_dict(key):
    try:
        val = config.find_one({"key":key})
        print('read:',val)
        return val
    except:
        print("error retrieving text from mongo:",key)
        return key
    
def write_dict(key,dct):
    if type(dct) == str:
        if '@' == dct[0]:
            fname = dct[1:]
            with open(fname,'r') as inf:
                dct = inf.read()
        dct = json.loads(dct)
    try:
        out_dct = {'key':key}
        out_dct.update(dct)
        print('out:',out_dct)
        post_id = config.insert_one(out_dct).inserted_id
        es.set_namespace(args)
#        write_str = json.dumps(out_dct)
        es.index_text(10, 'label', 'this is a test')
        return str(post_id)
    except:
        raise
    
def make_search(search={}):
    keys = [key_name for key_name in search.keys()]
    for key in keys:
        if search[key] == None:
            del search[key]
    file_list = fs.find(search)
    print('search %s results %d' % (search,file_list.count()))
    return file_list
    
def update_dict(key,dct):
    if type(dct) == str:
        dct = json.loads(dct)
    try:
        val = config.find_one({"key":key})
    except:
        print("error retrieving data from mongo:",key)
        return None
    try:
        val.update(dct)
        print('out:',val)
        post_id = config.save(val)
        return str(post_id)
    except:
        raise
        

def get_text(id):
    connect_if_not()
    try:
        if 'mongo:' in id:
            id = id.split(":")[1]
            val = text_collection.find_one({"_id": ObjectId(id)})
            return val['text_value']
        else:
            return id
    except:
        print("error retrieving text from mongo:",id)
        raise
        return id
    
def execute_service(arg_list):
    connect_if_not()
    print(arg_list)
    filename = arg_list[0]
    print('service ',filename)
    get_document_name(filename)
    svc_args = []
    svc_args.extend(['python3',filename])
    svc_args.extend(sys.argv[2:])
    subprocess.call(['pwd'])
    subprocess.check_call(svc_args)

if __name__ == '__main__':
    connect_service()
    if args.op == 'list':
        d = dict((db, [collection for collection in client[db].collection_names()])
                 for db in client.database_names())
        print(json.dumps(d))
    elif args.op == 'read':
        res = read_dict(args.key)
        parser.write_dict(res)
    elif args.op == 'delete':
        file_list = glob.glob(args.filename)
        for filename in file_list:
            delete_old_file({"full_path":filename})
    elif args.op == 'write':
        write_dict(args.key,args.value)
    elif args.op == 'update':
        update_dict(args.key,args.value)
    elif args.op == 'get_file':
        file_list = make_search(search={args.file_key:args.filename,"topic_name":args.topic})
        for fileobj in file_list:
            print('getting ',fileobj.full_path)
            filename = fileobj.full_path
            get_document_name(filename)
    elif args.op == 'get_file_id':
        file_list = make_search(search={"filename":args.filename})
        for fileobj in file_list:
            print('getting ',fileobj.filename)
            filename = fileobj.filename
            get_document_name(filename)
    elif args.op == 'put_file':
        file_list = glob.glob(args.filename)
        print(args.filename,file_list)
        for filename in file_list:
            print('adding ',filename)
            add_document(filename, topic=args.topic, target=args.target)
    elif args.op == 'service':
        execute_service(args.filename)
    elif args.op == 'list_files':
        file_list = fs.find()
        pp = pprint.PrettyPrinter(indent=4)
        for fileobj in file_list:
            dct = fileobj.__dict__['_file']
            pp.pprint(dct)
            print('')
    else:
        print('unknown operation')        


# 3058714

