#!/usr/bin/env python
import os.path
import sys
from sys import exit
import os
from pprint import pprint

def updatebosh(fname, newfile, mode):
	try:

		cpi_url = os.environ['BOSH_AZURE_CPI_URL']
		cpi_sha1 = os.environ['BOSH_AZURE_CPI_SHA1']
		if mode == 'performance':
			bosh_instance_type = os.environ['BOSH_AZURE_INSTANCE_TYPE']
			bosh_vm_storage_account = os.environ['BOSH_AZURE_VM_STORAGE_ACCOUNT']
		stemcell_url = os.environ['BOSH_AZURE_STEMCELL_URL']
		stemcell_sha1 = os.environ['BOSH_AZURE_STEMCELL_SHA1']

		with open(fname) as f:
			l = f.readlines()

		print('updating cpi')
		# change cpi 
		for i in l:
			if 'name: bosh-azure-cpi' in i:
				node_index = l.index(i)
				
				# change cpi url
				if l[node_index + 1].strip().startswith('url:'):
					print('find url node for cpi, changing...')
					l[node_index + 1] = l[node_index + 1].replace(l[node_index + 1].split()[-1], cpi_url)
					print('done')
				else:
					print('cannot find cpi url node')
					raise ValueError
				# change cpi sha1
				if l[node_index + 2].strip().startswith('sha1:'):
					print('find sha1 node for cpi, changing...')
					l[node_index + 2] = l[node_index + 2].replace(l[node_index + 2].split()[-1], cpi_sha1)    
					print('done')
				else:
					print('cannot find cpi sha1 node')
					raise ValueError

			# update bosh vm
			if mode == 'performance':
				if 'instance_type' in i:
					node_index = l.index(i)
					print('updating bosh')
					if bosh_instance_type == '':
						print('keep current bosh instance type as default, no changing...')
					else:
						print('find instance_type node for bosh, changing...')
						l[node_index] = l[node_index].replace(l[node_index].split()[-1],bosh_instance_type)
						print('done')
					# insert storage account name node
					print('inserting storage_account_name node for bosh')
					char_start_index = l[node_index].index('instance_type')
					space_str = l[node_index][:char_start_index]
					storage = space_str + 'storage_account_name: ' + bosh_vm_storage_account + '\n'
					l.insert(node_index + 1, storage)
					print('done')

				else: 
					pass

		if stemcell_url != '' and stemcell_sha1 != '':
			print('updating stemcell for bosh')
			for i in l:
				if 'url' in i and 'https' in i and 'stemcell' in i:
					print('find stemcell node for bosh, changing...')
					node_index = l.index(i)
					l[node_index] = l[node_index].replace(l[node_index].split()[-1], stemcell_url)
					l[node_index + 1] = l[node_index + 1].replace(l[node_index + 1].split()[-1], stemcell_sha1)
					print('done')
					break

		with open(newfile, 'w') as f:
			f.writelines(l)
		#pprint(l)

		renameyaml(fname,newfile)

	except KeyError as e:
		print('get environ failed, key:{}'.format(e))
	except IOError as e:
		print('open file failed, err:{}'.format(e))
	except ValueError as e:
		print('get node failed, err:{}'.format(e))
	except Exception as e:
		print(e)
	else:
		print('update yaml config for bosh successfully')
		return True

def updatecf(fname, newfile, mode):
	try:
		if mode == 'performance':
			compile_instance_type = os.environ['BOSH_AZURE_COMPILE_INSTANCE_TYPE']
			compile_vm_storage_account = os.environ['BOSH_AZURE_COMPILE_VM_STORAGE_ACCOUNT']
		stemcell_url = os.environ['BOSH_AZURE_STEMCELL_URL']
		stemcell_sha1 = os.environ['BOSH_AZURE_STEMCELL_SHA1']

		deploy_cf_sh_path = 'deploy_cloudfoundry.sh'

		with open(fname) as f:
			l = f.readlines()

		if mode == 'performance':
			print('updating compile')
			# update compile vm size
			for i in l:
				if 'compilation' in i:
					node_index = l.index(i)
					for ii in l[node_index:]:
						if 'instance_type' in ii:
							node_index = l.index(ii, node_index)
							if compile_instance_type == '':
								print('keep current compilation instance type as default, no changing...')
							else:
								print('find instance_type node for compile, changing...')
								l[node_index] = l[node_index].replace(l[node_index].split()[-1],compile_instance_type)
								print('done')
							break
					# get the space length for print
					print('inserting storage_account_name node for compile')
					char_start_index = l[node_index].index('instance_type')
					space_str = l[node_index][:char_start_index]
					storage = space_str + 'storage_account_name: ' + compile_vm_storage_account + '\n'
					# insert the storage acout name node
					l.insert(node_index + 1, storage)
					print('done')
					break

			with open(newfile,'w') as f:
				f.writelines(l)
			#pprint(l)

			renameyaml(fname,newfile)

		if stemcell_url != '' and stemcell_sha1 != '':
			print('updating stemcell for cf deployment')
			ver = stemcell_url.split('v=')[1]
			print('work with stemcell v{}'.format(ver))
			with open(deploy_cf_sh_path, 'r') as f:
				l = f.readlines()
			for i in l:
				if 'bosh upload stemcell http' in i:
					node_index = l.index(i)
					old_stemcell = i.split()[3]
					i = i.replace(old_stemcell, stemcell_url)
					l[node_index] = i
					break
			with open(deploy_cf_sh_path, 'w') as f:
				f.writelines(l)

	except KeyError as e:
		print('get environ failed, err:{}'.format(e))
	except IOError as e:
		print('open file failed, err:{}'.format(e))
	except ValueError as e:
		print('get node failed, error: {}'.format(e))
	except Exception as e:
		print(e)
	else:
		print('update yaml config for compile successfully')
		return True

def renameyaml(fname, newfile):
	# backup the original
	os.rename(fname, os.path.join(os.path.dirname(fname), os.path.basename(fname) + '.bak'))
	# rename the updated
	os.rename(newfile, fname)
	print('rename {} done'.format(fname))

if __name__ == "__main__":
	if len(sys.argv) == 1:
		sys.exit('please specify the yaml file path which want to update and the update test mode<deployment|performance>.')
	if len(sys.argv) == 2:
		sys.exit('please specify the update test mode<deployment|performance>.')
	if len(sys.argv) == 3:
		fpath = sys.argv[1]
		mode = sys.argv[2]

	if not os.path.exists(fpath):
		sys.exit('{} is not exits'.format(fpath))

	if mode != 'deployment' and mode != 'performance':
		sys.exit('{} is not a recognized mode, "deployment" or "performance" is allowed.'.format(mode))

	base_name = os.path.basename(fpath)
	dir_name = os.path.dirname(fpath)
	new_file_path = os.path.join(dir_name, 'new_' + base_name)
	print('save updated file as {}'.format(new_file_path))

	if base_name == 'bosh.yml':
		updatebosh(fpath, new_file_path, mode)
	elif base_name == 'multiple-vm-cf.yml':
		updatecf(fpath, new_file_path, mode)

