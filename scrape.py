
from numpy import genfromtxt
import datetime, time
import atexit
from sklearn import manifold, datasets
import uuid
import logging
import os, stat, sys

logger = logging.getLogger('freeflow')
svci = sys.argv[0]+'_'+str(uuid.uuid1())+'.svci'
tee_output = False


class Metafile(object):
    def __init__(self,filename,data):
        if filename == None:
            return None
        self.filename = filename
        if '.meta' in filename:
            logging.info("load metafile directly by name: %s"%filename)
            self.data = load_json(filename)
            self.filename = self.data.filename
        elif file_exists(self.meta_filename()):
            logging.info("load existing metafile")
            dct = load_json(self.meta_filename())
            self.data = dct
        else:
            self.data = {"svci":svci,"filename":self.filename,"creation":time.time(),"retain":0}
            self.data.update(data)
            save_json(self.meta_filename(),self.data)
            print("meta:",self.meta_filename())

    def get_filename(self):
        return self.filename
		
    def meta_filename(self):
        return "."+self.filename+".meta"
#        return "mf_"+self.filename

    def expired(self):
        try:
            if self.data.retain == 0:
                return False
        except:
            return False
        create_date = self.data.creation
        now = time.time()
        if self.creation+(self.retain*60.0*60.0*24.0) > time.time():
            return True
        else:
            return False
		
    def create_dict_mf(dct):
        for key, val in dct.items():
            if 'file' in key and not val == None and file_exists(val):
                mf = Metafile(val,{})
            elif val == None:
                logging.info("file %s is None"%key)

    def scan_metafile(fname):
        mf = Metafile(fname,{})
        if mf.expired():
            mf.delete()
			
    def scan_mf():
        for dirpath, dnames, fnames in os.walk("./"):
            for f in fnames:
                if f.endswith(".meta"):
                    Metafile.scan_metafile(os.path.join(dirpath, f))
                

def file_exists(fname):
    try:
        return os.path.isfile(fname)	
    except:
        raise Exception("error on testing %s for existance"%fname)

class ExitHooks(object):
    def __init__(self):
        self.exit_code = None
        self.exception = None

    def hook(self):
        self._orig_exit = sys.exit
        sys.exit = self.exit
        sys.excepthook = self.exc_handler

    def exit(self, code=0):
        self.exit_code = code
        self._orig_exit(code)

    def exc_handler(self, exc_type, exc, *args):
        print(exc,args)
        self.exception = exc

hooks = ExitHooks()

env_file = "env.json"

def load_json(fname):
  try:
    with open(fname, 'r') as inpf:
        str = inpf.read()
        return json.loads(str)
  except:
    return {}
    
def save_json(fname, dct):
    with open(fname, 'w') as outf:
        outf.write(json.dumps(dct))

def set_env(key,val):
    dct = load_json(env_file)
    os.environ[key.upper()] = str(val)
    dct[key] = str(val)
    save_json(env_file, dct)

def get_env(key):
    dct = load_json(env_file)
    if key in dct:
        return dct[key]
    else:
        return None

def stdin_mode():
    mode = os.fstat(0).st_mode
    print(sys.argv)
    if '-b' in sys.argv:
         print("terminal")
         return 'terminal'
    elif stat.S_ISFIFO(mode):
         return "piped"
    elif stat.S_ISREG(mode):
         return "redirected"
    else:
         print("terminal mode")
         return 'terminal'

import select
import re, ast

start_time = time.time()
tee = False
arguments = None

dict_str = None
import json

def get_output_data_json(results):
# scrape output data between markers. limits where output data is scraped but follows full json format.
    results = str(results)
    logger.info(results)
    app_lst = re.findall('<app_data>(.+?)</app_data>', results, re.DOTALL)
    app_data = ",".join(app_lst)
    if '{' in app_data:
        app_dict = json.loads(app_data)
        logger.info("app_dict:%s"%app_dict)
    else:
        logger.warning("app data not detected")
        app_dict = {}
    upstream_lst = re.findall('<upstream_data>(.+?)</upstream_data>', results, re.DOTALL)
    upstream_data = ",".join(upstream_lst)
    if '{' in upstream_data:
        upstream_dict = json.loads(upstream_data)
        logger.info("upstream_dict:%s"%upstream_dict)
    else:
        logger.info("upstream data not detected: %s"%upstream_data)
        upstream_dict = {}

#    print("up ",upstream_dict," app ",app_dict)
    upstream_dict.update(dict(app_dict)) # make sure app_data overwrites where duplicate
    logger.info("output data = %s"%upstream_data)
    return upstream_dict

def get_output_data(results):
# scrape output data using regular expression does not handle nested structures
    results = str(results)
    logger.info(results)
    dict_str = "{"+",".join(re.findall('{(.+?)}', results))+"}"
    logger.info("output data = %s"%dict_str)
    return ast.literal_eval(dict_str)

def json_scrape(results):
# scrape all upstream data using regex. does not handle nested data.
    global dict_str
    results = str(results)
    dict_str = "{"+",".join(re.findall('{(.+?)}', results))+"}"
#    logger.info("output data = %s"%dict_str)
    logger.info("scraped data: %s"%dict_str)
    return ast.literal_eval(dict_str)


def write_dict_file(key,filename):
#    write_dict({key:Metafile(filename,{"retain":60}).filename})
    write_dict({key:filename})
	
def write_dict(data):
# Store data to be written on exit
    global out_data
    Metafile.create_dict_mf(data)
    for key in data:
        if isinstance(data[key], (list, str, int, float, bool, type(None))):
            out_data[key] = data[key]
    

import json
def write_dict1(fh=sys.stdout,tee=True):
    global dict_str, out_data, in_dict
    for key, val in out_data.items():
        if not val == None:
#            logger.info("set env %s=%s"%(key,val))
            set_env(key,val)
# Write dict to stdout
#    if not dict_str == None and not arguments.t == None and not arguments.s:
    if tee:
        logger.info("tee is true, copy input data to output stream")
        dict_str = json.dumps(in_dict)
    if not dict_str == None and not arguments.s:
        fh.write("<upstream_data>\n")
        fh.write(dict_str)
        fh.write("</upstream_data>")
    if not arguments == None and (arguments.s == None or not arguments.s):
        fh.write("<app_data>\n")
        encode_data(out_data,fh=fh)
        fh.write("</app_data>\n")

def freeflow_terminate(fh=sys.stdout,tee=False):
    tee = tee_output
    delta_time=time.time()-start_time
    now = "%s"%(datetime.datetime.now())
    write_dict({'termination_time':now,'run_time':delta_time})
    if hooks.exit_code is not None:
        write_dict({'status':'error','exit_code':hooks.exit_code})
    elif hooks.exception is not None:
        write_dict({'status':'error','exception':hooks.exception})
    else:
        write_dict({'status':'normal'})
    for arg in vars(arguments):
        write_dict({'--'+arg:getattr(arguments,arg)})
    write_dict1(fh,tee)
    with open(svci,'w') as outf:        # create service instance file
        write_dict1(outf,tee)
    
def safe_eval(expr):
    if expr == None:
        return None
    elif not type(expr) == str:
        return expr
    try:
        return eval(expr)
    except:
        return expr

smethod = 'json'
    
def encode_data(out_data,fh=sys.stdout):
    if smethod == 'json':
           fh.write(json.dumps(out_data))
    elif smethod == 'simple':
           for key in out_data:
               fh.write('{"%s":"%s"}'%(key,out_data[key]))

def decode_data(st):
    logger.info("decode:%s"%st)
    if smethod == 'simple':
        return get_output_data(st)
    elif smethod == 'json':
        return get_output_data_json(st)
        
    

in_dict = {}
out_data = {}

def eval_argument(val):
    if type(val) == str and 'eval:' in val:
#                      try:
        logger.info("evaluate:%s"%val)
        new_val = eval(val.split("eval:")[1])
#                      except:
#                          print("unable to evaluate:%s"%new_val)
#                          new_val = new_val
        logger.info("old %s new %s "%(val,new_val))
        return new_val
    return val
   
import argparse
def parse_args(parser):
# wrapper around parse_args
    global in_dict, arguments, hooks, logger, tee_output
    parser.formatter_class = argparse.ArgumentDefaultsHelpFormatter
    logging.basicConfig(level='DEBUG')
    logger = logging.getLogger('root')
    args =  parser.parse_args(scrape_inputs_(parser))
    if not args.s:
        hooks.hook()
        atexit.register(freeflow_terminate)

    try:        
        logging.basicConfig(level=args.ll)
        logger = logging.getLogger('root')
        hdlr = logging.FileHandler('/home/gvasend/freeflow.log')
        formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
        hdlr.setFormatter(formatter)
        logger.addHandler(hdlr)
    except:
        logger = logging.getLogger('freeflow')
        print('unable to set logger level')

#    print("scrapped data",in_dict)
    dct = args.__dict__.copy()
#    print(in_dict)
#  resolve any indirect references
    for key, val in dct.items():
#        print("key ",key,"value ",val)
        new_val = val
        if type(val) == str and '?' in val and stdin_mode() == 'terminal':
            ptr = val.split("?")[1]
            new_val = get_env(ptr)
            logger.info("lookup key %s was %s now %s"%(ptr,val,new_val))
        if type(val) == str and '*' in val:
            ptr = val.split("*")[1]
#            print("indirect reference: ptr ")
            logger.info("search for %s"%ptr)
            for ink in in_dict:
#                print('checking ',ink)
                if ptr in ink:    # if the in_dict value is a string and the ptr is in the str we have a match
#            if ptr in in_dict:
#                print("     points to:",in_dict[ptr])
                    new_val = in_dict[ink]
        setattr(args, key, eval_argument(new_val))
    logger.info("final arguments %s"%args)
    tee_output = args.t
    arguments = args
    return args

def str_from_file(fname):
    with open(fname, 'r') as ifile:
        st = ifile.readlines()
    return "".join(st).rstrip()

def lookup_key(key,arguments):
    for arg_i in range(len(arguments)):
        if key in arguments[arg_i]:
            return arguments[arg_i+1]

def command_file(lst):
    return_list = []
    fname = None
    for opt_ind in range(len(lst)):
        opt = lst[opt_ind]
        if isinstance(opt, str) and '--argf' in opt:
            fname = lst[opt_ind+1]             # this argument will disappear from the argument list
            if '*' in fname:
                fname = lookup_key(fname[1:],lst)
        elif opt_ind > 0 and '--argf' in lst[opt_ind-1]:
            continue
        else:
            return_list.extend([opt])
    if fname == None:
        fname = lookup_key('command_file',lst)          # if a command file was not provided, search the default
    if not fname == None:
#        try:
            file_args = str_from_file(fname).split(" ")
            print("inserted arguments from file ",file_args)
            return_list.extend(file_args)
 #       except:
            print("exception of reading arguments from file %s"%fname)
            pass
#    print("return_list",return_list)
    return [x for x in return_list if not x == '']

import datetime    
def scrape_inputs_(parser):
    global in_dict
    global start_time
    start_time = time.time()
# scrape the stdin for incoming key/value data used to satisfy the command line arguments. Allows pipelined programs to have a more structured interface.
    now = "%s"%(datetime.datetime.now())

    mode = stdin_mode()
    print('mode=',mode)
    logger.info("stdin mode=%s"%mode)
    write_dict({'program':sys.argv[0],'execution_time':now})
    if not mode == 'terminal':    # if stdin data is available, scrape it
        st = sys.stdin.read()
    else:
        try:
          with open(env_file, 'r') as inpf:
              st = "<app_data>"+inpf.read()+"</app_data>"
              logger.debug("read environment data %s"%st)
        except:
          st = "{}"
          logger.warn("unable to lod environment data")
    if not st == None:
        needed_args = []
        for arg in parser._actions:
            needed_args.extend(arg.option_strings)
#        print("needed args",needed_args)

#        print("scraping stdin",st)
        in_dict = decode_data(st)
        arg_list = sys.argv[1:]
        for key in in_dict:
            if '--'+key in needed_args and not '--'+key in sys.argv:
                arg_list.extend(['--'+key,in_dict[key]])
#        print("collected data:",arg_list)
        return_list = arg_list
    else:                                           # if stdin data is not available, the command line has to have all the needed data
        logger.info("stdin not available, use only command lines")
        return_list = sys.argv[1:]
#    return command_file(return_list)                # insert command file arguments if found  disable for now. may not need
    print("return_list:%s"%return_list)
    return return_list
        
def load_file(feature_file):
    if '.csv' in feature_file:
        X = genfromtxt(feature_file, delimiter=',')
        zip_l = [list(a) for a in zip(*X)]
        y = zip_l[0]
        X1 = zip_l[1:]
        X = [list(a) for a in zip(*X1)]
#    print(X)
    elif '.libsvm' in feature_file:
        X, y = datasets.load_svmlight_files([feature_file])
        X = X.toarray()
    
    return X, y
    if '.csv' in feature_file:
        X = genfromtxt(feature_file, delimiter=',')
        zip_l = [list(a) for a in zip(*X)]
        y = zip_l[0]
        X1 = zip_l[1:]
        X = [list(a) for a in zip(*X1)]
#    print(X)
    elif '.libsvm' in feature_file:
        X, y = datasets.load_svmlight_files([feature_file])
        X = X.toarray()
    return X, y


from sklearn.externals import joblib

def load_model(fname):
    try:
        if not fname == None:
            return joblib.load(fname)
        else:
            return None
    except:
        return None
    
def save_model(model, fname):
#    print("type ",type(model))
    class_name = re.search('class \'(.*)\'>', str(type(model))).group(1)
    if fname == None:
        fname = class_name+"_"+str(uuid.uuid1())+'.pkl'
    logger.info("saving model as %s"%fname)
    joblib.dump(model, fname) 
    write_dict({'model_file':fname})


def add_arguments(parser,arg_list):
    for arg in arg_list:
        add_argument(parser,arg)

def add_argument(parser,name):
    if name=='n_jobs':
        parser.add_argument('--n_jobs',default=1,type=int, help='The number of jobs to use for the computation. This works by computing each of the n_init runs in parallel. If -1 all CPUs are used. If 1 is given, no parallel computing code is used at all, which is useful for debugging. For n_jobs below -1, (n_cpus + 1 + n_jobs) are used. Thus for n_jobs = -2, all CPUs but one are used.')
    if name=='random_state':
        parser.add_argument('--random_state',help='A pseudo random number generator used for the initialization of the residuals when eigen_solver == arpack.')
    if name=='verbose':
        parser.add_argument('--verbose',type=bool,default=False,help='Enable verbose output. Note that this setting takes advantage of a per-process runtime setting in libsvm that, if enabled, may not work properly in a multithreaded context.')
    if name == 'tol':
        parser.add_argument('--tol',type=float,default=1e-3,help='Tolerance for stopping criterion.')
    if name == 'gamma':
        parser.add_argument('--gamma',default=1.0,type=float,help='Kernel coefficient for rbf and poly kernels. Ignored by other kernels.')
    if name == 'neighbors_algorithm':
        parser.add_argument('--neighbors_algorithm',default='auto',choices=['auto','brute','kd_tree','ball_tree'],help='Algorithm to use for nearest neighbors search, passed to neighbors.NearestNeighbors instance.')
    if name == 'eigen_solver':
        parser.add_argument('--eigen_solver',choices=['arpack', 'lobpcg','amg'],help='The eigenvalue decomposition strategy to use. AMG requires pyamg to be installed. It can be faster on very large, sparse problems, but may also lead to instabilities.')




# model options
def model_options(parser):
    parser.add_argument('--model_file',default='*model_output_file',help='load existing model from file.')
    parser.add_argument('--model_output_file',help='load existing model from file.')
#    parser.add_argument('--model_output_file',default='eval:"sk_model_"+str(uuid.uuid1())+".pkl"',help='load existing model from file.')
    parser.add_argument('--action',choices=['fit','fit_predict','fit_transform','predict','transform','score','print'])

# all options
def all_options(parser):
    parser.add_argument('-t',help='Copy upstream data to downstream.',action="store_true")
    parser.add_argument('-s',help='Supress dict output.',action="store_true")
    parser.add_argument('-b',help='Disable read arguments from stdin.',action="store_true")
    parser.add_argument('--argf',help='Read command line arguments from a file.',default='*command_file')
    parser.add_argument('-ll',default='WARNING',help='set debugging level')



# output options
def output_options(parser):
    parser.add_argument('--output_file',default='eval:"sk_ff_"+str(uuid.uuid1())+".libsvm"',help='file containing output')

    parser.add_argument('--zero_based',default=True,type=bool)

    parser.add_argument('--comment',help='')

    parser.add_argument('--query_id',help='')

    parser.add_argument('--multilabel',type=bool,default=False,help='')
    
task_ids = {}

def get_task_id(task):
    global task_ids
    if task in task_ids:
        i = task_ids[task]+1
        task_ids[task] = i
        return task+"_"+str(i)
    else:
        task_ids[task] = 0
        return task+"_0"

def gen_workflow(dag_name,expr):
    outf = open(dag_name+".py",'w')
    outf.write("from so import SO\nfrom airflow.operators.dummy_operator import DummyOperator\nfrom airflow import DAG\nfrom datetime import datetime\n")
    outf.write("with DAG('%s', start_date=datetime(2017, 1, 1), schedule_interval=None) as dag:\n\n\n"%dag_name)
    tid = 1
    step_list = []
    pr_list = expr.split("|")
    for pr in pr_list:
#        print("step ",pr)
        task_list = pr.lstrip().split(" ")
#        print("task list ",task_list)
        task_name = task_list[1].split(".py")[0]
        task_id = get_task_id(task_name)
        tid += 1
        prog = task_list[1]
        step_list.extend(["SO(task_id='%s',process='%s',%s)"%(task_id,prog," ".join(task_list[2:]))])
    outf.write("   dag >> do >> "+" >> ".join(step_list))
    outf.write("\n")
    outf.close()


#with DAG('mean_shift1', start_date=datetime(2017, 1, 1), schedule_interval=None) as dag:
#   do = DummyOperator(task_id='start',dag=dag)
#   dag >> do >> SO(task_id='PCA',process="pca_analysis",kwargs={'feature_file':'*input_file'}) >> SO(task_id='email_pca',process="emailit",kwargs={'file_attachment':'*pca_file','subject':'PCA file','text':'the PCA file is #attached','to':'gvasend@gmail.com'})
#   dag >> do >> SO(task_id='mean_shift',process="mean_shift",kwargs={'feature_file':'*input_file'}) >> SO(task_id='email_ms',process="emailit",kwargs={'file_attachment':'*centroid_file','subject':'centroid file','text':' the centroid file for {name} is attached','to':'gvasend@gmail.com'})


