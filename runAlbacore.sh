#!/bin/bash

set -x
execute_command () {
	command=("${!1}")
	taskname="$2"
	donefile="$3"
	force="$4"
	outputfile="$5"
	
	JOBID=$PBS_JOBID
	###alter this to suit the job scheduler

	if [ "$force" -eq 1 ] || [ ! -e $donefile ] || [ ! -s $donefile ] || [ "`tail -n1 $donefile | cut -f3 -d','`" != " EXIT_STATUS:0" ]
	then
		echo COMMAND: "${command[@]}" >> $donefile
		if [ -z "$outputfile" ]
		then
			/usr/bin/time --format='RESOURCEUSAGE: ELAPSED=%e, CPU=%S, USER=%U, CPUPERCENT=%P, MAXRM=%M Kb, AVGRM=%t Kb, AVGTOTRM=%K Kb, PAGEFAULTS=%F, RPAGEFAULTS=%R, SWAP=%W, WAIT=%w, FSI=%I, FSO=%O, SMI=%r, SMO=%s, EXITSTATUS=%x' -o $donefile -a -- "${command[@]}"
			ret=$?
		else
			/usr/bin/time --format='RESOURCEUSAGE: ELAPSED=%e, CPU=%S, USER=%U, CPUPERCENT=%P, MAXRM=%M Kb, AVGRM=%t Kb, AVGTOTRM=%K Kb, PAGEFAULTS=%F, RPAGEFAULTS=%R, SWAP=%W, WAIT=%w, FSI=%I, FSO=%O, SMI=%r, SMO=%s, EXITSTATUS=%x' -o $donefile -a -- "${command[@]}" >$outputfile
			ret=$?			
		fi
		echo JOBID:$JOBID, TASKNAME:$taskname, EXIT_STATUS:$ret,  TIME:`date +%s` >>$donefile
  	if [ "$ret" -ne 0 ]
  	then
  		echo ERROR_command: $command
  		echo ERROR_exitcode: $taskname failed with $ret exit code.
  		exit $ret
  	fi
	elif [ -e $donefile ]
	then
		echo SUCCESS_command: $command
		echo SUCCESS_message: $taskname has finished with $ret exit code.
	fi
}

inputdir_local=$PBS_JOBFS/$dataid
outputdir_local=$PBS_JOBFS/BC_$dataid

command=(rsync -a $inputfile $PBS_JOBFS/)
execute_command command[@] $dataid.copy2local $outputdir/$dataid.copy2local.done 1

mkdir -p $inputdir_local
mkdir -p $outputdir_local

if [[ $inputfile == *".tar.gz" ]]
then
command=(tar --warning=no-unknown-keyword -xzf $PBS_JOBFS/`basename $inputfile` -C $inputdir_local)
execute_command command[@] $dataid.untar $outputdir/$dataid.untar.done 1
elif [[ $inputfile == *".zip" ]]
then
command=(unzip -q -o $PBS_JOBFS/`basename $inputfile` -d $inputdir_local)
execute_command command[@] $dataid.untar $outputdir/$dataid.untar.done 1
fi


##run albacore
module load albacore/1.2.1

if [[ $libkit == "SQK-LSK308" ]]
then
#module load albacore/1.2.2
command=(full_1dsq_basecaller.py -r -i $inputdir_local/ -t $threads -s $outputdir_local/ -o fastq,fast5 -q 10000000000000 -n 10000000000000 -f $flowcell -k $libkit)
execute_command command[@] $dataid.albacore $outputdir/$dataid.albacore.done 1
#module unload albacore/1.2.2
else
#module load albacore/1.2.1
command=(read_fast5_basecaller.py -r -i $inputdir_local/ -t $threads -s $outputdir_local/ -o fastq,fast5 -q 10000000000000 -n 10000000000000 -f $flowcell -k $libkit -c $configfile)
execute_command command[@] $dataid.albacore $outputdir/$dataid.albacore.done 1
#module unload python3/3.5.2 albacore/1.2.1
fi
module unload python3/3.5.2 albacore/1.2.1


##remove input directory
rm -rf $inputdir_local

##remove blank lines from fastq files as they are not properly formatted
sed '/^$/d' $outputdir_local/workspace/*.fastq > $outputdir_local/workspace/$dataid.fastq
##convert to fasta
sed -n '1~4s/^@/>/p;2~4p' $outputdir_local/workspace/$dataid.fastq > $outputdir_local/workspace/$dataid.fasta

##calculate md5sum for output fasta and fastq
command=(md5sum $outputdir_local/workspace/$dataid.fast*)
execute_command command[@] $dataid.copy2nas $outputdir/$dataid.calcmd5.done 1 $outputdir/$dataid.reads.md5


##keep a separate copy of the fasta and fastq for ease of use. Can be deleted as they will be contained within the .bc.tar.gz directory
##copy fasta/q files back to the network attached storage
command=(rsync -a $outputdir_local/workspace/$dataid.fast* $outputdir/)
execute_command command[@] $dataid.copy2nas $outputdir/$dataid.cpreads2nas.done 1


###fastq files are $outputdir_local/workspace/*.fastq
###fast5 files are in $outputdir_local/workspace/0
### you can add extra commands here for additional analysis of fastq or fast5 files
###if you can you should use $outputdir_local as the output directory for analysis results

##tar results folder
command=(tar czf $PBS_JOBFS/$dataid.bc.tar.gz -C $PBS_JOBFS/ BC_$dataid)
execute_command command[@] $dataid.tar $outputdir/$dataid.tar.done 1


##copy files back to the network attached storage
command=(rsync -a $PBS_JOBFS/$dataid.bc.tar.gz $outputdir/)
execute_command command[@] $dataid.copy2nas $outputdir/$dataid.copy2nas.done 1
