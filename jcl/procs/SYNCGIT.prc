//SYNCGIT PROC JBNAME='SYNCGIT',
//             QUAL='SITE.',
//             SOUTP='X'
//*********************************************************************
//** SAMPLE PROC: RUNS THE SOURCE SYNC SCRIPT THROUGH BPXBATCH.      **
//** REPLACE PATHS, OUTPUT CLASS, AND OPTIONAL DOWNSTREAM STEPS      **
//** TO MATCH YOUR SITE.                                             **
//*********************************************************************
//**                                                                 **
//**              JOB STEP RECOVERY PROCEDURES                       **
//**              ----------------------------                       **
//**                                                                 **
//**  JOBNAME: SYNCGIT         FORMERLY IN DOS:  NONE               **
//**                                                                 **
//**                                                                 **
//**  ABENDING STEP     RESTART STEP     CTM-R RESTART COND CODE     **
//**  -------------     ------------     -----------------------     **
//**                                                                 **
//**   STEP010           STEP010                000                  **
//**   STEP011           STEP010                000                  **
//**   STEP020           STEP020                000                  **
//**   STEP021           STEP020                000                  **
//*********************************************************************
//* BPXBATCH (UTIL) - RUN MAINFRAME-TO-GITHUB SYNC BASH SHELL SCRIPT  *
//*********************************************************************
//STEP010  EXEC PGM=BPXBATCH
//SYSPRINT DD  SYSOUT=&SOUTP
//STDENV   DD  PATHDISP=(KEEP,KEEP),
//             PATHOPTS=(ORDONLY),PATHMODE=SIRWXU,
// PATH='/u/your-user/projects/mainframe-source-sync/config/app_config.txt'
//STDOUT   DD  SYSOUT=&SOUTP
//STDERR   DD  SYSOUT=&SOUTP
//STDPARM  DD  *
SH cd $PROJECT_WORKSPACE;
cd $PROJECT_NAME;
/sw/mincnda/bin/bash bin/sync_mainframe_source.sh;
/*
//*********************************************************************
//* ABEND (ASM) - ABEND JOB IF SYNC SCRIPT RETURNED A REAL ERROR      *
//* NOTE: RC=0 (changes pushed) and RC=4 (no changes) are both        *
//* SUCCESS outcomes for sync_mainframe_source.sh; only RC > 4        *
//* (CONFIG_ERROR=8, PROCESSING_ERROR=12, GIT_ERROR=16, FATAL=20)     *
//* should trigger an abend.                                          *
//*********************************************************************
//         IF STEP010.RC > 4 THEN
//STEP011  EXEC PGM=ABEND
//STEPLIB  DD  DISP=SHR,DSN=YOUR.LINKLIB
//         ENDIF
//*
//*********************************************************************
//* OPTIONAL SITE-SPECIFIC DOWNSTREAM STEP                            *
//*********************************************************************
//STEP020  EXEC PGM=SITEHOOK,REGION=4096K,
// PARM='CONFIG=YOUR.CONFIG CMDFILE=&QUAL.CTLLIB(SYNCGIT)'
//STEPLIB  DD  DSN=YOUR.SITE.LOAD,DISP=SHR
//SYS0001  DD  SYSOUT=&SOUTP
//HOOKLOG  DD  SYSOUT=&SOUTP
//HOOKERR  DD  SYSOUT=&SOUTP
//HOOKOUT  DD  DSN=&&TEMP,DISP=(,PASS),SPACE=(TRK,(1,1),RLSE),
//             DCB=(LRECL=133,BLKSIZE=13300,RECFM=FB)
//*
//*********************************************************************
//* OPTIONAL SITE-SPECIFIC VALIDATION STEP                            *
//* VALIDATE OR REMOVE THIS SECTION AS NEEDED                         *
//*********************************************************************
//STEP021  EXEC PGM=SITECHECK,PARM='&JBNAME'
//STEPLIB  DD  DSN=YOUR.SITE.LOAD,DISP=SHR
//         DD  DSN=YOUR.LINKLIB,DISP=SHR
//CONTROLI DD  DSN=&&TEMP,DISP=(OLD,DELETE)
//REPORT   DD  SYSOUT=&SOUTP
//SYSOUT   DD  SYSOUT=&SOUTP
//SYSPRINT DD  SYSOUT=&SOUTP
//*
//         PEND