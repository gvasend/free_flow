
from numpy import genfromtxt
import datetime, time
import atexit
from sklearn import manifold, datasets
import uuid
import logging
import os, stat, sys

#logging.basicConfig(level="DEBUG")
logger = logging.getLogger('freeflow')
svci = sys.argv[0]+'_'+str(uuid.uuid1())+'.svci'
tee_output = False
retain = 0
input_str = ""
env_enabled = False

def extract_val(st):
    st1 = st.split(":")[1].split('"')[1]
    print("extract_val:",st,st1)
    return st1

def collectJson(key):
    st = input_str
    strs = []
    val_list = st.split(key)
    for idx in range(1,len(val_list)):
        strs.append(extract_val(val_list[idx]))
    print("strings extracted:",strs)
    return strs

class Metafile(object):
    def __init__(self,filename,data):
        if filename == None:
            return None
        self.filename = filename
        if '.meta' in filename:
            logging.warn("load metafile directly by name: %s"%filename)
            self.data = load_json(filename)
            self.filename = self.data["filename"]
            print(self.data)
            self.filename = self.data["filename"]
        elif file_exists(self.meta_filename()):
            logging.info("load existing metafile")
            dct = load_json(self.meta_filename())
            self.data = dct
        else:
            self.data = {"svci":svci,"filename":self.filename,"creation":time.time(),"retain":retain}
            self.data.update(data)
            save_json(self.meta_filename(),self.data)
            print("meta:",self.meta_filename())
            
    def delete(self):
        os.remove(self.filename)
        os.remove(self.meta_filename())

    def get_filename(self):
        return self.filename
		
    def meta_filename(self):
        return "."+self.filename+".meta"
#        return "mf_"+self.filename

    def expired(self):
        try:
            if self.data["retain"] == 0:
                return False
        except:
            return False
        if not "creation" in self.data:
            return False
        create_date = self.data["creation"]
        now = time.time()
        remain = time.time()-(self.creation+(self.retain*60.0*60.0*24.0))
        print("%s time remaining"%remain)
        if self.creation+(self.retain*60.0*60.0*24.0) > time.time():
            return True
        else:
            return False
		
    def create_dict_mf(dct):
        for key, val in dct.items():
            if 'file' in key and not val == None and file_exists(val):
                mf = Metafile(val,{})
            elif 'file' in key and val == None:
                logging.info("file %s is None"%key)

    def scan_metafile(fname, opts):
        mf = Metafile(fname,{})
        if mf.expired() or '--delete_all' in opts:
            mf.delete()
			
    def scan_mf(opts=""):
        for dirpath, dnames, fnames in os.walk("./"):
            for f in fnames:
                if f.endswith(".meta"):
                    Metafile.scan_metafile(os.path.join(dirpath, f), opts)
                                    

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
  return {}
  try:
    print("load env ",fname)
    with open(fname, 'r') as inpf:
        str = inpf.read()
        return json.loads(str)
  except:
    return {}
    
def save_json(fname, dct):
    with open(fname, 'w') as outf:
        outf.write(json.dumps(dct,sort_keys=True))

def set_env(key,val):
    dct = load_json(env_file)
    os.environ[key.upper()] = str(val)
    dct[key] = str(val)
    save_json(env_file, dct)

def get_env(key):
    global env_enabled
#    if args.e == False:
    if True:  #disable for now
        logging.info("environment disabled")
        return None
    dct = load_json(env_file)
    if key in dct:
        print("lookup env ",key, dct[key])
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
g_upstream_dict = {}
g_input_dict = {}
dict_str = None
import json

def get_output_data_json(results):
    global g_upstream_dict, g_input_dict, input_str
# scrape output data between markers. limits where output data is scraped but follows full json format.
    results = str(results)
    input_str = results # save for later use
    logger.info(results)
    app_lst = re.findall('<app_data>(.+?)</app_data>', results, re.DOTALL)
    app_data = ",".join(app_lst)
    print(">>>",app_data,"<<<")
    if '{' in app_data:
        app_dict = json.loads(app_data)
        g_input_dict = app_dict
        logger.info("app_dict:%s"%app_dict)
    else:
        logger.warning("app data not detected")
        app_dict = {}
    upstream_lst = re.findall('<upstream_data>(.+?)</upstream_data>', results, re.DOTALL)
    upstream_data = ",".join(upstream_lst)
    if '{' in upstream_data:
        upstream_dict = json.loads(upstream_data)
        g_upstream_dict = upstream_dict
        logger.info("upstream_dict:%s"%upstream_dict)
    else:
        logger.info("upstream data not detected: %s"%upstream_data)
        upstream_dict = {}

#    print("up ",upstream_dict," app ",app_dict)
    upstream_dict.update(dict(app_dict)) # make sure app_data overwrites where duplicate
    logger.info("output data = %s"%upstream_data)
    return upstream_dict
# TODO upstream dict now kept separate. when this is working this function contains dead code to merge upstream data which should be removed
#    return app_dict

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

def extend_name(dct,ext):
    new_dct = {}
    for key, val in dct.items():
        new_dct[key+ext] = val
    return new_dct		

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
        dict_str = json.dumps(extend_name(in_dict,'-1'),sort_keys=True)				# extend name to ovoid name conflicts
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
           fh.write(json.dumps(out_data,sort_keys=True))
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
    global in_dict, arguments, hooks, logger, tee_output, g_upstream_dict, g_input_dict, args
    parser.formatter_class = argparse.ArgumentDefaultsHelpFormatter
    logger = logging.getLogger('root')
    if '-r' in sys.argv:
        os.remove(env_file)
    args =  parser.parse_args(scrape_inputs_(parser))
    if not args.s:
        hooks.hook()
        atexit.register(freeflow_terminate)
    retain = args.k

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

    logger.info("scrapped data %s"%in_dict)
    logger.info("upstream data %s"%g_upstream_dict)
    dct = args.__dict__.copy()
    replacements = {}
#  resolve any indirect references
    for key, val in dct.items():
#        print("key ",key,"value ",val)
        new_val = val
        new_val = resolve_argument(key,val)
        if type(val) == str and '?' in val and stdin_mode() == 'terminal':
            ptr = val.split("?")[1]
            new_val = get_env(ptr)
            logger.info("lookup key %s was %s now %s"%(ptr,val,new_val))
        while type(new_val) == str and new_val[0] == '*':
            ptr = new_val.split("*")[1]
            logger.info("indirect search for %s"%ptr)
            new_val = ptr
            for ink in in_dict:
                if ptr in ink and not in_dict[ink] == None:    # if the in_dict value is a string and the ptr is in the str we have a match
                    new_val = in_dict[ink]
                    replacements[ink] = new_val
                    logger.info("found in arguments %s:%s"%(ptr,new_val))
                    break
            for ink in g_upstream_dict:
                if ptr == ink and not g_upstream_dict[ink] == None:    # if the in_dict value is a string and the ptr is in the str we have a match
                    new_val = g_upstream_dict[ink]
                    replacements[ink] = new_val
                    logger.info("found in upstream %s:%s"%(ptr,new_val))
                    break
        setattr(args, key, eval_argument(new_val))
    logger.info("final arguments %s"%args)
    cmd_line = " ".join(sys.argv)
    for key, value in replacements.items():
        cmd_line = cmd_line.replace("*"+key,value)
    write_dict({"command_line":cmd_line})
    tee_output = args.t
    arguments = args
    return args

def resolve_argument(name,val):
    logger.info("resolving %s"%name)
    try:
        env_key = name.upper()
        value = os.environ[env_key]
        print("%s resolves to %s via environment variable"%(env_key,value))
        return value
    except:
#        print("%s not present in env variable"%name)
        return val

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
    st = "{}"
    if not mode == 'terminal':    # if stdin data is available, scrape it
        st = sys.stdin.read()
    else:
        if '-e' in sys.argv:
            try:
              with open(env_file, 'r') as inpf:
                  st = "<app_data>"+inpf.read()+"</app_data>"
                  print("read env data")
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
    
def generate_file(name, ext, arg_v, file_arg):
#    print("type ",type(model))
    argv_file = getattr(arg_v, file_arg)
    if argv_file == None:
        argv_file = name+"_"+str(uuid.uuid1())+'.'+ext
        setattr(arg_v, file_arg, argv_file)
    logger.info("saving as %s"%argv_file)
    write_dict({name:argv_file})
    return arg_v


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

def neo4j_options(parser):
    parser.add_argument('--gdb_path',default='/db/data/',help='Graph db path')
    parser.add_argument('--gdb_url',default='localhost:7474',help='Graph db URL')
    parser.add_argument('--user',default='neo4j',help='Username')
    parser.add_argument('--password',default='N7287W06',help='credentials')
	
# all options
def all_options(parser):
    parser.add_argument('-id',default='not_provided',help='Associate with external id.')
    parser.add_argument('-t',help='Copy upstream data to downstream.',action="store_true")
    parser.add_argument('-s',help='Supress dict output.',action="store_true")
    parser.add_argument('-e',default=False,help='Disable environmental variables.',action="store_false")
    parser.add_argument('-r',help='Reset environmental variables.',action="store_true")
    parser.add_argument('-b',help='Disable read arguments from stdin.',action="store_true")
    parser.add_argument('--argf',help='Read command line arguments from a file.',default='*command_file')
    parser.add_argument('-ll',default='WARN',help='set debugging level')
    parser.add_argument('-k',type=int,default=1,help='How long to keep auto generated files (days). Default is 1 day')


# output options
def output_options(parser):
    parser.add_argument('--output_file',default='eval:"sk_ff_"+str(uuid.uuid1())+".libsvm"',help='file containing output')

#    parser.add_argument('--zero_based',default=True,type=bool)

    parser.add_argument("--zero_based", type=str2bool, nargs='?',
                        const=True, default=False,
                        help="zero based.")

    parser.add_argument('--comment',help='')

    parser.add_argument('--query_id',help='')

    parser.add_argument('--multilabel',type=bool,default=False,help='')
    
task_ids = {}

def str2bool(v):
    if v.lower() in ('yes', 'true', 't', 'y', '1'):
        return True
    elif v.lower() in ('no', 'false', 'f', 'n', '0'):
        return False
    else:
        raise argparse.ArgumentTypeError('Boolean value expected.')

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


