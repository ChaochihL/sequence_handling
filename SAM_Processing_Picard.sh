#!/bin/sh

#PBS -l mem=22gb,nodes=1:ppn=8,walltime=36:00:00
#PBS -m abe
#PBS -M user@example.com
#PBS -q oc

set -e
set -u
set -o pipefail

module load parallel

#   This script is a QSub submission script for converting a batch of SAM files to sorted and deduplicated BAM files
#   To use, on line 5, change the 'user@example.com' to your own email address
#       to get notificaitons on start and completion of this script
#   Add the full file path to list of samples on the 'SAMPLE_INFO' field on line 52
#       This should look like:
#           SAMPLE_INFO=${HOME}/Directory/list.txt
#       Use ${HOME}, as it is a link that the shell understands as your home directory
#           and the rest is the full path to the actual list of samples
#   Define a path to a reference genome on line 55
#       This should look like:
#           REF_GEN=${HOME}/Directory/reference_genome.fa
#   Put the full directory path for the output in the 'SCRATCH' field on line 58
#       This should look like:
#           SCRATCH="${HOME}/Out_Directory"
#       Adjust for your own out directory.
#   Name the project in the 'PROJECT' field on line 61
#       This should look lke:
#           PROJECT=Genetics
#       The final output path will be ${SCRATCH}/${PROJECT}/SAM_Processing
#   Define a path to the SAMTools in the 'SAMTOOLS' field on line 65
#       If using MSI, leave the definition as is to use their installation of SAMTools
#       Otherwise, it should look like this:
#           SAMTOOLS=${HOME}/software/samtools
#       Please be sure to comment out (put a '#' symbol in front of) the 'module load samtools' on line 64
#       And to uncomment (remove the '#' symbol) from lines 65 and 66
#   Define paths to the Picard installation, but not to 'picard.jar' itself, on line 69
#       If using MSI's Picard module, leave this blank, otherwise it should look like this:
#           PICARD_DIR=${HOME}/directory/picard
#       Where the 'picard.jar' file is located within '${HOME}/directory/picard'
#   Set the sequencing platform on line 72
#       This should look like:
#           PLATFORM=Illumina
#       This is set to Illumina by default; please see Picard's documentaiton for more details
#   Run this script with the qsub command
#       qsub SAM_Processing_Picard.sh
#   This script outputs sorted and deduplicated BAM files for each sample

#   List of SAM files for conversion
SAMPLE_INFO=

#   Reference genome to base the conversion from SAM to BAM off of
REF_GEN=

#   Scratch directory, for output
SCRATCH=

#   Name of project
PROJECT=

#	Load the SAMTools module for MSI, else define path to SAMTools installation
module load samtools
#SAMTOOLS=
#export PATH=$PATH:${SAMTOOLS}

#   Define path to the directory containing 'picard.jar' if not using MSI's Picard module
PICARD_DIR=

#   Sequencing platform
PLATFORM=Illumina

#   Change to the scratch directory
cd ${SCRATCH}

#   Make sure that java is installed
if `command -v java > /dev/null 2> /dev/null`
then
    echo "Java is installed"
else
    echo "Please install Java and add to your PATH"
    exit 1
fi

#   Make the outdirectories
OUT=${SCRATCH}/${PROJECT}/SAM_Processing
mkdir -p ${OUT}/stats ${OUT}/deduped ${OUT}/sorted ${OUT}/finished ${OUT}/raw

#   Define a function to process SAM files generated by BWA mem
#       This function will generate sorted and deduplicated BAM files
#       as well as alignment statistics for raw and finished BAM files
function dedup() {
    #   Today's date
    YMD=`date +%Y-%m-%d`
    #   Define varaibles within relation to function
    #   In order: SAM file being worked with, reference genome, outdirectory,
    #       sequencing platform, project name
    SAMFILE="$1"
    REF_SEQ="$3"
    OUTDIR="$4"
    TYPE="$5"
    PROJ="$6"
    #   Define path to Picard, either local or using MSI's Picard module
    if [[ -z "$2" ]]
    then
        #   Use MSI's Picard module, with changes to Java's heap memeory options
        module load picard
        PICARD_DIR=`echo $PTOOL | rev | cut -d " " -f 1 - | rev`
        PTOOL="java -Xmx15g -XX:MaxPermSize=10g -jar ${PICARD_DIR}"
    else
        #   Use local Picard installaiton, passed by arguments
        PICARD_DIR="$2"
        PTOOL="java -Xmx15g -XX:MaxPermSize=10g -jar ${PICARD_DIR}"
    fi
    #   Sample name, taken from full name of SAM file
    SAMPLE_NAME=`basename "${SAMFILE}" .sam`
    #   Use Samtools to trim out the reads we don't care about
    #       -f 3 gives us reads mapped in proper pair
    #       -F 256 excludes reads not in their primary alignments
    samtools view -f 3 -F 256 -bT "${REF_SEQ}" "${SAMFILE}" > "${OUTDIR}/raw/${SAMPLE_NAME}_${YMD}_raw.bam"
    #   Create alignment statistics for raw BAM files
    samtools flagstat "${OUTDIR}/raw/${SAMPLE_NAME}_${YMD}_raw.bam" > "${OUTDIR}/stats/${SAMPLE_NAME}_${YMD}_raw_stats.out"
    #   Picard tools to sort and index
    "${PTOOL}"/picard.jar SortSam \
        INPUT="${OUTDIR}/raw/${SAMPLE_NAME}_${YMD}_raw.bam" \
        OUTPUT="${OUTDIR}/sorted/${SAMPLE_NAME}_${YMD}_sorted.bam" \
        SORT_ORDER=coordinate \
        CREATE_INDEX=true \
        TMP_DIR="${HOME}/Scratch/Picard_Tmp"
    #   Then remove duplicates
    "${PTOOL}"/picard.jar MarkDuplicates \
        INPUT="${OUTDIR}/sorted/${SAMPLE_NAME}_${YMD}_sorted.bam" \
        OUTPUT="${OUTDIR}/deduped/${SAMPLE_NAME}_${YMD}_deduplicated.bam" \
        METRICS_FILE="${OUTDIR}/deduped/${SAMPLE_NAME}_${YMD}_Metrics.txt" \
        REMOVE_DUPLICATES=true \
        CREATE_INDEX=true \
        TMP_DIR="${HOME}/Scratch/Picard_Tmp" \
        MAX_RECORDS_IN_RAM=50000
    #   Then add read groups
    "${PTOOL}"/picard.jar AddOrReplaceReadGroups \
        INPUT="${OUTDIR}/deduped/${SAMPLE_NAME}_${YMD}_deduplicated.bam" \
        OUTPUT="${OUTDIR}/finished/${SAMPLE_NAME}_${YMD}_finished.bam" \
        RGID="${SAMPLE_NAME}" \
        RGPL="${TYPE}" \
        RGPU="${SAMPLE_NAME}" \
        RGSM="${SAMPLE_NAME}" \
        RGLB="${PROJ}_${SAMPLE_NAME}" \
        TMP_DIR="${HOME}/Scratch/Picard_Tmp" \
        CREATE_INDEX=True
    #   Create alignment statistics for finished BAM files
    samtools flagstat "${OUTDIR}/finished/${SAMPLE_NAME}_${YMD}_finished.bam" > "${OUTDIR}/stats/${SAMPLE_NAME}_${YMD}_finished_stats.out"
}

#   Export the function to be used by GNU parallel
export -f dedup

#   Pass variables to and run the function in parallel
cat ${SAMPLE_INFO} | parallel "dedup {} ${PICARD_DIR} ${REF_GEN} ${OUT} ${PLATFORM} ${PROJECT}"

#   Create a list of finished BAM files
find ${OUT}/finished -name "*_finished.bam" | sort > ${OUT}/${PROJECT}_finished_BAM_files.txt
echo "List of BAM files can be found at"
echo "${OUT}/${PROJECT}_finished_BAM_files.txt"
