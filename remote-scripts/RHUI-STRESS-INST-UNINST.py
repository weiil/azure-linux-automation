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

args = parser.parse_args()
duration = args.duration
pkg = args.package
timeout = args.timeout

pkg_download_path = "/tmp/rhui_stress"


def RunTest():
	UpdateState("TestRunning")
	RunLog.info('-'*15 + "RHUI STRESS TEST START" + '-'*15)
	RunLog.info("Test package: %s, Test duration: %s, Test base value: %s" % (pkg, duration, timeout))
	
	download_details = []
	install_details = []

	CleanTest(pkg)
	counter = 1
	start_time = time.time()
	# todo: if need to clean cache here
	while (time.time() - start_time) < duration:
		RigsterSigHandler(timeout)
		download_details.append(InstallPkg(pkg, counter))
		RemoveDownload()
		RigsterSigHandler(timeout)
		install_details.append(InstallPkg(pkg,counter,False))
		RemovePkg(pkg,counter)
		counter += 1

	UpdateState("TestCompleted")
	AnalyseResult(download_details, install_details)
	RunLog.info('-'*15 + 'TEST END' + '-'*15 )

def SigHandler(signum, frame):
	raise MyTimeoutException('operation timeout!')

def RigsterSigHandler(t):
	signal.signal(signal.SIGALRM, SigHandler)
	signal.alarm(t)

# todo: timeout the op
def InstallPkg(pkg, counter, download_only=True):
	cmd = 'yum install %s -y' % pkg
	op = 'install' 
	rst = False
	elapsed = None
	if download_only:
		op = 'download'
		cmd += ' --downloadonly --downloaddir=%s' % pkg_download_path
	RunLog.info('[START]%s %s #%s' % (op,pkg,counter))
	RunLog.info('execute cmd: %s' % cmd)
	st = time.time()
	try:
		rtc, out = commands.getstatusoutput(cmd)
	except MyTimeoutException, err:
		elapsed = time.time() - st
		RunLog.error('[TIMEOUT]%s %s #%s' % (op,pkg,counter))
	else:
		elapsed = time.time() - st
		if int(rtc) == 0:
			rst = True
			RunLog.info('[SUCCESS]%s %s #%s with %s seconds cost' % (op,pkg,counter,str(elapsed)))
		else:
			RunLog.error('[FAIL]%s %s #%s with error: %s' % (op,pkg,counter,out))
	finally:
		return (rst, elapsed)

# todo: detect if remove successfully
def RemovePkg(pkg, counter):
	RunLog.info('remove #%s' % counter)
	cmd = 'yum remove %s -y' % pkg
	RunLog.info('execute cmd: %s' % cmd)
	st = time.time()
	rtc, out = commands.getstatusoutput(cmd)
	elapsed = time.time() - st
	rst = False
	if int(rtc) == 0:
		rst = True
		RunLog.info('[SUCCESS]remove %s #%s' % (pkg,counter))
	else:
		RunLog.error('[FAIL]remove %s #%s' % (pkg,counter))
	return (rst, elapsed)

def RemoveDownload():
	JustRun('rm -rf %s' % pkg_download_path)

def CleanTest(pkg):
	RemoveDownload()
	JustRun('yum remove %s -y' % pkg)


def AnalyseResult(l_download, l_install):
	success_download_count, fail_download_count,success_install_count, fail_install_count = 0,0,0,0


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
		RunLog.info('-'*15 + "SUMMARY" + '-'*15)
		RunLog.info('*'*9 + 'Download:')
		RunLog.info('Total: %s, Success: %s, Fail: %s' % (len(l_download),success_download_count,fail_download_count))
		RunLog.info('The fastest download costs %s seconds' % min(cost_of_valid_download))
		RunLog.info('The slowest download costs %s seconds' % max(cost_of_valid_download))
		RunLog.info('The average download costs %s seconds' % str(sum(cost_of_valid_download)/len(cost_of_valid_download)))
		RunLog.info('*'*9 + 'Install:')
		RunLog.info('Total: %s Success: %s Fail: %s' % (len(l_install),success_install_count,fail_install_count))
		RunLog.info('The fastest install costs %s seconds' % min(cost_of_valid_install))
		RunLog.info('The slowest install costs %s seconds' % max(cost_of_valid_install))
		RunLog.info('The average install costs %s seconds' % str(sum(cost_of_valid_install)/len(cost_of_valid_install)))

		if fail_download_count == 0 and fail_install_count == 0:
			ResultLog.info('PASS')
		else:
			ResultLog.error('FAIL')

def RunlogWrapper(m,msg):
	if m == 'info':
		RunLog.info(msg)
	if m == 'error':
		RunLog.error(msg)
	print(msg)	

class MyTimeoutException(Exception):
	pass

RunTest()