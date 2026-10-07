//SYNCGIT  JOB ('ACCT'),'SOURCE SYNC',
//             CLASS=A,MSGCLASS=X,MSGLEVEL=(1,1),NOTIFY=&SYSUID,
//             REGION=0M
/*ROUTE    XEQ YOURSYS
/*JOBPARM  SYSAFF=YOURSYS
//         JCLLIB ORDER=(YOUR.PROCLIB)
//*********************************************************************
//** SAMPLE JOB: RUNS A BASH SCRIPT TO SYNCHRONIZE EXPORTED SOURCE   **
//** INTO A TARGET GIT REPOSITORY. REPLACE JOB CARD VALUES, ROUTING, **
//** AND PROC LIBRARIES TO MATCH YOUR SITE.                          **
//*********************************************************************
//SYNCGIT  EXEC PROC=SYNCGIT,
//             JBNAME='SYNCGIT',
//             QUAL='SITE.',
//             SOUTP='X'
//