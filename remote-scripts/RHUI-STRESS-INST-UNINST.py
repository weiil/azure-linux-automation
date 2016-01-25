#!/usr/bin/env python

from azuremodules import *
from argparse import ArgumentParser
import time
import commands
import signal

parser = ArgumentParser()
parser.add_argument('-d', '--duration', help='specify how long run time for testing', required=True, type=int)
parser.add_argument('-p', '--package', help='spcecify package name to keep install/remove from repo', required=True)
parser.add_argument('-t', '--timeout', help='specify the base value to evaluate elapsed time of downloading/installing package every time', required=True, type=int)
parser.add_argument('-s', '--save', help='save test data', required=False, action='store_true')

args = parser.parse_args()
duration = args.duration
pkg = args.package
timeout = args.timeout

pkg_download_path = "/tmp/rhui_stress"

def RunTest():
	UpdateState("TestRunning")
	RunLog.info('-'*30 + "RHUI STRESS TEST START" + '-'*30)
	RunLog.info('Test Infomation:')
	RunLog.info("\tTest package: %s, Test duration: %s, Test base value: %s" % (pkg, duration, timeout))
	RunLog.info('')

	download_details = []
	install_details = []

	CleanTest(pkg)
	counter = 1
	start_time = time.time()
	# todo: if need to clean cache here
	while (time.time() - start_time) < duration:
		RigsterSigHandler(timeout)
		download_details.append(InstallPkg(pkg, counter))
		UnrigsterSigHandler()
		RemoveDownload()
		RigsterSigHandler(timeout)
		install_details.append(InstallPkg(pkg,counter,False))
		UnrigsterSigHandler()
		RemovePkg(pkg,counter)
		counter += 1

	UpdateState("TestCompleted")
	AnalyseResult(download_details, install_details)

	if args.save:
		t = time.localtime()
		ts = "%d%02d%02d%02d%02d%02d" % (t.tm_year,t.tm_mon,t.tm_mday,t.tm_hour,t.tm_min,t.tm_sec)
		with open(str.format('download-%s.log' % ts),'w') as f:
			for i in iter(download_details):
				f.write(str(i[0])+'\t'+str(i[1])+'\n')
		with open(str.format('install-%s.log' % ts),'w') as f:
			for i in iter(download_details):
				f.write(str(i[0])+'\t'+str(i[1])+'\n')

	RunLog.info('-'*30 + 'TEST END' + '-'*30 )

def SigHandler(signum, frame):
	raise MyTimeoutException('operation timeout!')

def RigsterSigHandler(t):
	signal.signal(signal.SIGALRM, SigHandler)
	signal.alarm(t)

def UnrigsterSigHandler():
	signal.alarm(0)

def InstallPkg(pkg, counter, download_only=True):
	cmd = 'yum install %s -y' % pkg
	op = 'install' 
	rst = False
	elapsed = None
	if download_only:
		op = 'download'
		cmd += ' --downloadonly --downloaddir=%s' % pkg_download_path
	RunLog.info('[%s][#%s] >>>>>>>>> %s' % (op.upper(),counter,pkg))
	st = time.time()
	try:
		rtc, out = commands.getstatusoutput(cmd)
	except MyTimeoutException as err:
		elapsed = time.time() - st
		RunLog.error('\tTIMEOUT!!!')
	else:
		elapsed = time.time() - st
		if int(rtc) == 0:
			rst = True
			RunLog.info('\tSUCCESS with %s seconds cost!' % str(elapsed))
		else:
			RunLog.error('\tFAIL with error: %s!' % out)
	finally:
		return (rst, elapsed)

# todo: detect if remove successfully
def RemovePkg(pkg, counter):
	RunLog.info('[%s][#%s] >>>>>>>>> %s' % ('REMOVE',counter,pkg))
	cmd = 'yum remove %s -y' % pkg
	st = time.time()
	rtc, out = commands.getstatusoutput(cmd)
	elapsed = time.time() - st
	rst = False
	if int(rtc) == 0:
		rst = True
		RunLog.info('\tSUCCESS')
	else:
		RunLog.error('\tFAIL with error: %s!' % out)
	return (rst, elapsed)

def RemoveDownload():
	JustRun('rm -rf %s' % pkg_download_path)

def CleanTest(pkg):
	RemoveDownload()
	JustRun('yum remove %s -y' % pkg)


def AnalyseResult(l_download, l_install):
	success_download_count, fail_download_count,success_install_count, fail_install_count = 0,0,0,0

	try:
		if len(l_download) != 0 and len(l_install) != 0:
			for i in iter(l_download):
				if i[0]:
					success_download_count += 1
				else:
					fail_download_count += 1
			for i in iter(l_install):
				if i[0]:
					success_install_count += 1
				else:
					fail_install_count += 1
			
			cost_of_valid_download = [x[1] for x in iter(l_download) if x[0]]
			cost_of_valid_install = [x[1] for x in iter(l_install) if x[0]]

			# summary
			RunLog.info('-'*30 + "SUMMARY" + '-'*30)
			RunLog.info('*'*15 + 'Download Part:')
			RunLog.info('Total: %s, Success: %s, Fail: %s' % (len(l_download),success_download_count,fail_download_count))
			if len(cost_of_valid_download):
				RunLog.info('\tThe fastest download costs %s seconds' % min(cost_of_valid_download))
				RunLog.info('\tThe slowest download costs %s seconds' % max(cost_of_valid_download))
				RunLog.info('\tThe average download costs %s seconds' % str(sum(cost_of_valid_download)/len(cost_of_valid_download)))
			else:
				RunLog.error('\tNone valid download!!!')
			RunLog.info('*'*15 + 'Install Part:')
			RunLog.info('Total: %s Success: %s Fail: %s' % (len(l_install),success_install_count,fail_install_count))
			if len(cost_of_valid_install):
				RunLog.info('\tThe fastest install costs %s seconds' % min(cost_of_valid_install))
				RunLog.info('\tThe slowest install costs %s seconds' % max(cost_of_valid_install))
				RunLog.info('\tThe average install costs %s seconds' % str(sum(cost_of_valid_install)/len(cost_of_valid_install)))
			else:
				RunLog.error('\tNone valid install!!!')
				
			if fail_download_count == 0 and fail_install_count == 0:
				ResultLog.info('PASS')
			else:
				ResultLog.error('FAIL')
	except Exception as err:
		print(err)

def RunlogWrapper(m,msg):
	if m == 'info':
		RunLog.info(msg)
	if m == 'error':
		RunLog.error(msg)
	print(msg)	

class MyTimeoutException(Exception):
	pass

RunTest()