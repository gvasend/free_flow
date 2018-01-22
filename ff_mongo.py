#!/usr/bin/env python
import uuid
import time
import sys
from bson.objectid import ObjectId

def uid():
    return str(uuid.uuid1())

# **************************Mongo Support*************************************************

from pymongo import MongoClient
import gridfs


def md5sum(filename):
    hash = md5()
    with open(filename, "rb") as f:
        for chunk in iter(lambda: f.read(128 * hash.block_size), b""):
            hash.update(chunk)
    return hash.hexdigest()

text_collection = None
def connect_service(ip, port):
    global fs, client, db, text_collection
    client = MongoClient(ip, port)
    db = client.aif_document_db
    text_collection = db.text_collection
    fs = gridfs.GridFS(db)
    
# API - enters document into AIF 
def add_document(fname,iname,kwargs):
    rid = None
    tid = None
    retain_until = 30                       # by default retain the file for 30 days
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
    with open(fname, 'rb') as inpf:
#        fid = fs.put(inpf, filename=iname, checksum=csum)
         fs.put(inpf, filename=uid, full_path=fname, key_name=iname, run_id=rid, task_id=tid, checksum=csum, retain_until=retain_until)
         fid = uid
         logging.info("added file %s %s"%(fid, inpf))
    logging.info("add_document %s %s %s"%(fid,fname,iname))
    dir_lst = get_document_directory()
    logging.info("%s"%dir_lst)
    return fid

# API - localizes a file within AIF so tools that require the file to be on the local file system can operate on the file
def get_document_name(fname,oname):
    global fs
    with open(oname, 'wb') as bf:
        file = fs.find_one({"filename": fname})
        if file == None:
            return oname
        logging.info("get doc %s %s"%(oname,fname))
#        file = fs.get(fname)
        shutil.copyfileobj(file, bf)
    return oname

from hashlib import md5
def create_text(text):
#    id = uid()
    if b'<NO_TEXT>' in text:
        return text
    try:
        post_id = text_collection.insert_one({'text_value':text,'value_type':'text'}).inserted_id
        return "mongo:"+str(post_id)
    except:
        return b"db_fail:"+text
    

def get_text(id):
    try:
        if 'mongo:' in id:
            id = id.split(":")[1]
            val = text_collection.find_one({"_id": ObjectId(id)})
            return val['text_value']
        else:
            return id
    except:
        print("error retrieving text from mongo:",id)
        return id
    
connect_service('10.0.1.25', 27017)

# **************************Mongo Support end****************************************
